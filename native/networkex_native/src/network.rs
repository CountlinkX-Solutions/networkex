//! Network construction NIFs.

use networkex_core::network::{self, Components, Link, Network};
use rustler::{Binary, Env, OwnedBinary, ResourceArc};

/// A built network held in Rust memory for later queries.
pub struct NetworkResource(pub(crate) Network);

#[rustler::resource_impl]
impl rustler::Resource for NetworkResource {}

pub(crate) fn f64_binary<'a>(env: Env<'a>, values: &[f64]) -> Binary<'a> {
    let mut owned = OwnedBinary::new(values.len() * 8);
    let (slots, _) = owned.as_mut_slice().as_chunks_mut::<8>();
    for (slot, value) in slots.iter_mut().zip(values) {
        *slot = value.to_ne_bytes();
    }
    owned.release(env)
}

type ComponentsTerm = (usize, Vec<u32>, Vec<f64>, u32, u32, Vec<bool>);

fn components_term(c: &Components) -> ComponentsTerm {
    (
        c.n_components,
        c.labels.clone(),
        c.lengths.clone(),
        c.longest,
        c.largest,
        c.is_ring.clone(),
    )
}

type GraphTerm = (
    Vec<Link>,
    Vec<f64>,
    Vec<u32>,
    Vec<(Link, Link)>,
    ComponentsTerm,
);

type NetworkTerm<'a> = (
    ResourceArc<NetworkResource>,
    Binary<'a>,
    Vec<Link>,
    Vec<f64>,
    Vec<Vec<u32>>,
    ComponentsTerm,
    GraphTerm,
);

fn term<'a>(env: Env<'a>, ntw: Network) -> NetworkTerm<'a> {
    let flat: Vec<f64> = ntw.vertices.iter().flatten().copied().collect();
    let g = &ntw.graph;
    let graph = (
        g.edges.clone(),
        g.edge_lengths.clone(),
        g.non_articulation_points.clone(),
        g.arcs_to_edges.clone(),
        components_term(&g.components),
    );
    (
        ResourceArc::new(NetworkResource(ntw.clone())),
        f64_binary(env, &flat),
        ntw.arcs.clone(),
        ntw.arc_lengths.clone(),
        ntw.adjacency.clone(),
        components_term(&ntw.components),
        graph,
    )
}

/// A positive count, or `None` for 0 (the Elixir side sends 0 for `nil`).
fn positive(value: i64) -> Option<u32> {
    u32::try_from(value).ok().filter(|v| *v > 0)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn network_from_coords<'a>(
    env: Env<'a>,
    coords: Binary,
    offsets: Binary,
    vertex_sig: i64,
    vertex_atol: i64,
) -> Result<NetworkTerm<'a>, String> {
    let coords = networkex_core::bytes_to_f64s(coords.as_slice())?;
    let offsets = networkex_core::bytes_to_u32s(offsets.as_slice())?;
    let lines = networkex_core::lines::from_offsets(&coords, &offsets)?;
    let ntw = network::build_with(&lines, positive(vertex_sig), positive(vertex_atol))?;
    Ok(term(env, ntw))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn network_from_wkb<'a>(
    env: Env<'a>,
    wkbs: Vec<Binary>,
    vertex_sig: i64,
    vertex_atol: i64,
) -> Result<NetworkTerm<'a>, String> {
    let slices: Vec<&[u8]> = wkbs.iter().map(|b| b.as_slice()).collect();
    let lines = networkex_core::lines::from_wkb(&slices)?;
    let ntw = network::build_with(&lines, positive(vertex_sig), positive(vertex_atol))?;
    Ok(term(env, ntw))
}

// -- observations and distances ----------------------------------------------------------------

use networkex_core::distances::{self, Snapped};

/// A snapped pattern on the wire: arcs, snapped points, distances to the two vertices and
/// snapping distances.
type PatternTerm<'a> = (Vec<Link>, Binary<'a>, Binary<'a>, Binary<'a>);

fn decode_pattern(p: &PatternTerm) -> Result<Vec<Snapped>, String> {
    let points = networkex_core::bytes_to_f64s(p.1.as_slice())?;
    let to_v = networkex_core::bytes_to_f64s(p.2.as_slice())?;
    let snap_d = networkex_core::bytes_to_f64s(p.3.as_slice())?;
    let n = p.0.len();
    if points.len() != 2 * n || to_v.len() != 2 * n || snap_d.len() != n {
        return Err("inconsistent point pattern".to_string());
    }
    Ok((0..n)
        .map(|i| Snapped {
            arc: p.0[i],
            point: [points[2 * i], points[2 * i + 1]],
            to_vertices: (to_v[2 * i], to_v[2 * i + 1]),
            snap_distance: snap_d[i],
        })
        .collect())
}

fn pattern_term<'a>(env: Env<'a>, s: &[Snapped]) -> PatternTerm<'a> {
    let snapped: Vec<f64> = s.iter().flat_map(|o| o.point).collect();
    let to_v: Vec<f64> = s
        .iter()
        .flat_map(|o| [o.to_vertices.0, o.to_vertices.1])
        .collect();
    let snap_d: Vec<f64> = s.iter().map(|o| o.snap_distance).collect();
    (
        s.iter().map(|o| o.arc).collect(),
        f64_binary(env, &snapped),
        f64_binary(env, &to_v),
        f64_binary(env, &snap_d),
    )
}

#[rustler::nif(schedule = "DirtyCpu")]
fn network_snap<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    points: Binary,
) -> Result<PatternTerm<'a>, String> {
    let flat = networkex_core::bytes_to_f64s(points.as_slice())?;
    let pts: Vec<[f64; 2]> = flat.as_chunks::<2>().0.to_vec();
    Ok(pattern_term(env, &distances::snap(&resource.0, &pts)))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn network_distance_matrix<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    max_cells: u64,
) -> Result<Binary<'a>, String> {
    let n = resource.0.vertices.len() as u64;
    if n.saturating_mul(n) > max_cells {
        return Err(format!(
            "the distance matrix would have {} cells, above max_cells ({max_cells})",
            n.saturating_mul(n)
        ));
    }
    Ok(f64_binary(env, &distances::distance_matrix(&resource.0)))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn network_all_neighbors<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    source: PatternTerm,
    dest: Option<PatternTerm>,
    snap_dist: bool,
    diagonal: Option<f64>,
) -> Result<Binary<'a>, String> {
    let diagonal = diagonal.unwrap_or(f64::NAN);
    let src = decode_pattern(&source)?;
    let dst = dest.as_ref().map(decode_pattern).transpose()?;
    let d =
        distances::all_neighbor_distances(&resource.0, &src, dst.as_deref(), snap_dist, diagonal);
    Ok(f64_binary(env, &d))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn network_nearest<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    source: PatternTerm,
    dest: Option<PatternTerm>,
    snap_dist: bool,
    keep_zero_dist: bool,
) -> Result<(Vec<Vec<u32>>, Binary<'a>), String> {
    let src = decode_pattern(&source)?;
    let dst = dest.as_ref().map(decode_pattern).transpose()?;
    // spaghetti fills the diagonal with 0 when zero distances are not kept, NaN otherwise.
    let diagonal = if keep_zero_dist { f64::NAN } else { 0.0 };
    let n_dest = dst.as_ref().map_or(src.len(), Vec::len);
    let d =
        distances::all_neighbor_distances(&resource.0, &src, dst.as_deref(), snap_dist, diagonal);
    // Distances travel as an f64 binary: they may be infinite or NaN.
    let (idx, dist): (Vec<Vec<u32>>, Vec<f64>) = distances::nearest(&d, n_dest, !keep_zero_dist)
        .into_iter()
        .unzip();
    Ok((idx, f64_binary(env, &dist)))
}

// -- weights and counts --------------------------------------------------------------------------

use networkex_core::weights::{self, Weights};

type WeightsTerm<'a> = (usize, Vec<u32>, Vec<u32>, Binary<'a>);

fn weights_term<'a>(env: Env<'a>, w: Weights) -> WeightsTerm<'a> {
    (w.n, w.focal, w.neighbor, f64_binary(env, &w.weight))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn network_contiguity_weights<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    graph: bool,
    by_length: bool,
    values: Option<Binary>,
) -> Result<WeightsTerm<'a>, String> {
    let ntw = &resource.0;
    let (links, lengths) = if graph {
        (&ntw.graph.edges, &ntw.graph.edge_lengths)
    } else {
        (&ntw.arcs, &ntw.arc_lengths)
    };
    let values = values
        .map(|b| networkex_core::bytes_to_f64s(b.as_slice()))
        .transpose()?;
    if let Some(v) = &values {
        if v.len() != links.len() {
            return Err(format!(
                "weighting needs one value per link ({}), got {}",
                links.len(),
                v.len()
            ));
        }
    }
    let per_link = match &values {
        Some(v) => Some(v.as_slice()),
        None => by_length.then_some(lengths.as_slice()),
    };
    Ok(weights_term(env, weights::contiguity(links, per_link)))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn network_distance_band_weights<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    threshold: f64,
    max_cells: u64,
) -> Result<WeightsTerm<'a>, String> {
    let n = resource.0.vertices.len() as u64;
    if n.saturating_mul(n) > max_cells {
        return Err(format!(
            "distance-band weights need a {n} x {n} distance matrix, above max_cells ({max_cells})"
        ));
    }
    Ok(weights_term(
        env,
        weights::distance_band(&resource.0, threshold),
    ))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn network_counts(
    resource: ResourceArc<NetworkResource>,
    pattern: PatternTerm,
    graph: bool,
) -> Result<Vec<u32>, String> {
    let observations = decode_pattern(&pattern)?;
    Ok(weights::counts(&resource.0, &observations, graph))
}

// -- simulation and the K-function -------------------------------------------------------------

use networkex_core::kfunction;

#[rustler::nif]
fn network_arc_order(resource: ResourceArc<NetworkResource>) -> Vec<u32> {
    resource.0.arc_order.clone()
}

#[rustler::nif]
fn network_total_length(resource: ResourceArc<NetworkResource>) -> f64 {
    kfunction::total_length(&resource.0)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn network_simulate<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    positions: Binary,
) -> Result<PatternTerm<'a>, String> {
    let positions = networkex_core::bytes_to_f64s(positions.as_slice())?;
    Ok(pattern_term(
        env,
        &kfunction::simulate(&resource.0, &positions)?,
    ))
}

/// `[intensity, upperbound]`, the x axis, the observed curve, the simulated curves (flat, one
/// after another) and the upper and lower envelopes, as f64 binaries (the bound may be infinite).
type KTerm<'a> = (
    Binary<'a>,
    Binary<'a>,
    Binary<'a>,
    Binary<'a>,
    Binary<'a>,
    Binary<'a>,
);

#[rustler::nif(schedule = "DirtyCpu")]
fn network_global_auto_k<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    pattern: PatternTerm,
    steps: (usize, Option<f64>, f64),
    simulations: Vec<Binary>,
) -> Result<KTerm<'a>, String> {
    let (nsteps, upperbound, threshold) = steps;
    let pattern = decode_pattern(&pattern)?;
    let simulations = simulations
        .iter()
        .map(|b| networkex_core::bytes_to_f64s(b.as_slice()))
        .collect::<Result<Vec<_>, _>>()?;
    let k = kfunction::global_auto_k(
        &resource.0,
        &pattern,
        nsteps,
        upperbound,
        threshold,
        &simulations,
    )?;
    let flat: Vec<f64> = k.simulated.concat();
    Ok((
        f64_binary(env, &[k.intensity, k.upperbound]),
        f64_binary(env, &k.xaxis),
        f64_binary(env, &k.observed),
        f64_binary(env, &flat),
        f64_binary(env, &k.upper_envelope),
        f64_binary(env, &k.lower_envelope),
    ))
}

// -- utilities -----------------------------------------------------------------------------------

use networkex_core::utilities::{self, Split};

#[rustler::nif(schedule = "DirtyCpu")]
fn network_split_arcs<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    spec: (String, f64),
    max_arcs: u64,
) -> Result<NetworkTerm<'a>, String> {
    let split = match spec.0.as_str() {
        "distance" => Split::Distance(spec.1),
        // The count travels as a float, exact for every u32; anything else is refused rather
        // than saturated by the cast.
        "count" if spec.1.fract() == 0.0 && (0.0..=f64::from(u32::MAX)).contains(&spec.1) => {
            Split::Count(spec.1 as u32)
        }
        "count" => {
            return Err(format!(
                "the split count must be an integer from 2 to {}",
                u32::MAX
            ))
        }
        other => return Err(format!("unknown split {other:?}")),
    };
    // Checked before splitting: the pieces are allocated here, where nobody can interrupt it.
    utilities::check_split_size(&resource.0, split, max_arcs)?;
    Ok(term(env, utilities::split_arcs(&resource.0, split)?))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn network_extract_component<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    component: u32,
) -> Result<(NetworkTerm<'a>, Vec<u32>), String> {
    let (ntw, ids) = utilities::extract_component(&resource.0, component)?;
    Ok((term(env, ntw), ids))
}

/// `:unchanged` when the network has no cycle (the Elixir side keeps its struct).
#[rustler::nif(schedule = "DirtyCpu")]
fn network_spanning_tree<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    maximum: bool,
) -> Result<rustler::Term<'a>, String> {
    use rustler::Encoder;
    let tree = utilities::spanning_tree(&resource.0, maximum)?;
    if tree == resource.0 {
        return Ok(rustler::types::atom::Atom::from_str(env, "unchanged")
            .map_err(|_| "atom".to_string())?
            .encode(env));
    }
    Ok(term(env, tree).encode(env))
}

/// One shortest path on the wire: the pair, the via vertices (`None` on a shared arc) and the
/// path coordinates (flat).
type PathTerm<'a> = ((u32, u32), Option<(u32, u32)>, Binary<'a>);

#[rustler::nif(schedule = "DirtyCpu")]
fn network_shortest_paths<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    source: PatternTerm,
    dest: Option<PatternTerm>,
) -> Result<Vec<PathTerm<'a>>, String> {
    let src = decode_pattern(&source)?;
    let dst = dest.as_ref().map(decode_pattern).transpose()?;
    Ok(distances::shortest_paths(&resource.0, &src, dst.as_deref())
        .into_iter()
        .map(|p| {
            let flat: Vec<f64> = p.path.iter().flatten().copied().collect();
            (p.pair, p.via, f64_binary(env, &flat))
        })
        .collect())
}

// -- saving and loading -------------------------------------------------------------------------

use networkex_core::persist::{self, Params};

#[rustler::nif(schedule = "DirtyCpu")]
fn network_to_binary<'a>(
    env: Env<'a>,
    resource: ResourceArc<NetworkResource>,
    vertex_sig: i64,
    vertex_atol: i64,
) -> Binary<'a> {
    let params = Params {
        vertex_sig: positive(vertex_sig),
        vertex_atol: positive(vertex_atol),
    };
    let bytes = persist::encode(&resource.0, params);
    let mut owned = OwnedBinary::new(bytes.len());
    owned.as_mut_slice().copy_from_slice(&bytes);
    owned.release(env)
}

type LoadedTerm<'a> = (NetworkTerm<'a>, i64, i64);

#[rustler::nif(schedule = "DirtyCpu")]
fn network_from_binary<'a>(env: Env<'a>, bytes: Binary) -> Result<LoadedTerm<'a>, String> {
    let (ntw, params) = persist::decode(bytes.as_slice())?;
    let option = |x: Option<u32>| x.map_or(0, i64::from);
    Ok((
        term(env, ntw),
        option(params.vertex_sig),
        option(params.vertex_atol),
    ))
}
