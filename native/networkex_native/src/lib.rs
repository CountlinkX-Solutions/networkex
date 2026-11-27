//! Thin Rustler layer over `networkex_core`. NIFs return `Result<_, String>`; heavy ones run on
//! the dirty CPU scheduler.

mod network;

use rustler::Binary;

#[rustler::nif]
fn nif_version() -> u32 {
    networkex_core::abi_version()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn sum_f64(binary: Binary) -> Result<f64, String> {
    let values = networkex_core::bytes_to_f64s(binary.as_slice())?;
    Ok(networkex_core::sum_f64(&values))
}

rustler::init!("Elixir.Networkex.Native");
