defmodule Networkex.NetworkOracleTest do
  use ExUnit.Case, async: true

  alias Networkex.{Network, Reference}

  @tol 1.0e-9
  @fixture Reference.load!("network/construction.json")

  defp lines(c), do: Enum.map(c["lines"], fn line -> Enum.map(line, fn [x, y] -> {x, y} end) end)

  defp opts(c),
    do:
      Enum.map(c["options"], fn {k, v} when k in ~w(vertex_sig vertex_atol) ->
        {String.to_atom(k), v}
      end)

  defp pairs(list), do: Enum.map(list, fn [a, b] -> {a, b} end)

  for {c, i} <- Enum.with_index(@fixture["cases"]), not Map.has_key?(c, "spaghetti_fails") do
    test "#{c["name"]}" do
      c = Enum.at(@fixture["cases"], unquote(i))
      ntw = Network.new(lines(c), opts(c))

      assert length(ntw.vertices) == length(c["vertices"])

      Reference.assert_close(
        Enum.flat_map(ntw.vertices, &Tuple.to_list/1),
        List.flatten(c["vertices"]),
        0.0
      )

      assert ntw.arcs == pairs(c["arcs"])
      # Exact: split points depend on the last bit of the lengths (math.hypot).
      Reference.assert_close(ntw.arc_lengths, c["arc_lengths"], 0.0)
      assert ntw.adjacency == c["adjacency"]

      # spaghetti lists them in the order it found the neighbours; Networkex sorts them.
      for {expected, v} <- Enum.with_index(c["vertex_links"]) do
        assert Network.arcs_at(ntw, v) == expected |> pairs() |> Enum.sort()
      end

      n = c["network"]
      assert ntw.network.n_components == n["n_components"]
      assert ntw.network.component_labels == n["component_labels"]
      Reference.assert_close(ntw.network.component_lengths, n["component_lengths"], @tol)
      assert ntw.network.longest_component == n["longest_component"]
      assert ntw.network.largest_component == n["largest_component"]
      assert ntw.network.component_is_ring == n["component_is_ring"]
      assert ntw.network.fully_connected == n["fully_connected"]

      g = c["graph"]
      assert ntw.graph.edges == pairs(g["edges"])
      Reference.assert_close(ntw.graph.edge_lengths, g["edge_lengths"], @tol)
      assert ntw.graph.non_articulation_points == g["non_articulation_points"]

      assert ntw.graph.arcs_to_edges ==
               Enum.map(g["arcs_to_edges"], fn [a, e] -> {List.to_tuple(a), List.to_tuple(e)} end)

      assert ntw.graph.n_components == g["n_components"]
      assert ntw.graph.component_labels == g["component_labels"]
    end
  end
end
