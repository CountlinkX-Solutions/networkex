"""Generate spaghetti network weights and count fixtures (`fixtures/network/weights.json`).

Run from the repository root (under a memory cap):

    prlimit --as=3221225472 .venv/bin/python -I test/reference/generate_weights.py

The geodanet streets of Tempe with the crimes: contiguity weights of the arcs and of the graph
edges (binary and weighted by length), distance-band weights of the vertices for two thresholds,
the observation counts per arc and per graph edge, and the count vectors spaghetti's Moran uses
(with Moran's I and its analytic moments for reference).
"""

import sys
import warnings
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import geopandas as gpd  # noqa: E402
import numpy as np  # noqa: E402
import spaghetti  # noqa: E402

from common import dump_json, meta  # noqa: E402

warnings.simplefilter("ignore")
DATA = Path(__file__).resolve().parent / "data"


def triples(w, ids):
    index = {k: i for i, k in enumerate(ids)}
    out = []
    for k in w.neighbors:
        for n, wt in zip(w.neighbors[k], w.weights[k]):
            out.append([index[k], index[n], float(wt)])
    return {"n": int(w.n), "keys": [index[k] for k in w.neighbors], "triples": out}


def main():
    streets = gpd.read_file(DATA / "streets.shp")
    ntw = spaghetti.Network(in_data=streets)
    ntw_w = spaghetti.Network(in_data=streets, weightings=True)
    ntw.snapobservations(gpd.read_file(DATA / "crimes.shp"), "crimes")
    arcs, edges = ntw.arcs, ntw.edges
    out = {
        "network_binary": triples(ntw.w_network, arcs),
        "graph_binary": triples(ntw.w_graph, edges),
        "network_lengths": triples(ntw_w.w_network, ntw_w.arcs),
        "graph_lengths": triples(ntw_w.w_graph, ntw_w.edges),
        "distance_band": {},
    }
    vertices = list(range(len(ntw.vertex_list)))
    # Custom weightings: one seeded value per arc (or edge); each neighbour gets its own value.
    rng = np.random.default_rng(20261112)
    for name, graph, links in [("network_custom", False, arcs), ("graph_custom", True, edges)]:
        values = [float(v) for v in rng.uniform(0.5, 10.0, len(links))]
        w = ntw.contiguityweights(graph=graph, weightings=dict(zip(links, values)))
        out[name] = {**triples(w, links), "values": values}
    for t in [500.0, 1500.0]:
        out["distance_band"][str(t)] = triples(ntw.distancebandweights(t), vertices)
    pp = ntw.pointpatterns["crimes"]
    out["counts_network"] = sorted([list(k), v] for k, v in ntw.count_per_link(pp.obs_to_arc, graph=False).items())
    out["counts_graph"] = sorted([list(k), v] for k, v in ntw.count_per_link(pp.obs_to_arc, graph=True).items())
    for graph in [False, True]:
        moran, y = ntw.Moran("crimes", permutations=0, graph=graph)
        out["moran_graph" if graph else "moran_network"] = {"y": [float(v) for v in y], "I": moran.I, "EI": moran.EI,
                                                            "VI_norm": moran.VI_norm, "z_norm": moran.z_norm}
    dump_json("network/weights.json", {
        "name": "network_weights",
        "description": "spaghetti contiguity and distance-band weights, counts per link, Moran inputs",
        "meta": meta(),
        "cases": out,
    })
    print("ok")


if __name__ == "__main__":
    main()
