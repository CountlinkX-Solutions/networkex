"""Generate spaghetti shortest-path fixtures (`fixtures/network/paths.json`).

Run from the repository root (under a memory cap):

    prlimit --as=3221225472 .venv/bin/python -I test/reference/generate_paths.py

`Network.shortest_paths` from the trees of `allneighbordistances(gen_tree=True)`: the schools
of the geodanet streets among themselves, 40 crimes to the schools, and points on a lattice,
where many routes tie in length. Each path is the pair of observations, the (source, destination)
vertices spaghetti chose (or the same arc) and the path's coordinates.
"""

import sys
import warnings
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import geopandas as gpd  # noqa: E402
import spaghetti  # noqa: E402
from shapely.geometry import LineString, Point  # noqa: E402

from common import dump_json, meta  # noqa: E402

warnings.simplefilter("ignore")
DATA = Path(__file__).resolve().parent / "data"


def lines_of(geoms):
    coords = lambda g: g.coords if hasattr(g, "coords") else g.vertices  # noqa: E731
    return [[[float(c[0]), float(c[1])] for c in coords(g)] for g in geoms]


def case(ntw, name, orig, dest=None):
    _, tree = ntw.allneighbordistances(orig, destpattern=dest, gen_tree=True)
    paths = ntw.shortest_paths(tree, orig, pp_dest=dest)
    out = []
    for (pair, chain) in paths:
        via = tree[pair]
        out.append({"pair": [int(pair[0]), int(pair[1])],
                    "via": None if via == (-0.1, -0.1) else [int(via[0]), int(via[1])],
                    "path": [[float(v[0]), float(v[1])] for v in chain.vertices]})
    return {"name": name, "orig": orig, "dest": dest, "paths": out}


def main():
    streets = gpd.read_file(DATA / "streets.shp")
    ntw = spaghetti.Network(in_data=streets)
    ntw.snapobservations(gpd.read_file(DATA / "schools.shp"), "schools")
    crimes = gpd.read_file(DATA / "crimes.shp").iloc[:40]
    ntw.snapobservations(crimes, "crimes40")
    lattice = lines_of(spaghetti.regular_lattice((0, 0, 4, 4), 3, exterior=True))
    lat = spaghetti.Network(in_data=gpd.GeoDataFrame(geometry=[LineString(l) for l in lattice]))
    pts = [Point(0.3, 0.0), Point(3.7, 4.0), Point(2.0, 1.4), Point(0.0, 2.6), Point(4.0, 0.5)]
    lat.snapobservations(gpd.GeoDataFrame(geometry=pts), "pts")
    out = {
        "lattice": lattice,
        "lattice_points": [[p.x, p.y] for p in pts],
        "cases": [
            case(ntw, "schools", "schools"),
            case(ntw, "crimes_to_schools", "crimes40", "schools"),
            case(lat, "lattice", "pts"),
        ],
    }
    dump_json("network/paths.json", {
        "name": "network_paths",
        "description": "spaghetti shortest_paths from allneighbordistances trees",
        "meta": meta(),
        "cases": out,
    })
    print("ok")


if __name__ == "__main__":
    main()
