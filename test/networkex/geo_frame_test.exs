defmodule Networkex.GeoFrameTest do
  use ExUnit.Case, async: true

  @moduletag :geoframe

  alias GeoFrame.GeoDataFrame, as: GDF
  alias GeoFrame.GeoSeries, as: GS
  alias Networkex.{Network, Shapefile}

  @data Path.expand("../reference/data", __DIR__)

  setup_all do
    streets = GeoFrame.read_file!(Path.join(@data, "streets.shp"))
    crimes = GeoFrame.read_file!(Path.join(@data, "crimes.shp"))
    %{streets: streets, crimes: crimes}
  end

  test "a network from a frame is the network of its lines", %{streets: streets} do
    ntw = Networkex.GeoFrame.network(streets)
    direct = Network.new(Shapefile.read_lines(Path.join(@data, "streets.shp")))

    assert {ntw.vertices, ntw.arcs, ntw.arc_lengths} ==
             {direct.vertices, direct.arcs, direct.arc_lengths}
  end

  test "snapping frames and the frames of results", %{streets: streets, crimes: crimes} do
    ntw = Networkex.GeoFrame.network(streets)
    pp = Networkex.GeoFrame.snap(ntw, crimes)
    assert pp == Network.snap(ntw, Shapefile.read_points(Path.join(@data, "crimes.shp")))

    counts = Network.counts_per_link(ntw, pp)
    arcs = Networkex.GeoFrame.arcs(ntw, columns: %{crimes: counts}, crs: GDF.crs(streets))
    assert GDF.n_rows(arcs) == length(ntw.arcs)
    assert GDF.crs(arcs) == GDF.crs(streets)
    assert Explorer.Series.to_list(GDF.pull(arcs, "crimes")) == counts
    assert Explorer.Series.to_list(GDF.pull(arcs, "length")) == ntw.arc_lengths

    points = Networkex.GeoFrame.points(pp)

    assert Explorer.Series.to_list(GS.x(GDF.geometry(points))) ==
             Enum.map(pp.snapped, &elem(&1, 0))

    edges = Networkex.GeoFrame.arcs(ntw, graph: true)
    assert GDF.n_rows(edges) == length(ntw.graph.edges)

    paths =
      Network.shortest_paths(ntw, %{
        pp
        | arcs: Enum.take(pp.arcs, 3),
          points: Enum.take(pp.points, 3),
          snapped: Enum.take(pp.snapped, 3),
          dist_to_vertex: Enum.take(pp.dist_to_vertex, 3),
          dist_snapped: Enum.take(pp.dist_snapped, 3)
      })

    frame = Networkex.GeoFrame.paths(paths)
    assert Explorer.Series.to_list(GDF.pull(frame, "source")) == [0, 0, 1]
    assert Enum.all?(Explorer.Series.to_list(GDF.pull(frame, "length")), &(&1 > 0))
  end

  test "geographic frames are refused unless allowed", %{streets: streets} do
    # The streets carry the CRS of their .prj; label the same coordinates as longitude/latitude.
    geo = GDF.set_crs(streets, "EPSG:4326", allow_override: true)
    assert_raise ArgumentError, ~r/geographic/, fn -> Networkex.GeoFrame.network(geo) end
    assert %Network{} = Networkex.GeoFrame.network(geo, allow_geographic: true)
    assert_raise ArgumentError, ~r/GeoDataFrame/, fn -> Networkex.GeoFrame.network(:nope) end
  end
end
