"""Generate spaghetti Network construction fixtures (`fixtures/network/construction.json`).

Run from the repository root (under a memory cap):

    prlimit --as=3221225472 .venv/bin/python -I test/reference/generate_network.py

Cases: the geodanet streets of Tempe, AZ (293 lines, the spaghetti tutorials' network), a
regular lattice, a ring with a tail, two disconnected paths, duplicated arcs and polylines with
degree-2 vertices, coordinates with many digits under two `vertex_sig` values, a network
without unique arcs, and `vertex_atol` (decimal rounding after `vertex_sig`): an undershoot it
closes, many digits, exact binary ties and a combination with `vertex_sig=4`. Each case stores its input lines as coordinate lists and spaghetti's
vertices, arcs, arc lengths, adjacency, the arcs at each vertex, network components and the
extracted graph.
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


def lines_of(gdf):
    return [[list(c) for c in geom.coords] for geom in gdf.geometry]


def gdf(lines):
    return gpd.GeoDataFrame(geometry=[LineString(l) for l in lines])


def record(name, lines, **kw):
    try:
        ntw = spaghetti.Network(in_data=gdf(lines), **kw)
    except ValueError as e:
        # spaghetti itself fails on this input.
        print("spaghetti fails:", name, kw, e)
        return {"name": name, "options": kw, "lines": lines, "spaghetti_fails": str(e)}
    vertices = [list(ntw.vertex_coords[i]) for i in range(len(ntw.vertex_coords))]
    arcs = [list(a) for a in ntw.arcs]
    edges = [list(e) for e in ntw.edges]
    labels = list(ntw.network_component_labels)
    return {
        "name": name,
        "options": kw,
        "lines": lines,
        "vertices": vertices,
        "arcs": arcs,
        "arc_lengths": [ntw.arc_lengths[tuple(a)] for a in arcs],
        "adjacency": [sorted(ntw.adjacencylist[i]) for i in range(len(vertices))],
        # enum_links_vertex in spaghetti's order (the order the neighbours were found).
        "vertex_links": [[list(a) for a in ntw.enum_links_vertex(i)] for i in range(len(vertices))],
        "network": {
            "n_components": int(ntw.network_n_components),
            "component_labels": labels,
            "component_lengths": [ntw.network_component_lengths[c] for c in sorted(set(labels))],
            "longest_component": int(ntw.network_longest_component),
            "largest_component": int(ntw.network_largest_component),
            "component_is_ring": [bool(ntw.network_component_is_ring[c]) for c in sorted(set(labels))],
            "fully_connected": bool(ntw.network_fully_connected),
        },
        "graph": {
            "edges": edges,
            "edge_lengths": [ntw.edge_lengths[tuple(e)] for e in edges],
            "non_articulation_points": sorted(ntw.non_articulation_points),
            "arcs_to_edges": sorted([list(a), list(e)] for a, e in ntw.arcs_to_edges.items()),
            "n_components": int(ntw.graph_n_components),
            "component_labels": list(ntw.graph_component_labels),
        },
    }


def main():
    streets = lines_of(gpd.read_file(DATA / "streets.shp"))
    lattice = lines_of(gpd.GeoDataFrame(geometry=spaghetti.regular_lattice((0, 0, 3, 3), 2, exterior=True)))
    ring = [[[0, 0], [1, 0]], [[1, 0], [1, 1]], [[1, 1], [0, 1]], [[0, 1], [0, 0]], [[1, 1], [2, 2], [3, 2.5]]]
    disconnected = [[[0, 0], [1, 0], [2, 0]], [[10, 10], [11, 10]], [[11, 10], [11, 12]]]
    duplicates = [[[0, 0], [2, 0]], [[2, 0], [0, 0]], [[2, 0], [3, 1], [4, 1], [5, 3]], [[5, 3], [6, 3]], [[5, 3], [5, 5]]]
    digits = [[[1.23456789012345, 9.87654321098765], [2.3456789012345678, 9.0000000001]],
              [[2.3456789012345678, 9.0000000001], [3.141592653589793, 2.718281828459045]],
              [[3.1415926, 2.7182818], [0.000123456789, -4.5e-7]]]
    # Endpoints that miss each other by about 1e-5: vertex_atol=4 joins them.
    undershoot = [[[0.0, 0.0], [1.00001, 0.0]], [[1.0, 0.0], [2.0, 0.0]],
                  [[2.00002, 0.00001], [2.0, 1.0]], [[2.0, 1.0], [0.0, 0.0]]]
    # Exact binary ties at three decimals: Python rounds them half to even.
    ties = [[[1.0625, 2.1875], [3.0625, -0.0625]], [[3.0625, -0.0625], [5.5, 0.4375]],
            [[5.5, 0.4375], [1.0625, 2.1875]]]
    cases = [
        record("geodanet_streets", streets),
        record("lattice", lattice),
        record("ring_with_tail", ring),
        record("disconnected", disconnected),
        record("duplicates", duplicates),
        record("digits_sig11", digits),
        record("digits_sig4", digits, vertex_sig=4),
        record("duplicates_not_unique", duplicates, unique_arcs=False),
        record("undershoot", undershoot),
        record("undershoot_atol4", undershoot, vertex_atol=4),
        record("digits_atol3", digits, vertex_atol=3),
        record("ties_atol3", ties, vertex_atol=3),
        record("digits_sig4_atol2", digits, vertex_sig=4, vertex_atol=2),
    ]
    dump_json("network/construction.json", {
        "name": "network_construction",
        "description": "spaghetti.Network vertices, arcs, components and extracted graph",
        "meta": meta(),
        "cases": cases,
    })
    print(len(cases), "cases")


if __name__ == "__main__":
    main()
