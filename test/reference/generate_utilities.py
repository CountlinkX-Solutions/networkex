"""Generate spaghetti network utility fixtures (`fixtures/network/utilities.json`).

Run from the repository root (under a memory cap):

    prlimit --as=3221225472 .venv/bin/python -I test/reference/generate_utilities.py

* `regular_lattice` for several bounds, counts and with or without the exterior;
* `Network.split_arcs` by distance and by count on the geodanet streets and on a lattice (whose
  vertical arcs run downwards in one line), with the crimes snapped to the split network;
* `extract_component` of each component of a network made of three disconnected pieces;
* `spanning_tree` (minimum and maximum) of the streets, of a lattice and of a network that is
  already a tree.
"""

import sys
import warnings
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import geopandas as gpd  # noqa: E402
import spaghetti  # noqa: E402
from shapely.geometry import LineString  # noqa: E402

from common import dump_json, meta  # noqa: E402

warnings.simplefilter("ignore")
DATA = Path(__file__).resolve().parent / "data"


def lines_of(geoms):
    # shapely lines or libpysal chains (what regular_lattice returns).
    coords = lambda g: g.coords if hasattr(g, "coords") else g.vertices  # noqa: E731
    return [[[float(c[0]), float(c[1])] for c in coords(g)] for g in geoms]


def gdf(lines):
    return gpd.GeoDataFrame(geometry=[LineString(l) for l in lines])


def network_state(ntw, graph=True):
    ids = sorted(ntw.vertex_coords)
    arcs = [list(a) for a in ntw.arcs]
    labels = [int(v) for v in ntw.network_component_labels]
    out = {
        "vertex_ids": ids,
        "vertices": [list(map(float, ntw.vertex_coords[i])) for i in ids],
        "arcs": arcs,
        "arc_lengths": [float(ntw.arc_lengths[tuple(a)]) for a in arcs],
        "arc_order": [list(a) for a in ntw.arc_lengths],
        "adjacency": [sorted(ntw.adjacencylist[i]) for i in ids],
        "network": {
            "n_components": int(ntw.network_n_components),
            "component_labels": labels,
            "component_lengths": [float(ntw.network_component_lengths[c]) for c in sorted(set(labels))],
            "longest_component": int(ntw.network_longest_component),
            "largest_component": int(ntw.network_largest_component),
            "fully_connected": bool(ntw.network_fully_connected),
        },
    }
    if graph:
        edges = [list(e) for e in ntw.edges]
        out["graph"] = {
            "edges": edges,
            "edge_lengths": [float(ntw.edge_lengths[tuple(e)]) for e in edges],
            "non_articulation_points": sorted(ntw.non_articulation_points),
        }
    return out


def lattices():
    out = []
    for bounds, nh, nv, exterior in [
        ((0, 0, 1, 1), 1, None, False),
        ((0, 0, 1, 1), 2, None, True),
        ((0, 0, 3, 3), 2, None, True),
        ((-3.5, 2, 10, 7.25), 4, 2, False),
        ((-3.5, 2, 10, 7.25), 4, 2, True),
        ((0, 0, 10, 4), 3, 1, True),
    ]:
        lines = lines_of(spaghetti.regular_lattice(bounds, nh, nv=nv, exterior=exterior))
        out.append({"bounds": list(bounds), "nh": nh, "nv": nv, "exterior": exterior, "lines": lines})
    return out


def splits(streets, crimes, lattice):
    out = []
    for name, lines, params in [
        ("streets", streets, [(500.0, "distance"), (1000.0, "distance"), (2, "count"), (3, "count")]),
        ("lattice", lattice, [(0.4, "distance"), (0.25, "distance"), (3, "count")]),
    ]:
        for param, by in params:
            ntw = spaghetti.Network(in_data=gdf(lines))
            if name == "streets":
                ntw.snapobservations(crimes, "crimes")
            split = ntw.split_arcs(param, split_by=by)
            case = {"source": name, "split_param": param, "split_by": by, **network_state(split, graph=False)}
            if name == "streets":
                pp = split.pointpatterns["crimes"]
                ids = sorted(pp.obs_to_arc and pp.snapped_coordinates)
                arc_of = {o: a for a, obs in pp.obs_to_arc.items() for o in obs}
                case["crimes"] = {
                    "arcs": [list(arc_of[i]) for i in ids],
                    "snapped": [list(map(float, pp.snapped_coordinates[i])) for i in ids],
                    "dist_to_vertex": [[float(pp.dist_to_vertex[i][a]) for a in arc_of[i]] for i in ids],
                }
            out.append(case)
    return out


def components():
    pieces = (lines_of(spaghetti.regular_lattice((0, 0, 3, 3), 2, exterior=True))
              + [[[10.0, 0.0], [11.0, 0.0], [12.0, 1.0], [13.0, 1.0]], [[11.0, 0.0], [11.0, -2.0]]]
              + [[[20.0, 20.0], [21.0, 20.0]], [[21.0, 20.0], [21.0, 21.0]], [[21.0, 21.0], [20.0, 20.0]]])
    ntw = spaghetti.Network(in_data=gdf(pieces))
    labels = sorted(set(int(v) for v in ntw.network_component_labels))
    return {"lines": pieces,
            "components": [{"component": c, **network_state(spaghetti.extract_component(ntw, c))}
                           for c in labels]}


def trees(streets, lattice):
    out = []
    tree = [[[0.0, 0.0], [1.0, 0.0], [2.0, 0.0]], [[1.0, 0.0], [1.0, 1.0]]]
    for name, lines in [("streets", streets), ("lattice", lattice), ("tree", tree)]:
        for maximum in [False, True]:
            ntw = spaghetti.Network(in_data=gdf(lines))
            st = spaghetti.spanning_tree(ntw, maximum=maximum)
            out.append({"source": name, "maximum": maximum, **network_state(st)})
    return out


def main():
    streets = lines_of(gpd.read_file(DATA / "streets.shp").geometry)
    crimes = gpd.read_file(DATA / "crimes.shp")
    # A lattice whose last vertical line runs downwards.
    lattice = lines_of(spaghetti.regular_lattice((0, 0, 2, 2), 1, exterior=True))
    lattice.append([[2.5, 2.0], [2.5, 0.0]])
    lattice.append([[2.0, 2.0], [2.5, 2.0]])
    out = {
        "lattice": lattice,
        "regular_lattice": lattices(),
        "split_arcs": splits(streets, crimes, lattice),
        "extract_component": components(),
        "spanning_tree": trees(streets, lattice),
    }
    dump_json("network/utilities.json", {
        "name": "network_utilities",
        "description": "spaghetti regular_lattice, split_arcs, extract_component and spanning_tree",
        "meta": meta(),
        "cases": out,
    })
    print("ok")


if __name__ == "__main__":
    main()
