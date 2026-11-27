"""Shared helpers for the oracle fixture generators (dev-only; CI never runs Python).

Conventions
-----------
* Output is deterministic JSON: sorted keys, floats written with ``repr`` precision (shortest
  string that round-trips), one scalar array per line so diffs stay reviewable.
* JSON has no NaN/Infinity, so non-finite floats are written as the strings ``"nan"``,
  ``"inf"`` and ``"-inf"``. ``Networkex.Reference.load!/1`` decodes them.
* Every fixture carries a ``meta`` block with the library versions that produced it.
"""

import json
import math
from pathlib import Path

import numpy as np

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def meta():
    """Versions of the libraries that generated a fixture."""
    import libpysal
    import scipy
    import spaghetti

    return {
        "libpysal": libpysal.__version__,
        "numpy": np.__version__,
        "scipy": scipy.__version__,
        "spaghetti": spaghetti.__version__,
    }


def plain(obj):
    """Convert numpy values to plain JSON-ready Python, encoding non-finite floats."""
    if isinstance(obj, dict):
        return {str(k): plain(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [plain(v) for v in obj]
    if isinstance(obj, np.ndarray):
        return [plain(v) for v in obj.tolist()]
    if isinstance(obj, (np.bool_, bool)):
        return bool(obj)
    if isinstance(obj, (np.integer, int)):
        return int(obj)
    if isinstance(obj, (np.floating, float)):
        x = float(obj)
        if math.isnan(x):
            return "nan"
        if math.isinf(x):
            return "inf" if x > 0 else "-inf"
        return x
    return obj


def _render(obj, indent=0):
    pad = " " * (indent + 1)
    if isinstance(obj, dict):
        if not obj:
            return "{}"
        items = [f"{pad}{json.dumps(k)}: {_render(obj[k], indent + 1)}" for k in sorted(obj)]
        return "{\n" + ",\n".join(items) + "\n" + " " * indent + "}"
    if isinstance(obj, list):
        if all(not isinstance(v, (dict, list)) for v in obj):
            return "[" + ", ".join(json.dumps(v) for v in obj) + "]"
        items = [f"{pad}{_render(v, indent + 1)}" for v in obj]
        return "[\n" + ",\n".join(items) + "\n" + " " * indent + "]"
    return json.dumps(obj)


def dump_json(path, obj):
    """Write ``obj`` as deterministic JSON to ``path`` (relative paths go under fixtures/)."""
    path = Path(path)
    if not path.is_absolute():
        path = FIXTURES / path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_render(plain(obj)) + "\n")
