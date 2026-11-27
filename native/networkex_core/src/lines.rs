//! Polylines from the NIF wire format: flat coordinates with part offsets, or WKB
//! `LineString` / `MultiLineString` geometries (each line string one part).

use geo_traits::{CoordTrait, GeometryTrait, GeometryType, LineStringTrait, MultiLineStringTrait};
use wkb::reader::read_wkb;

/// Splits flat `[x0, y0, x1, y1, ...]` coordinates into parts at the vertex `offsets`
/// (`offsets[i]..offsets[i + 1]`, the last offset the vertex count).
pub fn from_offsets(coords: &[f64], offsets: &[u32]) -> Result<Vec<Vec<[f64; 2]>>, String> {
    let n = coords.len() / 2;
    let mut out = Vec::with_capacity(offsets.len().saturating_sub(1));
    for w in offsets.windows(2) {
        let (a, b) = (w[0] as usize, w[1] as usize);
        if a > b || b > n {
            return Err("line offsets are out of range".to_string());
        }
        out.push((a..b).map(|i| [coords[2 * i], coords[2 * i + 1]]).collect());
    }
    Ok(out)
}

fn push_line<L: LineStringTrait<T = f64>>(out: &mut Vec<Vec<[f64; 2]>>, line: &L) {
    out.push(line.coords().map(|c| [c.x(), c.y()]).collect());
}

/// Parts of WKB line geometries.
pub fn from_wkb(wkbs: &[&[u8]]) -> Result<Vec<Vec<[f64; 2]>>, String> {
    let mut out = Vec::new();
    for (i, bytes) in wkbs.iter().enumerate() {
        let parsed = read_wkb(bytes).map_err(|e| format!("geometry {i}: invalid WKB ({e})"))?;
        match parsed.as_type() {
            GeometryType::LineString(l) => push_line(&mut out, l),
            GeometryType::MultiLineString(ml) => {
                for l in ml.line_strings() {
                    push_line(&mut out, &l);
                }
            }
            _ => {
                return Err(format!(
                    "geometry {i}: expected LineString or MultiLineString"
                ))
            }
        }
    }
    Ok(out)
}
