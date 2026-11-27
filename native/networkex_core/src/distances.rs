// Portions of this file are derived from spaghetti 1.7.6 (https://github.com/pysal/spaghetti).
// Copyright 2017 PySAL-spaghetti Developers. Licensed under the BSD 3-Clause License, reproduced
// in LICENSES/BSD-3-Clause-spaghetti.txt; see NOTICE. Each derived function names its source.

//! Snapping observations to a network and distances along it, after spaghetti's
//! `snapobservations`, `full_distance_matrix`, `allneighbordistances` and
//! `nearestneighbordistances`.

use crate::hypot::hypot;
use crate::network::{Link, Network};
use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap};

/// An observation snapped to the network.
#[derive(Clone, Debug, PartialEq)]
pub struct Snapped {
    pub arc: Link,
    pub point: [f64; 2],
    /// Distances from the snapped point to the arc's first and second vertex.
    pub to_vertices: (f64, f64),
    /// Distance from the observation to its snapped point.
    pub snap_distance: f64,
}

fn length(a: [f64; 2], b: [f64; 2]) -> f64 {
    hypot(a[0] - b[0], a[1] - b[1])
}

// Derived from spaghetti 1.7.6: `squared_distance_point_link` (spaghetti/util.py).
/// spaghetti's `squared_distance_point_link`: squared distance to the segment and the nearest
/// point on it.
fn point_link(p: [f64; 2], p0: [f64; 2], p1: [f64; 2]) -> (f64, [f64; 2]) {
    let v = [p1[0] - p0[0], p1[1] - p0[1]];
    let w = [p[0] - p0[0], p[1] - p0[1]];
    let c1 = w[0] * v[0] + w[1] * v[1];
    if c1 <= 0.0 {
        return (w[0] * w[0] + w[1] * w[1], p0);
    }
    let c2 = v[0] * v[0] + v[1] * v[1];
    if c2 <= c1 {
        let d = [p[0] - p1[0], p[1] - p1[1]];
        return (d[0] * d[0] + d[1] * d[1], p1);
    }
    let b = c1 / c2;
    let pb = [p0[0] + b * v[0], p0[1] + b * v[1]];
    let d = [p[0] - pb[0], p[1] - pb[1]];
    (d[0] * d[0] + d[1] * d[1], pb)
}

fn lexical(a: &[f64; 4], b: &[f64; 4]) -> Ordering {
    a.iter()
        .zip(b)
        .map(|(x, y)| x.total_cmp(y))
        .find(|o| *o != Ordering::Equal)
        .unwrap_or(Ordering::Equal)
}

/// Snaps `points` to the nearest point of their nearest arc. Ties go to the arc with the
/// smallest `(head, tail)` coordinates, which is the arc spaghetti's descending scan keeps.
pub fn snap(ntw: &Network, points: &[[f64; 2]]) -> Vec<Snapped> {
    points
        .iter()
        .map(|&p| {
            let mut best: Option<(f64, [f64; 4], Link, [f64; 2])> = None;
            for &arc in &ntw.arcs {
                let (h, t) = (ntw.vertices[arc.0 as usize], ntw.vertices[arc.1 as usize]);
                let (d2, near) = point_link(p, h, t);
                let key = [h[0], h[1], t[0], t[1]];
                let better = match &best {
                    None => true,
                    Some((bd, bk, _, _)) => {
                        d2 < *bd || (d2 == *bd && lexical(&key, bk) == Ordering::Less)
                    }
                };
                if better {
                    best = Some((d2, key, arc, near));
                }
            }
            let (_, _, arc, near) = best.expect("a network has at least one arc");
            Snapped {
                arc,
                point: near,
                to_vertices: (
                    length(near, ntw.vertices[arc.0 as usize]),
                    length(near, ntw.vertices[arc.1 as usize]),
                ),
                snap_distance: length(p, near),
            }
        })
        .collect()
}

#[derive(PartialEq)]
struct State(f64, u32);
impl Eq for State {}
impl Ord for State {
    fn cmp(&self, other: &Self) -> Ordering {
        other
            .0
            .total_cmp(&self.0)
            .then_with(|| other.1.cmp(&self.1))
    }
}
impl PartialOrd for State {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// Neighbour lists with arc lengths.
fn weighted_adjacency(ntw: &Network) -> Vec<Vec<(u32, f64)>> {
    let mut adj = vec![Vec::new(); ntw.vertices.len()];
    for (arc, len) in ntw.arcs.iter().zip(&ntw.arc_lengths) {
        adj[arc.0 as usize].push((arc.1, *len));
        if arc.0 != arc.1 {
            adj[arc.1 as usize].push((arc.0, *len));
        }
    }
    adj
}

/// Shortest-path distances from `source` to every vertex (`INFINITY` when unreachable).
fn dijkstra(adj: &[Vec<(u32, f64)>], source: u32) -> Vec<f64> {
    dijkstra_tree(adj, source).0
}

/// Distances and the predecessor of each vertex on its shortest path from `source` (`None` for
/// the source and unreachable vertices). Of two equally short routes the first found is kept;
/// vertices at the same distance are settled by id.
fn dijkstra_tree(adj: &[Vec<(u32, f64)>], source: u32) -> (Vec<f64>, Vec<Option<u32>>) {
    let mut dist = vec![f64::INFINITY; adj.len()];
    let mut pred = vec![None; adj.len()];
    dist[source as usize] = 0.0;
    let mut heap = BinaryHeap::new();
    heap.push(State(0.0, source));
    while let Some(State(d, v)) = heap.pop() {
        if d > dist[v as usize] {
            continue;
        }
        for &(w, len) in &adj[v as usize] {
            let nd = d + len;
            if nd < dist[w as usize] {
                dist[w as usize] = nd;
                pred[w as usize] = Some(v);
                heap.push(State(nd, w));
            }
        }
    }
    (dist, pred)
}

/// The full vertex-to-vertex distance matrix (row-major).
pub fn distance_matrix(ntw: &Network) -> Vec<f64> {
    let adj = weighted_adjacency(ntw);
    (0..ntw.vertices.len() as u32)
        .flat_map(|v| dijkstra(&adj, v))
        .collect()
}

// Derived from spaghetti 1.7.6: `Network.allneighbordistances` (spaghetti/network.py).
/// Network distances between every source and destination observation, row-major. Without
/// `dest` the pattern is measured against itself and the diagonal gets `diagonal` (NaN by
/// default in spaghetti). With `snap_dist` the snapping distances are added (not on a shared
/// arc, as in spaghetti).
pub fn all_neighbor_distances(
    ntw: &Network,
    source: &[Snapped],
    dest: Option<&[Snapped]>,
    snap_dist: bool,
    diagonal: f64,
) -> Vec<f64> {
    let adj = weighted_adjacency(ntw);
    let mut rows: HashMap<u32, Vec<f64>> = HashMap::new();
    for s in source {
        for v in [s.arc.0, s.arc.1] {
            rows.entry(v).or_insert_with(|| dijkstra(&adj, v));
        }
    }
    let symmetric = dest.is_none();
    let dest = dest.unwrap_or(source);
    let ends = |o: &Snapped| {
        let extra = if snap_dist { o.snap_distance } else { 0.0 };
        (o.to_vertices.0 + extra, o.to_vertices.1 + extra)
    };
    let (ns, nd) = (source.len(), dest.len());
    let mut out = vec![f64::INFINITY; ns * nd];
    for (i, s) in source.iter().enumerate() {
        let (sd1, sd2) = ends(s);
        let start = if symmetric { i + 1 } else { 0 };
        for (j, t) in dest.iter().enumerate().skip(start) {
            let value = if (s.arc.0 == t.arc.0 && s.arc.1 == t.arc.1)
                || (s.arc.0 == t.arc.1 && s.arc.1 == t.arc.0)
            {
                length(s.point, t.point)
            } else {
                let (dd1, dd2) = ends(t);
                let (r1, r2) = (&rows[&s.arc.0], &rows[&s.arc.1]);
                let (d11, d21) = (r1[t.arc.0 as usize], r2[t.arc.0 as usize]);
                let (d12, d22) = (r1[t.arc.1 as usize], r2[t.arc.1 as usize]);
                let len_1 = (d11 + sd1).min(d21 + sd2) + dd1;
                let len_2 = (d12 + sd1).min(d22 + sd2) + dd2;
                if len_1 > len_2 {
                    len_2
                } else {
                    len_1
                }
            };
            out[i * nd + j] = value;
            if symmetric {
                out[j * nd + i] = value;
            }
        }
        if symmetric {
            out[i * nd + i] = diagonal;
        }
    }
    out
}

/// A shortest path between two observations.
#[derive(Clone, Debug, PartialEq)]
pub struct Path {
    /// Source and destination observation.
    pub pair: (u32, u32),
    /// The vertices of the source's and the destination's arcs the path leaves and enters by;
    /// `None` when both lie on the same arc.
    pub via: Option<(u32, u32)>,
    /// The snapped source, the vertices passed through and the snapped destination.
    pub path: Vec<[f64; 2]>,
}

// Derived from spaghetti 1.7.6: `Network.shortest_paths` (spaghetti/network.py).
/// spaghetti's removal of repeated vertices where two arcs of a path join: it walks the list
/// while removing from it, and removes the first occurrence of a repeated vertex.
fn drop_joints(mut v: Vec<[f64; 2]>) -> Vec<[f64; 2]> {
    let mut i = 0;
    while i < v.len() {
        if i + 1 < v.len() && v[i] == v[i + 1] {
            let first = v.iter().position(|p| *p == v[i]).expect("present");
            v.remove(first);
        }
        i += 1;
    }
    v
}

// Derived from spaghetti 1.7.6: `Network.allneighbordistances` with `gen_tree=True`
// (spaghetti/network.py).
/// The shortest paths between observations, after spaghetti's
/// `allneighbordistances(gen_tree=True)` and `shortest_paths`: every pair `i < j` of `source`
/// without `dest`, otherwise every source with every destination, in that order.
pub fn shortest_paths(ntw: &Network, source: &[Snapped], dest: Option<&[Snapped]>) -> Vec<Path> {
    let adj = weighted_adjacency(ntw);
    let mut trees: HashMap<u32, (Vec<f64>, Vec<Option<u32>>)> = HashMap::new();
    for s in source {
        for v in [s.arc.0, s.arc.1] {
            trees.entry(v).or_insert_with(|| dijkstra_tree(&adj, v));
        }
    }
    let symmetric = dest.is_none();
    let dest = dest.unwrap_or(source);
    let mut out = Vec::new();
    for (i, s) in source.iter().enumerate() {
        let start = if symmetric { i + 1 } else { 0 };
        for (j, t) in dest.iter().enumerate().skip(start) {
            let pair = (i as u32, j as u32);
            let same = (s.arc.0 == t.arc.0 && s.arc.1 == t.arc.1)
                || (s.arc.0 == t.arc.1 && s.arc.1 == t.arc.0);
            if same {
                out.push(Path {
                    pair,
                    via: None,
                    path: vec![s.point, t.point],
                });
                continue;
            }
            let (r1, r2) = (&trees[&s.arc.0].0, &trees[&s.arc.1].0);
            let (sd1, sd2) = s.to_vertices;
            let (dd1, dd2) = t.to_vertices;
            let pick = |dv: u32| {
                let (a, b) = (r1[dv as usize] + sd1, r2[dv as usize] + sd2);
                if a > b {
                    (b, s.arc.1)
                } else {
                    (a, s.arc.0)
                }
            };
            let (sd_1, sv1) = pick(t.arc.0);
            let (sd_2, sv2) = pick(t.arc.1);
            let via = if sd_1 + dd1 > sd_2 + dd2 {
                (sv2, t.arc.1)
            } else {
                (sv1, t.arc.0)
            };
            out.push(Path {
                pair,
                via: Some(via),
                path: route(ntw, &trees[&via.0].1, via, s.point, t.point),
            });
        }
    }
    out
}

// Derived from spaghetti 1.7.6: `Network.shortest_paths` (spaghetti/network.py).
/// The coordinates of a path through `via` (spaghetti's `generatetree` walk): the vertices from
/// the source vertex to the destination vertex, each arc as its two end points with the repeated
/// joints dropped, between the snapped observations.
fn route(
    ntw: &Network,
    pred: &[Option<u32>],
    (sv, dv): (u32, u32),
    from: [f64; 2],
    to: [f64; 2],
) -> Vec<[f64; 2]> {
    let mut back = Vec::new();
    let mut v = pred[dv as usize];
    while let Some(p) = v {
        back.push(p);
        v = pred[p as usize];
    }
    let mut nodes: Vec<u32> = if back.is_empty() { vec![dv] } else { back };
    nodes.reverse();
    nodes.push(dv);
    debug_assert!(nodes[0] == sv || pred[dv as usize].is_none());
    let joints: Vec<[f64; 2]> = nodes
        .windows(2)
        .flat_map(|w| [ntw.vertices[w[0] as usize], ntw.vertices[w[1] as usize]])
        .collect();
    let mut path = vec![from];
    path.extend(drop_joints(joints));
    path.push(to);
    path
}

/// Nearest destination(s) and the distance of each source row of `distances` (`n_dest` columns):
/// the minimum ignoring NaN, or with `nonzero` the minimum of the non-zero entries (spaghetti's
/// `keep_zero_dist`).
pub fn nearest(distances: &[f64], n_dest: usize, nonzero: bool) -> Vec<(Vec<u32>, f64)> {
    distances
        .chunks(n_dest.max(1))
        .map(|row| {
            let kept = row
                .iter()
                .copied()
                .filter(|v| !v.is_nan() && (!nonzero || *v != 0.0));
            let min = kept.fold(f64::NAN, |m, v| if m.is_nan() || v < m { v } else { m });
            let idx = row
                .iter()
                .enumerate()
                .filter(|(_, v)| **v == min)
                .map(|(j, _)| j as u32)
                .collect();
            (idx, min)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::network::build;

    fn square() -> Network {
        build(
            &[vec![
                [0.0, 0.0],
                [4.0, 0.0],
                [4.0, 3.0],
                [0.0, 3.0],
                [0.0, 0.0],
            ]],
            Some(11),
        )
        .unwrap()
    }

    #[test]
    fn snapping_projects_onto_the_nearest_arc() {
        let ntw = square();
        let s = snap(&ntw, &[[1.0, -0.5], [4.5, 1.0]]);
        assert_eq!(s[0].point, [1.0, 0.0]);
        assert_eq!(s[0].to_vertices, (1.0, 3.0));
        assert_eq!(s[0].snap_distance, 0.5);
        assert_eq!(s[1].point, [4.0, 1.0]);
    }

    #[test]
    fn paths_follow_the_shortest_route() {
        let ntw = square();
        let s = snap(&ntw, &[[1.0, 0.0], [1.0, 3.0], [3.0, 0.0]]);
        let paths = shortest_paths(&ntw, &s, None);
        assert_eq!(paths.len(), 3);
        // (1,0) to (1,3): back to (0,0), up to (0,3) and along the top.
        assert_eq!(
            paths[0].path,
            vec![[1.0, 0.0], [0.0, 0.0], [0.0, 3.0], [1.0, 3.0]]
        );
        // Two observations on the bottom arc: straight along it.
        assert_eq!((paths[1].via, paths[1].path.len()), (None, 2));
    }

    #[test]
    fn repeated_joints_are_dropped_as_spaghetti_does() {
        let (a, b, c) = ([0.0, 0.0], [1.0, 0.0], [2.0, 0.0]);
        assert_eq!(drop_joints(vec![a, b, b, c]), vec![a, b, c]);
        assert_eq!(drop_joints(vec![a, a]), vec![a]);
    }

    #[test]
    fn distances_go_around_the_network() {
        let ntw = square();
        let s = snap(&ntw, &[[1.0, 0.0], [1.0, 3.0]]);
        let d = all_neighbor_distances(&ntw, &s, None, false, f64::NAN);
        // Along the bottom to (0,0), up 3, then 1 along the top: 5; around the other side 9.
        assert_eq!(d[1], 5.0);
        assert!(d[0].is_nan());
        let near = nearest(&d, 2, false);
        assert_eq!(near[0], (vec![1], 5.0));
    }
}
