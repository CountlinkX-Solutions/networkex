defmodule Networkex.WeightsTest do
  use ExUnit.Case, async: true

  alias Networkex.Network

  setup do
    %{ntw: Network.new([[{0, 0}, {1, 0}, {3, 0}], [{1, 0}, {1, 2}], [{10, 10}, {11, 10}]])}
  end

  test "an arc on its own is an island", %{ntw: ntw} do
    w = Network.contiguity_weights(ntw)
    assert w.n == 4
    refute 3 in w.focal
  end

  test "counts per link and per edge", %{ntw: ntw} do
    pp = Network.snap(ntw, [{0.5, 0.1}, {2, -0.1}, {2.5, 0}, {10.5, 10}])
    assert Network.counts_per_link(ntw, pp) == [1, 2, 0, 1]
    assert length(Network.counts_per_link(ntw, pp, graph: true)) == length(ntw.graph.edges)
  end

  test "a value per link weights each neighbour by the neighbour's value", %{ntw: ntw} do
    w = Network.contiguity_weights(ntw, weighting: [10, 20, 30, 40])
    assert {w.n, w.focal, w.neighbor} == {4, [0, 0, 1, 1, 2, 2], [1, 2, 0, 2, 0, 1]}
    assert w.weight == [20.0, 30.0, 10.0, 30.0, 10.0, 20.0]

    assert Network.contiguity_weights(ntw, weighting: Nx.tensor([10, 20, 30, 40])) == w
    assert Network.contiguity_weights(ntw, graph: true, weighting: [10, 20, 30, 40]) == w
  end

  test "options are validated", %{ntw: ntw} do
    assert_raise ArgumentError, ~r/:weighting must be/, fn ->
      Network.contiguity_weights(ntw, weighting: :inverse)
    end

    assert_raise ArgumentError, ~r/weighting.*length 4/s, fn ->
      Network.contiguity_weights(ntw, weighting: [1, 2, 3])
    end

    assert_raise ArgumentError, ~r/weighting/, fn ->
      Network.contiguity_weights(ntw, weighting: [1, 2, :nan, 4])
    end

    assert_raise ArgumentError, ~r/options are/, fn -> Network.contiguity_weights(ntw, k: 2) end

    assert_raise ArgumentError, ~r/max_cells/, fn ->
      Network.distance_band_weights(ntw, 5, max_cells: 4)
    end
  end
end
