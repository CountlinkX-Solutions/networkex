# Parity with spaghetti

Entries are `planned` until delivered, then `available`. Deviations from spaghetti are listed
under each section once the functionality exists.

| spaghetti | Networkex | Since | Status |
|---|---|---|---|
| `Network` (vertices, arcs, components, graph extraction) | `Networkex.Network.new/2` | 0.1.0 | available (point lists or WKB lines, `vertex_sig`, `vertex_atol` since 0.2.0) |
| `enum_links_vertex` | `Networkex.Network.arcs_at/2` | 0.2.0 | available (sorted) |
| `snapobservations`, `compute_snap_dist`, `compute_distance_to_vertices` | `Networkex.Network.snap/2` | 0.1.0 | available |
| `full_distance_matrix` | `Networkex.Network.distance_matrix/2` | 0.1.0 | available (trees: `shortest_paths/3`) |
| `allneighbordistances`, `nearestneighbordistances` | `Networkex.Network.all_neighbor_distances/4`, `nearest_neighbor_distances/4` | 0.1.0 | available (`snap_dist`, `fill_diagonal`, `keep_zero_dist`) |
| `contiguityweights`, `distancebandweights`, `count_per_link` | `Networkex.Network.contiguity_weights/2`, `distance_band_weights/3`, `counts_per_link/3` | 0.1.0 | available (`weightings` values since 0.2.0; Moran: use `Spatex.ESDA.moran/3` on these arrays) |
| `GlobalAutoK`, `simulate_observations` | `Networkex.Network.global_auto_k/3`, `simulate_observations/3` | 0.1.0 | available |
| `split_arcs`, `regular_lattice`, `spanning_tree`, `extract_component` | `Networkex.Network.split_arcs/3`, `regular_lattice/3`, `spanning_tree/2`, `extract_component/2` | 0.1.0 | available |
| `savenetwork`, `loadnetwork` | `Networkex.Network.save/2`, `load/1` (`to_binary/1`, `from_binary/1`) | 0.2.0 | available (network only) |
| `shortest_paths` (with `allneighbordistances(gen_tree=True)`) | `Networkex.Network.shortest_paths/3` | 0.1.0 | available |

## Network weights notes

Verified against spaghetti 1.7.6 on the geodanet streets and crimes
(`fixtures/network/weights.json`): contiguity of arcs and graph edges, binary, by length and with
a seeded value per arc or edge (`weightings` dict, since 0.2.0: each neighbour gets its own value),
distance bands of 500 and 1500 feet, and counts per arc and per edge; every neighbour pair in
spaghetti's order, weights to 1e-9.

* Deviation: `distance_band_weights/3` keeps vertices without a neighbour as islands (spaghetti's
  `W` leaves them out, so its ids are not the vertex ids).
* `Moran` is not reimplemented: the weights and counts are Spatex's input arrays.

## Observations and distances notes

Verified against spaghetti 1.7.6 (`fixtures/network/distances.json`): the geodanet streets with
60 crimes and the 8 schools, and a synthetic network with observations on the same arc, exactly on
vertices, duplicated, and on two components. Snapped points, arcs, vertex and snapping distances,
the full distance matrix, all-neighbour distances (within and across patterns, with and without
`snap_dist`) and nearest neighbours (with ties and `keep_zero_dist: false`) match; distances to
1e-9.

Replicated on purpose:

* Snapping ties go to the arc with the smallest `(head, tail)` coordinates (spaghetti scans the
  candidate arcs in descending order and keeps the last one at the minimum distance).
* Two observations on the same arc are the straight-line distance apart, and `snap_dist` is not
  added to that distance.
* With `keep_zero_dist: false` the diagonal is 0 and zero distances are skipped.

Differences that do not change results: Dijkstra runs only from the vertices of the source
observations' arcs (spaghetti fills the whole vertex matrix first), and with a binary heap.

## Network construction notes

Verified against spaghetti 1.7.6 on 12 networks (`fixtures/network/construction.json`): the
geodanet streets of Tempe, a lattice, a ring with a tail, disconnected paths, duplicated arcs and
degree-2 chains, many-digit coordinates under two `vertex_sig` values, and `vertex_atol` on an
undershoot it closes, many digits, exact binary ties and together with `vertex_sig=4`. Vertices,
arcs, adjacency, the arcs at every vertex (`enum_links_vertex`), components and the extracted graph
match exactly, lengths to 1e-9.

Replicated on purpose:

* Coordinates are rounded with Python's `round` to `vertex_sig` significant digits, then to
  `vertex_atol` decimals (ties to even, as Python's `round`).
* An arc's length runs from the rounded vertex to the next vertex as given (unrounded).
* Segment lengths are CPython's `math.hypot`, which libpysal uses: its algorithm, not the
  platform's libm `hypot`, which rounds some lengths one ulp differently and differs between
  platforms. Lengths and split points are therefore the same on every platform;
  `fixtures/hypot/hypot.json` checks 4982 pairs bit for bit, every geodanet segment among them.
* Vertex rounding takes the decimal exponent from `log10`, as spaghetti does with `numpy.log10`.
  With `vertex_sig` 14 to 16, a coordinate within a few ulps of a power of ten can round
  differently depending on the `log10` implementation: numpy's (in spaghetti) and the platform's
  libm (here) disagree on some of them, e.g. `1000 - 5 ulp` on x86-64 Linux. No exact rule
  matches spaghetti there, so Networkex keeps the libm. With `vertex_sig` up to 13 (the default
  is 11) or 17, the rounded vertex does not depend on it.
* Graph components count only the lengths of edges that are also arcs, as spaghetti's
  `identify_components` does (not exposed).
* A ring with a tail merges the degree-2 vertices of the ring into a loop edge `(v, v)`.

Deviations:

* **MultiLineString parts are not joined.** spaghetti concatenates the vertices of all parts, so
  the last vertex of a part and the first of the next become a phantom arc. Networkex treats
  every part as its own line.
* `arcs_at/2` sorts the arcs at a vertex; spaghetti's `enum_links_vertex` lists them in the order
  it found the neighbours.
* `vertex_atol` without `vertex_sig` raises, and `vertex_atol` must be at least 1: spaghetti
  silently ignores both (it returns the coordinates early without `vertex_sig`, and `0` is falsy).
* `unique_arcs: false` is not offered: spaghetti fails on it (`identify_components` zips arcs
  with fewer component labels).
* A network whose arc lengths, or their sum, overflow a float (finite coordinates about 1e308
  apart) raises an `ArgumentError`; spaghetti computes infinite lengths.

## K-function notes

Verified against spaghetti 1.7.6 (`fixtures/network/kfunction.json`, geodanet streets with the
schools and the crimes). spaghetti draws with `numpy.random.uniform`; the generator records the
draws and the tests replay them (`:positions`, `:simulations`), so the simulated patterns, every
simulated curve and the envelopes match to 1e-9 (two simulations of 60 and 300 observations,
four K-functions with 7 to 25 steps, thresholds 0.1 to 0.5, default and explicit upper bounds).

Replicated on purpose:

* Arcs are laid end to end in their order of first appearance (spaghetti's `arc_lengths`), not
  in the sorted order of `arcs` (`arc_draw_order/1`).
* A simulated point sits its draw's distance back from the end of its arc's stretch, measured
  from the arc's first vertex; on a vertical arc spaghetti measures the coordinates from the
  lower vertex while the distances to the vertices keep the first-vertex convention.
* `K(r)` counts pairs strictly closer than `r`, `r` from 0 (numpy's `linspace`), and the
  envelope is the largest simulated value times `1 - threshold / 2` and the smallest times
  `threshold / 2` (scaled extremes, not quantiles).

Deviations:

* The draws come from Erlang's `:rand` (`:exsss`, seeded by `:seed`), not numpy's generator:
  seeded results are reproducible but not numpy's. Replaying numpy's draws gives spaghetti's
  results exactly.
* Fewer than 2 observations, 0 steps or 0 permutations are refused (spaghetti fails inside
  numpy).

## Utility notes

Verified against spaghetti 1.7.6 (`fixtures/network/utilities.json`): six lattices (with and
without the exterior, `nh != nv`) coordinate for coordinate; seven splits by distance and by
count of the geodanet streets and of a lattice with a downward vertical line (vertices, arcs,
lengths, draw order, adjacency, components; the crimes snapped again to the split streets); the
three components of a disconnected network; minimum and maximum spanning trees of the streets,
the lattice and a tree.

Replicated on purpose:

* Split points accumulate the piece length (`total += interval`), so a count split can leave a
  last piece of about 1e-14 when the pieces sum just below the arc length; arc lengths are
  `math.hypot`, bit for bit, since this depends on their last bit.
* A vertical arc is walked upwards; new vertex ids follow the arcs in sorted order.
* Spanning-tree ties keep the `arc_lengths` order and the tree is rebuilt from two-point lines,
  so its vertex ids follow the order in which arcs join it.
* `regular_lattice` takes the horizontal spacing from `nh` but the number of horizontal
  positions from `nv` (and the other way round).

Deviations:

* `extract_component` renumbers the component's vertices (their old ids are returned) and labels
  it component 0; spaghetti keeps the old ids and label.
* A split network also has its graph (spaghetti does not extract one) and carries no point
  patterns: snap the observations again.
* `split_arcs/3` refuses a split that could make more than `:max_arcs` arcs (default 250_000, at
  most 67_108_864), counted before splitting with one piece to spare for each arc cut (the tiny
  last piece above), so a split that returns never has more arcs than `:max_arcs`; spaghetti
  splits whatever it is given. Raise `:max_arcs` for larger splits.
* A split by count whose pieces would be shorter than the smallest normal float (about 2.2e-308)
  raises: such pieces lose precision, and spaghetti's loop can then make more pieces than the
  count, or never end.

## Shortest path notes

Verified against spaghetti 1.7.6 (`fixtures/network/paths.json`): the 28 paths between the
schools and the 320 from 40 crimes to the schools on the geodanet streets match exactly (pair
order, the vertices each path leaves and enters by, coordinates); on a lattice the 10 paths
have spaghetti's ends, vertices and lengths.

Replicated on purpose:

* The leaving and entering vertices follow spaghetti's comparisons (the first vertex of each arc
  on ties); observations on the same arc are joined directly.
* A path is the snapped source, every arc's two end points with the repeated joints dropped the
  way spaghetti drops them (the first occurrence of a repeated vertex), and the snapped
  destination.

Deviations:

* **Equal-length routes.** spaghetti settles equally distant vertices in the iteration order of a
  Python set; Networkex settles them by id. When two routes have exactly the same length (common
  on lattices, two of the ten lattice paths) the route can differ; its length does not.

## Saving and loading notes

Checked by round trips, not fixtures (spaghetti pickles its Python object): every built network,
split network, extracted component and spanning tree comes back equal, with its rounding options,
and answers snapping, distance, weight and draw-order queries as before. Truncated, extended or
inconsistent bytes and other format versions are errors.

Deviations:

* **The network only.** spaghetti's pickle holds the whole object: point patterns, distance
  matrices and network trees too. Networkex saves the network in its own versioned little-endian
  format; point patterns are plain data (`:erlang.term_to_binary/1`), and distances are computed
  again on demand.
