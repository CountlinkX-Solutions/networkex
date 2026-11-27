defmodule Networkex.DistancesOracleTest do
  use ExUnit.Case, async: true

  alias Networkex.{Network, Reference}

  @tol 1.0e-9
  @fixture Reference.load!("network/distances.json")

  defp pts(list), do: Enum.map(list, fn [x, y] -> {x, y} end)

  # Results use :infinity; the fixtures write "inf", decoded as :inf.
  defp norm(rows) when is_list(rows), do: Enum.map(rows, &norm/1)
  defp norm(:infinity), do: :inf
  defp norm(v), do: v

  for {c, i} <- Enum.with_index(@fixture["cases"]) do
    describe c["name"] do
      setup do
        c = Enum.at(@fixture["cases"], unquote(i))
        ntw = Network.new(Enum.map(c["lines"], &pts/1))

        patterns =
          Map.new(c["patterns"], fn {name, p} -> {name, Network.snap(ntw, pts(p["points"]))} end)

        %{c: c, ntw: ntw, patterns: patterns}
      end

      test "snapping", %{c: c, patterns: patterns} do
        for {name, expected} <- c["patterns"] do
          pp = patterns[name]

          Reference.assert_close(
            Enum.flat_map(pp.snapped, &Tuple.to_list/1),
            List.flatten(expected["snapped"]),
            @tol
          )

          assert pp.arcs == Enum.map(expected["arcs"], &List.to_tuple/1)

          Reference.assert_close(
            Enum.flat_map(pp.dist_to_vertex, &Tuple.to_list/1),
            List.flatten(expected["dist_to_vertex"]),
            @tol
          )

          Reference.assert_close(pp.dist_snapped, expected["dist_snapped"], @tol)
        end
      end

      test "distance matrix", %{c: c, ntw: ntw} do
        if expected = c["distance_matrix"] do
          Reference.assert_close(norm(Network.distance_matrix(ntw)), expected, @tol)
        end
      end

      test "all- and nearest-neighbour distances", %{c: c, ntw: ntw, patterns: patterns} do
        for {key, expected} <- c["all"] do
          [src, dst, snap] = String.split(key, "|")
          dst = if dst == "", do: nil, else: patterns[dst]
          got = Network.all_neighbor_distances(ntw, patterns[src], dst, snap_dist: snap == "True")
          Reference.assert_close(norm(got), expected, @tol)
        end

        for {key, expected} <- c["nearest"] do
          [src, dst, snap | rest] = String.split(key, "|")
          dst = if dst == "", do: nil, else: patterns[dst]
          opts = [snap_dist: snap == "True", keep_zero_dist: rest != ["no_zero"]]
          got = Network.nearest_neighbor_distances(ntw, patterns[src], dst, opts)
          assert Enum.map(got, fn {idx, _} -> idx end) == Enum.map(expected, &hd/1), key

          Reference.assert_close(
            Enum.map(got, fn {_, d} -> norm(d) end),
            Enum.map(expected, &List.last/1),
            @tol
          )
        end
      end
    end
  end
end
