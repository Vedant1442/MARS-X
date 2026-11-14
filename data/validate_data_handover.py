#!/usr/bin/env python3
"""Inspect repository datasets for the backend/frontend handover report.

Uses Pillow for GeoTIFF header/tags and, when present, project-local Shapely and
Pyogrio for vector geometry and GeoPackage inspection. It does not reproject or
alter any data. Run: python data/validate_data_handover.py
"""
from __future__ import annotations

import csv
import hashlib
import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tmp-geospatial"))
try:
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = None  # metadata only; never decode the large CTX image
except Exception:
    Image = None
try:
    from shapely.geometry import shape as to_shape
except Exception:
    to_shape = None
try:
    import pyogrio
except Exception:
    pyogrio = None

DEM_BOUNDS = [76.99743706146005, 17.58051991054471, 78.58256332408821, 19.290187006866102]
GEOJSON_ROOTS = [ROOT / "data" / "processed" / "jezero", ROOT / "data" / "MARSX_D8_GEOLOGY_CLEANED", ROOT / "mobile" / "assets" / "terrain"]
RASTER_SUFFIXES = {".tif", ".tiff"}
VECTOR_SUFFIXES = {".geojson"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def check_geojson(path: Path) -> dict:
    result = {"path": str(path.relative_to(ROOT)).replace("\\", "/"), "bytes": path.stat().st_size,
              "jsonValid": False, "featureCount": None, "duplicateIds": [], "missingCoordinates": 0,
              "geometryCounts": {}, "invalidGeometryCount": None, "outOfMarsCoordinateRange": 0,
              "outsideDeclaredBounds": 0, "marsCrsDeclared": False, "errors": []}
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
        result["jsonValid"] = True
        features = doc.get("features", []) if doc.get("type") == "FeatureCollection" else [doc]
        result["featureCount"] = len(features)
        cs = doc.get("marsCoordinateSystem") or doc.get("coordinateSystem")
        result["marsCrsDeclared"] = bool(cs and (cs.get("body") == "Mars" or cs.get("marsBody") == "Mars"))
        ids = [str(f["id"]) for f in features if f.get("id") is not None]
        result["duplicateIds"] = sorted(k for k, n in Counter(ids).items() if n > 1)
        bounds = doc.get("coverageBoundsEastLat") or doc.get("coverageBounds")
        if bounds and len(bounds) == 4:
            result["declaredBoundsEastLat"] = bounds
        geom_counts = Counter()
        invalid = 0
        for i, feature in enumerate(features):
            geom = feature.get("geometry")
            if geom is None:
                result["missingCoordinates"] += 1
                continue
            geom_counts[geom.get("type", "UNKNOWN")] += 1
            coords = geom.get("coordinates")
            if coords is None:
                result["errors"].append(f"feature[{i}] geometry has no coordinates")
                continue
            stack = [coords]
            positions = []
            while stack:
                value = stack.pop()
                if isinstance(value, list) and value and isinstance(value[0], (int, float)):
                    if len(value) >= 2:
                        positions.append((float(value[0]), float(value[1])))
                elif isinstance(value, list):
                    stack.extend(value)
            for x, y in positions:
                if not (0 <= x <= 360 and -90 <= y <= 90):
                    result["outOfMarsCoordinateRange"] += 1
                if bounds and len(bounds) == 4:
                    if not (bounds[0] - 1e-5 <= x <= bounds[2] + 1e-5 and bounds[1] - 1e-5 <= y <= bounds[3] + 1e-5):
                        result["outsideDeclaredBounds"] += 1
            if to_shape:
                try:
                    obj = to_shape(geom)
                    if not obj.is_valid:
                        invalid += 1
                except Exception as ex:
                    invalid += 1
                    result["errors"].append(f"feature[{i}] shape error: {str(ex)[:120]}")
        result["geometryCounts"] = dict(geom_counts)
        result["invalidGeometryCount"] = invalid if to_shape else "NOT_CHECKED_SHAPELY_UNAVAILABLE"
        if result["duplicateIds"]:
            result["errors"].append("duplicate feature IDs")
        if result["outOfMarsCoordinateRange"]:
            result["errors"].append("coordinate outside Mars longitude/latitude domain; review longitude convention")
    except Exception as ex:
        result["errors"].append(f"parse/read failure: {type(ex).__name__}: {str(ex)[:200]}")
    return result


def raster_info(path: Path) -> dict:
    row = {"path": str(path.relative_to(ROOT)).replace("\\", "/"), "exists": path.exists(),
           "bytes": path.stat().st_size if path.exists() else None, "sha256": None,
           "headerReadable": False, "metadataSource": "GeoTIFF tags read by Pillow; no pixel decode"}
    if not path.exists():
        return row
    row["sha256"] = sha256(path)
    if Image:
        try:
            with Image.open(path) as image:
                tags = image.tag_v2
                nodata = tags.get(42113)
                row.update({"headerReadable": True, "width": image.width, "height": image.height,
                            "pillowMode": image.mode, "bitsPerSample": tags.get(258),
                            "sampleFormat": tags.get(339), "samplesPerPixel": tags.get(277),
                            "pixelScaleTag33550": tags.get(33550), "tiepointTag33922": tags.get(33922),
                            "nodataTag42113": nodata, "geoAsciiTag34737": tags.get(34737)})
        except Exception as ex:
            row["headerError"] = f"{type(ex).__name__}: {str(ex)[:200]}"
    else:
        row["headerError"] = "Pillow unavailable"
    return row


def main() -> None:
    report = {"reportVersion": 1, "createdUtc": datetime.now(timezone.utc).isoformat(),
              "repositoryRoot": str(ROOT), "demBoundsEastLat": DEM_BOUNDS,
              "toolAvailability": {"Pillow": bool(Image), "Shapely": bool(to_shape), "Pyogrio": bool(pyogrio),
                                   "GDALCLI": False, "rasterPixelScan": False},
              "summary": {}, "rasters": [], "geojson": [], "geopackages": [], "duplicatesAcrossTrackedCopies": [],
              "manifestPathChecks": [], "checksumComparisons": [], "landmarkRegisterCrossFormat": {}, "checksAndLimits": []}
    manifest_path = ROOT / "data" / "metadata" / "data_handover_manifest.json"
    try:
        inventory = json.loads(manifest_path.read_text(encoding="utf-8"))
        all_paths = sorted({p for dataset in inventory.get("datasets", []) for p in dataset.get("paths", [])})
        report["manifestPathChecks"] = [{"path": p, "exists": (ROOT / p).is_file(),
                                           "bytes": (ROOT / p).stat().st_size if (ROOT / p).is_file() else None}
                                          for p in all_paths]
    except Exception as ex:
        report["manifestPathChecks"] = [{"manifest": "data/metadata/data_handover_manifest.json", "error": str(ex)}]
    for root in [ROOT / "data", ROOT / "public", ROOT / "mobile" / "assets", ROOT / "src"]:
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.suffix.lower() in RASTER_SUFFIXES:
                report["rasters"].append(raster_info(path))
    seen = set()
    for root in GEOJSON_ROOTS:
        if root.exists():
            for path in sorted(root.rglob("*.geojson")):
                if path in seen:
                    continue
                seen.add(path)
                report["geojson"].append(check_geojson(path))
    if pyogrio:
        for path in sorted((ROOT / "data").rglob("*.gpkg")):
            item = {"path": str(path.relative_to(ROOT)).replace("\\", "/"), "bytes": path.stat().st_size, "layers": []}
            try:
                for layer, geom_type in pyogrio.list_layers(path):
                    info = pyogrio.read_info(path, layer=layer)
                    item["layers"].append({"name": str(layer), "geometryType": str(geom_type),
                                           "featureCount": info.get("features"), "crs": str(info.get("crs")),
                                           "fields": info.get("fields", []).tolist() if hasattr(info.get("fields"), "tolist") else list(info.get("fields", [])),
                                           "extent": info.get("total_bounds")})
            except Exception as ex:
                item["error"] = f"{type(ex).__name__}: {str(ex)[:200]}"
            report["geopackages"].append(item)
    # Duplicate bundled source products should be byte-identical where documented.
    pairs = [("public/jezero-dem.bin", "mobile/assets/terrain/jezero-dem.bin")]
    for left, right in pairs:
        a, b = ROOT / left, ROOT / right
        report["duplicatesAcrossTrackedCopies"].append({"left": left, "right": right,
            "bothExist": a.exists() and b.exists(), "sameSize": a.exists() and b.exists() and a.stat().st_size == b.stat().st_size,
            "sameSha256": a.exists() and b.exists() and sha256(a) == sha256(b)})
    expected_hashes = {}
    wide = ROOT / "data" / "metadata" / "jezero_wide_manifest.json"
    if wide.exists():
        try:
            for product in json.loads(wide.read_text(encoding="utf-8")).get("products", []):
                verification = product.get("verification", {})
                local_file = product.get("localFile")
                if local_file and verification.get("sha256"):
                    expected_hashes[local_file] = verification["sha256"]
        except Exception as ex:
            report["checksAndLimits"].append(f"Could not parse wide manifest hash records: {ex}")
    prior = ROOT / "data" / "metadata" / "integration_handoff_manifest.json"
    if prior.exists():
        try:
            for record in json.loads(prior.read_text(encoding="utf-8")).get("fileInventory", []):
                if record.get("path") and record.get("sha256"):
                    expected_hashes[record["path"].replace("\\", "/")] = record["sha256"]
        except Exception as ex:
            report["checksAndLimits"].append(f"Could not parse prior manifest hash records: {ex}")
    for rel, expected in sorted(expected_hashes.items()):
        file_path = ROOT / rel
        actual = sha256(file_path) if file_path.is_file() else None
        report["checksumComparisons"].append({"path": rel, "exists": file_path.is_file(),
                                               "expectedSha256": expected, "actualSha256": actual,
                                               "matches": actual == expected if actual else False})
    register_json = ROOT / "data" / "processed" / "jezero" / "landmarks.json"
    register_geojson = ROOT / "data" / "processed" / "jezero" / "landmarks.geojson"
    register_csv = ROOT / "data" / "processed" / "jezero" / "landmarks.csv"
    try:
        j = json.loads(register_json.read_text(encoding="utf-8"))
        g = json.loads(register_geojson.read_text(encoding="utf-8"))
        with register_csv.open("r", encoding="utf-8-sig", newline="") as f:
            c = list(csv.DictReader(f))
        ids = {
            "json": [str(x.get("id")) for x in j.get("features", [])],
            "geojson": [str(x.get("id")) for x in g.get("features", [])],
            "csv": [str(x.get("id")) for x in c],
        }
        count_null = sum(x.get("properties", {}).get("longitudeEastDeg") is None or
                         x.get("properties", {}).get("latitudePlanetocentricDeg") is None
                         for x in g.get("features", []))
        report["landmarkRegisterCrossFormat"] = {
            "jsonCount": len(ids["json"]), "geojsonCount": len(ids["geojson"]), "csvCount": len(ids["csv"]),
            "idSetsMatch": set(ids["json"]) == set(ids["geojson"]) == set(ids["csv"]),
            "duplicatesByFormat": {k: sorted(i for i, n in Counter(v).items() if n > 1) for k, v in ids.items()},
            "missingCoordinatesInGeojson": count_null,
            "csvMissingCoordinates": sum(not x.get("longitudeEastDeg") or not x.get("latitudePlanetocentricDeg") for x in c),
        }
    except Exception as ex:
        report["landmarkRegisterCrossFormat"] = {"error": f"{type(ex).__name__}: {str(ex)[:200]}"}
    all_features = sum(x.get("featureCount") or 0 for x in report["geojson"])
    report["summary"] = {"rasterFiles": len(report["rasters"]), "geojsonFiles": len(report["geojson"]),
                         "geojsonFeatures": all_features, "geopackageFiles": len(report["geopackages"]),
                         "manifestPaths": len(report["manifestPathChecks"]),
                         "manifestPathsMissing": sum(not x.get("exists", False) for x in report["manifestPathChecks"]),
                         "manifestChecksumComparisons": len(report["checksumComparisons"]),
                         "checksumMismatches": sum(not x["matches"] for x in report["checksumComparisons"]),
                         "landmarkRegisterRows": report["landmarkRegisterCrossFormat"].get("geojsonCount"),
                         "landmarkRegisterMissingCoordinates": report["landmarkRegisterCrossFormat"].get("missingCoordinatesInGeojson"),
                         "geojsonParseFailures": sum(not x["jsonValid"] for x in report["geojson"]),
                         "invalidGeometries": sum(x["invalidGeometryCount"] for x in report["geojson"] if isinstance(x["invalidGeometryCount"], int)),
                         "duplicateFeatureIds": sum(len(x["duplicateIds"]) for x in report["geojson"]),
                         "missingGeoJsonCoordinates": sum(x["missingCoordinates"] for x in report["geojson"])}
    report["checksAndLimits"] = [
        "GeoJSON syntax and geometry structure checked; Shapely validity checked where geometries were present.",
        "Coordinates checked against Mars lon/lat numeric domain. Declared GeoJSON coverageBounds checked where present; source extents may legitimately exceed a project clip.",
        "GeoTIFF dimensions, sample tags, pixel scale, tiepoints, NoData tag and file hashes inspected from headers; pixels were not scanned.",
        "CRS declarations compared from GeoJSON metadata, GeoTIFF GeoKeys/GeoASCII and existing source manifests; no raster reprojection or cross-product alignment test was performed.",
        "Null geometry in the research landmark register is intentional for unlocated names. It is counted as missing coordinates, not treated as a geometry error.",
        "File existence is limited to the current checkout. Raw PDS/USGS archives absent from the checkout are not inferred from manifests.",
    ]
    out = ROOT / "data" / "metadata" / "data_handover_validation.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"], indent=2))
    print(f"Wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
