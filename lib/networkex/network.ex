# Portions of this file are derived from spaghetti 1.7.6 (https://github.com/pysal/spaghetti).
# Copyright 2017 PySAL-spaghetti Developers. Licensed under the BSD 3-Clause License, reproduced
# in LICENSES/BSD-3-Clause-spaghetti.txt; see NOTICE. Each derived function names its source.

defmodule Networkex.Network do
  @moduledoc """
  A spatial network built from line geometries, after `spaghetti.Network`.

  `new/2` turns every polyline into **arcs** between consecutive vertices. Vertices are
  identified by their coordinates rounded to `vertex_sig` significant digits (default 11, as in
  spaghetti), so lines that meet at the same rounded point are connected. Vertex ids follow the
  order in which vertices first appear.

  The result holds:

    * `vertices` - the rounded `{x, y}` of each vertex, by id;
    * `arcs` - `{i, j}` vertex pairs (`i <= j`), unique and sorted; `arc_lengths` aligned with
      them; `adjacency` - the neighbouring vertex ids of each vertex;
    * `network` - the connected components of the arcs: `n_components`, `component_labels` (one
      per arc, numbered by the first arc of each component), `component_lengths`,
      `longest_component`, `largest_component` (most vertices), `component_is_ring`,
      `fully_connected`;
    * `graph` - the network with every chain of degree-2 vertices (outside rings) merged into one
      edge: `edges`, `edge_lengths`, `non_articulation_points` (the merged vertices),
      `arcs_to_edges` and the components of the edges (`n_components`, `component_labels`).

  As in spaghetti an arc's length runs from the rounded vertex to the next vertex as given.

  ## Lines

  A list of lines, each a list of points (`{x, y}` or `[x, y]`), or a list of WKB `LineString` /
  `MultiLineString` binaries. Every line string is one part: unlike spaghetti, the last vertex of
  one part of a `MultiLineString` is not joined to the first vertex of the next.

  ## Options

    * `:vertex_sig` - significant digits of the vertex coordinates (default `11`; `nil` keeps
      them as given).
    * `:vertex_atol` - decimals the vertex coordinates are rounded to after `:vertex_sig`
      (default `nil`, no rounding), spaghetti's `vertex_atol`. It joins line ends that miss each
      other by less than half a unit of the last decimal, for data with known digitising errors.
      It needs `:vertex_sig`: spaghetti ignores it without, so Networkex refuses that.

  ## Examples

      iex> ntw = Networkex.Network.new([[{0, 0}, {1, 0}, {3, 0}], [{1, 0}, {1, 2}]])
      iex> {ntw.arcs, ntw.arc_lengths}
      {[{0, 1}, {1, 2}, {1, 3}], [1.0, 2.0, 2.0]}
      iex> ntw.graph.edges
      [{0, 1}, {1, 2}, {1, 3}]
  """

  alias Networkex.{Input, Native, PointPattern}

  @enforce_keys [
    :ref,
    :vertices,
    :arcs,
    :arc_lengths,
    :adjacency,
    :network,
    :graph,
    :vertex_sig,
    :vertex_atol
  ]
  defstruct @enforce_keys

  @type link :: {non_neg_integer(), non_neg_integer()}
  @type t :: %__MODULE__{
          ref: reference(),
          vertices: [{float(), float()}],
          arcs: [link()],
          arc_lengths: [float()],
          adjacency: [[non_neg_integer()]],
          network: map(),
          graph: map(),
          vertex_sig: pos_integer() | nil,
          vertex_atol: pos_integer() | nil
        }

  @doc "Builds a network from `lines`. See the module documentation."
  @spec new([term()], keyword()) :: t()
  def new(lines, opts \\ []) do
    opts = validate!(opts)
    sig = opts[:vertex_sig] || 0
    atol = opts[:vertex_atol] || 0

    result =
      case lines do
        [first | _] when is_binary(first) ->
          Native.network_from_wkb(lines, sig, atol)

        [_ | _] ->
          from_coords(lines, sig, atol)

        other ->
          raise ArgumentError, "lines must be a non-empty list, got: #{inspect(other, limit: 3)}"
      end

    result |> unwrap() |> from_term(opts[:vertex_sig], opts[:vertex_atol])
  end

  defp from_term(
         {ref, vertices, arcs, arc_lengths, adjacency, components, graph},
         vertex_sig,
         vertex_atol
       ) do
    {edges, edge_lengths, napts, arcs_to_edges, graph_components} = graph

    %__MODULE__{
      ref: ref,
      vertices:
        vertices |> Input.from_f64_binary() |> Enum.chunk_every(2) |> Enum.map(&List.to_tuple/1),
      arcs: arcs,
      arc_lengths: arc_lengths,
      adjacency: adjacency,
      network: components_map(components),
      graph:
        graph_components
        |> components_map()
        |> Map.take([:n_components, :component_labels])
        |> Map.merge(%{
          edges: edges,
          edge_lengths: edge_lengths,
          non_articulation_points: napts,
          arcs_to_edges: arcs_to_edges
        }),
      vertex_sig: vertex_sig,
      vertex_atol: vertex_atol
    }
  end

  # About 300 bytes per arc once the split network is Elixir terms, and a few times that while
  # the NIF and the VM build them: a few hundred megabytes at the default, the budget of
  # @default_max_cells (25 million distances, 200 MB as f64).
  @default_max_arcs 250_000
  # networkex_core's MAX_SPLIT_ARCS (2^26): up to this many pieces per arc, rounding adds at
  # most one, so the count below is an upper bound.
  @max_split_arcs 67_108_864

  @doc """
  The network with every arc longer than the split cut into pieces, after
  `spaghetti.Network.split_arcs`. `by: :distance` (default) cuts pieces of `split` length from
  the start of each arc (the last one shorter); `by: :count` cuts each arc into `split` equal
  pieces (an integer from 2 to 4_294_967_295).

  New vertices get the next ids, arc by arc; a new point exactly on an existing vertex reuses
  it. As in spaghetti a vertical arc is walked upwards, and the pieces are placed by adding up
  their length, so rounding can leave a last piece of the order of 1e-16 of the arc.
  Observations snapped to the original network are not carried over: snap them again with
  `snap/2`. Unlike spaghetti's split network, the result also has its `graph`.

  ## Size and time

  Option `:max_arcs` (default 250_000, at most 67_108_864) is a hard limit: a split that
  returns has at most that many arcs. The arcs are counted from the arc lengths before anything
  is allocated, and a split whose count exceeds `:max_arcs` raises an `ArgumentError`. The
  count gives an arc longer than the distance `ceil(length / split)` pieces and an arc split by
  count `split` pieces, each plus one for the tiny last piece rounding can leave, and every
  other arc 1, so it can exceed the result by up to one arc per arc cut. A split by count whose
  pieces would be shorter than the smallest normal float (about 2.2e-308) raises too. Without
  the limit, a split distance far below the arc lengths would allocate gigabytes in native
  code, which cannot be interrupted. 250_000 arcs take a few hundred megabytes of memory while
  the result is built; raise the limit for larger splits.

  `:max_arcs` bounds memory, not time. Building the graph of the split network takes time that
  grows with the square of its arcs: on a recent x86-64 machine about a third of a second for
  25_000 arcs, 3 seconds for 100_000 and nearly 20 seconds at the default limit, during which
  a dirty CPU scheduler is busy and the call cannot be interrupted. See "Known limitations" in
  the architecture guide.
  """
  @spec split_arcs(t(), number(), keyword()) :: t()
  def split_arcs(%__MODULE__{ref: ref} = ntw, split, opts \\ []) do
    unless Keyword.keyword?(opts) and Keyword.keys(opts) -- [:by, :max_arcs] == [],
      do: raise(ArgumentError, "options are :by and :max_arcs")

    spec = split_spec(Keyword.get(opts, :by, :distance), split)
    max_arcs = max_arcs!(Keyword.get(opts, :max_arcs, @default_max_arcs))

    ref
    |> Native.network_split_arcs(spec, max_arcs)
    |> unwrap()
    |> from_term(ntw.vertex_sig, ntw.vertex_atol)
  end

  defp max_arcs!(n) when is_integer(n) and n in 1..@max_split_arcs//1, do: n

  defp max_arcs!(other) do
    raise ArgumentError,
          ":max_arcs must be a positive integer up to #{@max_split_arcs}, got: #{inspect(other)}"
  end

  # The largest float (1.7976931348623157e308) as an integer: a larger integer has no float to
  # travel as. The count travels as a float too, exact up to the NIF's 32-bit limit.
  @max_float 2 ** 1024 - 2 ** 971
  @max_count 0xFFFF_FFFF

  defp split_spec(:distance, d) when is_float(d) and d > 0, do: {"distance", d}

  defp split_spec(:distance, d) when is_integer(d) and d > 0 and d <= @max_float,
    do: {"distance", d * 1.0}

  defp split_spec(:count, c) when is_integer(c) and c in 2..@max_count//1, do: {"count", c * 1.0}

  defp split_spec(:distance, _) do
    raise ArgumentError,
          "the split distance must be a positive number of at most 1.7976931348623157e308"
  end

  defp split_spec(:count, _),
    do: raise(ArgumentError, "the split count must be an integer from 2 to #{@max_count}")

  defp split_spec(by, _),
    do: raise(ArgumentError, ":by must be :distance or :count, got: #{inspect(by)}")

  @doc """
  One connected component (by its label in `network.component_labels`) as a network of its own,
  after `spaghetti.extract_component`. Returns `{component, vertex_ids}`: the component's
  vertices are renumbered in the order of their ids in `ntw`, which `vertex_ids` lists (unlike
  spaghetti, which keeps the old ids and labels).
  """
  @spec extract_component(t(), non_neg_integer()) :: {t(), [non_neg_integer()]}
  def extract_component(%__MODULE__{ref: ref} = ntw, component)
      when is_integer(component) and component >= 0 do
    {term, ids} = ref |> Native.network_extract_component(component) |> unwrap()
    {from_term(term, ntw.vertex_sig, ntw.vertex_atol), ids}
  end

  @doc """
  The minimum spanning tree of the network (`maximum: true` for the maximum one), after
  `spaghetti.spanning_tree` with its `"sort"` method: arcs join by increasing length (ties in
  `arc_draw_order/1`) unless they close a cycle, and the tree is built anew from them, so its
  vertex ids follow that order. A network without cycles is returned as it is.
  """
  @spec spanning_tree(t(), keyword()) :: t()
  def spanning_tree(%__MODULE__{ref: ref} = ntw, opts \\ []) do
    unless Keyword.keyword?(opts) and Keyword.keys(opts) -- [:maximum] == [],
      do: raise(ArgumentError, "the only option is :maximum")

    case ref |> Native.network_spanning_tree(flag!(opts, :maximum, false)) |> unwrap() do
      :unchanged -> ntw
      term -> from_term(term, 11, nil)
    end
  end

  @doc """
  The lines of a regular lattice inside `bounds` (`{min_x, min_y, max_x, max_y}`), after
  `spaghetti.regular_lattice`: `nh` lines across and `nv` (default `nh`) lines down, cut into
  segments at every crossing; `exterior: true` adds the border. Returns two-point lines for
  `new/2`.

  As in spaghetti, the horizontal spacing comes from `nh` and the vertical from `nv`, but the
  number of horizontal positions from `nv` and of vertical ones from `nh`: with `nh != nv` the
  lattice does not reach every border.

      iex> Networkex.Network.regular_lattice({0, 0, 1, 1}, 1)
      [[{0.0, 0.5}, {0.5, 0.5}], [{0.5, 0.5}, {1.0, 0.5}], [{0.5, 0.0}, {0.5, 0.5}], [{0.5, 0.5}, {0.5, 1.0}]]
  """
  @spec regular_lattice({number(), number(), number(), number()}, pos_integer(), keyword()) ::
          [[{float(), float()}]]
  # Derived from spaghetti 1.7.6: `regular_lattice` (spaghetti/network.py).
  def regular_lattice({x0, y0, x1, y1} = bounds, nh, opts \\ []) when is_integer(nh) and nh > 0 do
    unless Enum.all?([x0, y0, x1, y1], &is_number/1),
      do: raise(ArgumentError, "bounds must be four numbers")

    unless Keyword.keyword?(opts) and Keyword.keys(opts) -- [:nv, :exterior] == [],
      do: raise(ArgumentError, "options are :nv and :exterior")

    nv = lattice_count!(opts[:nv] || nh)
    exterior = flag!(opts, :exterior, false)
    incr_h = (x1 - x0) / (nh + 1)
    incr_v = (y1 - y0) / (nv + 1)
    space_h = for slot <- 0..(nv + 1), do: incr_h * slot
    space_v = for slot <- 0..(nh + 1), do: incr_v * slot

    chains(space_h, space_v, exterior, bounds, true) ++
      chains(space_h, space_v, exterior, bounds, false)
  end

  defp lattice_count!(n) when is_integer(n) and n > 0, do: n
  defp lattice_count!(_), do: raise(ArgumentError, ":nv must be a positive integer")

  # Derived from spaghetti 1.7.6: `build_chains` (spaghetti/util.py).
  # spaghetti's `build_chains`: horizontal lines step along x, vertical ones along y.
  defp chains(space_h, space_v, exterior, {x0, y0, _, _}, horizontal) do
    {h, v} = {List.to_tuple(space_h), List.to_tuple(space_v)}
    {minus_x, minus_y} = if horizontal, do: {1, 0}, else: {0, 1}
    trim = if exterior, do: 0, else: 1
    {trim_h, trim_v} = if horizontal, do: {0, trim}, else: {trim, 0}

    for plus_h <- trim_h..(tuple_size(h) - 1 - trim_h)//1,
        plus_v <- trim_v..(tuple_size(v) - 1 - trim_v)//1,
        plus_h - minus_x != -1 and plus_v - minus_y != -1 do
      [
        {x0 + elem(h, plus_h - minus_x), y0 + elem(v, plus_v - minus_y)},
        {x0 + elem(h, plus_h), y0 + elem(v, plus_v)}
      ]
    end
  end

  @default_max_cells 25_000_000

  @doc """
  Snaps `points` (`[{x, y}]`, `[[x, y]]`, an `{n, 2}` tensor or `{xs, ys}`) to the network:
  each goes to the nearest point of its nearest arc. On a tie the arc with the smallest vertex
  coordinates wins, as in spaghetti. Returns a `Networkex.PointPattern`.
  """
  @spec snap(t(), term()) :: PointPattern.t()
  def snap(%__MODULE__{ref: ref}, points) do
    {bin, _n} = Input.to_points_binary(points)

    ref
    |> Native.network_snap(bin)
    |> unwrap()
    |> pattern(bin |> Input.from_f64_binary() |> pairs())
  end

  defp pattern({arcs, snapped, to_vertex, dist}, points) do
    snapped = snapped |> Input.from_f64_binary() |> pairs()

    %PointPattern{
      points: points || snapped,
      snapped: snapped,
      arcs: arcs,
      dist_to_vertex: to_vertex |> Input.from_f64_binary() |> pairs(),
      dist_snapped: Input.from_f64_binary(dist)
    }
  end

  @doc """
  Shortest-path distances between every pair of vertices (`spaghetti.Network.full_distance_matrix`),
  as rows by vertex id; `:infinity` between components. Option `:max_cells` (default
  25_000_000) bounds the size of the matrix.
  """
  @spec distance_matrix(t(), keyword()) :: [[float() | :infinity]]
  def distance_matrix(%__MODULE__{ref: ref, vertices: vertices}, opts \\ []) do
    max_cells = Keyword.get(opts, :max_cells, @default_max_cells)

    ref
    |> Native.network_distance_matrix(max_cells)
    |> unwrap()
    |> Input.from_f64_binary()
    |> Enum.chunk_every(max(length(vertices), 1))
  end

  @doc """
  Network distances between every observation of `source` and of `dest` (rows by source),
  after `spaghetti.Network.allneighbordistances`. Without `dest` the pattern is measured against
  itself and the diagonal is `:nan` (or `fill_diagonal:`). Two observations on the same arc are
  the straight-line distance apart; otherwise the shortest of the four routes through the arcs'
  vertices. `snap_dist: true` adds the snapping distances (except on a shared arc, as in
  spaghetti).
  """
  @spec all_neighbor_distances(t(), PointPattern.t(), PointPattern.t() | nil, keyword()) :: [
          [term()]
        ]
  def all_neighbor_distances(
        %__MODULE__{ref: ref},
        %PointPattern{} = source,
        dest \\ nil,
        opts \\ []
      ) do
    unless Keyword.keyword?(opts) and Keyword.keys(opts) -- [:snap_dist, :fill_diagonal] == [],
      do: raise(ArgumentError, "options are :snap_dist and :fill_diagonal")

    diagonal = opts[:fill_diagonal]

    unless is_nil(diagonal) or is_number(diagonal),
      do: raise(ArgumentError, ":fill_diagonal must be a number")

    snap = flag!(opts, :snap_dist, false)
    n_dest = length((dest || source).arcs)

    ref
    |> Native.network_all_neighbors(
      wire(source),
      dest && wire(dest),
      snap,
      diagonal && diagonal * 1.0
    )
    |> unwrap()
    |> Input.from_f64_binary()
    |> Enum.chunk_every(max(n_dest, 1))
  end

  @doc """
  The nearest observation(s) of `dest` (or of `source` itself) to each observation of `source`,
  as `{indices, distance}` (all the indices at the minimum), after
  `spaghetti.Network.nearestneighbordistances`. Options `:snap_dist` (default `false`) and
  `:keep_zero_dist` (default `true`; with `false` zero distances, such as coincident
  observations, are skipped).
  """
  @spec nearest_neighbor_distances(t(), PointPattern.t(), PointPattern.t() | nil, keyword()) ::
          [{[non_neg_integer()], float()}]
  def nearest_neighbor_distances(
        %__MODULE__{ref: ref},
        %PointPattern{} = source,
        dest \\ nil,
        opts \\ []
      ) do
    unless Keyword.keyword?(opts) and Keyword.keys(opts) -- [:snap_dist, :keep_zero_dist] == [],
      do: raise(ArgumentError, "options are :snap_dist and :keep_zero_dist")

    snap = flag!(opts, :snap_dist, false)
    keep = flag!(opts, :keep_zero_dist, true)

    {idx, dist} =
      ref |> Native.network_nearest(wire(source), dest && wire(dest), snap, keep) |> unwrap()

    Enum.zip(idx, Input.from_f64_binary(dist))
  end

  @doc """
  The shortest path between observations along the network, after spaghetti's
  `allneighbordistances(gen_tree=True)` and `shortest_paths`: every pair `{i, j}` with `i < j` of
  `source` without `dest`, otherwise every source with every destination, in that order.

  Each path is `%{pair: {i, j}, via: {source_vertex, dest_vertex} | :same_arc, path: [{x, y}]}`:
  the vertices of the two observations' arcs it leaves and enters by, and its coordinates from the
  snapped source through the network vertices to the snapped destination. Two observations on the
  same arc are joined directly. Of two routes of exactly the same length the one through the
  vertex settled first (the smaller id among equal distances) is taken, which can differ from
  spaghetti's choice.
  """
  @spec shortest_paths(t(), PointPattern.t(), PointPattern.t() | nil) :: [map()]
  def shortest_paths(%__MODULE__{ref: ref}, %PointPattern{} = source, dest \\ nil) do
    ref
    |> Native.network_shortest_paths(wire(source), dest && wire(dest))
    |> unwrap()
    |> Enum.map(fn {pair, via, path} ->
      %{pair: pair, via: via || :same_arc, path: path |> Input.from_f64_binary() |> pairs()}
    end)
  end

  @doc """
  The arcs that touch `vertex` (an index into `vertices`), after
  `spaghetti.Network.enum_links_vertex`. They come sorted; spaghetti lists them in the order it
  found the neighbours.

      iex> ntw = Networkex.Network.new([[{0, 0}, {1, 0}, {3, 0}], [{1, 0}, {1, 2}]])
      iex> Networkex.Network.arcs_at(ntw, 1)
      [{0, 1}, {1, 2}, {1, 3}]
  """
  @spec arcs_at(t(), non_neg_integer()) :: [link()]
  def arcs_at(%__MODULE__{adjacency: adjacency}, vertex) do
    neighbors = is_integer(vertex) and vertex >= 0 and Enum.at(adjacency, vertex)

    unless is_list(neighbors),
      do:
        raise(
          ArgumentError,
          "vertex must be an id in 0..#{length(adjacency) - 1}, got: #{inspect(vertex)}"
        )

    neighbors
    |> Enum.map(fn n -> if n < vertex, do: {n, vertex}, else: {vertex, n} end)
    |> Enum.sort()
  end

  @doc """
  Contiguity weights of the arcs (or, with `graph: true`, of the graph edges), after
  `spaghetti.Network.contiguityweights`: two links are neighbours when they share a vertex.
  `weighting: :lengths` weights each neighbour by its length (spaghetti's `weightings=True`);
  the default `:binary` gives 1. `weighting: values`, one number per link (a list, `Nx` tensor or
  `Explorer` series, in the order of `arcs` or `graph.edges`), weights each neighbour by its own
  value, as spaghetti's `weightings` dict does.

  Returns `%{n:, focal:, neighbor:, weight:}` by link index (the order of `arcs` or
  `graph.edges`), the arrays `Spatex.Graph.from_arrays/3` takes; links without a neighbour are
  islands.
  """
  @spec contiguity_weights(t(), keyword()) :: map()
  def contiguity_weights(%__MODULE__{ref: ref} = ntw, opts \\ []) do
    unless Keyword.keyword?(opts) and Keyword.keys(opts) -- [:graph, :weighting] == [],
      do: raise(ArgumentError, "options are :graph and :weighting")

    graph = flag!(opts, :graph, false)

    {by_length, values} =
      case Keyword.get(opts, :weighting, :binary) do
        :binary ->
          {false, nil}

        :lengths ->
          {true, nil}

        other when is_atom(other) ->
          raise ArgumentError,
                ":weighting must be :binary, :lengths or one value per link, got: #{inspect(other)}"

        values ->
          n = length(if graph, do: ntw.graph.edges, else: ntw.arcs)
          {bin, ^n} = Input.to_f64_binary(values, name: "weighting", length: n)
          {false, bin}
      end

    ref
    |> Native.network_contiguity_weights(graph, by_length, values)
    |> unwrap()
    |> weights_map()
  end

  @doc """
  Distance-band weights of the vertices, after `spaghetti.Network.distancebandweights`: two
  vertices are neighbours (weight 1) when they are closer than `threshold` along the network.
  Unlike spaghetti, vertices without a neighbour stay as islands (spaghetti leaves them out), so
  the ids are the vertex ids. Option `:max_cells` bounds the distance matrix (default
  25_000_000).
  """
  @spec distance_band_weights(t(), number(), keyword()) :: map()
  def distance_band_weights(%__MODULE__{ref: ref}, threshold, opts \\ [])
      when is_number(threshold) do
    max_cells = Keyword.get(opts, :max_cells, @default_max_cells)

    ref
    |> Native.network_distance_band_weights(threshold * 1.0, max_cells)
    |> unwrap()
    |> weights_map()
  end

  @doc """
  The number of observations of `pattern` on each arc (or, with `graph: true`, each graph edge),
  aligned with `arcs` (or `graph.edges`), zeros included: the vector spaghetti's `Moran` analyses
  (`spaghetti.Network.count_per_link`).
  """
  @spec counts_per_link(t(), PointPattern.t(), keyword()) :: [non_neg_integer()]
  def counts_per_link(%__MODULE__{ref: ref}, %PointPattern{} = pattern, opts \\ []) do
    ref |> Native.network_counts(wire(pattern), flag!(opts, :graph, false)) |> unwrap()
  end

  @doc """
  The arcs in the order simulated observations are drawn along: the order in which they first
  appear in the lines (spaghetti's `arc_lengths`), not the sorted order of `arcs`.
  """
  @spec arc_draw_order(t()) :: [link()]
  def arc_draw_order(%__MODULE__{ref: ref, arcs: arcs}) do
    arcs = List.to_tuple(arcs)
    ref |> Native.network_arc_order() |> Enum.map(&elem(arcs, &1))
  end

  @doc """
  `count` observations placed uniformly at random along the network, after
  `spaghetti.Network.simulate_observations`. Returns a `Networkex.PointPattern` whose points are
  on the network (snapping distances 0).

  The arcs are laid end to end in `arc_draw_order/1` and each observation goes to a position
  drawn uniformly along that length. As in spaghetti, the point sits that position's distance
  back from the end of its arc's stretch, measured from the arc's first vertex (on a vertical
  arc, from the lower one).

  ## Options

    * `:seed` - an integer seed for reproducible draws (`:rand`'s `:exsss`); random by default;
    * `:positions` - the positions themselves (`count` numbers from 0 to the network length),
      for example to replay spaghetti's own draws.
  """
  @spec simulate_observations(t(), pos_integer(), keyword()) :: PointPattern.t()
  def simulate_observations(%__MODULE__{ref: ref} = ntw, count, opts \\ [])
      when is_integer(count) and count > 0 do
    unless Keyword.keyword?(opts) and Keyword.keys(opts) -- [:seed, :positions] == [],
      do: raise(ArgumentError, "options are :seed and :positions")

    positions =
      case opts[:positions] do
        nil -> ntw |> draws(seed_state(opts[:seed]), count) |> elem(0)
        list when is_list(list) and length(list) == count -> list
        _ -> raise ArgumentError, ":positions must be a list of #{count} numbers"
      end

    ref |> Native.network_simulate(f64_bin(positions)) |> unwrap() |> pattern(nil)
  end

  @doc """
  The global auto K-function of `pattern` along the network with a Monte Carlo envelope, after
  `spaghetti.Network.GlobalAutoK`.

  At each of `nsteps` distances `r` from 0 to `:upperbound`, `K(r)` counts the ordered pairs of
  observations closer than `r` along the network, over `n * lambda`, with `lambda` the
  observations per unit of network length. The same curve is computed for each of
  `:permutations` patterns of `n` observations simulated as in `simulate_observations/3`.

  Returns `%{intensity:, upperbound:, xaxis:, observed:, simulated:, upper_envelope:,
  lower_envelope:, seed:}` (`simulated` has one curve per permutation). The envelope is spaghetti's:
  the largest simulated value at each step times `1 - threshold / 2` and the smallest times
  `threshold / 2`.

  ## Options

    * `:nsteps` - the number of distances (default 10);
    * `:permutations` - the number of simulations (default 99);
    * `:threshold` - default 0.5;
    * `:upperbound` - the last distance (default the largest distance between two
      observations);
    * `:seed` - an integer seed for the simulations; without one a seed is drawn, and either
      way it is returned as `seed` (`nil` with `:simulations`);
    * `:simulations` - the positions of every simulation (lists of `n` numbers, as
      `simulate_observations/3`'s `:positions`), in place of drawing them.
  """
  @spec global_auto_k(t(), PointPattern.t(), keyword()) :: map()
  def global_auto_k(%__MODULE__{ref: ref} = ntw, %PointPattern{} = pattern, opts \\ []) do
    opts = validate_k!(opts)
    n = length(pattern.arcs)
    seed = if opts[:simulations], do: nil, else: opts[:seed] || :rand.uniform(2 ** 31 - 1)

    simulations =
      opts[:simulations] ||
        ntw
        |> draws(seed_state(seed), n * opts[:permutations])
        |> elem(0)
        |> Enum.chunk_every(n)

    {head, x, observed, simulated, upper, lower} =
      ref
      |> Native.network_global_auto_k(
        wire(pattern),
        {opts[:nsteps], opts[:upperbound] && opts[:upperbound] * 1.0, opts[:threshold] * 1.0},
        Enum.map(simulations, &f64_bin/1)
      )
      |> unwrap()

    [intensity, upperbound] = Input.from_f64_binary(head)

    %{
      intensity: intensity,
      upperbound: upperbound,
      xaxis: Input.from_f64_binary(x),
      observed: Input.from_f64_binary(observed),
      simulated: simulated |> Input.from_f64_binary() |> Enum.chunk_every(opts[:nsteps]),
      upper_envelope: Input.from_f64_binary(upper),
      lower_envelope: Input.from_f64_binary(lower),
      seed: seed
    }
  end

  @k_defaults [nsteps: 10, permutations: 99, threshold: 0.5, upperbound: nil]
  @k_options [:seed, :simulations | Keyword.keys(@k_defaults)]

  @doc """
  The network as a binary, after `spaghetti.Network.savenetwork`: `from_binary/1` reads it back,
  in this or another VM. `:erlang.term_to_binary/1` is not enough, because a network holds a
  reference to Rust memory that does not outlive the VM.

  The binary is Networkex's own little-endian format (version 1): the vertices, arcs, arc lengths,
  the arc order and the rounding options. Adjacency, components and the graph are derived again on
  load, as when the network was built. Point patterns (`Networkex.PointPattern`) are plain data:
  keep them with `:erlang.term_to_binary/1`.
  """
  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{ref: ref} = ntw),
    do: Native.network_to_binary(ref, ntw.vertex_sig || 0, ntw.vertex_atol || 0)

  @doc """
  A network from a binary of `to_binary/1`, or `{:error, reason}` when the binary is not one
  (another format version, truncated, inconsistent).
  """
  @spec from_binary(binary()) :: {:ok, t()} | {:error, String.t()}
  def from_binary(binary) when is_binary(binary) do
    case Native.network_from_binary(binary) do
      {:ok, {term, sig, atol}} ->
        {:ok, from_term(term, positive_or_nil(sig), positive_or_nil(atol))}

      {:error, reason} ->
        {:error, to_string(reason)}
    end
  end

  def from_binary(other),
    do: raise(ArgumentError, "expected a binary, got: #{inspect(other, limit: 3)}")

  @doc """
  Writes the network to `path` (`to_binary/1`), after `spaghetti.Network.savenetwork`.
  """
  @spec save(t(), Path.t()) :: :ok | {:error, File.posix()}
  def save(%__MODULE__{} = ntw, path), do: File.write(path, to_binary(ntw))

  @doc """
  Reads a network written by `save/2`, after `spaghetti.Network.loadnetwork`: `{:error, posix}`
  when the file cannot be read, `{:error, reason}` when it is not a network.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, File.posix() | String.t()}
  def load(path) do
    with {:ok, binary} <- File.read(path), do: from_binary(binary)
  end

  defp positive_or_nil(0), do: nil
  defp positive_or_nil(n), do: n

  defp validate_k!(opts) do
    unless Keyword.keyword?(opts) and Keyword.keys(opts) -- @k_options == [],
      do: raise(ArgumentError, "options are #{inspect(@k_options)}")

    opts = Keyword.merge(@k_defaults, opts)
    Enum.each(opts, fn {key, value} -> check_k!(key, value) end)
    opts
  end

  defp check_k!(key, v) when key in [:nsteps, :permutations] and not (is_integer(v) and v > 0),
    do: raise(ArgumentError, "#{inspect(key)} must be a positive integer")

  defp check_k!(:threshold, v) when not is_number(v),
    do: raise(ArgumentError, ":threshold must be a number")

  defp check_k!(:upperbound, v) when not (is_nil(v) or (is_number(v) and v >= 0)),
    do: raise(ArgumentError, ":upperbound must be a non-negative number")

  defp check_k!(:simulations, v)
       when not (is_nil(v) or (is_list(v) and v != [])),
       do: raise(ArgumentError, ":simulations must be a non-empty list of position lists")

  defp check_k!(:simulations, [_ | _] = v) do
    unless Enum.all?(v, &is_list/1),
      do: raise(ArgumentError, ":simulations must be a non-empty list of position lists")
  end

  defp check_k!(_key, _value), do: :ok

  defp seed_state(nil), do: :rand.seed_s(:exsss)
  defp seed_state(seed) when is_integer(seed), do: :rand.seed_s(:exsss, seed)

  defp seed_state(seed),
    do: raise(ArgumentError, ":seed must be an integer, got: #{inspect(seed)}")

  # Uniform positions along the network, in [0, length).
  defp draws(%__MODULE__{ref: ref}, state, count) do
    total = Native.network_total_length(ref)

    Enum.map_reduce(1..count//1, state, fn _, st ->
      {u, st} = :rand.uniform_real_s(st)
      {u * total, st}
    end)
  end

  defp f64_bin(values), do: values |> Input.to_f64_binary() |> elem(0)

  defp weights_map({n, focal, neighbor, weight}),
    do: %{n: n, focal: focal, neighbor: neighbor, weight: Input.from_f64_binary(weight)}

  defp wire(%PointPattern{} = p) do
    bin = fn pairs ->
      pairs |> Enum.flat_map(&Tuple.to_list/1) |> Input.to_f64_binary() |> elem(0)
    end

    {dist, _} = Input.to_f64_binary(p.dist_snapped)
    {p.arcs, bin.(p.snapped), bin.(p.dist_to_vertex), dist}
  end

  defp flag!(opts, key, default) do
    case Keyword.get(opts, key, default) do
      v when is_boolean(v) -> v
      v -> raise ArgumentError, "#{inspect(key)} must be true or false, got: #{inspect(v)}"
    end
  end

  defp pairs(flat), do: flat |> Enum.chunk_every(2) |> Enum.map(&List.to_tuple/1)

  defp from_coords(lines, sig, atol) do
    {coords, offsets} =
      Enum.map_reduce(lines, 0, fn line, offset ->
        unless is_list(line), do: raise(ArgumentError, "every line must be a list of points")
        {bin, n} = Input.to_points_binary(line)
        {{bin, offset + n}, offset + n}
      end)
      |> elem(0)
      |> Enum.unzip()

    offsets_bin = for o <- [0 | offsets], into: <<>>, do: <<o::unsigned-native-32>>
    Native.network_from_coords(IO.iodata_to_binary(coords), offsets_bin, sig, atol)
  end

  defp components_map({n, labels, lengths, longest, largest, is_ring}) do
    %{
      n_components: n,
      component_labels: labels,
      component_lengths: lengths,
      longest_component: longest,
      largest_component: largest,
      component_is_ring: is_ring,
      fully_connected: n == 1
    }
  end

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, reason}), do: raise(ArgumentError, to_string(reason))

  defp validate!(opts) do
    unless Keyword.keyword?(opts), do: raise(ArgumentError, "options must be a keyword list")

    case Keyword.keys(opts) -- [:vertex_sig, :vertex_atol] do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown option(s) #{inspect(unknown)}"
    end

    opts = Keyword.merge([vertex_sig: 11, vertex_atol: nil], opts)
    sig = digits!(opts, :vertex_sig)
    atol = digits!(opts, :vertex_atol)

    if is_nil(sig) and not is_nil(atol),
      do: raise(ArgumentError, ":vertex_atol needs :vertex_sig (spaghetti ignores it without)")

    opts
  end

  defp digits!(opts, name) do
    case opts[name] do
      value when is_nil(value) or (is_integer(value) and value in 1..17) ->
        value

      other ->
        raise ArgumentError,
              "#{inspect(name)} must be nil or an integer in 1..17, got: #{inspect(other)}"
    end
  end
end
