defmodule Networkex.WeightsOracleTest do
  use ExUnit.Case, async: true

  alias Networkex.{Network, Reference}

  @fixture Reference.load!("network/weights.json")["cases"]
  @data Path.expand("../reference/data", __DIR__)

  setup_all do
    lines = read_lines(Path.join(@data, "streets.shp"))
    ntw = Network.new(lines)
    crimes = read_points(Path.join(@data, "crimes.shp"))
    %{ntw: ntw, crimes: Network.snap(ntw, crimes)}
  end

  # Minimal Shapefile readers for the test data (polylines and points, no M or Z).
  defp records(path) do
    <<_header::binary-size(100), body::binary>> = File.read!(path)
    parse(body, [])
  end

  defp parse(<<_n::big-32, len::big-32, content::binary-size(len * 2), rest::binary>>, acc),
    do: parse(rest, [content | acc])

  defp parse(<<>>, acc), do: Enum.reverse(acc)

  defp read_lines(path) do
    for <<3::little-32, _box::binary-size(32), parts::little-32, points::little-32, rest::binary>> <-
          records(path) do
      <<starts::binary-size(parts * 4), coords::binary-size(points * 16)>> = rest
      starts = for <<s::little-32 <- starts>>, do: s
      pts = for <<x::little-float-64, y::little-float-64 <- coords>>, do: {x, y}

      starts
      |> Enum.zip(Enum.drop(starts, 1) ++ [points])
      |> Enum.map(fn {a, b} -> Enum.slice(pts, a, b - a) end)
    end
    |> Enum.concat()
  end

  defp read_points(path) do
    for <<1::little-32, x::little-float-64, y::little-float-64>> <- records(path), do: {x, y}
  end

  defp triples(w),
    do: Enum.zip_with([w.focal, w.neighbor, w.weight], fn [f, n, wt] -> [f, n, wt] end)

  defp assert_weights(w, expected) do
    got = triples(w)
    assert Enum.map(got, &Enum.take(&1, 2)) == Enum.map(expected["triples"], &Enum.take(&1, 2))

    Reference.assert_close(
      Enum.map(got, &List.last/1),
      Enum.map(expected["triples"], &List.last/1),
      1.0e-9
    )
  end

  test "contiguity weights of the arcs and of the graph edges", %{ntw: ntw} do
    assert_weights(Network.contiguity_weights(ntw), @fixture["network_binary"])
    assert_weights(Network.contiguity_weights(ntw, graph: true), @fixture["graph_binary"])

    assert_weights(
      Network.contiguity_weights(ntw, weighting: :lengths),
      @fixture["network_lengths"]
    )

    assert_weights(
      Network.contiguity_weights(ntw, graph: true, weighting: :lengths),
      @fixture["graph_lengths"]
    )
  end

  test "contiguity weights with a value per arc or edge (spaghetti's weightings dict)",
       %{ntw: ntw} do
    for {key, graph} <- [{"network_custom", false}, {"graph_custom", true}] do
      expected = @fixture[key]

      assert_weights(
        Network.contiguity_weights(ntw, graph: graph, weighting: expected["values"]),
        expected
      )
    end
  end

  test "distance-band weights of the vertices", %{ntw: ntw} do
    for {threshold, expected} <- @fixture["distance_band"] do
      assert_weights(Network.distance_band_weights(ntw, String.to_float(threshold)), expected)
    end
  end

  test "observation counts per arc and per edge, the Moran inputs", %{ntw: ntw, crimes: crimes} do
    for {graph, counts, moran} <- [
          {false, "counts_network", "moran_network"},
          {true, "counts_graph", "moran_graph"}
        ] do
      links = if graph, do: ntw.graph.edges, else: ntw.arcs
      got = Network.counts_per_link(ntw, crimes, graph: graph)
      assert length(got) == length(links)

      nonzero =
        links
        |> Enum.zip(got)
        |> Enum.reject(fn {_, c} -> c == 0 end)
        |> Enum.map(fn {{a, b}, c} -> [[a, b], c] end)

      assert nonzero == @fixture[counts]
      assert Enum.map(got, &(&1 * 1.0)) == @fixture[moran]["y"]
    end
  end
end
