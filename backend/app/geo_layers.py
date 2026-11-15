"""Geospatial layers reader for Jezero Crater science targets, rover traverse, and landmarks.

Loads processed GeoJSON datasets from data/processed/jezero/ derived from:
- USGS SIM 3464 (Geologic Map of Jezero Crater & Nili Planum)
- NASA Mars 2020 PLACES Rover Localizations (best_interp.csv, PDS Geosciences Node)
- Published Perseverance landing coordinates (Stack et al. 2023)
"""
from __future__ import annotations
import json, os
from typing import Any, Optional


def _find_processed_dir() -> str | None:
    candidates = [
        os.environ.get("MARSX_GEOJSON_PATH"),
        os.path.join(os.path.dirname(__file__), "..", "..", "data", "processed", "jezero"),
        os.path.join(os.path.dirname(__file__), "..", "data", "processed", "jezero"),
    ]
    for c in candidates:
        if c and os.path.isdir(os.path.abspath(c)):
            return os.path.abspath(c)
    return None


class GeoLayersCatalog:
    def __init__(self, processed_dir: Optional[str] = None):
        self.processed_dir = processed_dir or _find_processed_dir()
        self._landmarks: list[dict[str, Any]] = []
        self._rover_stops: list[dict[str, Any]] = []
        self._rover_traverse: Optional[dict[str, Any]] = None
        self._location_features: list[dict[str, Any]] = []
        self._manifest: dict[str, Any] = {}
        self._loaded = False

    def _load_file(self, filename: str) -> Any:
        if not self.processed_dir:
            return None
        path = os.path.join(self.processed_dir, filename)
        if os.path.isfile(path):
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        return None

    def load(self) -> None:
        if self._loaded or not self.processed_dir:
            return

        lm_data = self._load_file("jezero_landmarks.geojson")
        if lm_data and "features" in lm_data:
            self._landmarks = lm_data["features"]

        stops_data = self._load_file("perseverance_rover_stops.geojson")
        if stops_data and "features" in stops_data:
            self._rover_stops = stops_data["features"]

        trav_data = self._load_file("perseverance_rover_traverse.geojson")
        if trav_data:
            self._rover_traverse = trav_data

        feats_data = self._load_file("sim3464_location_features.geojson")
        if feats_data and "features" in feats_data:
            self._location_features = feats_data["features"]

        man_data = self._load_file("source_manifest.json")
        if man_data:
            self._manifest = man_data

        self._loaded = True

    def get_landmarks(self) -> list[dict[str, Any]]:
        self.load()
        return self._landmarks

    def get_science_targets(self) -> list[dict[str, Any]]:
        """Return real science targets formatted for MARS-X planners, including all 15 mapped Jezero landmarks."""
        from . import core
        self.load()
        targets = []
        seen_names: set[str] = set()

        # 1. Authoritative landmarks from GeoJSON
        for idx, feat in enumerate(self._landmarks):
            props = feat.get("properties", {})
            coords = feat.get("geometry", {}).get("coordinates", [0, 0])
            name = props.get("name", f"Landmark-{idx+1}")
            seen_names.add(name.lower())
            kind = props.get("kind", "reference_point")
            # Match against core.TARGETS for local image_url and astrobiological significance
            matched = next((t for t in core.TARGETS if t["name"].lower() in name.lower() or name.lower() in t["name"].lower()), None)
            targets.append({
                "id": feat.get("id") or (matched["id"] if matched else f"LM_{idx+1}"),
                "name": name,
                "type": kind.replace("_", " ").title(),
                "coord": {"lon": coords[0], "lat": coords[1]},
                "value": matched["value"] if matched else (0.95 if "landing" in kind else 0.85),
                "confidence": "HIGH" if "published" in props.get("coordinateStatus", "") else "MEDIUM",
                "source": props.get("sourceLabel") or "USGS SIM 3464 / PDS",
                "citation": props.get("source", ""),
                "note": props.get("note", "Verified Jezero feature"),
                "image_url": matched["image_url"] if matched else None,
                "significance": matched["significance"] if matched else None,
                "perseverance_history": matched["perseverance_history"] if matched else None,
                "data_type": "DERIVED",
            })

        # 2. All 15 Mapped Jezero Expedition Landmarks (from nipun_branch + processed register)
        for t in core.TARGETS:
            if t["name"].lower() in seen_names:
                continue
            seen_names.add(t["name"].lower())
            targets.append({
                "id": t["id"],
                "name": t["name"],
                "type": t["type"],
                "category": t.get("category"),
                "subcategory": t.get("subcategory"),
                "coord": {"lon": t["lon"], "lat": t["lat"]},
                "grid": {"x": t["x"], "y": t["y"]},
                "value": t["value"],
                "confidence": t["conf"],
                "source": "USGS SIM 3464 / NASA Mars 2020 PDS",
                "citation": "https://pubs.usgs.gov/publication/sim3464",
                "note": t["note"],
                "image_url": t.get("image_url"),
                "significance": t.get("significance"),
                "perseverance_history": t.get("perseverance_history"),
                "data_type": "DERIVED",
            })

        # 3. Key representative craters / geologic features from SIM 3464
        for idx, feat in enumerate(self._location_features[:15]):
            props = feat.get("properties", {})
            coords = feat.get("geometry", {}).get("coordinates", [0, 0])
            ftype = props.get("TYPE", "feature")
            targets.append({
                "id": f"GEO_{props.get('sourceFid', idx+1)}",
                "name": f"{ftype.title()} #{props.get('sourceFid', idx+1)}",
                "type": f"USGS Geologic Feature ({ftype})",
                "coord": {"lon": coords[0], "lat": coords[1]},
                "value": 0.70,
                "confidence": "HIGH",
                "source": props.get("sourceProduct", "USGS SIM 3464"),
                "citation": props.get("sourceUrl", "https://pubs.usgs.gov/publication/sim3464"),
                "note": "Geological location feature from USGS SIM 3464.",
                "data_type": "DERIVED",
            })

        return targets

    def get_landmarks_register(self) -> dict[str, Any]:
        """Return the full landmark register enriched with the 15 mapped Jezero landmarks and close-up images."""
        from . import core
        self.load()
        reg = self._load_file("landmarks_register.json")
        if reg and isinstance(reg, dict):
            return {
                **reg,
                "mapped_landmarks": core.TARGETS,
                "mapped_count": len(core.TARGETS),
                "data_type": "DERIVED",
            }
        return {
            "mapped_landmarks": core.TARGETS,
            "mapped_count": len(core.TARGETS),
            "data_type": "DERIVED",
        }

    def get_rover_traverse(self) -> dict[str, Any]:
        self.load()
        if self._rover_traverse:
            return self._rover_traverse
        return {
            "type": "FeatureCollection",
            "features": [],
            "properties": {"status": "NO_TRAVERSE_DATA"},
        }

    def get_rover_stops(
        self,
        sol_min: Optional[int] = None,
        sol_max: Optional[int] = None,
        limit: int = 500,
    ) -> dict[str, Any]:
        self.load()
        stops = self._rover_stops
        if sol_min is not None:
            stops = [s for s in stops if s.get("properties", {}).get("sol", 0) >= sol_min]
        if sol_max is not None:
            stops = [s for s in stops if s.get("properties", {}).get("sol", 0) <= sol_max]

        return {
            "type": "FeatureCollection",
            "features": stops[:limit],
            "total_count": len(self._rover_stops),
            "filtered_count": len(stops),
            "data_type": "MEASURED",
            "source": "NASA Mars 2020 PLACES Release 16 (PDS Geosciences Node)",
            "citation": "https://pds-geosciences.wustl.edu/m2020/urn-nasa-pds-mars2020_rover_places/",
        }

    def get_provenance_manifest(self) -> dict[str, Any]:
        self.load()
        return self._manifest


# Global singleton instance
geo_catalog = GeoLayersCatalog()
