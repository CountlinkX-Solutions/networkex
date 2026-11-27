defmodule Networkex.PointPattern do
  @moduledoc """
  Observations snapped to a network (`Networkex.Network.snap/2`), after spaghetti's
  `PointPattern` after `snapobservations`.

    * `points` - the observations as given;
    * `snapped` - the nearest point of the network to each observation;
    * `arcs` - the arc (`{i, j}`) each observation is snapped to;
    * `dist_to_vertex` - `{to_i, to_j}`, distances from the snapped point to the arc's vertices;
    * `dist_snapped` - distances from each observation to its snapped point.
  """

  @enforce_keys [:points, :snapped, :arcs, :dist_to_vertex, :dist_snapped]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          points: [{float(), float()}],
          snapped: [{float(), float()}],
          arcs: [{non_neg_integer(), non_neg_integer()}],
          dist_to_vertex: [{float(), float()}],
          dist_snapped: [float()]
        }
end
