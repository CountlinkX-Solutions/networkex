defmodule Networkex.GeoFrame do
  @moduledoc """
  Adapter between [GeoFrame](https://hexdocs.pm/geoframe), a library of geospatial data frames,
  and Networkex.

  Networkex does not depend on GeoFrame. This module calls GeoFrame's public API (and Explorer's,
  which GeoFrame brings) at runtime, and raises an `ArgumentError` saying so when GeoFrame is not
  loaded. Add `{:geoframe, "~> 0.3.4"}` to your own dependencies to use it.

    * `network/2` builds a `Networkex.Network` from the line geometries of a
      `GeoFrame.GeoDataFrame` or `GeoFrame.GeoSeries`;
    * `snap/2` snaps the centroids of a frame's geometries (points are their own centroid);
    * `arcs/2`, `points/2` and `paths/2` turn networks, point patterns and shortest paths back into
      `GeoFrame.GeoDataFrame`s, for maps (`GeoFrame.Kino.deck/2`) and further GeoFrame work.

  ## Geographic coordinates

  Network lengths are Euclidean, so on longitude/latitude they measure degrees. `network/2`
  raises `ArgumentError` for a geographic CRS unless `allow_geographic: true`; project the frame
  first (`GeoFrame.GeoDataFrame.to_crs/2`).

  ## Examples

      streets = GeoFrame.read_file!("streets.shp")
      ntw = Networkex.GeoFrame.network(streets)
      crimes = Networkex.GeoFrame.snap(ntw, GeoFrame.read_file!("crimes.shp"))
      Networkex.GeoFrame.arcs(ntw, columns: %{"crimes" => Networkex.Network.counts_per_link(ntw, crimes)})
  """

  alias Networkex.{Network, PointPattern}

  @gdf GeoFrame.GeoDataFrame
  @gs GeoFrame.GeoSeries
  @df Explorer.DataFrame

  @doc """
  A network from the line geometries (`LineString` or `MultiLineString`) of a
  `GeoFrame.GeoDataFrame` or `GeoFrame.GeoSeries`. Options of `Networkex.Network.new/2`, plus
  `allow_geographic: true` to accept longitude/latitude.
  """
  @spec network(struct(), keyword()) :: Network.t()
  def network(frame, opts \\ []) do
    ensure_geoframe!()
    {allow, opts} = Keyword.pop(opts, :allow_geographic, false)
    series = series(frame)

    if allow != true and call(@gs, :is_geographic, [series]) == true do
      raise ArgumentError,
            "the geometry has a geographic CRS, so network lengths would be degrees: project " <>
              "it first (GeoFrame.GeoDataFrame.to_crs/2) or pass allow_geographic: true"
    end

    series |> wkb() |> Network.new(opts)
  end

  @doc """
  Snaps the centroids of the geometries of a `GeoFrame.GeoDataFrame` or `GeoFrame.GeoSeries` to
  the network (`Networkex.Network.snap/2`).
  """
  @spec snap(Network.t(), struct()) :: PointPattern.t()
  def snap(%Network{} = ntw, frame) do
    ensure_geoframe!()
    centroids = call(@gs, :centroid, [series(frame)])
    xs = call(@gs, :x, [centroids])
    ys = call(@gs, :y, [centroids])
    Network.snap(ntw, {xs, ys})
  end

  @doc """
  The arcs of the network as a `GeoFrame.GeoDataFrame` of two-point lines with the columns
  `"arc"` (index), `"i"`, `"j"` (vertex ids) and `"length"`. With `graph: true`, the graph edges
  instead (straight lines between their end vertices). Options:

    * `:columns` - a map of extra columns, each a list with one value per arc (or edge), such as
      `Networkex.Network.counts_per_link/3`;
    * `:crs` - the CRS of the result.
  """
  @spec arcs(Network.t(), keyword()) :: struct()
  def arcs(%Network{} = ntw, opts \\ []) do
    ensure_geoframe!()

    {links, lengths} =
      if opts[:graph],
        do: {ntw.graph.edges, ntw.graph.edge_lengths},
        else: {ntw.arcs, ntw.arc_lengths}

    vertices = List.to_tuple(ntw.vertices)
    lines = Enum.map(links, fn {i, j} -> line([elem(vertices, i), elem(vertices, j)]) end)

    columns =
      Map.merge(
        %{
          "arc" => Enum.to_list(0..(length(links) - 1)//1),
          "i" => Enum.map(links, &elem(&1, 0)),
          "j" => Enum.map(links, &elem(&1, 1)),
          "length" => lengths
        },
        Map.new(opts[:columns] || %{}, fn {k, v} -> {to_string(k), v} end)
      )

    frame(lines, columns, opts[:crs])
  end

  @doc """
  A point pattern as a `GeoFrame.GeoDataFrame` of points: the snapped points (default) or, with
  `which: :observed`, the observations as given; with the columns `"i"`, `"j"` (the arc) and
  `"snap_distance"`, plus `:columns` and `:crs` as in `arcs/2`.
  """
  @spec points(PointPattern.t(), keyword()) :: struct()
  def points(%PointPattern{} = pp, opts \\ []) do
    ensure_geoframe!()
    coords = if opts[:which] == :observed, do: pp.points, else: pp.snapped

    columns =
      Map.merge(
        %{
          "i" => Enum.map(pp.arcs, &elem(&1, 0)),
          "j" => Enum.map(pp.arcs, &elem(&1, 1)),
          "snap_distance" => pp.dist_snapped
        },
        Map.new(opts[:columns] || %{}, fn {k, v} -> {to_string(k), v} end)
      )

    frame(Enum.map(coords, &point/1), columns, opts[:crs])
  end

  @doc """
  Shortest paths (`Networkex.Network.shortest_paths/3`) as a `GeoFrame.GeoDataFrame` of lines
  with the columns `"source"`, `"dest"` and `"length"`; `:crs` as in `arcs/2`.
  """
  @spec paths([map()], keyword()) :: struct()
  def paths(paths, opts \\ []) when is_list(paths) do
    ensure_geoframe!()

    columns = %{
      "source" => Enum.map(paths, &elem(&1.pair, 0)),
      "dest" => Enum.map(paths, &elem(&1.pair, 1)),
      "length" => Enum.map(paths, &path_length(&1.path))
    }

    frame(Enum.map(paths, &line(&1.path)), columns, opts[:crs])
  end

  defp path_length(path) do
    path
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [{x1, y1}, {x2, y2}] -> :math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2) end)
    |> Enum.sum()
  end

  # Little-endian WKB, so that coordinates go to GeoFrame bit for bit.
  defp point({x, y}), do: <<1, 1::little-32, x * 1.0::little-float-64, y * 1.0::little-float-64>>

  defp line(coords) do
    body =
      for {x, y} <- coords, into: <<>>, do: <<x * 1.0::little-float-64, y * 1.0::little-float-64>>

    <<1, 2::little-32, length(coords)::little-32, body::binary>>
  end

  defp frame(wkbs, columns, crs) do
    geometry = call(@gs, :from_wkb!, [wkbs, [crs: crs]])
    call(@gdf, :new, [call(@df, :new, [columns]), geometry])
  end

  defp wkb(series), do: call(@gs, :to_wkb, [series])

  defp series(%{__struct__: @gdf} = frame), do: call(@gdf, :geometry, [frame])
  defp series(%{__struct__: @gs} = series), do: series

  defp series(other) do
    raise ArgumentError,
          "expected a GeoFrame.GeoDataFrame or GeoFrame.GeoSeries, got: #{inspect(other, limit: 3)}"
  end

  defp ensure_geoframe! do
    unless Code.ensure_loaded?(@gdf) do
      raise ArgumentError,
            ~s(Networkex.GeoFrame needs GeoFrame: add {:geoframe, "~> 0.3.4"} to your dependencies)
    end
  end

  defp call(mod, fun, args), do: apply(mod, fun, args)
end
