#!/usr/bin/env python3
"""Export authoritative Jezero GIS and Perseverance PLACES data for offline use.

Inputs are downloaded into data/raw/JezeroLandmarks/ and unpacked from the USGS
SIM 3464 database. This script only creates derived GeoJSON; it does not edit
the Flutter app or alter the source datasets.

One-time environment (GDAL-backed pyogrio, PROJ-backed pyproj, Shapely 2):
    python -m pip install -r data/requirements-geodata.txt
Run from the repository root:
    python data/build_jezero_vectors.py
"""
from __future__ import annotations

import csv
import hashlib
import json
import math
import re
import zipfile
from collections import Counter
from datetime import date
from pathlib import Path
from typing import Any

import pyogrio
from pyproj import CRS, Transformer
from shapely import from_wkb, make_valid
from shapely.geometry import Point, box, mapping
from shapely.ops import transform as transform_geometry


ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw" / "JezeroLandmarks"
ZIP = RAW / "sim3464_database.zip"
CSV = RAW / "best_interp.csv"
LABEL = RAW / "best_interp.csv.xml"
RELEASE_NOTES = RAW / "release_notes.txt"
SAMPLE_EVENTS = RAW / "ThreeForks" / "sample_drop_timestamps.csv"
SAMPLE_EVENTS_LABEL = RAW / "ThreeForks" / "sample_drop_timestamps.xml"
USGS_GDB = RAW / "usgs" / "sim3464_JezeroNili_FINAL" / "Geodatabase" / "Nili.gdb"
USGS_CRS = RAW / "usgs" / "sim3464_JezeroNili_FINAL" / "CoordinateSystems" / "MTM_clon77_5E.prj"
OUT = ROOT / "data" / "processed" / "jezero"
MANIFEST = ROOT / "data" / "metadata" / "jezero_wide_manifest.json"

USGS_MAP_URL = "https://pubs.usgs.gov/publication/sim3464"
PDS_PLACES_URL = "https://pds-geosciences.wustl.edu/missions/mars2020/places.htm"
PDS_TABLE_URL = "https://pds-geosciences.wustl.edu/m2020/urn-nasa-pds-mars2020_rover_places/data_localizations/best_interp.csv"

GEOMETRY_SIMPLIFY_M = 8.0
GEOJSON_COORDINATE_DIGITS = 6


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def plain(value: Any) -> Any:
    if hasattr(value, "item"):
        value = value.item()
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return str(value)


def rounded_geometry(geometry: Any) -> dict[str, Any]:
    def round_nested(value: Any) -> Any:
        if isinstance(value, (tuple, list)):
            return [round_nested(part) for part in value]
        return round(float(value), GEOJSON_COORDINATE_DIGITS)

    data = mapping(geometry)
    return {"type": data["type"], "coordinates": round_nested(data["coordinates"])}


def feature(fid: Any, geometry: Any, properties: dict[str, Any]) -> dict[str, Any]:
    return {
        "type": "Feature",
        "id": str(fid),
        "geometry": rounded_geometry(geometry),
        "properties": properties,
    }


def collection(name: str, description: str, features: list[dict[str, Any]], bounds: list[float]) -> dict[str, Any]:
    return {
        "type": "FeatureCollection",
        "name": name,
        "description": description,
        "marsCoordinateSystem": {
            "body": "Mars",
            "datum": "Mars 2000 sphere",
            "sphereRadiusMetres": 3396190,
            "longitude": "east-positive degrees, 0 to 360",
            "latitude": "planetocentric degrees",
            "geojsonOrdinateOrder": ["longitudeEastDeg", "latitudePlanetocentricDeg"],
            "note": "Coordinates use Mars longitude and latitude; they are not Earth WGS 84 coordinates.",
        },
        "coverageBoundsEastLat": bounds,
        "features": features,
    }


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, ensure_ascii=False, separators=(",", ":"))
        stream.write("\n")


def extract_gdb_if_needed() -> None:
    if USGS_GDB.exists():
        return
    if not ZIP.exists():
        raise FileNotFoundError(f"Download the USGS database first: {ZIP}")
    base = "sim3464_JezeroNili_FINAL/"
    with zipfile.ZipFile(ZIP) as archive:
        wanted = [
            name for name in archive.namelist()
            if name.startswith(base + "Geodatabase/Nili.gdb/")
            or name.startswith(base + "CoordinateSystems/")
        ]
        for name in wanted:
            archive.extract(name, RAW / "usgs")
    if not USGS_GDB.exists():
        raise FileNotFoundError("USGS archive did not contain the expected Nili.gdb")


def raster_mars_bounds() -> tuple[list[float], Any, Any]:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    product = next(item for item in manifest["products"] if item["id"] == "M20_JezeroCrater_CTXDEM_20m")
    verify = product["verification"]
    width, height = verify["rasterSizePixels"]
    x0, y0 = verify["projectedOriginMetres"]
    px, py = verify["pixelSizeMetres"]
    projected = CRS.from_proj4(
        "+proj=eqc +lat_ts=18.4663 +lat_0=0 +lon_0=0 "
        "+a=3396190 +b=3396190 +units=m +no_defs +type=crs"
    )
    mars_geographic = CRS.from_proj4("+proj=longlat +a=3396190 +b=3396190 +no_defs +type=crs")
    transform = Transformer.from_crs(projected, mars_geographic, always_xy=True)
    corners = [
        transform.transform(x0, y0),
        transform.transform(x0 + width * px, y0),
        transform.transform(x0 + width * px, y0 + height * py),
        transform.transform(x0, y0 + height * py),
    ]
    min_lon = min(p[0] for p in corners)
    max_lon = max(p[0] for p in corners)
    min_lat = min(p[1] for p in corners)
    max_lat = max(p[1] for p in corners)
    return [min_lon, min_lat, max_lon, max_lat], projected, mars_geographic


def read_layer(layer: str) -> tuple[dict[str, Any], list[Any], list[Any], list[Any]]:
    meta, fids, geometries, columns = pyogrio.raw.read(USGS_GDB, layer=layer, return_fids=True)
    records = []
    for index in range(len(fids)):
        props = {str(key): plain(values[index]) for key, values in zip(meta["fields"], columns)}
        records.append((int(fids[index]), geometries[index], props))
    return meta, records, geometries, columns


def usgs_layer(layer: str, source_transform: Transformer, clip: Any, *, simplify: float = GEOMETRY_SIMPLIFY_M) -> tuple[list[dict[str, Any]], Counter[str]]:
    meta, records, _, _ = read_layer(layer)
    output: list[dict[str, Any]] = []
    kept_types: Counter[str] = Counter()
    for fid, raw_geometry, props in records:
        if raw_geometry is None:
            continue
        geometry = from_wkb(raw_geometry)
        if geometry.is_empty:
            continue
        if simplify and geometry.geom_type not in ("Point", "MultiPoint"):
            geometry = geometry.simplify(simplify, preserve_topology=True)
        geometry = transform_geometry(lambda x, y, z=None: source_transform.transform(x, y), geometry)
        if not geometry.is_valid:
            geometry = make_valid(geometry)
        if not geometry.intersects(clip):
            continue
        clipped = geometry.intersection(clip)
        if clipped.is_empty:
            continue
        props.update({
            "sourceLayer": layer,
            "sourceFid": fid,
            "sourceProduct": "USGS SIM 3464 Geologic Map of Jezero Crater and the Nili Planum Region",
            "sourceUrl": USGS_MAP_URL,
            "coordinateMethod": "USGS Mars Transverse Mercator map geometry transformed to Mars east longitude and planetocentric latitude",
            "displaySimplificationToleranceMetres": simplify if simplify else 0,
            "coverageNote": "Clipped to the verified CTX DEM footprint. The source USGS geologic map covers only its own published map boundary; outside it means unmapped by this source, not absence of a feature.",
        })
        output.append(feature(f"{layer}-{fid}", clipped, props))
        kind = str(props.get("TYPE", props.get("name", "feature")))
        kept_types[kind] += 1
    return output, kept_types


def export_usgs(bounds: list[float], geographic: CRS) -> dict[str, Any]:
    source_wkt = pyogrio.read_info(USGS_GDB, layer="GeoUnits_v1")["crs"]
    source_transform = Transformer.from_crs(CRS.from_wkt(source_wkt), geographic, always_xy=True)
    clip = box(bounds[0], bounds[1], bounds[2], bounds[3])
    stats: dict[str, Any] = {}

    for layer, filename, title in [
        ("GeoUnits_v1", "sim3464_geologic_units.geojson", "USGS geologic unit polygons"),
        ("GeoContacts", "sim3464_geologic_contacts.geojson", "USGS geologic contacts"),
        ("LinearFeatures", "sim3464_linear_landforms.geojson", "USGS mapped ridges, channels, rim crests, and delta fronts"),
        ("SurfaceFeatures", "sim3464_surface_features.geojson", "USGS mapped surface features"),
        ("LocationFeatures", "sim3464_location_features.geojson", "USGS small crater locations"),
        ("LandingEllipse", "sim3464_landing_ellipse.geojson", "USGS Mars 2020 landing ellipse"),
        ("MapBoundary", "sim3464_map_coverage.geojson", "USGS SIM 3464 mapped coverage boundary"),
    ]:
        output, type_counts = usgs_layer(layer, source_transform, clip)
        write_json(OUT / filename, collection(title, f"USGS SIM 3464 source layer {layer}; geometry clipped to the downloaded crater-wide CTX DEM footprint.", output, bounds))
        stats[layer] = {"outputFeatureCount": len(output), "featureTypes": dict(type_counts), "outputBytes": (OUT / filename).stat().st_size}

    # The USGS nomenclature layer stores text-label polygons. Export a point at
    # each label centroid for map annotation only, never as a feature boundary.
    _, records, _, _ = read_layer("Nomenclature")
    labels = []
    for fid, raw_geometry, props in records:
        if raw_geometry is None:
            continue
        label_geometry = from_wkb(raw_geometry)
        label_geometry = transform_geometry(lambda x, y, z=None: source_transform.transform(x, y), label_geometry)
        anchor = label_geometry.centroid
        if not clip.covers(anchor):
            continue
        source_text = str(props.get("TextString") or "").strip()
        # USGS text labels may use repeated spaces between letters. Keep normal
        # word spacing for labels such as "Neretva  Vallis".
        if re.search(r"(?:[A-Za-z]\s{2,}){3,}[A-Za-z]", source_text):
            display_name = " ".join("".join(part.split()) for part in re.split(r"\s{5,}", source_text)).strip()
        else:
            display_name = re.sub(r"\s+", " ", source_text).strip()
        props = {
            "name": display_name,
            "sourceLabelText": source_text,
            "kind": "usgs_map_nomenclature_label_anchor",
            "coordinateDigits": 6,
            "coordinateStatus": "derived_map_label_anchor",
            "sourceLabel": "Sun and Stack (2020), USGS Scientific Investigations Map 3464, Nomenclature layer",
            "source": USGS_MAP_URL,
            "sourceLayer": "Nomenclature",
            "sourceFid": fid,
            "anchorMethod": "centroid of USGS text annotation geometry",
            "note": "This coordinate places the map label. It is not the center, surveyed location, or boundary of the named feature.",
        }
        labels.append(feature(f"sim3464-label-{fid}", anchor, props))
    write_json(OUT / "sim3464_named_label_anchors.geojson", collection("USGS SIM 3464 named map-label anchors", "Display-only anchor points from USGS nomenclature text labels. They are not feature centroids or boundaries.", labels, bounds))
    stats["Nomenclature"] = {"outputFeatureCount": len(labels), "names": [item["properties"]["name"] for item in labels], "outputBytes": (OUT / "sim3464_named_label_anchors.geojson").stat().st_size}
    return stats


def export_landmark_index(bounds: list[float]) -> int:
    """Combine the two verified reference points and map-label anchors."""
    current = json.loads((ROOT / "mobile" / "assets" / "terrain" / "jezero-landmarks.geojson").read_text(encoding="utf-8"))
    anchors = json.loads((OUT / "sim3464_named_label_anchors.geojson").read_text(encoding="utf-8"))
    # The mobile asset is the expanded index after integration. Keep only its
    # published reference points before appending freshly generated anchors.
    reference_points = [
        item for item in current["features"]
        if item.get("properties", {}).get("kind") != "usgs_map_nomenclature_label_anchor"
    ]
    features = reference_points + list(anchors["features"])
    write_json(OUT / "jezero_landmarks.geojson", collection(
        "Jezero reference points and USGS map-label anchors",
        "An offline index of the published landing and crater reference points plus named USGS nomenclature label anchors. The anchors label map features; they are not boundaries or surveyed feature centers. Use the companion polygon and line layers for the geologic shapes.",
        features,
        bounds,
    ))
    return len(features)


def export_rover(bounds: list[float]) -> dict[str, Any]:
    if not CSV.exists():
        raise FileNotFoundError(f"Download the PDS PLACES localization table first: {CSV}")
    with CSV.open("r", encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))

    localized = []
    for row in rows:
        if row.get("frame") != "ROVER":
            continue
        try:
            lon = float(row["longitude"])
            lat = float(row["planetocentric_latitude"])
            sol = int(row["sol"])
            sclk = int(row["sclk"])
        except (TypeError, ValueError, KeyError):
            continue
        if lon == -9999 or lat == -9999 or sol < 0 or sclk <= 0:
            continue
        if not (bounds[0] <= lon <= bounds[2] and bounds[1] <= lat <= bounds[3]):
            continue
        localized.append({
            "longitude": lon,
            "latitude": lat,
            "sol": sol,
            "sclk": sclk,
            "site": row.get("site"),
            "drive": row.get("drive"),
            "pose": row.get("pose"),
            "elevationM": float(row["elevation"]) if row.get("elevation") not in (None, "", "-9999") else None,
            "planetodeticLatitudeDeg": float(row["planetodetic_latitude"]) if row.get("planetodetic_latitude") not in (None, "", "-9999") else None,
        })
    localized.sort(key=lambda row: (row["sclk"], row["sol"], int(row["site"] or 0), int(row["drive"] or 0), int(row["pose"] or 0)))

    # The full observation-position table is available as the retained raw CSV.
    # This compact GeoJSON keeps the latest localized rover row per sol for the
    # offline historical traverse view.
    per_sol: dict[int, dict[str, Any]] = {}
    for row in localized:
        per_sol[row["sol"]] = row
    stops = sorted(per_sol.values(), key=lambda row: row["sol"])
    point_features = []
    for row in stops:
        properties = {
            "name": f"Perseverance localized position, sol {row['sol']}",
            "kind": "rover_localization",
            "sol": row["sol"],
            "spacecraftClock": row["sclk"],
            "site": row["site"],
            "drive": row["drive"],
            "pose": row["pose"],
            "elevationM": row["elevationM"],
            "planetodeticLatitudeDeg": row["planetodeticLatitudeDeg"],
            "sourceLabel": "Mars 2020 Rover PLACES Release 16, best_interp.csv",
            "source": PDS_TABLE_URL,
            "positionMethod": "PDS best_interp localized/interpolated position; position accuracy is not specified by this table",
            "note": "One latest-SCLK archived ROVER row for this sol. This is a localized rover position, not a camera panorama pose and not a complete wheel-track record.",
        }
        point_features.append(feature(f"m20-sol-{row['sol']}", Point(row["longitude"], row["latitude"]), properties))

    write_json(OUT / "perseverance_rover_stops.geojson", collection("Perseverance archived rover localizations by sol", "The latest archived PLACES ROVER localization row per sol inside the downloaded CTX DEM footprint. Missing sols remain missing; no locations are invented.", point_features, bounds))

    segments: list[list[dict[str, Any]]] = []
    current: list[dict[str, Any]] = []
    for row in stops:
        if current and row["sol"] - current[-1]["sol"] > 2:
            if len(current) >= 2:
                segments.append(current)
            current = []
        current.append(row)
    if len(current) >= 2:
        segments.append(current)
    line_features = []
    for index, segment in enumerate(segments, 1):
        line_features.append(feature(
            f"m20-traverse-segment-{index}",
            # This is only a display connection between archived positions.
            # Do not present it as the exact driven wheel path.
            __import__("shapely.geometry", fromlist=["LineString"]).LineString([(r["longitude"], r["latitude"]) for r in segment]),
            {
                "name": f"Perseverance archived position sequence, sols {segment[0]['sol']}–{segment[-1]['sol']}",
                "kind": "rover_localization_sequence",
                "startSol": segment[0]["sol"],
                "endSol": segment[-1]["sol"],
                "positionCount": len(segment),
                "sourceLabel": "Mars 2020 Rover PLACES Release 16, best_interp.csv",
                "source": PDS_TABLE_URL,
                "positionMethod": "line joining one archived localization per available sol; positions may be interpolated",
                "note": "Display-only rover position sequence. It is not the exact wheel track. Gaps longer than two sols are left disconnected.",
            },
        ))
    write_json(OUT / "perseverance_rover_traverse.geojson", collection("Perseverance archived localization sequence", "Line segments connect archived per-sol locations, leaving long data gaps unconnected. They are not actual wheel tracks.", line_features, bounds))

    notes = RELEASE_NOTES.read_text(encoding="utf-8", errors="replace") if RELEASE_NOTES.exists() else ""
    latest_release = re.search(r"Release Number:\s*(\d+).*?Release Date:\s*([0-9-]+).*?covers all data from ([0-9-]+) through ([0-9-]+), or sols (\d+) to (\d+)", notes, re.S)
    release = None
    if latest_release:
        release = {
            "release": int(latest_release.group(1)),
            "releaseDate": latest_release.group(2),
            "startDate": latest_release.group(3),
            "endDate": latest_release.group(4),
            "startSol": int(latest_release.group(5)),
            "endSol": int(latest_release.group(6)),
        }
    return {
        "sourceRows": len(rows),
        "roverRowsWithinRasterFootprint": len(localized),
        "uniqueSolsWithinRasterFootprint": len(stops),
        "traverseSegments": len(line_features),
        "solRangeInOutput": [stops[0]["sol"], stops[-1]["sol"]] if stops else None,
        "release": release,
        "csvSha256": sha256(CSV),
        "csvBytes": CSV.stat().st_size,
        "xmlLabelBytes": LABEL.stat().st_size if LABEL.exists() else None,
        "pdsReleaseNotes": "data/raw/JezeroLandmarks/release_notes.txt",
        "positionCaveat": "best_interp is a localized/interpolated archive product. The PDS Release 16 notes report ROVER,n,0 rows were omitted; positions and motion between archived localizations must not be described as a fully observed wheel path.",
        "stopsOutputBytes": (OUT / "perseverance_rover_stops.geojson").stat().st_size,
        "traverseOutputBytes": (OUT / "perseverance_rover_traverse.geojson").stat().st_size,
    }


def main() -> None:
    if not USGS_GDB.exists():
        extract_gdb_if_needed()
    OUT.mkdir(parents=True, exist_ok=True)
    bounds, dem_projected, mars_geographic = raster_mars_bounds()
    usgs = export_usgs(bounds, mars_geographic)
    rover = export_rover(bounds)
    landmark_count = export_landmark_index(bounds)
    usgs_meta = RAW / "usgs" / "sim3464_JezeroNili_FINAL" / "Metadata" / "SIM3464_metadata.xml"
    result = {
        "manifestVersion": 1,
        "generatedOn": date.today().isoformat(),
        "region": "USGS SIM 3464 and all Mars 2020 PLACES positions inside the downloaded crater-wide CTX DEM footprint",
        "coordinateSystem": {
            "body": "Mars",
            "datum": "Mars 2000 sphere",
            "radiusMetres": 3396190,
            "longitude": "east-positive degrees",
            "latitude": "planetocentric degrees",
            "geojsonOrder": ["longitudeEastDeg", "latitudePlanetocentricDeg"],
            "demBoundsEastLat": bounds,
            "coordinateDigitsInGeoJSON": GEOJSON_COORDINATE_DIGITS,
            "precisionNote": "Stored decimal places are for stable coordinate encoding and do not imply that the source location is accurate to that precision.",
        },
        "sources": [
            {
                "name": "USGS Scientific Investigations Map 3464 geodatabase",
                "citation": "Sun, V.Z., and Stack, K.M., 2020, Geologic map of Jezero crater and the Nili Planum region, Mars, USGS SIM 3464, scale 1:75,000.",
                "url": USGS_MAP_URL,
                "downloadUrl": "https://pubs.usgs.gov/sim/3464/sim3464_database.zip",
                "localArchive": "data/raw/JezeroLandmarks/sim3464_database.zip",
                "archiveSha256": sha256(ZIP),
                "sourceMetadata": str(usgs_meta.relative_to(ROOT)) if usgs_meta.exists() else None,
                "actualCoverage": "MapBoundary layer in sim3464_map_coverage.geojson; the source map does not cover the full crater-wide CTX DEM. Unmapped area is unknown, not feature absence.",
                "geometrySimplificationMetres": GEOMETRY_SIMPLIFY_M,
                "layers": usgs,
            },
            {
                "name": "Mars 2020 Rover PLACES, Release 16",
                "url": PDS_PLACES_URL,
                "tableUrl": PDS_TABLE_URL,
                "localTable": "data/raw/JezeroLandmarks/best_interp.csv",
                "localLabel": "data/raw/JezeroLandmarks/best_interp.csv.xml",
                **rover,
            },
            {
                "name": "PDS Mars 2020 Three Forks Depot sample-drop events",
                "url": "https://pds-geosciences.wustl.edu/missions/mars2020/",
                "bundleUrl": "https://pds-geosciences.wustl.edu/m2020/urn-nasa-pds-mars2020_sample_depot_three_forks/",
                "tableUrl": "https://pds-geosciences.wustl.edu/m2020/urn-nasa-pds-mars2020_sample_depot_three_forks/data/sample_drop_events/sample_drop_timestamps.csv",
                "localTable": str(SAMPLE_EVENTS.relative_to(ROOT)) if SAMPLE_EVENTS.exists() else None,
                "localLabel": str(SAMPLE_EVENTS_LABEL.relative_to(ROOT)) if SAMPLE_EVENTS_LABEL.exists() else None,
                "tableSha256": sha256(SAMPLE_EVENTS) if SAMPLE_EVENTS.exists() else None,
                "eventCount": sum(1 for _ in SAMPLE_EVENTS.open(encoding="utf-8")) - 1 if SAMPLE_EVENTS.exists() else None,
                "coordinatesPresent": False,
                "use": "Sample names and event times only; not sufficient to position individual tubes. Do not infer coordinates from the image or from a nearby rover position.",
            },
        ],
        "outputs": [
            "sim3464_geologic_units.geojson",
            "sim3464_geologic_contacts.geojson",
            "sim3464_linear_landforms.geojson",
            "sim3464_surface_features.geojson",
            "sim3464_location_features.geojson",
            "sim3464_landing_ellipse.geojson",
            "sim3464_map_coverage.geojson",
            "sim3464_named_label_anchors.geojson",
            "jezero_landmarks.geojson",
            "perseverance_rover_stops.geojson",
            "perseverance_rover_traverse.geojson",
        ],
        "notes": [
            "USGS SIM 3464 maps geology and landforms at 1:75,000; its geologic unit polygons are regional map interpretations, not astronaut-scale obstacle surveys.",
            "USGS nomenclature points are centroids of text annotation polygons and serve only as display anchors.",
            f"The combined landmark point index has {landmark_count} items: two published reference points and USGS map-label anchors. Geologic extents and contacts are in companion vector layers.",
            "USGS vectors are transformed from the supplied Mars Transverse Mercator projection to a Mars spherical geographic coordinate system, then clipped to the CTX DEM bounds.",
            "Perseverance PLACES localizations are kept separate from geological features and from any generated astronaut routes.",
        ],
    }
    write_json(OUT / "source_manifest.json", result)
    print(json.dumps({"outputDirectory": str(OUT), "demBoundsEastLat": bounds, "usgsLayers": usgs, "rover": rover}, indent=2))


if __name__ == "__main__":
    main()
