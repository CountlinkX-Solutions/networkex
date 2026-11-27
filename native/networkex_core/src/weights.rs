//! Network spatial weights and observation counts, after spaghetti's `contiguityweights`,
//! `distancebandweights` and `count_per_link`. Weights are `(focal, neighbor, weight)` triples
//! by link (or vertex) index, the layout of `Spatex.Graph.from_arrays/3`.

use crate::distances::Snapped;
use crate::network::{Link, Network};
use std::collections::HashMap;

/// Weights as parallel arrays.
#[derive(Clone, Debug, PartialEq)]
pub struct Weights {
    /// Number of observations (links or vertices); those without neighbours are islands.
    pub n: usize,
    pub focal: Vec<u32>,
    pub neighbor: Vec<u32>,
    pub weight: Vec<f64>,
}

/// Links touch when they share a vertex. `values` (one per link) weights each neighbour by its
/// own value: spaghetti's `weightings`, a dict by link, or the lengths for `weightings=True`.
/// Without `values` every weight is 1. Neighbours come in link order.
pub fn contiguity(links: &[Link], values: Option<&[f64]>) -> Weights {
    let mut by_vertex: HashMap<u32, Vec<usize>> = HashMap::new();
    for (i, &(a, b)) in links.iter().enumerate() {
        by_vertex.entry(a).or_default().push(i);
        if b != a {
            by_vertex.entry(b).or_default().push(i);
        }
    }
    let (mut focal, mut neighbor, mut weight) = (Vec::new(), Vec::new(), Vec::new());
    for (i, &(a, b)) in links.iter().enumerate() {
        let mut ns: Vec<usize> = by_vertex[&a]
            .iter()
            .chain(by_vertex.get(&b).into_iter().flatten())
            .copied()
            .filter(|&j| j != i)
            .collect();
        ns.sort_unstable();
        ns.dedup();
        for j in ns {
            focal.push(i as u32);
            neighbor.push(j as u32);
            weight.push(values.map_or(1.0, |v| v[j]));
        }
    }
    Weights {
        n: links.len(),
        focal,
        neighbor,
        weight,
    }
}

/// Vertices closer than `threshold` along the network (strictly), weight 1, in vertex order.
pub fn distance_band(ntw: &Network, threshold: f64) -> Weights {
    let n = ntw.vertices.len();
    let matrix = crate::distances::distance_matrix(ntw);
    let (mut focal, mut neighbor, mut weight) = (Vec::new(), Vec::new(), Vec::new());
    for i in 0..n {
        for j in 0..n {
            if i != j && matrix[i * n + j] < threshold {
                focal.push(i as u32);
                neighbor.push(j as u32);
                weight.push(1.0);
            }
        }
    }
    Weights {
        n,
        focal,
        neighbor,
        weight,
    }
}

/// Observations per arc (`graph = false`) or per graph edge, aligned with `ntw.arcs` or
/// `ntw.graph.edges` (zeros included, the vector spaghetti's `Moran` uses).
pub fn counts(ntw: &Network, observations: &[Snapped], graph: bool) -> Vec<u32> {
    let links: &[Link] = if graph { &ntw.graph.edges } else { &ntw.arcs };
    let index: HashMap<Link, usize> = links.iter().enumerate().map(|(i, l)| (*l, i)).collect();
    let to_edge: HashMap<Link, Link> = ntw.graph.arcs_to_edges.iter().copied().collect();
    let mut out = vec![0u32; links.len()];
    for o in observations {
        let key = if graph {
            *to_edge.get(&o.arc).unwrap_or(&o.arc)
        } else {
            o.arc
        };
        if let Some(&i) = index.get(&key) {
            out[i] += 1;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::network::build;

    #[test]
    fn contiguity_of_a_star() {
        // Three arcs meeting at (0, 0) and one further out.
        let ntw = build(
            &[
                vec![[0.0, 0.0], [1.0, 0.0], [2.0, 0.0]],
                vec![[0.0, 0.0], [0.0, 1.0]],
                vec![[0.0, 0.0], [-1.0, 0.0]],
            ],
            Some(11),
        )
        .unwrap();
        let w = contiguity(&ntw.arcs, None);
        assert_eq!(w.n, 4);
        // Arc (0,1) touches (0,3), (0,4) at vertex 0 and (1,2) at vertex 1.
        assert_eq!(w.focal.iter().filter(|&&f| f == 0).count(), 3);
        let lengths = contiguity(&ntw.arcs, Some(&ntw.arc_lengths));
        assert!(lengths.weight.iter().all(|&v| v == 1.0));
    }

    #[test]
    fn distance_band_is_strict() {
        let ntw = build(&[vec![[0.0, 0.0], [1.0, 0.0], [3.0, 0.0]]], Some(11)).unwrap();
        let w = distance_band(&ntw, 2.0);
        // 0-1 at 1 and 1-2 at 2: only the first pair is closer than 2.
        assert_eq!((w.focal, w.neighbor), (vec![0, 1], vec![1, 0]));
    }
}
