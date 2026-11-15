# MARS-X data

The requested 29-name Jezero landmark research register is in
[`processed/jezero/landmarks.json`](processed/jezero/landmarks.json),
[`landmarks.geojson`](processed/jezero/landmarks.geojson), and
[`landmarks.csv`](processed/jezero/landmarks.csv). Its evidence policy and
remaining coordinate joins are documented in [`docs/landmark_register.md`](../docs/landmark_register.md).

See [`docs/DATA_SOURCES.md`](../docs/DATA_SOURCES.md) for the plain-language source register required for the hackathon. It distinguishes downloaded source files, processed data, and layers integrated into the app, and records coverage, resolution, limits, and citations.

For the frontend/backend integration team, see the parallel-work plan and data contract in [`docs/integration_handoff.md`](../docs/integration_handoff.md) and the machine-readable inventory in [`data/metadata/integration_handoff_manifest.json`](metadata/integration_handoff_manifest.json). D6/D8 are ready for a coordinate-aware preview prototype; source-processing and cross-dataset spatial QA remain explicit gates before scientific sign-off.

`python3 data/fetch_datasets.py` queries live USGS STAC / PDS endpoints and writes `catalogue/datasets.json`.

Catalogue records that were HTTP-checked, with verification dates:
- **D3** HiRISE controlled DTM catalogue (6 USGS STAC items). The original PDS3 `.IMG` for `DTEEC_045994_1985_046060_1985_U01` is now in `raw/D3/` (gitignored) and is the source used by the terrain builder.
- **D4** CTX controlled DTMs (37 items; large footprints, fallback only).
- **D9** MEDA derived TIRS + RHS tables for sols 10, 14, 20, 28 (archived, not live) in `raw/D9/` with PDS4 labels.

**D5 caveat:** the catalogue entry for the 463 m colorized MOLA shaded-relief product returned HTTP 403 during the last check. It is a rendered hillshade, not raw elevation, and is not the MOLA DEM planned for terrain height.

The full-crater 20 m CTX DEM and matching 5 m orthomosaic are downloaded and verified. The Flutter app now bundles a 100 m CTX route grid, a geospatially aligned 100 m image overview, and partial USGS mapped rim lines. Regenerate those assets with `python data/build_crater_wide_app_assets.py`; the script reads the source rasters in `raw/JezeroWide/` and never modifies them. The full-resolution source mosaics remain outside the APK, and the orthomosaic's smaller footprint remains transparent after alignment. The local HiRISE DTM footprint (about 4.1 × 2.65 km in the app crop) remains a landing-area detail source, not the crater-wide route grid. See the [source register](../docs/DATA_SOURCES.md) and [machine-readable manifest](metadata/jezero_wide_manifest.json) for product details, checksums, projections, and status.

## Crater-wide Flutter terrain
`python data/build_crater_wide_app_assets.py` aggregates the USGS 20 m CTX DEM to a 100 m route grid and geospatially warps the matching 5 m image to those same grid centers. Output elevation uses signed 16-bit metres with `-32768` as NoData. Any 100 m output cell containing a source NoData sample is retained as unknown. The app derives slope and roughness from this grid and plans across the full CTX footprint (which includes surrounding terrain beyond the crater rim). The grid and overview cover the full crater context but do not resolve small rocks or suit-scale hazards.

## HiRISE landing-area detail source
`python3 data/build_dem.py` reads the original PDS3 HiRISE product `data/raw/D3/DTEEC_045994_1985_046060_1985_U01.IMG` directly, using its embedded label and little-endian 32-bit elevations. It builds a deterministic ~4.1 x 2.7 km ground patch centered on the published Perseverance landing location. It writes `public/jezero-dem.bin` (480x304 Int16 decimetres, used by the 3D view), `src/jezeroGrid.ts` (120x76 web planning grid), and matching Flutter terrain binary/metadata under `mobile/assets/terrain/`. The output preserves NoData and includes Mars projected grid-cell centers.

## Jezero geology and rover position layers

The raw USGS SIM 3464 geodatabase and PDS Mars 2020 PLACES localization table are in `raw/JezeroLandmarks/` (large downloaded files are gitignored). The SIM 3464 ZIP is about 349 MB and contains more than the vector data used here; the build script extracts only its geodatabase and coordinate-system/metadata files. PLACES `best_interp.csv`, its PDS XML label, and release notes are kept together. To obtain them on a new checkout, run `python data/fetch_landmark_sources.py`.

To regenerate the source-linked offline GeoJSON after acquiring those raw files:

```powershell
python -m pip install -r data/requirements-geodata.txt
python data/build_jezero_vectors.py
```

Outputs go to `data/processed/jezero/`. They include geologic-unit polygons, geologic contacts, mapped landforms, surface features, crater points, the landing ellipse, SIM 3464 coverage boundary, map-label anchor points, and Perseverance per-sol localizations/traverse display segments. The converter preserves the Mars spherical coordinate frame, clips map geometry to the verified CTX DEM footprint, and records source identifiers. SIM 3464 does not cover the full CTX DEM footprint; use its coverage layer to show the unmapped area. Rover lines connect archived localized positions and are not exact wheel tracks.

The geology outputs remain source-preparation outputs. The Flutter map currently draws the named reference points, rover localizations, and mapped crater-rim crest segments; full geologic-unit polygons and D6/D8 are not yet active app layers.
