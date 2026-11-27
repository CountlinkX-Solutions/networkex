"""Generate spaghetti K-function fixtures (`fixtures/network/kfunction.json`).

Run from the repository root (under a memory cap):

    prlimit --as=3221225472 .venv/bin/python -I test/reference/generate_kfunction.py

The geodanet streets of Tempe with the schools and the crimes. spaghetti draws its simulated
observations with `numpy.random.uniform`; the draws are recorded so that the simulations can be
replayed exactly: `simulate_observations` (the arc each draw falls on, the coordinates and the
distances to the arc's vertices) and `GlobalAutoK` (the observed curve, every simulated curve and
the envelopes) for several step counts, thresholds and upper bounds.
"""

import sys
import warnings
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import geopandas as gpd  # noqa: E402
import numpy  # noqa: E402
import spaghetti  # noqa: E402

from common import dump_json, meta  # noqa: E402

warnings.simplefilter("ignore")
DATA = Path(__file__).resolve().parent / "data"

DRAWS = []
_uniform = numpy.random.uniform


def recording_uniform(*args, **kwargs):
    out = _uniform(*args, **kwargs)
    DRAWS.append([float(v) for v in numpy.atleast_1d(out)])
    return out


numpy.random.uniform = recording_uniform


def floats(values):
    return [float(v) for v in values]


def simulated(ntw, count, seed):
    numpy.random.seed(seed)
    DRAWS.clear()
    sim = ntw.simulate_observations(count)
    arcs, coords, to_vertex = [], [], []
    for i in range(count):
        d2v = sim.dist_to_vertex[i]
        a, b = list(d2v)
        arcs.append([a, b])
        coords.append(floats(sim.snapped_coordinates[i]))
        to_vertex.append([float(d2v[a]), float(d2v[b])])
    return {"count": count, "positions": DRAWS[0], "arcs": arcs, "coords": coords, "to_vertex": to_vertex}


def k_case(ntw, name, nsteps, permutations, threshold, upperbound, seed):
    pp = ntw.pointpatterns[name]
    numpy.random.seed(seed)
    DRAWS.clear()
    k = ntw.GlobalAutoK(pp, nsteps=nsteps, permutations=permutations, threshold=threshold,
                        upperbound=upperbound)
    return {
        "pattern": name, "nsteps": nsteps, "permutations": permutations, "threshold": threshold,
        "upperbound_option": upperbound, "simulations": [list(d) for d in DRAWS],
        "lam": float(k.lam), "upperbound": float(k.upperbound), "xaxis": floats(k.xaxis),
        "observed": floats(k.observed), "sim": [floats(row) for row in k.sim],
        "upper": floats(k.upperenvelope), "lower": floats(k.lowerenvelope),
    }


def main():
    ntw = spaghetti.Network(in_data=gpd.read_file(DATA / "streets.shp"))
    for name in ["schools", "crimes"]:
        ntw.snapobservations(gpd.read_file(DATA / f"{name}.shp"), name)
    out = {
        "arc_order": [list(a) for a in ntw.arc_lengths],
        "simulate": [simulated(ntw, 60, 7), simulated(ntw, 300, 11)],
        "global_auto_k": [
            k_case(ntw, "schools", 10, 9, 0.5, None, 1),
            k_case(ntw, "schools", 25, 5, 0.1, 3000.0, 2),
            k_case(ntw, "crimes", 10, 4, 0.5, None, 3),
            k_case(ntw, "crimes", 7, 3, 0.25, 1500.0, 4),
        ],
    }
    dump_json("network/kfunction.json", {
        "name": "network_kfunction",
        "description": "spaghetti GlobalAutoK and simulate_observations with recorded draws",
        "meta": meta(),
        "cases": out,
    })
    print("ok")


if __name__ == "__main__":
    main()
