# MARS-X data pipeline: what happens to the data

This is a practical walkthrough of the data work in this repository. It describes which original sources feed which outputs, what each script does, how the app uses the outputs, and where processing cannot currently be reproduced from the repository alone.

For a non-technical overview of the datasets, see [DATA_SOURCES.md](DATA_SOURCES.md). For detailed file metadata and team integration notes, see [DATA_HANDOVER.md](DATA_HANDOVER.md).

## Data flow at a glance

```text
NASA / USGS / PDS / FU Berlin source files
                 │
                 ├── HiRISE DTM ──> small landing-area terrain files
                 │                   ├── web 3D + local web/backend planner
                 │                   └── Flutter local terrain files
                 │
                 ├── CTX DEM + CTX image ──> 100 m height grid + aligned overview
                 │                           └── Flutter crater-wide map/planner
                 │
                 ├── USGS SIM 3464 GIS ──> clipped geology vectors + label anchors
                 │                         └── source-prepared; only partial rim lines used in Flutter
                 │
                 ├── PDS PLACES ──> rover points + display-only traverse lines
                 │                  └── rover points are in Flutter; line is not
                 │
                 └── USGS / FU Berlin / PDS evidence ──> 29-name landmark register
                                                    └── research/export data; not an app layer
```

The original input files are kept separately from processed files and app assets. Processing should read source files and write derivatives; it should not rewrite source rasters or GIS archives.

## 1. Find and acquire source data

### Product catalogue

`python data/fetch_datasets.py` asks the USGS STAC catalogue what products overlap the landing-area search box and records product IDs, footprints, nominal pixel size, URLs, and some HTTP availability checks in `data/catalogue/`. Use `--full` only when you intentionally want the script to download its listed large HiRISE DTM source as well. The script also records selected archived MEDA tables. Its catalogue is a discovery list; a listed product is not automatically downloaded, processed, or added to an app.

### Geology and rover sources

`python data/fetch_landmark_sources.py` downloads the USGS SIM 3464 GIS archive, PDS PLACES rover localization CSV and labels/release notes, and the Three Forks sample-drop event CSV and label into `data/raw/JezeroLandmarks/`. Large raw files are not app assets. Existing non-empty files are kept unless `--force` is supplied.

The two crater-wide CTX TIFFs are stored under `data/raw/JezeroWide/`. They are from the [USGS Jezero CTX product](https://astrogeology.usgs.gov/search/map/mars_2020_science_investigation_ctx_dem_mosaic). There is no CTX download command in this repository: obtain the DEM and image from the source product links in [DATA_SOURCES.md](DATA_SOURCES.md), then place the unchanged files in that folder. Their XML labels belong alongside them.

FU Berlin WFS snapshots are stored under `data/raw/JezeroLandmarks/FUBerlin/`. Those snapshots were queried and cached as source data; the repository does not yet have a downloader for them. Raw coordinates in those files are projected metres in Mars EPSG:49911. Although the responses have a `.geojson` extension, do not pass their raw x/y values to a reader that assumes longitude and latitude.

## 2. Build the landing-area HiRISE terrain

Run:

```powershell
python data/build_dem.py
```

Input: `data/raw/D3/DTEEC_045994_1985_046060_1985_U01.IMG`, the original PDS3 HiRISE elevation product, plus its STAC record under `data/catalogue/`.

The script reads the PDS label inside the source file to learn its dimensions, data type, map scale, projection offsets, valid elevation range, and missing-value marker. It then:

1. Converts the published Perseverance landing coordinate to a source image pixel.
2. Selects a fixed-size patch centered on the landing site, within the source image.
3. Resamples that patch with bilinear interpolation to a 480 × 304 display grid.
4. Makes a smaller 120 × 76 planning grid by averaging each 4 × 4 display-grid block. If any display sample in a planning block is missing, that planning cell is marked NoData.
5. Stores heights as little-endian signed 16-bit integers in decimetres; `-32768` means NoData. Metadata records the grid transform, coverage, source hash, and elevation units.

Outputs:

- `public/jezero-dem.bin` and `public/jezero-dem.json` — web terrain patch and metadata.
- `src/jezeroGrid.ts` — generated web planning grid.
- `mobile/assets/terrain/jezero-dem.bin`, `jezero-dem.json`, and `jezero-grid.bin` — Flutter copy and planning grid.

This is a landing-area patch, not a full-crater terrain product. The script writes the generated TypeScript data file but does not change the web application logic.

## 3. Build the crater-wide CTX app assets

Install the listed geodata requirements if needed:

```powershell
python -m pip install -r data/requirements-geodata.txt
```

Then run:

```powershell
python data/build_crater_wide_app_assets.py
```

Inputs: the 20 m Float32 CTX DEM and 5 m grayscale CTX image in `data/raw/JezeroWide/`, plus `data/metadata/jezero_wide_manifest.json` for source transforms and checksums.

The script reads the GeoTIFF transform tags instead of stretching the image to match the DEM edges. It reduces the DEM from 20 m to a 100 m route grid by averaging each 5 × 5 block. A 100 m cell remains NoData if any one of its 25 source cells is NoData. Heights are rounded to whole metres and stored as little-endian signed 16-bit values; `-32768` is the NoData marker. The source DEM is 4,456 × 5,067 pixels; the output route grid is 891 × 1,013 cells. Unused trailing source rows/columns are dropped because they do not make a complete 5 × 5 block.

The 5 m image is sampled onto the same 100 m cell centers using the DEM and image GeoTIFF transforms, with bilinear resampling. Pixels outside the original image footprint are transparent. Thus the image may not cover every DEM cell.

Outputs:

- `mobile/assets/terrain/jezero-ctx-100m-elevation.bin` — compact whole-crater height grid.
- `mobile/assets/terrain/jezero-ctx-100m-elevation.json` — dimensions, CRS, transform, source and NoData information.
- `mobile/assets/terrain/jezero-ctx-overview.png` — aligned grayscale overview image with transparency outside the image footprint.
- `mobile/assets/terrain/jezero-ctx-crater-rim.geojson` — selected USGS rim-crest line segments, copied from the processed SIM 3464 output.

Flutter declares these assets in `mobile/pubspec.yaml`; `mobile/lib/app/providers.dart` loads the height grid, rim lines, reference points, and rover positions. The Flutter terrain grid code converts the user’s Mars coordinates into grid cells and the map screen uses the overview image. This is an offline 100 m terrain view; small rocks and local hazards are not resolved. The backend and web terrain currently use the HiRISE patch rather than this CTX grid.

## 4. Convert the USGS SIM 3464 geology map and PDS rover data

Install the dependencies in `data/requirements-geodata.txt`, then make sure the source files from step 1 exist. Run:

```powershell
python data/build_jezero_vectors.py
```

The script extracts the USGS geodatabase and coordinate-system files from `data/raw/JezeroLandmarks/sim3464_database.zip` if they have not already been extracted. It reads layers with Pyogrio, converts their Mars Transverse Mercator coordinates to east longitude / planetocentric latitude on the Mars sphere, repairs invalid source shapes if possible, simplifies non-point geometries with an 8 m tolerance while preserving topology, clips them to the CTX raster footprint, and preserves source layer/record identifiers and coverage notes.

The resulting GeoJSON files in `data/processed/jezero/` include geologic units, contacts, linear landforms, surface features, small crater locations, the landing ellipse, the map coverage boundary, and label anchors. Label anchors are calculated from text-label shapes; they position map text only and are not feature centers.

The same script reads PDS `best_interp.csv`. It keeps valid `ROVER` localization rows inside the CTX raster bounds, sorts them by mission clock, and selects the latest archived localization for each available sol. In this checkout that produces 531 point stops for sols 0–1897. It connects stops with lines only when the gap between available sols is at most two sols, producing 120 display segments. These are not surveyed wheel tracks and have no per-point numerical positional-accuracy field. The PDS release notes also document omitted rows.

Principal outputs:

- `data/processed/jezero/sim3464_*.geojson` — converted source map layers.
- `data/processed/jezero/jezero_landmarks.geojson` — landing/crater reference points plus USGS map-label anchors.
- `data/processed/jezero/perseverance_rover_stops.geojson` — one archived position per available sol.
- `data/processed/jezero/perseverance_rover_traverse.geojson` — display-only lines between those positions.
- `data/processed/jezero/source_manifest.json` — sources, processing notes, counts, and checksums.

The full processed geology layers are not active in Flutter. The reference point index and rover stop points have app copies; selected crater-rim lines are also packaged for display. The coverage boundary must be used to show where the source USGS map has no data.

## 5. Build the requested landmark register

Run:

```powershell
python data/build_landmark_register.py
```

The script combines evidence from the processed USGS layers, FU Berlin snapshots, PDS PLACES, and the PDS sample reports cited in the register. It writes the same 29 records to JSON, GeoJSON, and CSV under `data/processed/jezero/`.

It adds geometries only for supported locations or source shapes. The current register contains 8 points, a two-point panorama MultiPoint, 3 channel lines, 1 possible paleolake polygon, and 2 USGS GeometryCollections. Fourteen names still have null geometry. The lines are matched to official Gazetteer centers spatially because FU Berlin’s source lines have no names. The lake is one possible level reconstruction. Observation and sample points are not boundaries. Unknown values remain null.

For FU Berlin projected map coordinates, the script uses the Mars sphere radius (3,396,190 m) to convert equirectangular x/y metres to angular coordinates. The result is east-positive longitude and planetocentric latitude. The output is a research register, not yet an app layer.

## 6. Validation and inventory

Run:

```powershell
python data/validate_data_handover.py
```

The validator writes `data/metadata/data_handover_validation.json`. It checks manifest file paths, parses GeoJSON, checks IDs and coordinate ranges, checks geometry validity where Shapely is installed, reads GeoTIFF header metadata and hashes files against recorded manifests, inspects GeoPackage metadata when Pyogrio is installed, and compares landmark IDs across JSON/GeoJSON/CSV.

It does **not** scan all raster pixel values, run GDAL alignment checks, reproject files, test imagery-to-elevation pixel registration, validate every source’s science interpretation, or prove a route is safe. A clean report only means the checks listed in the report passed on that checkout.

## 7. Products present without a reproducible processing script

The cleaned D6 THEMIS and D8 geology rasters, GeoPackages, and some GeoJSON exports under `data/MARSX_D6_THEMIS_CLEANED/` and `data/MARSX_D8_GEOLOGY_CLEANED/` are deliverables prepared earlier in the project. Their metadata and hashes are inventoried, but this checkout does not contain the complete scripts and source configuration needed to recreate every cleaned product. Treat them as existing prepared files, not as a reproducible pipeline, until their original recipes are restored.

The optional MOLA crop helper is `scripts/fetch_mola_jezero_crop.py`; it can fetch and crop a PDS elevation tile when run, but there is no generated MOLA output in this checkout. MEDA tables in `data/raw/D9/` are archived readings and are not currently processed into a map layer.

## 8. Remaining pipeline work

- Add reproducible download/checksum handling for the CTX source pair and FU Berlin WFS snapshots.
- Obtain the published 2024 FU Berlin valleys-and-deltas GIS archive and integrate its northern delta / valley geometries after validating CRS and checksum. The repository endpoint blocked a prior download attempt.
- Find authoritative geometries or mission target records for the 14 unresolved landmark names. Do not turn panorama locations into feature boundaries.
- Obtain exact positions for the ten Three Forks sample tubes; current local event data contains names/times, not coordinates.
- Add reproducible source recipes for cleaned D6/D8 products, then perform cross-raster alignment checks.
- Generate and validate a hazard layer from terrain evidence if needed. Keep safety/hazard fields separate from scientific importance.
- Update [DATA_HANDOVER.md](DATA_HANDOVER.md), the dataset manifest, and validation report when a source or output changes.

Pathfinding implementation work is maintained by a teammate on another branch; it is not included as a data-processing step here. Once merged, confirm it uses the correct terrain grid, coordinate transform, and NoData mask.
