#!/usr/bin/env python3
"""Fetch only the PDS MOLA topography rows that cover Jezero.

The public source is a 129,761,280-byte PDS IMG. This script uses one HTTP
Range request for the crater-centered latitude rows, then crops the longitude
columns locally. It aborts if the server ignores Range, so it never silently
downloads the whole source tile.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_URL = (
    "https://pds-geosciences.wustl.edu/mgs/"
    "urn-nasa-pds-mgs_mola_topography_derived/meg128/megt44n000hb.img"
)
LABEL_URL = SOURCE_URL.removesuffix(".img") + ".lbl"
RADIUS_M = 3_396_000.0  # MOLA MEGDR label: spherical radius, metres.
PPD = 128
TILE_W = 11_520
TILE_H = 5_632
ROW_BYTES = TILE_W * 2
TILE_NORTH = 44.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--radius-km",
        type=float,
        default=40.0,
        help="Half-width of the square map area around Jezero's Gazetteer center (default: 40 km).",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=ROOT / "data" / "processed" / "jezero",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not 1.0 <= args.radius_km <= 100.0:
        raise SystemExit("--radius-km must be between 1 and 100")

    # Center from the USGS Planetary Names Gazetteer entry for Jezero.
    center_lon, center_lat = 77.69, 18.41
    half_m = args.radius_km * 1000.0
    half_lat = math.degrees(half_m / RADIUS_M)
    half_lon = math.degrees(half_m / (RADIUS_M * math.cos(math.radians(center_lat))))
    west, east = center_lon - half_lon, center_lon + half_lon
    south, north = center_lat - half_lat, center_lat + half_lat

    if west < 0 or east > 90 or south < 0 or north > 44:
        raise SystemExit("Requested area falls outside MEGT44N000HB.IMG")

    col0 = max(0, math.floor(west * PPD))
    col1 = min(TILE_W, math.ceil(east * PPD))
    row0 = max(0, math.floor((TILE_NORTH - north) * PPD))
    row1 = min(TILE_H, math.ceil((TILE_NORTH - south) * PPD))
    if col1 <= col0 or row1 <= row0:
        raise SystemExit("The requested area produced an empty raster window")

    byte0 = row0 * ROW_BYTES
    byte1 = row1 * ROW_BYTES - 1
    request = urllib.request.Request(
        SOURCE_URL,
        headers={
            "Range": f"bytes={byte0}-{byte1}",
            "User-Agent": "MARS-X terrain preprocessing/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        if response.status != 206:
            raise SystemExit(
                f"PDS server returned HTTP {response.status}, not partial content; "
                "stopped without downloading the full MOLA tile."
            )
        content_range = response.headers.get("Content-Range", "")
        expected_range = f"bytes {byte0}-{byte1}/"
        if not content_range.startswith(expected_range):
            raise SystemExit(f"Unexpected Content-Range: {content_range!r}")
        raw_rows = response.read()

    expected_bytes = (row1 - row0) * ROW_BYTES
    if len(raw_rows) != expected_bytes:
        raise SystemExit(f"Expected {expected_bytes} bytes, received {len(raw_rows)}")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = ROOT / "data" / "raw" / "MOLA"
    raw_dir.mkdir(parents=True, exist_ok=True)
    raw_path = raw_dir / f"MEGT44N000HB_rows_{row0}_{row1}.img"
    raw_path.write_bytes(raw_rows)

    width, height = col1 - col0, row1 - row0
    dem_path = args.out_dir / "jezero_mola_elevation_s16le.bin"
    with dem_path.open("wb") as output:
        for row in range(height):
            row_start = row * ROW_BYTES
            packed = raw_rows[row_start : row_start + ROW_BYTES]
            values = struct.unpack(f">{TILE_W}h", packed)
            output.write(struct.pack(f"<{width}h", *values[col0:col1]))

    transform = {
        "west": col0 / PPD,
        "north": TILE_NORTH - row0 / PPD,
        "east": col1 / PPD,
        "south": TILE_NORTH - row1 / PPD,
        "pixelSizeDegrees": 1.0 / PPD,
    }
    metadata = {
        "dataset": "MGS MOLA MEGDR topography, MEGT44N000HB.IMG",
        "sourceUrl": SOURCE_URL,
        "labelUrl": LABEL_URL,
        "sourceLicense": "Not specified in the product label; retain PDS citation and provenance.",
        "center": {"longitudeEast": center_lon, "latitudePlanetocentric": center_lat},
        "requestedHalfWidthKm": args.radius_km,
        "crs": {
            "body": "Mars",
            "projection": "Simple Cylindrical",
            "latitudeType": "planetocentric",
            "longitudeDirection": "east-positive",
            "radiusMeters": RADIUS_M,
            "linearUnits": "metres",
        },
        "raster": {
            "width": width,
            "height": height,
            "sampleType": "signed 16-bit little-endian",
            "elevationUnits": "metres above MOLA areoid",
            "rowOrder": "north to south",
            "noData": None,
            "transform": transform,
            "file": dem_path.name,
            "sha256": hashlib.sha256(dem_path.read_bytes()).hexdigest(),
        },
        "sourceWindow": {
            "firstRowZeroBased": row0,
            "lastRowExclusive": row1,
            "firstColumnZeroBased": col0,
            "lastColumnExclusive": col1,
            "rawRowsFile": str(raw_path.relative_to(ROOT)),
            "rawBytesFetched": len(raw_rows),
            "fullSourceBytes": 129_761_280,
        },
    }
    (args.out_dir / "jezero_mola_metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"metadata": metadata}, indent=2))


if __name__ == "__main__":
    main()
