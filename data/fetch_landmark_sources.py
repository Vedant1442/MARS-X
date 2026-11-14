#!/usr/bin/env python3
"""Download authoritative Jezero geology and rover-location source files.

Run from the repository root with:
    python data/fetch_landmark_sources.py

Use --force to replace existing downloads. Large source files stay in
data/raw/JezeroLandmarks/ and are not included in the APK.
"""
from __future__ import annotations

import argparse
import os
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "data" / "raw" / "JezeroLandmarks"
SOURCES = [
    ("USGS SIM 3464 geodatabase ZIP", "https://pubs.usgs.gov/sim/3464/sim3464_database.zip", "sim3464_database.zip"),
    ("PDS PLACES rover localizations", "https://pds-geosciences.wustl.edu/m2020/urn-nasa-pds-mars2020_rover_places/data_localizations/best_interp.csv", "best_interp.csv"),
    ("PDS PLACES product label", "https://pds-geosciences.wustl.edu/m2020/urn-nasa-pds-mars2020_rover_places/data_localizations/best_interp.csv.xml", "best_interp.csv.xml"),
    ("PDS PLACES release notes", "https://pds-geosciences.wustl.edu/m2020/urn-nasa-pds-mars2020_rover_places/document/release_notes.txt", "release_notes.txt"),
    ("PDS Three Forks sample-drop events", "https://pds-geosciences.wustl.edu/m2020/urn-nasa-pds-mars2020_sample_depot_three_forks/data/sample_drop_events/sample_drop_timestamps.csv", "ThreeForks/sample_drop_timestamps.csv"),
    ("PDS Three Forks event-table label", "https://pds-geosciences.wustl.edu/m2020/urn-nasa-pds-mars2020_sample_depot_three_forks/data/sample_drop_events/sample_drop_timestamps.xml", "ThreeForks/sample_drop_timestamps.xml"),
]


def download(name: str, url: str, relative_path: str, force: bool) -> None:
    path = DEST / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.stat().st_size and not force:
        print(f"Already present: {relative_path} ({path.stat().st_size:,} bytes); use --force to refresh")
        return
    partial = path.with_suffix(path.suffix + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": "MARS-X-landmark-data/1.0"})
    total = 0
    try:
        with urllib.request.urlopen(request, timeout=60) as response, partial.open("wb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
                total += len(chunk)
                if total % (32 * 1024 * 1024) < len(chunk):
                    print(f"{name}: {total / (1024 * 1024):.0f} MiB downloaded", flush=True)
        os.replace(partial, path)
    except Exception:
        partial.unlink(missing_ok=True)
        raise
    print(f"Downloaded: {relative_path} ({total:,} bytes)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="replace existing files")
    args = parser.parse_args()
    for name, url, path in SOURCES:
        download(name, url, path, args.force)


if __name__ == "__main__":
    main()
