defmodule Networkex.UtilitiesOracleTest do
  use ExUnit.Case, async: true

  alias Networkex.{Network, Reference, Shapefile}

  @tol 1.0e-9
  @fixture Reference.load!("network/utilities.json")["cases"]
  @data Path.expand("../reference/data", __DIR__)

  setup_all do
    # Defines the option atoms String.to_existing_atom/1 looks up.
    Code.ensure_loaded!(Network)
    streets = Shapefile.read_lines(Path.join(@data, "streets.shp"))
    crimes = Shapefile.read_points(Path.join(@data, "crimes.shp"))
    %{lines: %{"streets" => streets, "lattice" => points(@fixture["lattice"])}, crimes: crimes}
  end

  defp points(lines), do: Enum.map(lines, fn line -> Enum.map(line, &List.to_tuple/1) end)
  defp pairs(list), do: Enum.map(list, &List.to_tuple/1)
  defp flat(tuples), do: Enum.flat_map(tuples, &Tuple.to_list/1)

  # Vertex ids of the fixture are spaghetti's; `ids` maps ours to them (identity unless a
  # component was extracted and renumbered).
  defp assert_network(ntw, c, ids) do
    to_ours = ids |> Enum.with_index() |> Map.new()
    ours = fn {a, b} -> {to_ours[a], to_ours[b]} end
    assert ids == c["vertex_ids"]
    Reference.assert_close(flat(ntw.vertices), List.flatten(c["vertices"]), 0.0)
    assert ntw.arcs == c["arcs"] |> pairs() |> Enum.map(ours)
    Reference.assert_close(ntw.arc_lengths, c["arc_lengths"], @tol)
    assert Network.arc_draw_order(ntw) == c["arc_order"] |> pairs() |> Enum.map(ours)

    assert ntw.adjacency ==
             Enum.map(c["adjacency"], fn ns -> ns |> Enum.map(&to_ours[&1]) |> Enum.sort() end)

    n = c["network"]
    assert ntw.network.n_components == n["n_components"]
    Reference.assert_close(ntw.network.component_lengths, n["component_lengths"], @tol)
    assert ntw.network.fully_connected == n["fully_connected"]

    if g = c["graph"] do
      assert ntw.graph.edges == g["edges"] |> pairs() |> Enum.map(ours)
      Reference.assert_close(ntw.graph.edge_lengths, g["edge_lengths"], @tol)

      assert ntw.graph.non_articulation_points ==
               g["non_articulation_points"] |> Enum.map(&to_ours[&1]) |> Enum.sort()
    end
  end

  for {c, i} <- Enum.with_index(@fixture["regular_lattice"]) do
    @c c
    test "regular_lattice #{i}: #{inspect(c["bounds"])} nh=#{c["nh"]} nv=#{inspect(c["nv"])} exterior=#{c["exterior"]}" do
      [x0, y0, x1, y1] = @c["bounds"]

      lines =
        Network.regular_lattice({x0, y0, x1, y1}, @c["nh"],
          nv: @c["nv"],
          exterior: @c["exterior"]
        )

      assert Enum.map(lines, &flat/1) == Enum.map(@c["lines"], &List.flatten/1)
    end
  end

  for {c, i} <- Enum.with_index(@fixture["split_arcs"]) do
    @c c
    test "split_arcs #{i}: #{c["source"]} by #{c["split_by"]} #{c["split_param"]}",
         %{lines: lines, crimes: crimes} do
      c = @c
      ntw = Network.new(lines[c["source"]])

      split =
        Network.split_arcs(ntw, c["split_param"], by: String.to_existing_atom(c["split_by"]))

      assert_network(split, c, Enum.to_list(0..(length(split.vertices) - 1)//1))

      if expected = c["crimes"] do
        pp = Network.snap(split, crimes)
        assert pp.arcs == pairs(expected["arcs"])
        Reference.assert_close(flat(pp.snapped), List.flatten(expected["snapped"]), @tol)

        Reference.assert_close(
          flat(pp.dist_to_vertex),
          List.flatten(expected["dist_to_vertex"]),
          @tol
        )
      end
    end
  end

  for {c, i} <- Enum.with_index(@fixture["extract_component"]["components"]) do
    @c c
    test "extract_component #{i}" do
      ntw = Network.new(points(@fixture["extract_component"]["lines"]))
      {component, ids} = Network.extract_component(ntw, @c["component"])
      assert_network(component, @c, ids)
      assert Enum.all?(component.network.component_labels, &(&1 == 0))
    end
  end

  for {c, i} <- Enum.with_index(@fixture["spanning_tree"]) do
    @c c
    test "spanning_tree #{i}: #{c["source"]} maximum=#{c["maximum"]}", %{lines: lines} do
      lines =
        Map.put(lines, "tree", [[{0.0, 0.0}, {1.0, 0.0}, {2.0, 0.0}], [{1.0, 0.0}, {1.0, 1.0}]])

      tree = Network.spanning_tree(Network.new(lines[@c["source"]]), maximum: @c["maximum"])
      assert_network(tree, @c, Enum.to_list(0..(length(tree.vertices) - 1)//1))
    end
  end
end
