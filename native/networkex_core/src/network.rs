// Portions of this file are derived from spaghetti 1.7.6 (https://github.com/pysal/spaghetti).
// Copyright 2017 PySAL-spaghetti Developers. Licensed under the BSD 3-Clause License, reproduced
// in LICENSES/BSD-3-Clause-spaghetti.txt; see NOTICE. Each derived function names its source.

//! Network construction after `spaghetti.Network`: vertices from line coordinates rounded to
//! `vertex_sig` significant digits, arcs between consecutive vertices, connected components and
//! the graph obtained by merging chains of degree-2 vertices.

use crate::hypot::hypot;
use crate::kfunction::total_length;
use std::collections::{BTreeMap, BTreeSet, HashMap};

/// An arc or graph edge: vertex ids, the smaller first.
pub type Link = (u32, u32);

/// Connected components of the links (arcs or graph edges), as spaghetti's `identify_components`.
#[derive(Clone, Debug, PartialEq)]
pub struct Components {
    pub n_components: usize,
    /// Component of each link, numbered by the first link of each component.
    pub labels: Vec<u32>,
    /// Total arc length per component (label order).
    pub lengths: Vec<f64>,
    /// The component with the largest length / the most vertices (the first on ties).
    pub longest: u32,
    pub largest: u32,
    /// Whether every vertex of the component has exactly two neighbours.
    pub is_ring: Vec<bool>,
}

/// The extracted graph (`spaghetti.Network.extractgraph`).
#[derive(Clone, Debug, PartialEq)]
pub struct Graph {
    pub edges: Vec<Link>,
    pub edge_lengths: Vec<f64>,
    pub non_articulation_points: Vec<u32>,
    pub arcs_to_edges: Vec<(Link, Link)>,
    pub components: Components,
}

/// A network.
#[derive(Clone, Debug, PartialEq)]
pub struct Network {
    /// Rounded coordinates by vertex id (ids in order of first appearance).
    pub vertices: Vec<[f64; 2]>,
    pub arcs: Vec<Link>,
    pub arc_lengths: Vec<f64>,
    /// Arc indices in order of first appearance in the input (the order of spaghetti's
    /// `arc_lengths`, along which simulated observations are drawn).
    pub arc_order: Vec<u32>,
    /// Neighbouring vertex ids of each vertex, ascending.
    pub adjacency: Vec<Vec<u32>>,
    pub components: Components,
    pub graph: Graph,
}

/// Python's `round(x, ndigits)`: the exact binary value rounded to `ndigits` decimals, ties to
/// even, read back as the nearest double. Negative `ndigits` round to tens, hundreds, ...
fn python_round(x: f64, ndigits: i32) -> f64 {
    if ndigits >= 0 {
        format!("{:.*}", ndigits as usize, x).parse().unwrap_or(x)
    } else {
        let p = 10f64.powi(-ndigits);
        (x / p).round_ties_even() * p
    }
}

// Derived from spaghetti 1.7.6: `Network._round_sig` (spaghetti/network.py).
/// spaghetti's `_round_sig`: each coordinate rounded to `sig` significant digits, then to `atol`
/// decimals (`vertex_atol`). Without `sig` the coordinates are kept as given, `atol` included.
fn round_vertex(v: [f64; 2], sig: Option<u32>, atol: Option<u32>) -> [f64; 2] {
    let Some(sig) = sig else { return v };
    v.map(|val| {
        let val = if val == 0.0 {
            val
        } else {
            let nd = -(val.abs().log10().floor() as i32) + (sig as i32 - 1);
            python_round(val, nd)
        };
        match atol {
            Some(atol) => python_round(val, atol as i32),
            None => val,
        }
    })
}

/// Hash key of a coordinate pair; `-0.0` equals `+0.0`, as Python's tuple keys.
pub(crate) fn key(v: [f64; 2]) -> (u64, u64) {
    let canon = |x: f64| if x == 0.0 { 0u64 } else { x.to_bits() };
    (canon(v[0]), canon(v[1]))
}

/// libpysal's `get_points_dist` (`math.hypot`): the split points depend on the last bit, so
/// this is CPython's algorithm, not the platform's libm (see `crate::hypot`).
fn distance(a: [f64; 2], b: [f64; 2]) -> f64 {
    hypot(a[0] - b[0], a[1] - b[1])
}

pub(crate) fn link(a: u32, b: u32) -> Link {
    if a <= b {
        (a, b)
    } else {
        (b, a)
    }
}

// Derived from spaghetti 1.7.6: the component attributes of `Network.identify_components`
// (spaghetti/network.py).
/// Components of `links` (two links touch when they share a vertex).
fn components(links: &[Link], lengths: &HashMap<Link, f64>, adjacency: &[Vec<u32>]) -> Components {
    let n = links.len();
    let mut parent: Vec<usize> = (0..n).collect();
    fn find(parent: &mut [usize], i: usize) -> usize {
        let mut r = i;
        while parent[r] != r {
            r = parent[r];
        }
        let mut c = i;
        while parent[c] != r {
            let next = parent[c];
            parent[c] = r;
            c = next;
        }
        r
    }
    let mut by_vertex: HashMap<u32, usize> = HashMap::new();
    for (i, &(a, b)) in links.iter().enumerate() {
        for v in [a, b] {
            match by_vertex.get(&v) {
                Some(&j) => {
                    let (ri, rj) = (find(&mut parent, i), find(&mut parent, j));
                    if ri != rj {
                        parent[ri.max(rj)] = ri.min(rj);
                    }
                }
                None => {
                    by_vertex.insert(v, i);
                }
            }
        }
    }
    // Labels in order of the first link of each component (scipy's connected_components order).
    let mut label_of_root: HashMap<usize, u32> = HashMap::new();
    let mut labels = Vec::with_capacity(n);
    for i in 0..n {
        let r = find(&mut parent, i);
        let next = label_of_root.len() as u32;
        labels.push(*label_of_root.entry(r).or_insert(next));
    }
    let k = label_of_root.len();
    let mut comp_lengths = vec![0.0; k];
    let mut comp_vertices: Vec<BTreeSet<u32>> = vec![BTreeSet::new(); k];
    for (i, l) in links.iter().enumerate() {
        let c = labels[i] as usize;
        // spaghetti sums the arc lengths of the component's links found among the arcs.
        if let Some(len) = lengths.get(l) {
            comp_lengths[c] += len;
        }
        comp_vertices[c].insert(l.0);
        comp_vertices[c].insert(l.1);
    }
    let first_max = |values: &[f64]| {
        let mut best = 0;
        for (i, &v) in values.iter().enumerate() {
            if v > values[best] {
                best = i;
            }
        }
        best as u32
    };
    let counts: Vec<f64> = comp_vertices.iter().map(|s| s.len() as f64).collect();
    Components {
        n_components: k,
        labels,
        longest: first_max(&comp_lengths),
        largest: first_max(&counts),
        is_ring: comp_vertices
            .iter()
            .map(|vs| vs.iter().all(|&v| adjacency[v as usize].len() == 2))
            .collect(),
        lengths: comp_lengths,
    }
}

/// Builds a network from polylines (each a list of `[x, y]`). Every polyline is one part: there
/// is no arc between the end of one and the start of the next.
pub fn build(lines: &[Vec<[f64; 2]>], vertex_sig: Option<u32>) -> Result<Network, String> {
    build_with(lines, vertex_sig, None)
}

// Derived from spaghetti 1.7.6: the vertex and arc loop of `Network._extractnetwork`
// (spaghetti/network.py).
/// `build` with spaghetti's `vertex_atol`: vertex coordinates are also rounded to that many
/// decimals after `vertex_sig`.
pub fn build_with(
    lines: &[Vec<[f64; 2]>],
    vertex_sig: Option<u32>,
    vertex_atol: Option<u32>,
) -> Result<Network, String> {
    let mut ids: HashMap<(u64, u64), u32> = HashMap::new();
    let mut vertices: Vec<[f64; 2]> = Vec::new();
    let mut adjacency: Vec<BTreeSet<u32>> = Vec::new();
    let mut arc_lengths: HashMap<Link, f64> = HashMap::new();
    let mut arcs: BTreeSet<Link> = BTreeSet::new();
    let mut first_seen: Vec<Link> = Vec::new();
    let mut id_of =
        |v: [f64; 2], vertices: &mut Vec<[f64; 2]>, adjacency: &mut Vec<BTreeSet<u32>>| {
            *ids.entry(key(v)).or_insert_with(|| {
                vertices.push(v);
                adjacency.push(BTreeSet::new());
                (vertices.len() - 1) as u32
            })
        };
    for line in lines {
        if line.iter().flatten().any(|c| !c.is_finite()) {
            return Err("line coordinates must be finite".to_string());
        }
        for pair in line.windows(2) {
            let v = round_vertex(pair[0], vertex_sig, vertex_atol);
            let vid = id_of(v, &mut vertices, &mut adjacency);
            let nvid = id_of(
                round_vertex(pair[1], vertex_sig, vertex_atol),
                &mut vertices,
                &mut adjacency,
            );
            adjacency[vid as usize].insert(nvid);
            adjacency[nvid as usize].insert(vid);
            let arc = link(vid, nvid);
            if arcs.insert(arc) {
                first_seen.push(arc);
            }
            // spaghetti measures from the rounded vertex to the unrounded next one.
            arc_lengths.insert(arc, distance(v, pair[1]));
        }
    }
    if arcs.is_empty() {
        return Err("a network needs at least one line with two vertices".to_string());
    }
    let adjacency: Vec<Vec<u32>> = adjacency
        .into_iter()
        .map(|s| s.into_iter().collect())
        .collect();
    assemble(
        vertices,
        arcs.into_iter().collect(),
        &arc_lengths,
        &first_seen,
        adjacency,
    )
}

/// A network from its parts: `arcs` sorted and unique, `arc_lengths` by arc, `order` the arcs in
/// spaghetti's `arc_lengths` order and `adjacency` ascending. Derives the components and the
/// graph. Refuses lengths that overflow a float (finite coordinates far apart, or arcs whose
/// lengths add up past `f64::MAX`), which no caller could use.
pub(crate) fn assemble(
    vertices: Vec<[f64; 2]>,
    arcs: Vec<Link>,
    arc_lengths: &HashMap<Link, f64>,
    order: &[Link],
    adjacency: Vec<Vec<u32>>,
) -> Result<Network, String> {
    if let Some(&(a, b)) = arcs.iter().find(|a| !arc_lengths[a].is_finite()) {
        return Err(format!(
            "the arc from {:?} to {:?} is too long: its length overflows a float",
            vertices[a as usize], vertices[b as usize]
        ));
    }
    let network_components = components(&arcs, arc_lengths, &adjacency);
    let graph = extract_graph(&arcs, arc_lengths, &adjacency, &network_components);
    let position: HashMap<Link, u32> = arcs
        .iter()
        .enumerate()
        .map(|(i, a)| (*a, i as u32))
        .collect();
    let ntw = Network {
        arc_order: order.iter().map(|a| position[a]).collect(),
        vertices,
        arc_lengths: arcs.iter().map(|a| arc_lengths[a]).collect(),
        arcs,
        adjacency,
        components: network_components,
        graph,
    };
    // Every length the network reports is a sum of arc lengths.
    let sums = [
        &ntw.components.lengths,
        &ntw.graph.edge_lengths,
        &ntw.graph.components.lengths,
    ];
    if !(total_length(&ntw).is_finite() && sums.iter().all(|s| s.iter().all(|l| l.is_finite()))) {
        return Err("the network is too long: its total length overflows a float".to_string());
    }
    Ok(ntw)
}

// Derived from spaghetti 1.7.6: `Network.extractgraph`, `_yield_napts`, `_evaluate_napts` and
// `_yieldneighbor` (spaghetti/network.py).
/// spaghetti's `extractgraph`: chains of degree-2 vertices (outside rings) become one edge.
fn extract_graph(
    arcs: &[Link],
    arc_lengths: &HashMap<Link, f64>,
    adjacency: &[Vec<u32>],
    comps: &Components,
) -> Graph {
    // Non-articulation points: degree-2 vertices of the components that are not rings.
    let mut napts: BTreeSet<u32> = BTreeSet::new();
    for (i, &(a, b)) in arcs.iter().enumerate() {
        if comps.is_ring[comps.labels[i] as usize] {
            continue;
        }
        for v in [a, b] {
            if adjacency[v as usize].len() == 2 {
                napts.insert(v);
            }
        }
    }
    let mut edges: Vec<Link> = arcs.to_vec();
    let mut lengths: BTreeMap<Link, f64> = arcs.iter().map(|a| (*a, arc_lengths[a])).collect();
    let mut arcs_to_edges: BTreeMap<Link, Link> = BTreeMap::new();
    let mut remaining: Vec<u32> = napts.iter().copied().collect();
    let mut idx = 0;
    while idx < remaining.len() {
        let s = remaining[idx];
        let mut bridge = vec![s];
        let mut stack: Vec<u32> = adjacency[s as usize]
            .iter()
            .copied()
            .filter(|n| remaining.contains(n) && !bridge.contains(n))
            .collect();
        while let Some(c) = stack.pop() {
            if bridge.contains(&c) {
                continue;
            }
            remaining.retain(|&v| v != c);
            bridge.push(c);
            for n in &adjacency[c as usize] {
                if remaining.contains(n) && !bridge.contains(n) {
                    stack.push(*n);
                }
            }
        }
        let (new_edge, merged): (Link, Vec<Link>) = if bridge.len() == 1 {
            let n = &adjacency[s as usize];
            (link(n[0], n[1]), vec![link(s, n[0]), link(s, n[1])])
        } else {
            let mut start_end: BTreeMap<u32, u32> = BTreeMap::new();
            let mut redundant: BTreeSet<Link> = BTreeSet::new();
            for &b in &bridge {
                for &n in &adjacency[b as usize] {
                    if bridge.contains(&n) {
                        redundant.insert(link(b, n));
                    } else {
                        start_end.insert(b, n);
                    }
                }
            }
            let ends: Vec<u32> = start_end.values().copied().collect();
            for (k, v) in &start_end {
                redundant.insert(link(*k, *v));
            }
            (
                link(ends[0], *ends.last().unwrap_or(&ends[0])),
                redundant.into_iter().collect(),
            )
        };
        let mut total = 0.0;
        for r in &merged {
            if let Some(pos) = edges.iter().position(|e| e == r) {
                edges.remove(pos);
            }
            total += lengths.remove(r).unwrap_or(0.0);
            arcs_to_edges.insert(*r, new_edge);
        }
        lengths.insert(new_edge, total);
        edges.push(new_edge);
        idx += 1;
    }
    let edges: Vec<Link> = edges
        .into_iter()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    let edge_lengths: HashMap<Link, f64> = lengths.into_iter().collect();
    let graph_components = components(&edges, arc_lengths, adjacency);
    Graph {
        edge_lengths: edges.iter().map(|e| edge_lengths[e]).collect(),
        edges,
        non_articulation_points: napts.into_iter().collect(),
        arcs_to_edges: arcs_to_edges.into_iter().collect(),
        components: graph_components,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn python_rounding_to_significant_digits() {
        assert_eq!(
            round_vertex([1.23456789012345, 9.87654321098765], Some(11), None),
            [1.2345678901, 9.876543211]
        );
        assert_eq!(
            round_vertex([0.000123456789, -4.5e-7], Some(4), None),
            [0.0001235, -4.5e-7]
        );
        assert_eq!(round_vertex([0.0, 2.5], Some(1), None), [0.0, 2.0]);
        assert_eq!(round_vertex([3.0, 4.0], None, None), [3.0, 4.0]);
    }

    #[test]
    fn a_path_with_a_degree_two_vertex_becomes_one_edge() {
        let ntw = build(&[vec![[0.0, 0.0], [1.0, 0.0], [3.0, 0.0]]], Some(11)).unwrap();
        assert_eq!(ntw.arcs, vec![(0, 1), (1, 2)]);
        assert_eq!(ntw.arc_lengths, vec![1.0, 2.0]);
        assert_eq!(ntw.graph.edges, vec![(0, 2)]);
        assert_eq!(ntw.graph.edge_lengths, vec![3.0]);
        assert_eq!(ntw.graph.non_articulation_points, vec![1]);
        assert_eq!(ntw.components.n_components, 1);
    }

    #[test]
    fn parts_are_not_joined_and_components_are_labelled_in_link_order() {
        let ntw = build(
            &[vec![[0.0, 0.0], [1.0, 0.0]], vec![[5.0, 5.0], [6.0, 5.0]]],
            Some(11),
        )
        .unwrap();
        assert_eq!(ntw.arcs, vec![(0, 1), (2, 3)]);
        assert_eq!(ntw.components.labels, vec![0, 1]);
        assert!(build(&[vec![[0.0, 0.0]]], Some(11)).is_err());
    }

    #[test]
    fn vertex_atol_rounds_after_sig_and_needs_it() {
        let lines = [vec![[1.00001, 0.0625], [2.0, 0.0]]];
        let ntw = build_with(&lines, Some(11), Some(3)).unwrap();
        // Ties go to even, as Python's round.
        assert_eq!(ntw.vertices[0], [1.0, 0.062]);
        let ntw = build_with(&lines, None, Some(3)).unwrap();
        assert_eq!(ntw.vertices[0], [1.00001, 0.0625]);
    }

    #[test]
    fn lengths_that_overflow_a_float_are_refused() {
        // Finite coordinates whose difference overflows: the arc has no finite length.
        let err = build(&[vec![[-1e308, 0.0], [1e308, 0.0]]], Some(11)).unwrap_err();
        assert!(err.contains("too long"), "{err}");
        // Finite arcs whose sum overflows, in one component and over two.
        for lines in [
            vec![vec![[-1e308, 0.0], [0.0, 0.0], [1e308, 0.0]]],
            vec![
                vec![[0.0, 0.0], [1e308, 0.0]],
                vec![[0.0, 1.0], [1e308, 1.0]],
            ],
        ] {
            let err = build(&lines, Some(11)).unwrap_err();
            assert!(err.contains("total length"), "{err}");
        }
        assert_eq!(
            build(&[vec![[0.0, 0.0], [1e308, 0.0]]], Some(11))
                .unwrap()
                .arc_lengths,
            vec![1e308]
        );
    }
}
