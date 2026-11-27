defmodule Networkex.DistancesTest do
  use ExUnit.Case, async: true

  alias Networkex.{Network, PointPattern}

  @lines [[{0, 0}, {4, 0}, {4, 3}], [{10, 10}, {12, 10}]]

  setup do
    ntw = Network.new(@lines)
    %{ntw: ntw, pp: Network.snap(ntw, [{1, -1}, {4, 2}, {11, 11}])}
  end

  test "snap gives a PointPattern", %{pp: pp} do
    assert %PointPattern{arcs: [{0, 1}, {1, 2}, {3, 4}], dist_snapped: [1.0, +0.0, 1.0]} = pp
    assert pp.snapped == [{1.0, 0.0}, {4.0, 2.0}, {11.0, 10.0}]
  end

  test "components apart are :infinity and the diagonal can be filled", %{ntw: ntw, pp: pp} do
    [[a, b, c] | _] = Network.all_neighbor_distances(ntw, pp)
    assert a == :nan and b == 5.0 and c == :infinity
    [[zero | _] | _] = Network.all_neighbor_distances(ntw, pp, nil, fill_diagonal: 0)
    assert zero == 0.0
    # The third observation is on another component: both others are at :infinity.
    assert Network.nearest_neighbor_distances(ntw, pp) == [
             {[1], 5.0},
             {[0], 5.0},
             {[0, 1], :infinity}
           ]
  end

  test "the distance matrix is guarded", %{ntw: ntw} do
    assert length(Network.distance_matrix(ntw)) == 5

    assert_raise ArgumentError, ~r/max_cells/, fn ->
      Network.distance_matrix(ntw, max_cells: 10)
    end
  end

  test "options are validated", %{ntw: ntw, pp: pp} do
    assert_raise ArgumentError, ~r/options are/, fn ->
      Network.all_neighbor_distances(ntw, pp, nil, bogus: 1)
    end

    assert_raise ArgumentError, ~r/:snap_dist must be true or false/, fn ->
      Network.nearest_neighbor_distances(ntw, pp, nil, snap_dist: 1)
    end

    assert_raise ArgumentError, ~r/:fill_diagonal must be a number/, fn ->
      Network.all_neighbor_distances(ntw, pp, nil, fill_diagonal: :x)
    end
  end
end
