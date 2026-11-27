"""Generate `math.hypot` fixtures (`fixtures/hypot/hypot.json`).

Run from the repository root (under a memory cap):

    prlimit --as=3221225472 .venv/bin/python -I test/reference/generate_hypot.py

libpysal measures segments with `math.hypot`, and CPython computes it with its own algorithm,
not with the platform's libm, so arc lengths and split points depend on its last bit. The cases
are special values (zeros, subnormals, values near overflow, infinities and NaN), seeded random
pairs over many magnitudes, coordinate-sized differences, near-equal and very unequal pairs,
integers, and every segment of the geodanet streets. Each case stores `x`, `y` and
`hypot(x, y)`; `meta.python` is the CPython version that computed them.
"""

import math
import platform
import sys
import warnings
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import geopandas as gpd  # noqa: E402
import numpy as np  # noqa: E402

from common import dump_json, meta  # noqa: E402

warnings.simplefilter("ignore")
DATA = Path(__file__).resolve().parent / "data"
SEED = 20261112

TINY = 5e-324  # smallest subnormal
MIN = sys.float_info.min  # smallest normal
MAX = sys.float_info.max
INF = math.inf
NAN = math.nan


def special():
    values = [0.0, -0.0, TINY, 3 * TINY, MIN / 2, MIN, 2 * MIN, 1.0, 3.0, 4.0, 1e300, MAX / 2, MAX]
    pairs = [(x, y) for x in values for y in values]
    pairs += [(INF, 1.0), (1.0, -INF), (INF, NAN), (NAN, -INF), (NAN, 1.0), (0.0, NAN)]
    pairs += [(NAN, NAN), (INF, INF), (-3.0, -4.0), (-0.0, 5.0)]
    return pairs


def random_pairs(rng):
    def floats(n, lo_exp, hi_exp):
        mantissa = rng.uniform(1.0, 2.0, n)
        exponent = rng.integers(lo_exp, hi_exp, n, endpoint=True)
        sign = rng.choice([-1.0, 1.0], n)
        return sign * np.ldexp(mantissa, exponent)

    pairs = []
    # Any magnitudes, independently.
    pairs += zip(floats(1500, -60, 60), floats(1500, -60, 60))
    # Near the ends of the exponent range.
    pairs += zip(floats(100, 1015, 1023), floats(100, 1000, 1023))
    pairs += zip(floats(100, -1022, -1000), floats(100, -1022, -990))
    # Subnormals.
    subnormal = lambda n: rng.integers(1, 2**52, n).astype(np.uint64).view(np.float64)  # noqa: E731
    pairs += zip(subnormal(100), subnormal(100))
    # Coordinate differences of projected data, in metres.
    pairs += zip(rng.uniform(-5000.0, 5000.0, 1500), rng.uniform(-5000.0, 5000.0, 1500))
    # Near-equal legs.
    x = rng.uniform(1.0, 1e4, 500)
    pairs += zip(x, x * (1.0 + rng.uniform(-1e-6, 1e-6, 500)))
    # One leg much shorter.
    x = rng.uniform(1.0, 1e4, 500)
    pairs += zip(x, x * 10.0 ** rng.uniform(-20.0, -1.0, 500))
    # Integers.
    pairs += zip(rng.integers(0, 10**6, 200).astype(float), rng.integers(0, 10**6, 200).astype(float))
    return [(float(x), float(y)) for x, y in pairs]


def geodanet_segments():
    """The coordinate differences libpysal's `get_points_dist` measures on the geodanet streets."""
    streets = gpd.read_file(DATA / "streets.shp")
    pairs = []
    for geom in streets.geometry:
        coords = list(geom.coords)
        for (x0, y0), (x1, y1) in zip(coords, coords[1:]):
            pairs.append((x0 - x1, y0 - y1))
    return pairs


def main():
    rng = np.random.default_rng(SEED)
    pairs = special() + random_pairs(rng) + geodanet_segments()
    cases = {
        "x": [x for x, _ in pairs],
        "y": [y for _, y in pairs],
        "hypot": [math.hypot(x, y) for x, y in pairs],
    }
    fixture_meta = {**meta(), "python": platform.python_version(), "seed": SEED}
    dump_json("hypot/hypot.json", {"cases": cases, "meta": fixture_meta})
    print(f"hypot: {len(pairs)} cases")


if __name__ == "__main__":
    main()
