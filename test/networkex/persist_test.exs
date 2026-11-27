defmodule Networkex.PersistTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Networkex.{Network, Shapefile}

  @data Path.expand("../reference/data", __DIR__)

  defp same_network?(a, b), do: Map.delete(a, :ref) == Map.delete(b, :ref)

  defp round_trip(ntw) do
    assert {:ok, back} = ntw |> Network.to_binary() |> Network.from_binary()
    back
  end

  setup_all do
    %{streets: Network.new(Shapefile.read_lines(Path.join(@data, "streets.shp")))}
  end

  test "a network comes back equal and answers queries as before", %{streets: ntw} do
    back = round_trip(ntw)
    assert same_network?(back, ntw)
    assert back.ref != ntw.ref

    crimes = Shapefile.read_points(Path.join(@data, "crimes.shp"))
    assert Network.snap(back, crimes) == Network.snap(ntw, crimes)
    assert Network.distance_matrix(back) == Network.distance_matrix(ntw)
    assert Network.arc_draw_order(back) == Network.arc_draw_order(ntw)

    assert Network.contiguity_weights(back, graph: true) ==
             Network.contiguity_weights(ntw, graph: true)
  end

  test "derived networks and the rounding options come back too" do
    lines = [[{0.0, 0.0}, {1.00001, 0.0}], [{1.0, 0.0}, {2.0, 0.0}, {2.0, 1.0}, {0.0, 0.0}]]
    ntw = Network.new(lines, vertex_atol: 4)

    for net <- [
          ntw,
          Network.new(lines, vertex_sig: nil),
          Network.split_arcs(ntw, 0.4),
          elem(Network.extract_component(ntw, 0), 0),
          Network.spanning_tree(ntw)
        ] do
      back = round_trip(net)
      assert same_network?(back, net)
      assert {back.vertex_sig, back.vertex_atol} == {net.vertex_sig, net.vertex_atol}
    end
  end

  @tag :tmp_dir
  test "save/2 and load/1 go through a file", %{streets: ntw, tmp_dir: dir} do
    path = Path.join(dir, "streets.nwkx")
    assert Network.save(ntw, path) == :ok
    assert {:ok, back} = Network.load(path)
    assert same_network?(back, ntw)
    assert Network.load(Path.join(dir, "missing.nwkx")) == {:error, :enoent}
  end

  test "anything else is an error, not a crash", %{streets: ntw} do
    bin = Network.to_binary(ntw)
    assert {:error, message} = Network.from_binary("not a network")
    assert message =~ "Networkex"

    for cut <- [0, 4, 31, div(byte_size(bin), 2), byte_size(bin) - 1] do
      assert {:error, _} = Network.from_binary(binary_part(bin, 0, cut))
    end

    <<magic::binary-4, _version::little-32, rest::binary>> = bin
    assert {:error, message} = Network.from_binary(magic <> <<99::little-32>> <> rest)
    assert message =~ "version"

    assert_raise ArgumentError, fn -> Network.from_binary(:nope) end
  end

  property "random networks round-trip" do
    point = tuple({integer(-50..50), integer(-50..50)})
    line = list_of(point, min_length: 2, max_length: 5)

    check all(lines <- list_of(line, min_length: 1, max_length: 8), max_runs: 60) do
      ntw = Network.new(lines)
      assert same_network?(round_trip(ntw), ntw)
    end
  end
end
