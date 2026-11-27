//! A network as bytes and back, after spaghetti's `savenetwork` / `loadnetwork` (which pickle the
//! network object).
//!
//! Format version 1, little-endian:
//!
//! | field | type |
//! |---|---|
//! | magic | `b"NWKX"` |
//! | version | `u32` (1) |
//! | `vertex_sig`, `vertex_atol` | `u32` each, 0 for none |
//! | vertex count `V`, arc count `A` | `u64` each |
//! | vertices | `V` x (`f64` x, `f64` y) |
//! | arcs | `A` x (`u32`, `u32`), sorted, unique, smaller id first |
//! | arc lengths | `A` x `f64` |
//! | arc order | `A` x `u32`, a permutation of the arc indices |
//!
//! Adjacency, components and the graph are derived again on load (`network::assemble`), as for
//! every network Networkex builds. Malformed bytes give an error, never a panic.

use crate::network::{assemble, Link, Network};
use std::collections::{BTreeSet, HashMap};

const MAGIC: &[u8; 4] = b"NWKX";
const HEADER: u128 = 32;

/// The current format version.
pub const VERSION: u32 = 1;

/// The rounding options a network was built with.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Params {
    pub vertex_sig: Option<u32>,
    pub vertex_atol: Option<u32>,
}

/// The network and its rounding options as bytes.
pub fn encode(ntw: &Network, params: Params) -> Vec<u8> {
    let (v, a) = (ntw.vertices.len(), ntw.arcs.len());
    let mut out = Vec::with_capacity(32 + 16 * v + 20 * a);
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&VERSION.to_le_bytes());
    for option in [params.vertex_sig, params.vertex_atol] {
        out.extend_from_slice(&option.unwrap_or(0).to_le_bytes());
    }
    out.extend_from_slice(&(v as u64).to_le_bytes());
    out.extend_from_slice(&(a as u64).to_le_bytes());
    for c in ntw.vertices.iter().flatten() {
        out.extend_from_slice(&c.to_le_bytes());
    }
    for &(x, y) in &ntw.arcs {
        out.extend_from_slice(&x.to_le_bytes());
        out.extend_from_slice(&y.to_le_bytes());
    }
    for length in &ntw.arc_lengths {
        out.extend_from_slice(&length.to_le_bytes());
    }
    for i in &ntw.arc_order {
        out.extend_from_slice(&i.to_le_bytes());
    }
    out
}

/// A network from bytes written by `encode`.
pub fn decode(bytes: &[u8]) -> Result<(Network, Params), String> {
    let mut r = Reader { bytes, at: 0 };
    if r.take::<4>().ok().as_ref() != Some(MAGIC) {
        return Err("not a Networkex network (no NWKX header)".to_string());
    }
    let version = r.u32()?;
    if version != VERSION {
        return Err(format!(
            "unsupported Networkex network format version {version} (this build reads {VERSION})"
        ));
    }
    let option = |x: u32| (x > 0).then_some(x);
    let params = Params {
        vertex_sig: option(r.u32()?),
        vertex_atol: option(r.u32()?),
    };
    let (v, a) = (r.u64()?, r.u64()?);
    // The size must match before anything is allocated, so a forged count cannot reserve memory.
    let expected = HEADER + 16 * u128::from(v) + 20 * u128::from(a);
    if bytes.len() as u128 != expected {
        return Err(format!(
            "a network of {v} vertices and {a} arcs takes {expected} bytes, got {}",
            bytes.len()
        ));
    }
    let (v, a) = (v as usize, a as usize);
    if a == 0 {
        return Err("a network needs at least one arc".to_string());
    }

    let mut vertices = Vec::with_capacity(v);
    for _ in 0..v {
        let p = [r.f64()?, r.f64()?];
        if !p.iter().all(|c| c.is_finite()) {
            return Err("vertex coordinates must be finite".to_string());
        }
        vertices.push(p);
    }
    let mut arcs: Vec<Link> = Vec::with_capacity(a);
    for i in 0..a {
        let arc = (r.u32()?, r.u32()?);
        if arc.0 > arc.1 || arc.1 as usize >= v {
            return Err(format!(
                "arc {i} {arc:?} is not an arc between {v} vertices"
            ));
        }
        if arcs.last().is_some_and(|prev| *prev >= arc) {
            return Err("arcs must be sorted and unique".to_string());
        }
        arcs.push(arc);
    }
    let mut lengths = HashMap::with_capacity(a);
    for &arc in &arcs {
        let length = r.f64()?;
        if !(length.is_finite() && length >= 0.0) {
            return Err(format!("arc {arc:?} has length {length}"));
        }
        lengths.insert(arc, length);
    }
    let mut seen = vec![false; a];
    let mut order = Vec::with_capacity(a);
    for _ in 0..a {
        let i = r.u32()? as usize;
        if i >= a || std::mem::replace(&mut seen[i], true) {
            return Err("the arc order must be a permutation of the arcs".to_string());
        }
        order.push(arcs[i]);
    }

    // Adjacency follows from the arcs, as when the network was built.
    let mut adjacency: Vec<BTreeSet<u32>> = vec![BTreeSet::new(); v];
    for &(x, y) in &arcs {
        adjacency[x as usize].insert(y);
        adjacency[y as usize].insert(x);
    }
    if let Some(i) = adjacency.iter().position(BTreeSet::is_empty) {
        return Err(format!("vertex {i} has no arc"));
    }
    let adjacency = adjacency
        .into_iter()
        .map(|s| s.into_iter().collect())
        .collect();
    Ok((
        assemble(vertices, arcs, &lengths, &order, adjacency)?,
        params,
    ))
}

/// Little-endian reads that fail at the end of the bytes.
struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl Reader<'_> {
    fn take<const N: usize>(&mut self) -> Result<[u8; N], String> {
        let chunk = self
            .at
            .checked_add(N)
            .and_then(|end| self.bytes.get(self.at..end))
            .and_then(|s| <[u8; N]>::try_from(s).ok())
            .ok_or_else(|| "the network bytes end too early".to_string())?;
        self.at += N;
        Ok(chunk)
    }

    fn u32(&mut self) -> Result<u32, String> {
        self.take().map(u32::from_le_bytes)
    }

    fn u64(&mut self) -> Result<u64, String> {
        self.take().map(u64::from_le_bytes)
    }

    fn f64(&mut self) -> Result<f64, String> {
        self.take().map(f64::from_le_bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::network::build_with;
    use crate::utilities;

    fn sample() -> Network {
        build_with(
            &[
                vec![[0.0, 0.0], [1.0, 0.0], [3.0, 0.0]],
                vec![[1.0, 0.0], [1.0, 2.0]],
                vec![[3.0, 0.0], [3.0, 2.0], [1.0, 2.0]],
                vec![[10.0, 10.0], [11.0, 10.0]],
            ],
            Some(11),
            Some(3),
        )
        .unwrap()
    }

    const PARAMS: Params = Params {
        vertex_sig: Some(11),
        vertex_atol: Some(3),
    };

    #[test]
    fn round_trips_built_and_derived_networks() {
        let ntw = sample();
        let derived = [
            ntw.clone(),
            utilities::split_arcs(&ntw, utilities::Split::Distance(0.75)).unwrap(),
            utilities::extract_component(&ntw, 0).unwrap().0,
            utilities::spanning_tree(&ntw, false).unwrap(),
        ];
        for net in derived {
            for params in [PARAMS, Params::default()] {
                let (back, back_params) = decode(&encode(&net, params)).unwrap();
                assert_eq!(back, net);
                assert_eq!(back_params, params);
            }
        }
    }

    #[test]
    fn every_truncation_and_extra_byte_is_an_error() {
        let bytes = encode(&sample(), PARAMS);
        for cut in 0..bytes.len() {
            assert!(decode(&bytes[..cut]).is_err(), "cut at {cut}");
        }
        let mut longer = bytes.clone();
        longer.push(0);
        assert!(decode(&longer).is_err());
    }

    /// A change to valid bytes that must make them invalid.
    type Tamper<'a> = Box<dyn Fn(&mut Vec<u8>) + 'a>;

    /// The bytes with `f` applied, for malformed inputs.
    fn tampered(f: impl Fn(&mut Vec<u8>)) -> Result<(Network, Params), String> {
        let mut bytes = encode(&sample(), PARAMS);
        f(&mut bytes);
        decode(&bytes)
    }

    #[test]
    fn malformed_bytes_are_errors() {
        let ntw = sample();
        let (v, a) = (ntw.vertices.len(), ntw.arcs.len());
        let vertices_at = 4 + 4 + 8 + 16;
        let arcs_at = vertices_at + 16 * v;
        let lengths_at = arcs_at + 8 * a;
        let order_at = lengths_at + 8 * a;
        let put_u32 =
            |b: &mut Vec<u8>, at: usize, x: u32| b[at..at + 4].copy_from_slice(&x.to_le_bytes());
        let put_f64 =
            |b: &mut Vec<u8>, at: usize, x: f64| b[at..at + 8].copy_from_slice(&x.to_le_bytes());

        let cases: Vec<(&str, Tamper<'_>)> = vec![
            ("magic", Box::new(|b| b[0] = b'X')),
            ("version", Box::new(|b| put_u32(b, 4, 2))),
            (
                "huge vertex count",
                Box::new(|b| b[16..24].copy_from_slice(&u64::MAX.to_le_bytes())),
            ),
            (
                "non-finite vertex",
                Box::new(move |b| put_f64(b, vertices_at, f64::NAN)),
            ),
            (
                "vertex id out of range",
                Box::new(move |b| put_u32(b, arcs_at + 4, v as u32)),
            ),
            (
                "arc ends reversed",
                Box::new(move |b| {
                    put_u32(b, arcs_at, 1);
                    put_u32(b, arcs_at + 4, 0);
                }),
            ),
            (
                "arcs out of order",
                Box::new(move |b| {
                    let (first, second) = (
                        b[arcs_at..arcs_at + 8].to_vec(),
                        b[arcs_at + 8..arcs_at + 16].to_vec(),
                    );
                    b[arcs_at..arcs_at + 8].copy_from_slice(&second);
                    b[arcs_at + 8..arcs_at + 16].copy_from_slice(&first);
                }),
            ),
            (
                "negative length",
                Box::new(move |b| put_f64(b, lengths_at, -1.0)),
            ),
            (
                "order not a permutation",
                Box::new(move |b| put_u32(b, order_at, ntw.arc_order[1])),
            ),
        ];
        for (name, f) in cases {
            assert!(tampered(f).is_err(), "{name} was accepted");
        }
    }

    #[test]
    fn a_vertex_without_arcs_is_an_error() {
        // One more vertex than the arcs use, with the counts and sizes kept consistent.
        let ntw = sample();
        let mut bytes = encode(&ntw, PARAMS);
        let v = ntw.vertices.len();
        bytes[16..24].copy_from_slice(&((v + 1) as u64).to_le_bytes());
        let at = 32 + 16 * v;
        bytes.splice(at..at, [0u8; 16]);
        assert!(decode(&bytes).unwrap_err().contains("vertex"));
    }
}
