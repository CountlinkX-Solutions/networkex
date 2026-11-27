// Portions of this file are derived from spaghetti 1.7.6 (https://github.com/pysal/spaghetti).
// Copyright 2017 PySAL-spaghetti Developers. Licensed under the BSD 3-Clause License, reproduced
// in LICENSES/BSD-3-Clause-spaghetti.txt; see NOTICE. Each derived function names its source.

//! Network utilities after spaghetti: `Network.split_arcs`, `extract_component` and
//! `spanning_tree`.

use crate::kfunction::point_along;
use crate::network::{assemble, build, key, link, Link, Network};
use std::collections::{BTreeSet, HashMap};

/// How `split_arcs` cuts the arcs.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Split {
    /// Pieces of this length from the start of each arc, the last one shorter.
    Distance(f64),
    /// Each arc in this many pieces of equal length.
    Count(u32),
}

/// spaghetti's `arc_lengths` dict: insertion order, removal and in-place update.
#[derive(Default)]
struct OrderedLengths {
    entries: Vec<Option<(Link, f64)>>,
    index: HashMap<Link, usize>,
}

impl OrderedLengths {
    fn insert(&mut self, arc: Link, length: f64) {
        match self.index.get(&arc) {
            Some(&i) => self.entries[i] = Some((arc, length)),
            None => {
                self.index.insert(arc, self.entries.len());
                self.entries.push(Some((arc, length)));
            }
        }
    }

    fn remove(&mut self, arc: Link) {
        if let Some(i) = self.index.remove(&arc) {
            self.entries[i] = None;
        }
    }

    fn get(&self, arc: Link) -> f64 {
        self.entries[self.index[&arc]].expect("a present arc").1
    }
}

fn check_split(split: Split) -> Result<(), String> {
    match split {
        Split::Distance(d) if !(d.is_finite() && d > 0.0) => {
            Err("the split distance must be a positive number".to_string())
        }
        Split::Count(c) if c <= 1 => Err("arcs must be split in at least 2".to_string()),
        _ => Ok(()),
    }
}

/// The most pieces `split_arcs` cuts an arc of `length` into: `ceil(length / d)` for a split
/// distance `d` shorter than the arc and `c` for a split count `c`, plus one, as the pieces are
/// placed by adding up their length and rounding can leave a last, tiny piece (see
/// `split_arc_estimate`); 1 for an arc that stays whole. It saturates at `u64::MAX`.
fn most_pieces(length: f64, split: Split) -> u64 {
    // The same test as `split_arcs`: an arc is cut when its interval is shorter than it.
    match split {
        // A float-to-integer cast saturates, so a huge ratio gives u64::MAX.
        Split::Distance(d) if d < length => ((length / d).ceil() as u64).saturating_add(1),
        Split::Count(c) if length / f64::from(c) < length => u64::from(c) + 1,
        _ => 1,
    }
}

/// An upper bound on the arcs `split_arcs` makes, counted without making them, so that a caller
/// can refuse a split too large to allocate: the sum of `most_pieces` over the arcs, saturating
/// at `u64::MAX`.
///
/// Why one extra piece per arc is enough: `split_arcs` adds the interval `i` to the length
/// covered so far, `t`, until `t >= length`. Each addition rounds by a relative error of at
/// most `u = 2^-53`, so after `k` additions `t >= k * i * (1 - u)^k`, and `length / i` is
/// computed within the same relative error. With `c` the counted pieces, `k = c + 1` additions
/// reach the length whenever `(c + 1) * (c + 2) * u <= 1`, which holds below `MAX_SPLIT_ARCS`
/// pieces. That needs pieces of normal floats: a count split that would make pieces below
/// `f64::MIN_POSITIVE` (where the error is absolute, not relative) is refused.
///
/// A piece that falls exactly on an arc not yet split takes that arc's place, with the piece's
/// length (as in spaghetti's `arc_lengths` dict), so `split_arcs` may cut that arc by a shorter
/// length than the one counted here: with a distance it then stays whole, with a count it
/// still makes at most `c + 1` pieces. The bound holds either way.
pub fn split_arc_estimate(ntw: &Network, split: Split) -> Result<u64, String> {
    check_split(split)?;
    let mut total = 0u64;
    for &length in &ntw.arc_lengths {
        if let Split::Count(c) = split {
            let interval = length / f64::from(c);
            if interval < length && interval < f64::MIN_POSITIVE {
                return Err(format!(
                    "an arc of length {length:e} split in {c} would make pieces shorter than \
                     the smallest normal float ({:e})",
                    f64::MIN_POSITIVE
                ));
            }
        }
        total = total.saturating_add(most_pieces(length, split));
    }
    Ok(total)
}

/// The highest `max_arcs` a split accepts: up to this many pieces per arc, rounding adds at
/// most one (see `split_arc_estimate`). It is also far above the splits the graph extraction
/// handles in reasonable time, which grows with the square of the arcs.
pub const MAX_SPLIT_ARCS: u64 = 1 << 26;

/// Refuses, before anything is allocated, a split that could make more than `max_arcs` arcs:
/// returns the bound of `split_arc_estimate`, which `split_arcs` never exceeds.
pub fn check_split_size(ntw: &Network, split: Split, max_arcs: u64) -> Result<u64, String> {
    if max_arcs > MAX_SPLIT_ARCS {
        return Err(format!(
            "max_arcs must be at most {MAX_SPLIT_ARCS}, got {max_arcs}"
        ));
    }
    let estimate = split_arc_estimate(ntw, split)?;
    if estimate > max_arcs {
        return Err(format!(
            "the split would make up to {estimate} arcs, above max_arcs ({max_arcs})"
        ));
    }
    Ok(estimate)
}

// Derived from spaghetti 1.7.6: `Network.split_arcs` (spaghetti/network.py).
/// Splits every arc longer than the split into pieces, as `spaghetti.Network.split_arcs`. New
/// vertices get the next ids along each arc (in arc order); a new point that falls exactly on an
/// existing vertex reuses it. A vertical arc is walked upwards, as spaghetti places its points
/// from the lower vertex. It allocates every piece: bound it with `check_split_size` first. It
/// never makes more arcs than `split_arc_estimate`: an arc whose pieces would not add up to it
/// within `most_pieces` (only possible with pieces below the smallest normal float) is an
/// error, not an endless loop.
pub fn split_arcs(ntw: &Network, split: Split) -> Result<Network, String> {
    check_split(split)?;
    let mut vertices = ntw.vertices.clone();
    let mut ids: HashMap<(u64, u64), u32> = vertices
        .iter()
        .enumerate()
        .map(|(i, v)| (key(*v), i as u32))
        .collect();
    let mut adjacency: Vec<BTreeSet<u32>> = ntw
        .adjacency
        .iter()
        .map(|ns| ns.iter().copied().collect())
        .collect();
    let mut lengths = OrderedLengths::default();
    for &i in &ntw.arc_order {
        lengths.insert(ntw.arcs[i as usize], ntw.arc_lengths[i as usize]);
    }
    let mut arcs: BTreeSet<Link> = ntw.arcs.iter().copied().collect();
    for &arc in &ntw.arcs {
        let length = lengths.get(arc);
        let mut interval = match split {
            Split::Distance(d) => d,
            Split::Count(c) => length / c as f64,
        };
        if interval >= length {
            continue;
        }
        let (mut start, mut end) = arc;
        let (s, e) = (vertices[start as usize], vertices[end as usize]);
        if s[1] > e[1] && s[0] == e[0] {
            std::mem::swap(&mut start, &mut end);
        }
        adjacency[start as usize].remove(&end);
        adjacency[end as usize].remove(&start);
        lengths.remove(arc);
        arcs.remove(&arc);
        let most = most_pieces(length, split);
        let mut made = 0u64;
        let mut total = 0.0;
        while total < length {
            made += 1;
            if made > most {
                return Err(format!(
                    "the pieces of an arc of length {length:e} do not add up to its length"
                ));
            }
            let stop = if total + interval >= length {
                interval = length - total;
                total = length;
                end
            } else {
                total += interval;
                let p = point_along(ntw, arc, total);
                *ids.entry(key(p)).or_insert_with(|| {
                    vertices.push(p);
                    adjacency.push(BTreeSet::new());
                    (vertices.len() - 1) as u32
                })
            };
            adjacency[start as usize].insert(stop);
            adjacency[stop as usize].insert(start);
            let piece = link(start, stop);
            arcs.insert(piece);
            lengths.insert(piece, interval);
            start = stop;
        }
    }
    let order: Vec<Link> = lengths.entries.iter().flatten().map(|(a, _)| *a).collect();
    let by_arc: HashMap<Link, f64> = lengths.entries.iter().flatten().copied().collect();
    assemble(
        vertices,
        arcs.into_iter().collect(),
        &by_arc,
        &order,
        adjacency
            .into_iter()
            .map(|s| s.into_iter().collect())
            .collect(),
    )
}

/// The arcs of one network component as a network of their own, as spaghetti's
/// `extract_component`. Vertices are renumbered in the order of their old ids, which are
/// returned alongside; arcs, lengths and the graph are those of the component.
pub fn extract_component(ntw: &Network, component: u32) -> Result<(Network, Vec<u32>), String> {
    if component as usize >= ntw.components.n_components {
        return Err(format!(
            "the network has {} components, no component {component}",
            ntw.components.n_components
        ));
    }
    let keep: Vec<bool> = ntw
        .components
        .labels
        .iter()
        .map(|&l| l == component)
        .collect();
    let old_ids: Vec<u32> = ntw
        .arcs
        .iter()
        .zip(&keep)
        .filter(|(_, k)| **k)
        .flat_map(|(a, _)| [a.0, a.1])
        .collect::<BTreeSet<u32>>()
        .into_iter()
        .collect();
    let new_id: HashMap<u32, u32> = old_ids
        .iter()
        .enumerate()
        .map(|(i, &v)| (v, i as u32))
        .collect();
    let map = |a: Link| (new_id[&a.0], new_id[&a.1]);
    let mut arcs = Vec::new();
    let mut by_arc = HashMap::new();
    for ((arc, len), k) in ntw.arcs.iter().zip(&ntw.arc_lengths).zip(&keep) {
        if *k {
            arcs.push(map(*arc));
            by_arc.insert(map(*arc), *len);
        }
    }
    let order: Vec<Link> = ntw
        .arc_order
        .iter()
        .filter(|&&i| keep[i as usize])
        .map(|&i| map(ntw.arcs[i as usize]))
        .collect();
    let adjacency = old_ids
        .iter()
        .map(|&v| {
            ntw.adjacency[v as usize]
                .iter()
                .map(|n| new_id[n])
                .collect()
        })
        .collect();
    let vertices = old_ids.iter().map(|&v| ntw.vertices[v as usize]).collect();
    Ok((
        assemble(vertices, arcs, &by_arc, &order, adjacency)?,
        old_ids,
    ))
}

fn find(parent: &mut [u32], v: u32) -> u32 {
    let mut r = v;
    while parent[r as usize] != r {
        r = parent[r as usize];
    }
    let mut c = v;
    while parent[c as usize] != r {
        let next = parent[c as usize];
        parent[c as usize] = r;
        c = next;
    }
    r
}

/// The minimum (or maximum) spanning tree, as spaghetti's `spanning_tree` with the `"sort"`
/// method: the arcs by length (ties in `arc_lengths` order) join the tree unless they close a
/// cycle, and the tree is built anew from them as two-point lines in that order (default
/// `vertex_sig`). A network without cycles is returned as it is.
pub fn spanning_tree(ntw: &Network, maximum: bool) -> Result<Network, String> {
    let n = ntw.vertices.len();
    // A forest has as many arcs as vertices minus components (a loop arc is a cycle).
    if ntw.arcs.len() + ntw.components.n_components <= n && ntw.arcs.iter().all(|(a, b)| a != b) {
        return Ok(ntw.clone());
    }
    let mut order: Vec<usize> = ntw.arc_order.iter().map(|&i| i as usize).collect();
    order.sort_by(|&i, &j| {
        let (a, b) = (ntw.arc_lengths[i], ntw.arc_lengths[j]);
        if maximum {
            b.total_cmp(&a)
        } else {
            a.total_cmp(&b)
        }
    });
    let mut parent: Vec<u32> = (0..n as u32).collect();
    let mut lines = Vec::new();
    for i in order {
        let (a, b) = ntw.arcs[i];
        let (ra, rb) = (find(&mut parent, a), find(&mut parent, b));
        if ra != rb {
            parent[ra.max(rb) as usize] = ra.min(rb);
            lines.push(vec![ntw.vertices[a as usize], ntw.vertices[b as usize]]);
        }
    }
    build(&lines, Some(11))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn square() -> Network {
        build(
            &[vec![
                [0.0, 0.0],
                [2.0, 0.0],
                [2.0, 1.0],
                [0.0, 1.0],
                [0.0, 0.0],
            ]],
            Some(11),
        )
        .unwrap()
    }

    #[test]
    fn splitting_adds_vertices_along_the_arcs() {
        let ntw = square();
        let split = split_arcs(&ntw, Split::Distance(1.5)).unwrap();
        // The two long sides gain a vertex 1.5 along; the short ones are kept.
        assert_eq!(split.vertices.len(), 6);
        assert_eq!(split.vertices[4], [1.5, 0.0]);
        assert_eq!(split.arcs.len(), 6);
        let total: f64 = split.arc_lengths.iter().sum();
        assert!((total - 6.0).abs() < 1e-12);
        let halves = split_arcs(&ntw, Split::Count(2)).unwrap();
        assert_eq!(halves.arcs.len(), 8);
        assert!(split_arcs(&ntw, Split::Count(1)).is_err());
    }

    #[test]
    fn the_arcs_of_a_split_are_estimated_without_splitting() {
        // Arcs of length 2, 1, 2 and 1. Each arc that is cut is allowed one more piece than
        // its length gives, for the tiny last piece that rounding can leave.
        let ntw = square();
        for (split, arcs, estimate) in [
            (Split::Distance(0.5), 12, 16),
            (Split::Distance(1.5), 6, 8),
            (Split::Count(3), 12, 16),
            (Split::Count(2), 8, 12),
        ] {
            assert_eq!(split_arc_estimate(&ntw, split), Ok(estimate));
            assert_eq!(split_arcs(&ntw, split).unwrap().arcs.len() as u64, arcs);
        }
        // Arcs no longer than the distance stay whole, the arc as long as it included.
        assert_eq!(split_arc_estimate(&ntw, Split::Distance(2.0)), Ok(4));
        assert_eq!(split_arc_estimate(&ntw, Split::Distance(5.0)), Ok(4));
        // A tiny distance: 2 * 2^31 + 2 * 2^30 pieces and one more per arc, counted rather
        // than made.
        assert_eq!(
            split_arc_estimate(&ntw, Split::Distance(2f64.powi(-30))),
            Ok(6_442_450_948)
        );
        // It saturates instead of overflowing.
        assert_eq!(
            split_arc_estimate(&ntw, Split::Distance(f64::MIN_POSITIVE)),
            Ok(u64::MAX)
        );
    }

    #[test]
    fn a_split_that_ends_in_a_tiny_piece_is_within_the_estimate() {
        // A tenth of 1 added ten times is 0.9999999999999999, so the split ends in an eleventh
        // piece of about 1.1e-16, as spaghetti's does.
        let ntw = build(&[vec![[0.0, 0.0], [1.0, 0.0]]], Some(11)).unwrap();
        let split = split_arcs(&ntw, Split::Count(10)).unwrap();
        assert_eq!(split.arcs.len(), 11);
        assert!(split.arc_lengths.iter().any(|&l| l < 1e-15));
        assert_eq!(split_arc_estimate(&ntw, Split::Count(10)), Ok(11));
        assert!(check_split_size(&ntw, Split::Count(10), 10).is_err());
        assert_eq!(check_split_size(&ntw, Split::Count(10), 11), Ok(11));
    }

    /// SplitMix64: a fixed, seeded sequence, so the fuzz tests are reproducible.
    struct Rng(u64);

    impl Rng {
        fn next(&mut self) -> u64 {
            self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
            let mut z = self.0;
            z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
            z ^ (z >> 31)
        }

        /// Uniform in [0, 1).
        fn unit(&mut self) -> f64 {
            (self.next() >> 11) as f64 / (1u64 << 53) as f64
        }

        fn below(&mut self, n: u64) -> u64 {
            self.next() % n
        }
    }

    fn assert_within_estimate(ntw: &Network, split: Split, case: &str) {
        let estimate = split_arc_estimate(ntw, split).unwrap();
        let arcs = split_arcs(ntw, split).unwrap().arcs.len() as u64;
        assert!(
            arcs <= estimate,
            "{case}: {split:?} made {arcs} arcs, estimated {estimate}"
        );
        // A max_arcs of the estimate admits the split, and the split respects it.
        assert_eq!(check_split_size(ntw, split, estimate), Ok(estimate));
    }

    #[test]
    fn the_estimate_bounds_random_splits() {
        let mut rng = Rng(20_261_126);
        for case in 0..3000 {
            // Coordinates from 1e-6 to 1e6 wide, so the lengths have every kind of last bit.
            let scale = 10f64.powi(rng.below(13) as i32 - 6);
            let lines: Vec<Vec<[f64; 2]>> = (0..1 + rng.below(3))
                .map(|_| {
                    (0..2 + rng.below(3))
                        .map(|_| [rng.unit() * scale, rng.unit() * scale])
                        .collect()
                })
                .collect();
            let ntw = build(&lines, Some(11)).unwrap();
            let split = if rng.below(2) == 0 {
                Split::Count(2 + rng.below(60) as u32)
            } else {
                Split::Distance(scale * (0.005 + rng.unit()))
            };
            assert_within_estimate(&ntw, split, &format!("case {case}"));
        }
    }

    #[test]
    fn the_estimate_bounds_splits_that_fall_on_the_arc_end() {
        // Lengths that are whole numbers of pieces, where the accumulated pieces fall just
        // short of the arc or just past it.
        let unit = build(&[vec![[0.0, 0.0], [1.0, 0.0]]], Some(11)).unwrap();
        for c in 2..400 {
            assert_within_estimate(&unit, Split::Count(c), "unit arc");
        }
        let mut rng = Rng(7);
        for k in 1..300 {
            let d = [0.1, 0.3, 0.7, 1.1, 2.0f64.powi(-7) * 3.0][k % 5];
            let length = d * k as f64;
            let ntw = build(&[vec![[0.0, 0.0], [length, 0.0]]], None).unwrap();
            assert_within_estimate(&ntw, Split::Distance(d), &format!("{k} pieces of {d}"));
            // The same length along a slanted arc, whose points need the slope.
            let a = rng.unit() * std::f64::consts::FRAC_PI_2;
            let slanted = build(
                &[vec![[0.0, 0.0], [length * a.cos(), length * a.sin()]]],
                None,
            )
            .unwrap();
            assert_within_estimate(&slanted, Split::Distance(d), &format!("slanted {k}"));
            assert_within_estimate(&slanted, Split::Count(k as u32 + 1), "slanted count");
        }
        // Many pieces on one arc, where the rounding of the accumulated length grows (a few
        // thousand: the graph of a long chain takes time with the square of its arcs).
        for (length, d) in [(1.0, 3e-4), (1000.0, 0.3), (7.0, 7.0 / 2999.0)] {
            let ntw = build(&[vec![[0.0, 0.0], [length, 0.0]]], None).unwrap();
            assert_within_estimate(&ntw, Split::Distance(d), "long arc");
        }
    }

    #[test]
    fn pieces_shorter_than_the_smallest_normal_float_are_refused() {
        // 7 subnormal units split in 5: a piece of 1.4 units rounds to 1, which would make 7
        // pieces; split in 2, one unit rounds to a piece of 0, which would never end.
        let unit = f64::from_bits(1);
        for (length, c) in [(7.0 * unit, 5), (unit, 2)] {
            let ntw = build(&[vec![[0.0, 0.0], [length, 0.0]]], None).unwrap();
            assert_eq!(ntw.arc_lengths, vec![length]);
            let err = split_arc_estimate(&ntw, Split::Count(c)).unwrap_err();
            assert!(err.contains("shorter than"), "{err}");
        }
        // A subnormal split distance is fine: adding it up is exact.
        let ntw = build(&[vec![[0.0, 0.0], [3e-320, 0.0]]], None).unwrap();
        assert_within_estimate(&ntw, Split::Distance(1e-321), "subnormal distance");
    }

    #[test]
    fn max_arcs_is_checked_against_the_estimate_and_its_ceiling() {
        let ntw = square();
        assert_eq!(check_split_size(&ntw, Split::Distance(0.5), 16), Ok(16));
        let err = check_split_size(&ntw, Split::Distance(0.5), 15).unwrap_err();
        assert_eq!(
            err,
            "the split would make up to 16 arcs, above max_arcs (15)"
        );
        assert_eq!(
            check_split_size(&ntw, Split::Distance(0.5), MAX_SPLIT_ARCS),
            Ok(16)
        );
        let err = check_split_size(&ntw, Split::Distance(0.5), MAX_SPLIT_ARCS + 1).unwrap_err();
        assert!(err.contains("at most 67108864"), "{err}");
        // A split distance too small to add up (a piece below half an ulp of the length
        // covered so far) could never end; it is far above the ceiling.
        let ntw = build(&[vec![[0.0, 0.0], [1.0, 0.0]]], Some(11)).unwrap();
        let err =
            check_split_size(&ntw, Split::Distance(2f64.powi(-60)), MAX_SPLIT_ARCS).unwrap_err();
        assert!(err.contains("above max_arcs"), "{err}");
        assert!(check_split_size(&ntw, Split::Count(0), 10).is_err());
    }

    #[test]
    fn the_estimate_refuses_the_splits_split_arcs_refuses() {
        let ntw = square();
        for d in [0.0, -1.0, f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
            assert!(split_arc_estimate(&ntw, Split::Distance(d)).is_err());
            assert!(split_arcs(&ntw, Split::Distance(d)).is_err());
        }
        assert!(split_arc_estimate(&ntw, Split::Count(1)).is_err());
        assert!(split_arc_estimate(&ntw, Split::Count(0)).is_err());
    }

    #[test]
    fn components_are_extracted_and_renumbered() {
        let ntw = build(
            &[
                vec![[0.0, 0.0], [1.0, 0.0]],
                vec![[5.0, 5.0], [6.0, 5.0], [7.0, 5.0]],
            ],
            Some(11),
        )
        .unwrap();
        let (c, ids) = extract_component(&ntw, 1).unwrap();
        assert_eq!(ids, vec![2, 3, 4]);
        assert_eq!(c.arcs, vec![(0, 1), (1, 2)]);
        assert_eq!(c.components.n_components, 1);
        assert!(extract_component(&ntw, 2).is_err());
    }

    #[test]
    fn the_spanning_tree_drops_the_longest_arc_of_a_cycle() {
        let tree = spanning_tree(&square(), false).unwrap();
        assert_eq!(tree.arcs.len(), 3);
        assert_eq!(tree.arc_lengths.iter().sum::<f64>(), 4.0);
        let max = spanning_tree(&square(), true).unwrap();
        assert_eq!(max.arc_lengths.iter().sum::<f64>(), 5.0);
        // A tree stays as it is.
        assert_eq!(spanning_tree(&tree, false).unwrap(), tree);
    }
}
