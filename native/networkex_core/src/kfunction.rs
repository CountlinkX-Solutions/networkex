// Portions of this file are derived from spaghetti 1.7.6 (https://github.com/pysal/spaghetti).
// Copyright 2017 PySAL-spaghetti Developers. Licensed under the BSD 3-Clause License, reproduced
// in LICENSES/BSD-3-Clause-spaghetti.txt; see NOTICE. Each derived function names its source.

//! Simulated observations and the global auto K-function, after spaghetti's
//! `simulate_observations` and `GlobalAutoK`. The random positions along the network are an
//! input, so that a simulation can be replayed exactly; the caller draws them.

use crate::distances::{all_neighbor_distances, Snapped};
use crate::network::{Link, Network};

/// The network length, summed in the order simulated observations are drawn along.
pub fn total_length(ntw: &Network) -> f64 {
    ntw.arc_order
        .iter()
        .map(|&i| ntw.arc_lengths[i as usize])
        .sum()
}

// Derived from spaghetti 1.7.6: `Network._newpoint_coords` (spaghetti/network.py).
/// spaghetti's `_newpoint_coords`: the point `distance` along the arc. On a vertical arc the
/// distance runs from the lower vertex, as in spaghetti, whichever vertex comes first.
pub(crate) fn point_along(ntw: &Network, arc: Link, distance: f64) -> [f64; 2] {
    let [x1, y1] = ntw.vertices[arc.0 as usize];
    let [x2, y2] = ntw.vertices[arc.1 as usize];
    if x1 == x2 {
        let y0 = if y1 < y2 {
            y1 + distance
        } else if y1 > y2 {
            y2 + distance
        } else {
            y1
        };
        return [x1, y0];
    }
    let m = (y2 - y1) / (x2 - x1);
    let x0 = if x1 > x2 {
        x1 - distance / (1.0 + m * m).sqrt()
    } else {
        x1 + distance / (1.0 + m * m).sqrt()
    };
    [x0, m * (x0 - x1) + y1]
}

// Derived from spaghetti 1.7.6: `Network.simulate_observations` (spaghetti/network.py).
/// Observations at `positions` along the network (each in `[0, total_length]`), with the arcs
/// laid end to end in the order of first appearance. As in spaghetti the distance to the arc's
/// first vertex is measured back from the end of the arc's stretch.
pub fn simulate(ntw: &Network, positions: &[f64]) -> Result<Vec<Snapped>, String> {
    let mut stops = Vec::with_capacity(ntw.arc_order.len());
    let mut acc = 0.0;
    for &i in &ntw.arc_order {
        acc += ntw.arc_lengths[i as usize];
        stops.push(acc);
    }
    positions
        .iter()
        .map(|&r| {
            if !(r.is_finite() && r >= 0.0 && r <= acc) {
                return Err(format!("positions must lie in [0, {acc}], got {r}"));
            }
            // `r == total` can only come from rounding a draw just below it: the last arc.
            let idx = stops.partition_point(|&s| s <= r).min(stops.len() - 1);
            let k = ntw.arc_order[idx] as usize;
            let arc = ntw.arcs[k];
            let from_start = stops[idx] - r;
            Ok(Snapped {
                arc,
                point: point_along(ntw, arc, from_start),
                to_vertices: (from_start, ntw.arc_lengths[k] - from_start),
                snap_distance: 0.0,
            })
        })
        .collect()
}

/// numpy's `linspace(0, stop, num)`.
fn linspace(stop: f64, num: usize) -> Vec<f64> {
    if num == 1 {
        return vec![0.0];
    }
    let step = stop / (num - 1) as f64;
    let mut x: Vec<f64> = (0..num).map(|i| i as f64 * step).collect();
    if let Some(last) = x.last_mut() {
        *last = stop;
    }
    x
}

/// The pairwise distances of a pattern, upper triangle row by row.
fn pair_distances(ntw: &Network, pattern: &[Snapped]) -> Vec<f64> {
    let n = pattern.len();
    let full = all_neighbor_distances(ntw, pattern, None, false, f64::NAN);
    (0..n)
        .flat_map(|i| ((i + 1)..n).map(move |j| (i, j)))
        .map(|(i, j)| full[i * n + j])
        .collect()
}

// Derived from spaghetti 1.7.6: `global_auto_k` (spaghetti/analysis.py).
/// spaghetti's `global_auto_k`: twice the pairs closer than each step, over `n * intensity`.
fn curve(n: usize, distances: &[f64], x: &[f64], intensity: f64) -> Vec<f64> {
    let denominator = n as f64 * intensity;
    x.iter()
        .map(|&r| distances.iter().filter(|&&d| d < r).count() as f64 * 2.0 / denominator)
        .collect()
}

/// A global auto K-function and its simulation envelope.
#[derive(Clone, Debug, PartialEq)]
pub struct KFunction {
    /// Observations per unit of network length.
    pub intensity: f64,
    pub upperbound: f64,
    pub xaxis: Vec<f64>,
    pub observed: Vec<f64>,
    /// One curve per simulation.
    pub simulated: Vec<Vec<f64>>,
    pub upper_envelope: Vec<f64>,
    pub lower_envelope: Vec<f64>,
}

fn nan_fold(values: impl Iterator<Item = f64>, pick: fn(f64, f64) -> f64) -> f64 {
    values
        .filter(|v| !v.is_nan())
        .fold(f64::NAN, |m, v| if m.is_nan() { v } else { pick(m, v) })
}

// Derived from spaghetti 1.7.6: `GlobalAutoK.computeobserved` and `computepermutations`,
// `FuncBase.setbounds` and `computeenvelope` (spaghetti/analysis.py).
/// The K-function of `pattern` at `nsteps` distances from 0 to `upperbound` (by default the
/// largest distance between two observations), with one simulated curve per entry of
/// `simulations` (positions as in `simulate`, one per observation). The envelope is spaghetti's:
/// the largest simulated value times `1 - threshold / 2` and the smallest times `threshold / 2`.
pub fn global_auto_k(
    ntw: &Network,
    pattern: &[Snapped],
    nsteps: usize,
    upperbound: Option<f64>,
    threshold: f64,
    simulations: &[Vec<f64>],
) -> Result<KFunction, String> {
    let n = pattern.len();
    if n < 2 {
        return Err("the K-function needs at least 2 observations".to_string());
    }
    if nsteps == 0 || simulations.is_empty() {
        return Err("the K-function needs at least one step and one simulation".to_string());
    }
    let distances = pair_distances(ntw, pattern);
    let upperbound = upperbound.unwrap_or_else(|| nan_fold(distances.iter().copied(), f64::max));
    let intensity = n as f64 / total_length(ntw);
    let xaxis = linspace(upperbound, nsteps);
    let observed = curve(n, &distances, &xaxis, intensity);
    let simulated = simulations
        .iter()
        .map(|positions| {
            if positions.len() != n {
                return Err(format!("every simulation needs {n} positions"));
            }
            let sim = simulate(ntw, positions)?;
            Ok(curve(n, &pair_distances(ntw, &sim), &xaxis, intensity))
        })
        .collect::<Result<Vec<_>, String>>()?;
    let column =
        |k: usize, pick: fn(f64, f64) -> f64| nan_fold(simulated.iter().map(|c| c[k]), pick);
    Ok(KFunction {
        intensity,
        upperbound,
        upper_envelope: (0..nsteps)
            .map(|k| column(k, f64::max) * (1.0 - threshold / 2.0))
            .collect(),
        lower_envelope: (0..nsteps)
            .map(|k| column(k, f64::min) * (threshold / 2.0))
            .collect(),
        xaxis,
        observed,
        simulated,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::network::build;

    fn line() -> Network {
        build(&[vec![[0.0, 0.0], [4.0, 0.0], [4.0, 3.0]]], Some(11)).unwrap()
    }

    #[test]
    fn positions_run_along_the_arcs_in_order() {
        let ntw = line();
        assert_eq!(total_length(&ntw), 7.0);
        let s = simulate(&ntw, &[1.0, 5.0, 7.0]).unwrap();
        // 1 into the first arc is 3 back from its end; 5 is 1 into the vertical arc, 2 from its
        // end, measured up from the lower vertex.
        assert_eq!(
            (s[0].arc, s[0].point, s[0].to_vertices),
            ((0, 1), [3.0, 0.0], (3.0, 1.0))
        );
        assert_eq!(
            (s[1].arc, s[1].point, s[1].to_vertices),
            ((1, 2), [4.0, 2.0], (2.0, 1.0))
        );
        assert_eq!(s[2].to_vertices, (0.0, 3.0));
        assert!(simulate(&ntw, &[7.5]).is_err());
    }

    #[test]
    fn k_counts_pairs_closer_than_each_step() {
        let ntw = line();
        let pattern = simulate(&ntw, &[0.5, 1.5, 6.5]).unwrap();
        let k = global_auto_k(&ntw, &pattern, 3, None, 0.5, &[vec![0.5, 1.5, 6.5]]).unwrap();
        // The points sit at x = 3.5 and 2.5 on the first arc and 0.5 up the second: pair
        // distances 1, 1 and 2, so the bound is 2 and the steps 0, 1 and 2.
        assert_eq!(k.xaxis, vec![0.0, 1.0, 2.0]);
        let unit = 2.0 / (3.0 * (3.0 / 7.0));
        assert_eq!(k.observed, vec![0.0, 0.0, 2.0 * unit]);
        assert_eq!(k.upper_envelope[2], 2.0 * unit * 0.75);
        assert_eq!(k.lower_envelope[2], 2.0 * unit * 0.25);
    }
}
