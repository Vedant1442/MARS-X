# MARS-X Jezero data handover

**Audience:** backend and frontend teams  
**Inventory:** `data/metadata/data_handover_manifest.json`  
**Validation output:** `data/metadata/data_handover_validation.json`  
**Validation command:** `python data/validate_data_handover.py`

This handover describes files present in this checkout and confirms integration
only where runtime code or Flutter asset declarations load them. The Flutter
map and planner currently load the crater-wide 100 m CTX grid, its aligned
overview, reference points, rover stops, and partial rim lines. The web app and
backend still use the local HiRISE terrain patch. D6/D8 products and the full
requested landmark register are not runtime layers. Pathfinding work from a
teammate branch is not treated as completed unless it is present and verified
in this checkout.

## Coordinate contract

- Use Mars coordinates explicitly: longitude east-positive, normally 0–360°;
  latitude planetocentric unless a product label states otherwise. GeoJSON
  coordinates are `[longitude, latitude]` under the project's Mars extension.
- The shared Mars sphere radius used by most local products is 3,396,190 m.
  Mars geographic coordinates are **not WGS 84**; generic GeoJSON/web-map
  consumers often assume WGS 84, so transform explicitly or use Mars-aware
  parsing.
- Target CTX bounds are west/south/east/north
  `[76.997437, 17.580520, 78.582563, 19.290187]`. Source footprints vary.
- Native projections differ: CTX uses equidistant cylindrical centered at 0°
  with planetocentric standard parallel 18.4663°; SIM 3464 uses Mars Transverse
  Mercator centered at 77.5°; project app-EQC files use a local equirectangular
  projection centered at 77.5° with standard parallel 18.4°; HiRISE has its own
  projected transform. Do not align by matching image dimensions or stretching
  extents.
- Keep NoData, missing map coverage, and unknown landmark locations explicit.
  Do not convert missing values to zero or treat unmapped areas as feature-free.

## Data available now

### Raster and terrain products

| Dataset and exact path(s) | Type, source, CRS, coverage and resolution | Runtime status and consumer use | Limitations |
|---|---|---|---|
| **HiRISE D3 source:** `data/raw/D3/DTEEC_045994_1985_046060_1985_U01.IMG`; metadata/catalogue `data/catalogue/stac_DTEEC_045994_1985_046060_1985_U01.json` | PDS3 IMG DTM source, about 1.0097 m/pixel; published footprint about 77.3834–77.5011°E, 18.3053–18.5484°N. Mars 2015/planetocentric/equirectangular per source label and generated metadata. Elevation metres. | Source input for regeneration only; no runtime component reads the IMG directly. | Local landing area only. Keep the source label with the file; don't treat nominal source pixel scale as planner resolution. |
| **HiRISE display and planner outputs:** `mobile/assets/terrain/jezero-dem.bin`, `mobile/assets/terrain/jezero-dem.json`, `mobile/assets/terrain/jezero-grid.bin`, `public/jezero-dem.bin`, `public/jezero-dem.json`, `src/jezeroGrid.ts` | Derived from D3 by `data/build_dem.py`. Display grid is 480×304 Int16 little-endian decimetres (`-32768` NoData), about 8.6 m spacing; planner grid 120×76, cells about 34.25×34.91 m, metadata cellM 34.58 m. Roughly 4.11×2.65 km, centered near landing. Elevations in metres after decoding. | **Flutter:** DEM/metadata asset loaded; grid drives local map and A* planner. **Web:** generated TypeScript grid drives planner; `Terrain3D.tsx` fetches public binary. **Backend:** `backend/app/core.py` loads public binary. | This is the existing HiRISE implementation and remains the active terrain. Backend loader currently does not mask `-32768` before averaging. Backend API also uses a hard-coded small geographic AOI rather than the exact generated grid georeference; validate its coordinate-to-cell mapping before relying on route output. |
| **Crater-wide CTX DEM:** `data/raw/JezeroWide/M20_JezeroCrater_CTXDEM_20m.tif`; app outputs `mobile/assets/terrain/jezero-ctx-100m-elevation.bin` and `.json` | Source GeoTIFF, 4456×5067, 1-band Float32, 20×20 m. App grid is 891×1013 signed Int16 metres at about 100 m spacing. Mars 2000 sphere, equidistant cylindrical, central meridian 0°, standard parallel 18.4663° planetocentric. Elevation metres; source NoData `-3.4028235e+38`, app NoData `-32768`. | **Integrated in Flutter:** asset declared in `mobile/pubspec.yaml`, loaded in `providers.dart`, used by the crater-wide map and route planner. Not loaded by the web app or backend runtime. | Stereo-derived and aggregated; small hazards are unresolved. The rectangular grid extends beyond the crater rim. Alignment and seams still require independent QA. |
| **CTX orthomosaic:** `data/raw/JezeroWide/M20_JezeroCrater_CTXortho_mosaic_5m.tif`; Flutter output `mobile/assets/terrain/jezero-ctx-overview.png` | Source GeoTIFF, 17766×20234, 1-band Byte grayscale, about 5.002 m/pixel. Same Mars sphere/projection parameters as CTX DEM. Image digital numbers, not elevation. Source footprint is slightly smaller than the DEM. | **Overview integrated in Flutter** and aligned to the 100 m route-grid cells; not loaded by web/backend. | Flutter uses the resampled overview, not all 5 m pixels. Pixels beyond source coverage are transparent. |
| **D6 THEMIS source grid:** `data/MARSX_D6_THEMIS_CLEANED/themis_jezero_clean_source_grid.tif` | GeoTIFF 890×890 Float32, 100 m; simple cylindrical Mars, central meridian 0°, standard parallel 0°, sphere 3,396,190 m. Projected bounds 4,564,100–4,653,100 m E, 1,052,100–1,141,100 m N. Thermal inertia `J m-2 K-1 s-1/2`; NoData 0, about 62.36% valid. Source: Edwards & Buz 2021, Zenodo 10.5281/zenodo.4931348. | **Present, not integrated.** | Derived thermophysical property, not temperature. Exact archive member/checksum and processing source were not supplied. |
| **D6 cleaned Mars TM:** `data/MARSX_D6_THEMIS_CLEANED/themis_jezero_clean_mars_tm_100m.tif` | GeoTIFF 566×595 Float32, 100 m; Mars 2000 sphere Transverse Mercator, central meridian 77.5°, metres. Clipped to SIM 3464 MapBoundary. NoData 0; 55.02% valid. | **Present, not integrated.** Backend can read with geospatial raster tooling; frontend needs an explicit reprojection/reader. | Bilinear resampling does not increase detail. Alignment not independently validated. |
| **D6 app-EQC:** `data/MARSX_D6_THEMIS_CLEANED/themis_jezero_clean_app_eqc_100m.tif`; metadata `data/MARSX_D6_THEMIS_CLEANED/themis_metadata.json` | GeoTIFF 563×594 Float32, 100 m; local Mars EQC centered 77.5°, standard parallel 18.4°. NoData 0; 55.35% valid. Its dimensions/transform match the D8 app-EQC categorical TIFF. | **Present, not integrated.** Suitable as a development preview fixture with explicit CRS and NoData. | Matching grid declaration is not proof of pixel-level alignment. Not aligned by declaration to CTX or HiRISE. Never label as temperature. |
| **D8 geologic-unit ID rasters:** `data/MARSX_D8_GEOLOGY_CLEANED/jezero_geologic_unit_id_100m.tif`, `data/MARSX_D8_GEOLOGY_CLEANED/jezero_geologic_unit_id_app_eqc_100m.tif`; lookup `data/MARSX_D8_GEOLOGY_CLEANED/geologic_unit_lookup.json` | Categorical GeoTIFF UInt16, one band; Mars TM 566×595 and local EQC 563×594, both 100 m. NoData/unknown ID 0. IDs map through lookup; they are not science scores. Source: USGS SIM 3464. | **Present, not integrated.** Frontend can prototype an app-EQC layer with nearest-neighbor sampling; backend can resolve IDs using lookup. | Rasterization provenance and pixel alignment need review. Blank science-weight template is not a usable score layer. |

### Vector, tabular and named-feature products

| Dataset and exact path(s) | Geometry/format, source, CRS and coverage | Runtime status and consumer use | Limitations |
|---|---|---|---|
| **USGS SIM 3464 processed vectors:** `data/processed/jezero/sim3464_geologic_units.geojson` (unit polygons); `sim3464_geologic_contacts.geojson` (contacts); `sim3464_linear_landforms.geojson` (channels, rim crests, ridges, delta fronts); `sim3464_surface_features.geojson` (surface polygons); `sim3464_location_features.geojson` (small-crater points); `sim3464_landing_ellipse.geojson`; `sim3464_map_coverage.geojson`; `sim3464_named_label_anchors.geojson` | GeoJSON FeatureCollections with Mars coordinate extension; east-positive longitude/planetocentric latitude. Derived from Sun & Stack 2020, USGS SIM 3464, transformed from Mars TM, clipped to CTX footprint and simplified by 8 m. Coverage polygon marks narrower SIM 3464 map area. Counts are in `data/processed/jezero/source_manifest.json`. | **Processed, not loaded by Flutter/web/backend runtime.** Backend can query/convert them now with a Mars-aware reader; frontend can render with a Mars map transform and coverage mask. | Label anchors position map text, not feature centers. Outside coverage means unmapped, not feature-free. Regional 1:75,000 geology is not an astronaut obstacle survey. |
| **D8 cleaned longitude/latitude vectors:** `data/MARSX_D8_GEOLOGY_CLEANED/geounits_mars_lonlat.geojson`, `geocontacts_mars_lonlat.geojson`, `surface_features_mars_lonlat.geojson`, `location_features_mars_lonlat.geojson`, `linear_features_mars_lonlat.geojson` | GeoJSON MultiPolygon/MultiLineString/Point by layer. SIM 3464 source. Project inventory describes Mars east-longitude/planetocentric latitude; individual files lack a Mars CRS member. | **Present, not integrated.** Prefer Mars-coordinate-aware consumers or GeoPackage variants. | Large files and implicit custom CRS; do not hand to a default Earth GeoJSON map widget. |
| **D8 GeoPackages:** `data/MARSX_D8_GEOLOGY_CLEANED/jezero_geology_clean_mars_tm.gpkg`, `data/MARSX_D8_GEOLOGY_CLEANED/jezero_geology_app_eqc.gpkg` | GeoPackage vector layers for geounits (MultiPolygon), contacts (MultiLineString), surface features, location points, linear features, plus source layers in package. Pyogrio metadata reports 1,304 geounits, 2,496 contacts, 285 surface polygons, 341 location points, 382 linear features in the cleaned bundle. | **Present, not integrated.** Good backend query source with OGR. Frontend should consume a packaged/filtered layer or backend results. | App-EQC CRS has generic/unknown names though numeric parameters are recorded; transformation, repair and alignment provenance need confirmation. |
| **Processed rover localizations:** `data/processed/jezero/perseverance_rover_stops.geojson`; Flutter copy `mobile/assets/terrain/perseverance-rover-stops.geojson`; source `data/raw/JezeroLandmarks/best_interp.csv` | 531 per-sol Point positions inside CTX footprint, sols 0–1897, PDS PLACES Release 16. Mars east longitude/planetocentric latitude. Source has 33,458 rows total. | **Flutter asset integrated**; map draws available points in the crater-wide CTX view. Web/backend do not load this source layer. | Interpolated/localized archive positions; numeric positional uncertainty absent. Not camera poses or a complete wheel track. Gaps and omitted PDS rows remain. |
| **Traverse display lines:** `data/processed/jezero/perseverance_rover_traverse.geojson` | 120 display segments derived from available PLACES positions; disconnected for gaps longer than two sols. Mars coordinate extension. | **Processed only; not included in Flutter assets**. | Connections are not exact wheel tracks and must not be used for safety or traversability claims. |
| **Reference/label point index:** `data/processed/jezero/jezero_landmarks.geojson`; Flutter copy `mobile/assets/terrain/jezero-landmarks.geojson` | 10 Point features: landing site, Jezero gazetteer center, and eight SIM 3464 text-label anchors; Mars-aware GeoJSON. | **Flutter asset integrated**; loaded by provider and map screen, with only points inside current local georeference visible. No web/backend loading of this file. | Not the full requested register. Label anchors are not feature centers. |
| **Requested landmark register:** `data/processed/jezero/landmarks.json`, `landmarks.geojson`, `landmarks.csv`; generator `data/build_landmark_register.py` | 29 requested names; currently 15 non-null geometries: 8 points, 1 MultiPoint, 3 channel MultiLineStrings, 1 possible-paleolake Polygon, and 2 SIM 3464 GeometryCollections. Fourteen names remain null. Mars east-positive longitude, planetocentric latitude, Mars 2000 sphere. | **Not integrated.** Backend can parse it now as a Mars-aware catalogue/spatial source. Frontend can prototype display with Mars CRS handling, geometry-collection support, null filtering, and source metadata. | FU Berlin WFS channel attribution is spatial because source lines lack names. The lake is one possible reconstructed level. Panorama/sample/visit points are not feature centers. SIM 3464 geometry is limited to map and DEM coverage. No terrain hazards are included. Read `docs/landmark_register.md` before display/use. |
| **Three Forks sample events:** `data/raw/JezeroLandmarks/ThreeForks/sample_drop_timestamps.csv` | CSV with 10 depot events; no coordinates and no geometry. PDS sample depot source. | **Not integrated; event context only.** | Cannot be mapped without an authoritative sample-localization join. Do not infer tube coordinates from imagery or nearby rover positions. |
| **Lookup/weight and source metadata:** `data/MARSX_D8_GEOLOGY_CLEANED/geologic_unit_lookup.json`, `science_weight_template.csv`, `data/MARSX_D6_THEMIS_CLEANED/themis_metadata.json`, `data/processed/jezero/source_manifest.json`, `data/metadata/jezero_wide_manifest.json` | JSON/CSV metadata, attribute lookup and provenance. | Available to both teams for source labels, unit names and product inspection. | `science_weight_template.csv` weights are blank; do not use for route costs. D6/D8 handoff records contain provenance gaps. |

Catalogue/support files include `data/catalogue/datasets.json` and six `data/catalogue/stac_*.json` records. They describe product discovery, not additional integrated layers. No MOLA raster is present in this checkout; `scripts/fetch_mola_jezero_crop.py` is a helper, not proof of a downloaded product.

## Current landmarks and rover coverage

The 29-row register is a source-backed **name/evidence inventory**, not a complete GIS layer: 15 geometries are available and 14 are null. The separate 10-point index is what Flutter currently loads. Do not merge the two by assuming label-anchor points are feature centers. Remaining gaps include exact geometries for informal campaign targets, Three Forks tube coordinates, and a validated hazard layer.

Rover data available: 531 per-sol PLACES points, 120 processed line segments, and a 10-event Three Forks table without coordinates. Flutter bundles and draws the rover points in the crater-wide CTX view; the traverse lines are not bundled.

## Route planner capability and limits

- **Flutter planner:** A* route candidates on the 891×1013 CTX-derived grid at about 100 m spacing, with NoData and slope-based exclusions, route metrics, and the crater-wide overview. It also retains local HiRISE terrain assets, but the active crater-wide map route path uses CTX. Small terrain hazards remain unresolved.
- **Backend API:** FastAPI route generation/comparison, Dijkstra/A*, terrain sampling, route metrics and simulated risk/time on the same HiRISE grid, with synthetic fallback. It does not load CTX, SIM 3464, D6/D8 or rover layer files. Its `/api/science-targets` are demonstration placeholders, not mission GIS targets. Backend constants also assume a 35.99 m cell while generated metadata reports about 34.58 m; reconcile this with the actual grid transform.
- **Web app:** React engine uses a generated HiRISE grid in `src/jezeroGrid.ts`; `Terrain3D.tsx` loads `public/jezero-dem.bin`. The web terrain/route view is local HiRISE, not crater-wide CTX.
- **Safety:** These are educational candidates. Slope thresholds and speed, risk, roughness, uncertainty or science weighting are model assumptions; no output certifies astronaut mobility or surface safety. Backend binary loading also needs NoData and coordinate-to-cell correction/verification before operational data use.

## What each team can use right now

### Backend

- Use the HiRISE bundle for continued local prototype work, while fixing NoData handling and validating coordinate mapping before trusting API metrics.
- Use `data/processed/jezero/*.geojson` as read-only GIS fixtures with the collection's Mars coordinate metadata; use the D8 GeoPackages for efficient queries where their CRS is understood.
- Build CTX window/tile readers from `data/raw/JezeroWide/` now. Do not describe them as live API layers until a reader and coordinate transform are implemented.
- Use the register for names/provenance only; null geometry is not routable. Keep science significance separate from route costs and hazards.

### Frontend

- Flutter can use its existing local HiRISE DEM, 10-point reference index, and 531-point rover localization asset now; these are already in `mobile/pubspec.yaml` and loaded by providers.
- Web can use the generated HiRISE grid and public binary now. Its current route waypoints are generated terrain landmarks, not the named register.
- For new vector previews, use processed SIM 3464 GeoJSON with its Mars extension and display the map coverage polygon. Filter null geometries. Do not load unannotated D8 `*_mars_lonlat.geojson` into a default Earth map widget.
- The current Flutter CTX preview is integrated; full-resolution CTX browsing and D6/D8 rendering remain future work. Keep DEM and image as distinct layers and their footprints separate.

## Reproduction and processing

| Operation | Command/script | Inputs/output and caveat |
|---|---|---|
| Rebuild HiRISE binaries | `python data/build_dem.py` | Reads `data/raw/D3/...U01.IMG`; writes `public/jezero-dem.*`, `src/jezeroGrid.ts`, and Flutter terrain assets. Keep existing implementation intact. |
| Acquire source layers | `python data/fetch_landmark_sources.py` | Network download for SIM 3464 and PDS PLACES/sample data; do not rerun unless intentionally refreshing source inputs. |
| Rebuild SIM 3464/PLACES vectors | `python data/build_jezero_vectors.py` | Requires `pyogrio`, `pyproj`, `shapely`; writes `data/processed/jezero/`. Raw USGS SIM 3464 GDB is present under `data/raw/JezeroLandmarks/usgs/sim3464_JezeroNili_FINAL/Geodatabase/Nili.gdb`; PDS PLACES CSV is `data/raw/JezeroLandmarks/best_interp.csv`. |
| Rebuild requested landmark register | `python data/build_landmark_register.py` | Rewrites only the three named landmark exports. |
| Fetch dataset catalogues | `python data/fetch_datasets.py` | Live network requests; writes catalogue metadata and optional sources. It is not a local build step. |
| Validate handover | `python data/validate_data_handover.py` | Read-only inspection; writes `data/metadata/data_handover_validation.json`. Uses Pillow and project-local Shapely/Pyogrio when present; no raster pixel scan. |

`data/build_crater_wide_app_assets.py` builds the current 100 m CTX grid and overview; there is no full-resolution CTX tile/pyramid builder. The pathfinding algorithm work is understood to be on a teammate branch and is not treated as a data-team task here; after it is merged, validate that it consumes the project DEM georeference, NoData mask, and future hazard inputs. `scripts/fetch_mola_jezero_crop.py` and `scripts/download_hirise.py` are acquisition helpers, not evidence of those products being installed.

## Validation report summary

The checked-in report `data/metadata/data_handover_validation.json` was generated
before the latest CTX asset integration inventory edits. Its numbers describe
that earlier run; rerun `python data/validate_data_handover.py` to refresh them.
That report records:

- 7 GeoTIFFs, 19 GeoJSON files, 2 GeoPackages inspected; all 49 paths in the manifest at that time existed.
- 19 manifest/source checksums compared against the files on disk; 0 mismatches. The three landmark exports each have 29 rows, matching ID sets, and no duplicate IDs.
- Landmark exports: 29 records, 14 null geometries, no duplicate IDs, valid GeoJSON and geometry structure. The register also has 2 GeometryCollections, each containing mapped components; two records intentionally have geometry but no representative point.
- GeoJSON coordinates fit Mars numeric longitude/latitude domains; coordinates in collections with declared bounds fit those bounds. Five cleaned D8 GeoJSON collections do not embed Mars CRS metadata; interpret only using the project manifest/GeoPackage, never Earth defaults.
- GeoTIFF headers were readable for all 7 rasters; dimensions, pixel tags, tie points, NoData tags and checksums were inspected. CTX orthomosaic has no GeoTIFF NoData tag. Pixel values/masks were not scanned.
- Pixel-level raster validation, full GDAL metadata inspection, coordinate control-point tests, reprojection, CTX/HiRISE alignment and cross-raster pixel alignment were **not** performed. No scientific alignment pass is implied.

## Outstanding tasks and biggest blockers

1. **Coordinate correctness and CRS:** establish canonical Mars CRS transforms between CTX, HiRISE, D6, D8 and app-EQC; test known control points and correct backend AOI/grid mapping.
2. **CTX package and runtime:** build a windowed/multiresolution DEM plus image reader/package; add frontend layer rendering and backend sampling without loading a giant raster into memory.
3. **NoData and alignment:** correct backend HiRISE NoData handling; validate CTX seams, overlap, ortho alignment and vertical reference; verify D6/D8 raster alignment.
4. **Landmark evidence:** add authoritative geometry or named observation/sample positions for the 14 null-geometry register entries. Keep geological feature extents separate from rover observation points; use per-sol rover localizations only for the named visits specifically linked by mission sources. Join official individual tube deployment positions for Three Forks.
5. **Hazard and route inputs:** derive a supported slope/roughness/hazard layer and provide a documented data contract for the teammate pathfinding branch to consume; keep scientific value separate from route safety.

**Estimate:** about 2–4 engineering weeks for a usable first CTX offline viewer/backend window-sampling prototype with CRS and NoData QA; add roughly 1–3 weeks for authoritative named-waypoint joins, map coverage-aware rendering, and a reviewed hazard/planning layer. Scientific sign-off could take longer if source alignments or positions cannot be independently reproduced. This is a planning estimate, not a verified schedule.
