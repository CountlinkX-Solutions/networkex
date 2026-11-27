defmodule Networkex.NetworkTest do
  use ExUnit.Case, async: true

  alias Networkex.Network

  doctest Networkex.Network

  defp linestring(points) do
    body =
      for {x, y} <- points, into: <<>>, do: <<x * 1.0::little-float-64, y * 1.0::little-float-64>>

    <<1, 2::little-32, length(points)::little-32, body::binary>>
  end

  defp multilinestring(parts) do
    body = parts |> Enum.map(&linestring/1) |> IO.iodata_to_binary()
    <<1, 5::little-32, length(parts)::little-32, body::binary>>
  end

  test "WKB lines give the same network as point lists" do
    lines = [[{0, 0}, {1, 0}, {3, 0}], [{1, 0}, {1, 2}]]
    from_points = Network.new(lines)
    from_wkb = Network.new(Enum.map(lines, &linestring/1))
    assert Map.drop(from_wkb, [:ref]) == Map.drop(from_points, [:ref])
  end

  test "the parts of a MultiLineString are not joined (spaghetti joins them)" do
    ntw = Network.new([multilinestring([[{0, 0}, {1, 0}], [{5, 5}, {6, 5}]])])
    assert ntw.arcs == [{0, 1}, {2, 3}]
    assert ntw.network.n_components == 2
  end

  test "vertex_sig merges nearly equal coordinates" do
    lines = [[{0, 0}, {1.00001, 0}], [{1.00002, 0}, {2, 0}]]
    assert Network.new(lines).network.n_components == 2
    assert Network.new(lines, vertex_sig: 4).network.n_components == 1
    assert Network.new(lines, vertex_sig: nil).vertex_sig == nil
  end

  test "inputs and options are validated" do
    assert_raise ArgumentError, ~r/non-empty list/, fn -> Network.new([]) end

    assert_raise ArgumentError, ~r/at least one line with two vertices/, fn ->
      Network.new([[{0, 0}]])
    end

    assert_raise ArgumentError, ~r/LineString or MultiLineString/, fn ->
      Network.new([<<1, 1::little-32, 0::64, 0::64>>])
    end

    assert_raise ArgumentError, ~r/:vertex_sig/, fn ->
      Network.new([[{0, 0}, {1, 1}]], vertex_sig: 0)
    end

    assert_raise ArgumentError, ~r/unknown option/, fn ->
      Network.new([[{0, 0}, {1, 1}]], bogus: 1)
    end
  end

  test "arcs_at/2 lists the arcs that touch a vertex" do
    ntw = Network.new([[{0, 0}, {1, 0}, {3, 0}], [{1, 0}, {1, 2}]])
    assert Network.arcs_at(ntw, 1) == [{0, 1}, {1, 2}, {1, 3}]
    assert Network.arcs_at(ntw, 3) == [{1, 3}]

    for bad <- [-1, 4, 1.0, :one] do
      assert_raise ArgumentError, ~r/vertex/, fn -> Network.arcs_at(ntw, bad) end
    end
  end

  describe "vertex_atol" do
    @undershoot [[{0.0, 0.0}, {1.00001, 0.0}], [{1.0, 0.0}, {2.0, 0.0}]]

    test "rounds vertices to decimals after vertex_sig, and is kept on the network" do
      assert Network.new(@undershoot).network.n_components == 2
      ntw = Network.new(@undershoot, vertex_atol: 4)
      assert ntw.network.n_components == 1
      assert ntw.vertices == [{0.0, 0.0}, {1.0, 0.0}, {2.0, 0.0}]
      assert {ntw.vertex_sig, ntw.vertex_atol} == {11, 4}
      assert Network.new(@undershoot).vertex_atol == nil
    end

    test "derived networks keep it; spanning trees are new networks, as in spaghetti" do
      ntw = Network.new([[{0.0, 0.0}, {4.0, 0.0}], [{4.0, 0.0}, {4.0, 3.0}]], vertex_atol: 2)
      assert Network.split_arcs(ntw, 1.0).vertex_atol == 2
      assert elem(Network.extract_component(ntw, 0), 0).vertex_atol == 2
      assert Network.spanning_tree(ntw).vertex_atol == 2

      ring = [[{0, 0}, {1, 0}], [{1, 0}, {1, 1}], [{1, 1}, {0, 0}]]
      tree = ring |> Network.new(vertex_atol: 2) |> Network.spanning_tree()
      assert {tree.vertex_sig, tree.vertex_atol} == {11, nil}
    end

    test "is validated" do
      line = [[{0, 0}, {1, 1}]]

      for bad <- [0, -1, 18, 2.0, "3"] do
        assert_raise ArgumentError, ~r/:vertex_atol/, fn ->
          Network.new(line, vertex_atol: bad)
        end
      end

      # spaghetti ignores vertex_atol without vertex_sig: refuse it rather than ignore it.
      assert_raise ArgumentError, ~r/:vertex_atol needs :vertex_sig/, fn ->
        Network.new(line, vertex_sig: nil, vertex_atol: 3)
      end
    end
  end
end
