//! Pure-Rust algorithms behind Networkex. No Rustler types here, so everything is unit-testable
//! and reusable outside Elixir.

pub mod distances;
pub mod hypot;
pub mod kfunction;
pub mod lines;
pub mod network;
pub mod persist;
pub mod utilities;
pub mod weights;

/// Version of the Rust-side ABI the Elixir layer expects (bumped on breaking NIF changes).
pub fn abi_version() -> u32 {
    2
}

/// Decodes a native-endian `f64` byte slice (the NIF wire format for numeric vectors).
pub fn bytes_to_f64s(bytes: &[u8]) -> Result<Vec<f64>, String> {
    if !bytes.len().is_multiple_of(8) {
        return Err(format!(
            "f64 binary length {} is not a multiple of 8",
            bytes.len()
        ));
    }
    let (chunks, _) = bytes.as_chunks::<8>();
    Ok(chunks.iter().map(|c| f64::from_ne_bytes(*c)).collect())
}

/// Decodes a native-endian `u32` byte slice (the NIF wire format for index vectors).
pub fn bytes_to_u32s(bytes: &[u8]) -> Result<Vec<u32>, String> {
    if !bytes.len().is_multiple_of(4) {
        return Err(format!(
            "u32 binary length {} is not a multiple of 4",
            bytes.len()
        ));
    }
    let (chunks, _) = bytes.as_chunks::<4>();
    Ok(chunks.iter().map(|c| u32::from_ne_bytes(*c)).collect())
}

/// Encodes `f64`s in the NIF wire format.
pub fn f64s_to_bytes(values: &[f64]) -> Vec<u8> {
    values.iter().flat_map(|v| v.to_ne_bytes()).collect()
}

/// Sums a slice of `f64` (a smoke test of the NIF boundary).
pub fn sum_f64(values: &[f64]) -> f64 {
    values.iter().sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version_is_two() {
        assert_eq!(abi_version(), 2);
    }

    #[test]
    fn f64_wire_format_roundtrips() {
        let values = [1.5_f64, -2.0, f64::INFINITY, 0.0];
        assert_eq!(bytes_to_f64s(&f64s_to_bytes(&values)).unwrap(), values);
        assert_eq!(bytes_to_f64s(&[]).unwrap(), Vec::<f64>::new());
    }

    #[test]
    fn bytes_to_f64s_rejects_bad_length() {
        let err = bytes_to_f64s(&[0u8; 9]).unwrap_err();
        assert!(err.contains("multiple of 8"), "{err}");
    }
}
