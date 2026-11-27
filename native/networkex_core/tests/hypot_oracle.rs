//! `hypot` against CPython's `math.hypot` (`test/reference/fixtures/hypot/hypot.json`), bit for
//! bit: libpysal measures arcs with it, so arc lengths and split points depend on the last bit.

use networkex_core::hypot::hypot;
use std::path::Path;

/// One scalar array of the fixture. `common.py` writes each scalar array on its own line, as
/// `"name": [v, v, ...]`, with non-finite floats as the strings "nan", "inf" and "-inf".
fn array(json: &str, name: &str) -> Vec<f64> {
    let prefix = format!("\"{name}\": [");
    let line = json
        .lines()
        .map(str::trim)
        .find(|l| l.starts_with(&prefix))
        .unwrap_or_else(|| panic!("no {name} array in the fixture"));
    let body = line[prefix.len()..]
        .trim_end_matches(',')
        .trim_end_matches(']');
    body.split(", ")
        .map(|v| match v.trim_matches('"') {
            "nan" => f64::NAN,
            "inf" => f64::INFINITY,
            "-inf" => f64::NEG_INFINITY,
            s => s
                .parse()
                .unwrap_or_else(|_| panic!("bad float {s:?} in {name}")),
        })
        .collect()
}

#[test]
fn matches_cpython_bit_for_bit() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../test/reference/fixtures/hypot/hypot.json");
    let json = std::fs::read_to_string(&path).expect("hypot fixture");
    let (xs, ys, expected) = (array(&json, "x"), array(&json, "y"), array(&json, "hypot"));
    assert_eq!(xs.len(), expected.len());
    assert_eq!(ys.len(), expected.len());

    let mismatches: Vec<String> = xs
        .iter()
        .zip(&ys)
        .zip(&expected)
        .filter_map(|((&x, &y), &want)| {
            let got = hypot(x, y);
            let same = if want.is_nan() {
                got.is_nan()
            } else {
                got.to_bits() == want.to_bits()
            };
            (!same).then(|| format!("hypot({x:e}, {y:e}): expected {want:e}, got {got:e}"))
        })
        .collect();

    assert!(
        mismatches.is_empty(),
        "{} of {} cases differ from CPython, e.g.:\n{}",
        mismatches.len(),
        expected.len(),
        mismatches[..mismatches.len().min(10)].join("\n")
    );
}
