// Ported from CPython 3.13 `vector_norm` (Modules/mathmodule.c).
// Copyright (c) 2001-2024 Python Software Foundation; All Rights Reserved.
// Licensed under the Python Software Foundation License Version 2, reproduced in
// LICENSES/PSF-2.0.txt; THIRD_PARTY_NOTICES.md summarises the changes made to CPython's code.

//! Euclidean length of a two-dimensional vector, as CPython's `math.hypot`.
//!
//! libpysal measures segments with `math.hypot`, so arc lengths and the points where spaghetti
//! splits arcs depend on its last bit. CPython does not call the platform's libm `hypot`: it
//! computes the norm with its own algorithm (`vector_norm` in `Modules/mathmodule.c`). `f64::hypot`
//! calls the libm, which rounds some lengths one ulp differently and differs between platforms.
//!
//! This is the same algorithm for two arguments: a lossless power-of-two scaling, error-free
//! squaring with a fused multiply-add (Ogita, Rump and Oishi, 2005), compensated summation of the
//! squares (Neumaier), and a differential correction of the square root (Borges, 2019). It only
//! uses operations IEEE 754 rounds correctly (`+ - * /`, `sqrt` and `mul_add`), so the result is
//! the same on every platform and equals CPython's (verified against
//! `test/reference/fixtures/hypot/hypot.json`).

/// `math.hypot(x, y)`: an infinity wins over a NaN, then a NaN gives NaN.
pub fn hypot(x: f64, y: f64) -> f64 {
    let (x, y) = (x.abs(), y.abs());
    if x.is_infinite() || y.is_infinite() {
        return f64::INFINITY;
    }
    if x.is_nan() || y.is_nan() {
        return f64::NAN;
    }
    norm(x, y, x.max(y))
}

/// `vector_norm` for two finite, non-negative values whose maximum is `max`.
fn norm(x: f64, y: f64, max: f64) -> f64 {
    if max == 0.0 {
        return max;
    }
    let max_e = frexp_exponent(max);
    if max_e < -1023 {
        // 2^-max_e would overflow: bring subnormals into the normal range first (exact).
        return f64::MIN_POSITIVE
            * norm(
                x / f64::MIN_POSITIVE,
                y / f64::MIN_POSITIVE,
                max / f64::MIN_POSITIVE,
            );
    }
    let scale = pow2(-max_e);

    let (mut csum, mut frac1, mut frac2) = (1.0, 0.0, 0.0);
    for v in [x, y] {
        let v = v * scale; // lossless: |v| < 1
        let (hi, lo) = mul(v, v); // lossless squaring
        let (sum, err) = fast_sum(csum, hi); // lossless addition
        csum = sum;
        frac1 += lo;
        frac2 += err;
    }
    let mut h = (csum - 1.0 + (frac1 + frac2)).sqrt();
    let (hi, lo) = mul(-h, h);
    let (sum, err) = fast_sum(csum, hi);
    csum = sum;
    frac1 += lo;
    frac2 += err;
    let x = csum - 1.0 + (frac1 + frac2);
    h += x / (2.0 * h); // differential correction
    h / scale
}

/// Error-free product: `hi + lo == a * b` exactly, with `hi` the rounded product.
fn mul(a: f64, b: f64) -> (f64, f64) {
    let hi = a * b;
    (hi, a.mul_add(b, -hi))
}

/// Error-free sum for `|a| >= |b|`: `hi + lo == a + b` exactly.
fn fast_sum(a: f64, b: f64) -> (f64, f64) {
    let hi = a + b;
    (hi, (a - hi) + b)
}

/// The exponent `e` of `frexp(v)`, `v = m * 2^e` with `0.5 <= m < 1`, for finite `v > 0`.
fn frexp_exponent(v: f64) -> i32 {
    let bits = v.to_bits();
    let biased = ((bits >> 52) & 0x7ff) as i32;
    if biased == 0 {
        // Subnormal: the exponent follows from the highest set bit of the mantissa.
        let mantissa = bits & ((1 << 52) - 1);
        (64 - mantissa.leading_zeros() as i32) - 1074
    } else {
        biased - 1022
    }
}

/// `2^n` for `-1074 <= n <= 1023`, exactly (subnormal below `-1022`).
fn pow2(n: i32) -> f64 {
    if n >= -1022 {
        f64::from_bits(((n + 1023) as u64) << 52)
    } else {
        f64::from_bits(1u64 << (n + 1074))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn special_values() {
        assert_eq!(hypot(3.0, 4.0), 5.0);
        assert_eq!(hypot(-3.0, -4.0), 5.0);
        assert_eq!(hypot(0.0, -0.0).to_bits(), 0.0f64.to_bits());
        assert_eq!(hypot(f64::INFINITY, f64::NAN), f64::INFINITY);
        assert_eq!(hypot(f64::NAN, f64::NEG_INFINITY), f64::INFINITY);
        assert!(hypot(f64::NAN, 1.0).is_nan());
        assert_eq!(hypot(f64::MAX, f64::MAX), f64::INFINITY);
        assert_eq!(hypot(f64::MAX, 0.0), f64::MAX);
        assert_eq!(hypot(5e-324, 0.0), 5e-324);
    }

    #[test]
    fn symmetric() {
        for (x, y) in [(1.5, 2.25), (1e-300, 3e-310), (4096.125, -0.001)] {
            assert_eq!(hypot(x, y).to_bits(), hypot(y, x).to_bits());
        }
    }

    #[test]
    fn exponent_helpers() {
        assert_eq!(frexp_exponent(0.75), 0);
        assert_eq!(frexp_exponent(1.0), 1);
        assert_eq!(frexp_exponent(3.0), 2);
        assert_eq!(frexp_exponent(f64::MIN_POSITIVE), -1021);
        assert_eq!(frexp_exponent(5e-324), -1073);
        assert_eq!(frexp_exponent(f64::MAX), 1024);
        assert_eq!(pow2(0), 1.0);
        assert_eq!(pow2(1023), 2f64.powi(1023));
        assert_eq!(pow2(-1022), f64::MIN_POSITIVE);
        assert_eq!(pow2(-1024), f64::MIN_POSITIVE / 4.0);
        assert_eq!(pow2(-1074), 5e-324);
    }
}
