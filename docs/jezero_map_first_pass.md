# Jezero map data first pass

## What is available locally

- The app still displays a small, real HiRISE DTM window around Perseverance's landing area. It is not yet the whole-crater view.
- The crater-wide USGS CTX DEM (20 m/pixel) and matching CTX orthomosaic (5 m/pixel) are downloaded and verified under `data/raw/JezeroWide/`. They are not yet integrated into the app.
- The USGS SIM 3464 geodatabase and Mars 2020 PLACES rover-localization table are now downloaded. A repeatable converter writes their map features and rover positions to `data/processed/jezero/`.
- The Flutter APK now bundles the expanded 10-point reference/label-anchor index and 531 PDS PLACES per-sol rover localizations. The map shows the subset that falls inside its local HiRISE DTM. Full-crater CTX rasters and mapped geology remain prepared on disk, not yet rendered in the app.
- The app's route planner currently plans on the local HiRISE grid and uses heuristic costs. These are candidate educational routes, not astronaut safety guidance.
- There are no real rover panorama assets in the app yet. Rover images and camera poses still need to be joined from mission archives before creating panoramas.

## Geologic and landform layers

`data/processed/jezero/` contains derived GeoJSON from Sun and Stack's USGS SIM 3464 geodatabase:

- 1,021 geologic-unit polygon fragments after clipping to the downloaded CTX DEM footprint.
- 1,999 mapped geologic contacts.
- 306 mapped lines, including fluvial channels, delta-lobe fronts, ridge crests, crater-rim crests, and lineaments.
- 187 surface-feature polygons, 258 small-crater points, and the landing ellipse.
- Eight named USGS map-label anchor points in the shared landmark index. These place map text; they do not represent the named feature's center or boundary.

SIM 3464 is a 1:75,000 regional geologic map. Its published map boundary is about 76.8–77.8° east and 17.7–18.7° north. The CTX terrain mosaic is wider, about 76.9974–78.5826° east and 17.5805–19.2902° north. The map-coverage polygon is provided separately so areas outside the geological map remain visibly unmapped rather than appearing feature-free.

The geodatabase uses Mars Transverse Mercator on the Mars 2000 sphere. The export transforms its geometries into Mars longitude east-positive and planetocentric latitude, clips them to the verified CTX DEM bounds, and simplifies display geometry by 8 m. This scale supports regional geology and landforms, not small-rock detection.

## Perseverance localizations

`data/processed/jezero/perseverance_rover_stops.geojson` contains 531 per-sol rover localization points inside the CTX DEM footprint from PDS PLACES Release 16. The companion `perseverance_rover_traverse.geojson` connects these points into 120 display segments and leaves gaps longer than two sols disconnected. The raw `best_interp.csv`, its PDS XML label, and release notes are retained under `data/raw/JezeroLandmarks/`.

PLACES `best_interp` is a localized/interpolated archive product, not a complete record of wheel motion. Its Release 16 notes say `ROVER,n,0` rows were omitted. A displayed line between positions is therefore not an exact driven path, and the archive does not provide a numeric position-error value in this table. Sol, site, drive, and source identifiers remain attached to the output points.

The PDS Three Forks sample-drop table contains the names and times of the ten depot events, but no geographic coordinates. It is retained as a source for later matching. The app must not place the individual tubes from a screenshot or by copying the rover's nearby position as if it were an exact tube coordinate.

## Next work before app integration

1. Finish a named-landmark register that combines map labels, geologic polygon names, mission campaign features, and rover/sample observations without confusing display anchors with feature boundaries.
2. Join requested landmark observations to their authoritative coordinates or source geometries. Kodiak, Artuby Ridge, Máaz, Séítah, Three Forks, and sample locations need distinct location evidence; the source layers above do not define every one of those names.
3. Decide which offline vector layers to bundle and how the Flutter map will render their different geometry types and coverage boundaries.
4. Integrate the crater-wide elevation and imagery after the geospatial database is reviewed. The current route grid is still the landing-site HiRISE patch and cannot plan across all of Jezero.
5. Acquire real rover images with their product labels and use archived camera geometry only where the image set supports a valid panorama.

Source details and plain-language explanations for the hackathon are in [`DATA_SOURCES.md`](DATA_SOURCES.md). The vector export can be regenerated with `python data/build_jezero_vectors.py` after installing `data/requirements-geodata.txt` and obtaining the raw source files.
