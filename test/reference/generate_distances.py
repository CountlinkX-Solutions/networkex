"""Generate spaghetti snapping and network distance fixtures (`fixtures/network/distances.json`).

Run from the repository root (under a memory cap):

    prlimit --as=3221225472 .venv/bin/python -I test/reference/generate_distances.py

Cases: the geodanet streets of Tempe with its crimes (the first 60, to keep the fixture small) and
schools; a synthetic network with points on the same arc, points exactly on vertices (snapping
ties), duplicated points and two disconnected components.
"""

import sys
import warnings
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import geopandas as gpd  # noqa: E402
import numpy as np  # noqa: E402
import spaghetti  # noqa: E402
from shapely.geometry import LineString, Point  # noqa: E402

from common import dump_json, meta  # noqa: E402

warnings.simplefilter("ignore")
DATA = Path(__file__).resolve().parent / "data"


def points_gdf(pts):
    return gpd.GeoDataFrame(geometry=[Point(p) for p in pts])


def pattern_record(ntw, name):
    pp = ntw.pointpatterns[name]
    idx = sorted(pp.points)
    arc_of = {}
    for arc, obs in pp.obs_to_arc.items():
        for i in obs:
            arc_of[i] = list(arc)
    return {
        "points": [list(pp.points[i]["coordinates"]) for i in idx],
        "snapped": [list(pp.snapped_coordinates[i]) for i in idx],
        "arcs": [arc_of[i] for i in idx],
        "dist_to_vertex": [list(pp.dist_to_vertex[i].values()) for i in idx],
        "dist_snapped": [pp.dist_snapped[i] for i in idx],
    }


def nearest_record(nn):
    return [[sorted(int(j) for j in nn[i][0]), float(nn[i][1])] for i in sorted(nn)]


def case(name, lines, patterns, full_matrix=True):
    ntw = spaghetti.Network(in_data=gpd.GeoDataFrame(geometry=[LineString(l) for l in lines]))
    for pname, pts in patterns.items():
        ntw.snapobservations(points_gdf(pts), pname)
    out = {"name": name, "lines": lines, "patterns": {p: pattern_record(ntw, p) for p in patterns}}
    ntw.full_distance_matrix(1)
    if full_matrix:
        out["distance_matrix"] = ntw.distance_matrix
    names = list(patterns)
    out["all"] = {}
    out["nearest"] = {}
    for src in names:
        for dst in [None] + [d for d in names if d != src]:
            for snap in [False, True]:
                key = f"{src}|{dst or ''}|{snap}"
                out["all"][key] = ntw.allneighbordistances(src, dst, snap_dist=snap)
                out["nearest"][key] = nearest_record(ntw.nearestneighbordistances(src, dst, snap_dist=snap))
        out["nearest"][f"{src}||False|no_zero"] = nearest_record(
            ntw.nearestneighbordistances(src, None, keep_zero_dist=False))
    return out


def main():
    streets = [[list(c) for c in g.coords] for g in gpd.read_file(DATA / "streets.shp").geometry]
    crimes = [list(g.coords[0]) for g in gpd.read_file(DATA / "crimes.shp").geometry][:60]
    schools = [list(g.coords[0]) for g in gpd.read_file(DATA / "schools.shp").geometry]
    synth_lines = [[[0, 0], [4, 0]], [[4, 0], [4, 3]], [[4, 3], [0, 3]], [[0, 3], [0, 0]],
                   [[4, 0], [8, 0], [8, 2]], [[20, 20], [24, 20]], [[24, 20], [24, 25]]]
    a = [[1, 0.2], [3, -0.5], [4, 0], [4, 1.5], [0, 0], [0.5, 2.9], [6, 0.1], [8, 1], [21, 19], [24, 22], [1, 0.2]]
    b = [[2, 3.1], [7.5, -0.2], [22, 20.5], [4, 3]]
    cases = [
        case("geodanet", streets, {"crimes": crimes, "schools": schools}),
        case("synthetic", synth_lines, {"a": a, "b": b}),
    ]
    dump_json("network/distances.json", {
        "name": "network_distances",
        "description": "spaghetti snapping, distance matrix, all- and nearest-neighbour distances",
        "meta": meta(),
        "cases": cases,
    })
    print(len(cases), "cases")


if __name__ == "__main__":
    main()
