# MARS-X: Project Plan

An offline Flutter app (Android APK) for planning and "walking" a simulated Mars surface excursion in Jezero Crater, with no GPS and no internet.

> **Read first.** This is a simulation. Slope limits, walking speed, risk scores and some layers are our assumptions or models, and the app labels them. I wrote this without live web access, so package names, dataset URLs and numbers marked **VERIFY** must be checked before we depend on them. We never present made-up data as real.

---

## 1. Project description

### The problem
Planning a Mars walk means juggling imagery, elevation, geology and weather data that live in different places, usually online, usually without any route logic. And on Mars (or in a simulation of it) there is no GPS to tell you where you are.

### What MARS-X does
1. The user opens a **3D, interactive, offline map** of the Jezero study area and can switch filters on and off: contour lines, slope, temperature, pressure, minerals/geology.
2. The user **taps a start point and an end point** on the map.
3. The app computes **three routes**: **Safest**, **Quickest** and **Most scientifically important**, each with a **risk score** (0-100), distance, time estimate and elevation profile.
4. The user picks one route and **follows it without GPS** using **5-6 landmarks**. At each landmark the app shows what it looks like, how to get to the next one, and **why it matters scientifically**. When the user reaches it, they tap **Next**.
5. A short **simulated flyover video** shows what the track looks like along the way.
6. A **mission report** summarises the route, risks, targets, data sources and limitations.

### Who it's for
Students, judges and space enthusiasts who want to see how terrain, science value and risk trade off in a Mars walk, using real NASA/USGS data.

### What it is not
Not an operational astronaut tool, not live data, not multi-area, no accounts or cloud. Archived rover readings are never shown as live.

### Why the "no GPS" design is a feature
Without GPS, navigation becomes **landmark to landmark**, the way a real traverse is briefed. It also forces the app to explain the terrain, not just draw a line.

---

## 2. Feature list

**Must have**
- Offline 3D map with vertical-exaggeration slider, tilt/rotate/zoom
- Filters: contour, slope, temperature, pressure, minerals/geology (with opacity and legends)
- Tap to set start/end; tap anywhere to inspect (elevation, slope, roughness, passable)
- Three routes with risk scores and side-by-side comparison
- Landmark stepper (5-6 landmarks) with scientific importance and Next/Back
- Simulated flyover of the chosen route
- Mission report, methodology/data-sources screen, saved missions

**Extras I recommend adding**
- **"Why this route?"** panel: one plain sentence on why each route differs
- **Elevation profile** with landmarks marked and a "you are here" marker that moves when you tap Next
- **Estimated time and consumables** (clearly labelled simulated)
- **Data-type badges** on everything: MEASURED, DERIVED, HISTORICAL, SIMULATED
- **Assumptions editor**: change max slope or weights and re-plan (shows how sensitive the route is)
- **Route sensitivity check**: re-plan with slope +/-2 degrees and show whether the route changes
- **Landmark close-up**: high-zoom HiRISE crop, plus Perseverance Mastcam-Z/Navcam photos where an official image exists nearby
- **Share/export** the report as PDF
- **Glossary** (what is a DTM, slope, MEDA...)
- **Practice mode** (fixed demo route) so the app is never an empty screen

---

## 3. Architecture

```
NASA / USGS data
      |
[Build-time pipeline, Python: GDAL, Rasterio, NumPy]   <- we run it once; not shipped
  ingest -> normalize -> terrain analysis -> science layers -> tiles -> bundle
      |
 Data bundle (inside the APK)
      |
+------------------ Flutter app (Dart) ------------------+
| Data layer      bundle loader, tile source, SQLite     |
| Domain layer    cost model, A*, track builder,         |
|                 landmark selector, risk, report        |  <- pure Dart, no UI imports
| Presentation    3D map, filters, planner, stepper      |
+--------------------------------------------------------+
```

**Principles**
- **No server.** Everything runs on the phone.
- **Heavy geospatial work is done at build time**, so the app only loads ready-made rasters and tiles.
- **Domain logic is pure Dart**, so it is unit-testable and fast.
- **Routing runs in a background isolate**; the UI stays smooth.
- **Python reference router** exists only to check the Dart router.

---

## 4. Tech stack

| Part | Choice | Notes |
|---|---|---|
| App | Flutter (Dart), Android APK | Build with `--split-per-abi` |
| State | Riverpod | VERIFY version |
| 3D map | MapLibre native for Flutter with terrain (raster-DEM) | **VERIFY terrain support** in the Flutter plugin; spike first |
| 3D fallback | Local WebView running MapLibre GL JS or three.js from bundled assets | Works fully offline; still interactive |
| 2D emergency fallback | `flutter_map` + MBTiles | If 3D can't be made reliable |
| Local DB | `drift` or `sqflite` | Saved missions |
| Charts | `fl_chart` | Elevation profile |
| PDF | `pdf` + `share_plus` | Report export |
| Video | On-device camera-path flyover (no mp4 needed) | Optional pre-rendered clips for demo routes |
| Data pipeline | Python, GDAL, Rasterio, NumPy, pyproj, GeoPandas | Build time only |
| Tiles | MBTiles/PMTiles, terrain-RGB DEM tiles, vector contours | Built by pipeline |
| CI | GitHub Actions: `flutter test`, build APK | |

---

## 5. Data

Sources follow DATASETS.md. Sources used and how:

| Need | Source | Type |
|---|---|---|
| Basemap | CTX mosaic; HiRISE image inset | MEASURED |
| Elevation / slope / roughness / contours | HiRISE DTM, fallback CTX DTM, last-resort coarse DEM | DERIVED |
| Geology / minerals | USGS Jezero geologic map; CRISM-derived mineral maps if available (otherwise geologic units only) | DERIVED |
| Temperature layer | THEMIS-based thermal products if available (VERIFY); otherwise show rover MEDA readings only, no spatial map | DERIVED / MEASURED |
| Pressure layer | **Modelled from elevation**, calibrated to archived MEDA mean pressure | **SIMULATED** (no instrument maps pressure over an area) |
| Environment readings | Perseverance MEDA archived subset | MEASURED, archived |
| Radiation | Curiosity RAD, Gale Crater | HISTORICAL, other location |
| Science targets | Published papers + rover observation metadata | DERIVED, cited |

**Honesty rules for the filters**
- **Contour, slope:** computed from the DEM. Real derived products.
- **Temperature:** only a spatial layer if a real thermal product covers the area. Rover readings are single-point and time-dependent, so they appear as point readings with time, not as a map.
- **Pressure:** the model is `P(h) = P0 * exp(-(h - h0) / H)` with `P0` from archived MEDA data and scale height `H` as a documented assumption (VERIFY). The layer is stamped SIMULATED.
- **Minerals:** if CRISM-derived maps aren't practical, the layer shows **geologic units** and says so.

### Data bundle (inside the APK)
```
manifest.json         version, checksums
catalogue.json        sources, instruments, resolution, type, citations
terrain/              elevation, slope, roughness, obstacle, science_value (+ grid.json)
tiles/                basemap, hillshade, slope, temperature*, pressure*, minerals* (MBTiles)
tiles/dem_terrain/    terrain-RGB DEM tiles for the 3D view
vector/               contours, geologic_units.geojson, science_targets.geojson, landmarks
environment/          observations.json with full provenance
config/               profiles.json, assumptions.json
```
*only if the data exists. The app validates checksums at startup. Observations missing unit, instrument, time or source are dropped at build time.

**Size plan** (targets, not measurements): terrain layers a few MB; basemap + hillshade tiles tens of MB; DEM tiles tens of MB; small HiRISE inset tens of MB. Aim for about 150 MB total, otherwise ship an optional data pack.

---

## 6. Detailed technical implementation

### 6.1 Coordinates and Mars geometry
- Longitude/latitude: planetocentric, east positive, GeoJSON order `[lon, lat]`.
- **All distances and slopes use Mars's radius, 3,396,190 m.** Don't use library distance helpers that assume Earth.
- Analysis grid: local equirectangular projection, e.g. `+proj=eqc +lat_ts=18.4 +lat_0=0 +lon_0=77.5 +R=3396190 +units=m` (VERIFY the exact parameters).
- Display tiles use Web Mercator with Mars lon/lat degrees, for rendering only.

### 6.2 Terrain preparation (build time, Python)
1. Choose a study area of about 10 x 10 km where the DTM and geologic map overlap.
2. Reproject, clip and align DEM, imagery and geology to one grid.
3. Resample to a **10 m planning grid** (about 1 million cells). Keep a finer DEM only for rendering.
4. **Slope** with Horn's method on that grid. Note: slope depends on cell size, so we state the baseline.
5. **Roughness**: local standard deviation of detrended elevation (3x3 window).
6. **Obstacle mask**: nodata, slope above hard limit, steep-scarp buffer.
7. **Science value (V)**: rasterize geologic-unit weights (expert weights in a config file, labelled assumptions) plus proximity to cited targets.
8. Normalize S, R, V to 0-1, store as `uint8`, write `grid.json` (CRS, transform, shape, scale factors).
9. Generate contours, hillshade, terrain-RGB tiles, overlay tiles, bundle, manifest.

### 6.3 The track-making algorithm

**Grid graph.** 8-connected cells; step length is 10 m or 14.14 m.

**Cell factor** (stays positive, so A* works):
```
factor(c) = max(0.1, 1 + ws*S + wr*R + we*E + wo*O - wv*V)
edge_cost(a,b) = step_len * 0.5 * (factor(a) + factor(b))
```
`E` is the uphill penalty for that edge (signed elevation change over distance, normalised). `O` is a soft penalty near obstacles.

**Hard exclusions:** nodata, slope over the max slope (default is a simulation assumption, not a certified limit), obstacle mask, outside the study area.

**Three profiles**

| Route | ws | wr | we | wo | wv | Extra rule |
|---|---|---|---|---|---|---|
| Safest | high | high | medium | high | 0 | lower max slope than the others |
| Quickest | low | low | low | medium | 0 | closest to the straight line |
| Most scientific | medium | medium | low | medium | high | detour cap: length <= 1.5 x quickest route |

The detour cap stops the science route from wandering across the whole map to collect points. If the cap is hit, the algorithm re-runs with a smaller `wv`.

**Search.** A* with the octile-distance heuristic, scaled by the minimum factor (0.1), so it stays admissible. Dijkstra (same code, h=0) runs in tests and in "compare algorithms" mode to prove the cost matches and to show nodes expanded. Implementation uses `Float32List` for g-scores, `Int32List` for parents, and an array-based binary heap. No per-node objects. Search is limited to a corridor around the straight line (widened if no path is found).

**Smoothing.** Grid paths look like staircases. After search, run line-of-sight "string pulling": remove a vertex if the straight segment between its neighbours stays inside passable cells and costs no more than the original (within a small tolerance). Re-validate afterwards.

**Validation (every route):** endpoints passable, path continuous, no excluded cells, recomputed cost equals reported cost, within the time budget.

**Start/end handling:** if the tapped point is impassable, snap to the nearest passable cell within 100 m and tell the user; otherwise reject with a clear message.

**Time estimate:** `time = sum(length / speed(slope))` where `speed(slope)` is a simple configurable curve, labelled SIMULATED.

### 6.4 Risk score (0-100, simulated)
Per route, compute five parts, each in 0-1:

| Part | Meaning |
|---|---|
| Pmax | max slope on route / max slope limit |
| Pcaution | share of route length above a caution slope (assumption, e.g. 10 degrees, configurable) |
| Prough | mean roughness along the route |
| Punc | share of route on low-confidence cells (near nodata, coarse DEM) |
| Ptime | estimated time / time budget |

```
risk = 100 * (0.30*Pmax + 0.25*Pcaution + 0.20*Prough + 0.15*Punc + 0.10*Ptime)
```
Levels: under 25 low, 25-50 moderate, 50-75 high, 75+ very high. Weights and thresholds are simulation assumptions shown in the methodology screen and in the report. The app shows the five parts as a small breakdown so the score is explainable.

**Science score** per route: sum of V along the path plus importance of landmarks passed, normalised 0-100. Shown beside risk so the trade-off is visible.

### 6.5 Landmark selection (the no-GPS feature)
Goal: 5-6 landmarks along the chosen route that are **recognisable and scientifically meaningful**, spread out evenly enough to navigate between.

1. Sample the route every ~25 m with distance-along-route `s`.
2. **Candidates:**
   - Science targets within ~150 m of the route (snapped to the nearest route point).
   - Terrain landmarks: crossings between geologic units, local elevation highs/lows, strong slope breaks, ridge/crest points.
3. **Score** each candidate: `0.6 * science_importance + 0.4 * distinctiveness - distance_penalty`.
   - Distinctiveness comes from terrain curvature, unit contrast and elevation prominence.
4. Pick `K` landmarks (K = 5 or 6 depending on route length) by dynamic programming: maximise total score with gap limits `0.5 * L/(K+1) <= gap <= 1.8 * L/(K+1)`.
5. If no valid set exists, relax the gap limits, then fill the remaining slots with evenly spaced terrain landmarks.
6. **For each landmark the app generates:** name, position, bearing and distance to the next one, elevation change, slope range of the leg, estimated leg time, a short plain-language description ("ridge crest, ground drops on your right"), scientific importance with a citation (from the catalogue or the geologic unit description), and a HiRISE close-up crop from bundled tiles.
7. Terrain landmarks without a published science note are described by geologic unit and terrain only; the app never invents a science claim.

### 6.6 Following the track without GPS
- The **stepper screen** shows: current landmark, next landmark, bearing arrow (relative to map north), distance, leg slope/risk, mini-map and the "why it matters" card.
- **Next** advances the "you are here" marker and the elevation profile; **Back** undoes it.
- Optional **hands-off helper**: "I'm lost" shows the 3 nearest landmarks and the leg overview, so the user can re-anchor on the map.
- Progress is saved, so closing the app doesn't lose position.

### 6.7 The 3D interactive map
- Terrain mesh from the **terrain-RGB DEM tiles** (bundled), with the CTX/HiRISE basemap draped on top.
- Controls: pan, rotate, tilt, zoom, vertical-exaggeration slider, reset-north.
- **Filters** are overlay layers draped on the terrain: contour (vector lines), slope (colour ramp), temperature, pressure, minerals/geology. Each has an opacity slider, legend with units, and a data-type badge. Several can be on at once.
- Routes are drawn as lines on the terrain with landmark markers; tapping a marker opens its card.
- Performance: limit tile zoom to the study area, cap mesh resolution, lazy-load overlays, throttle camera updates.
- Because 3D support in Flutter map plugins is the biggest uncertainty, build a **small spike first**: offline tiles + terrain + one overlay + a line. If it fails, use the WebView fallback; if that fails too, ship 2D with hillshade and say so.

### 6.8 Simulated flyover ("short video")
There is no real footage of this exact route, and the user can pick any route, so the app **generates the video on the device**: a 15-30 second camera path that follows the route at low altitude through the 3D terrain with the real imagery draped on it, pausing briefly at each landmark. It is labelled "Simulated flyover from real terrain data". For landmarks near Perseverance's actual path, the app can show official rover photos with attribution. For demo routes we may also bundle pre-rendered clips.

### 6.9 Environment screen
Archived MEDA readings with unit, instrument, observation time (UTC and sol), data age, location, source, data type. A banner says "archived, not live". Radiation shows as "Gale Crater, historical".

### 6.10 Saved missions and report
SQLite stores missions (start, end, chosen route, landmarks, progress, assumptions used). The report has: overview, selected route, landmarks and science, terrain risk with breakdown, environment, estimated duration (simulated), data provenance, known limitations. PDF export through the share sheet.

### 6.11 Code layout
```
lib/
  app/            routing, theme, providers
  data/           bundle_loader, tile_source, mission_repo (SQLite), catalogue
  domain/
    geo/          mars_geodesy, grid, sampling
    terrain/      cost_model, hazards
    routing/      astar, dijkstra, smoothing, validation, profiles
    track/        landmark_selector, leg_describer, risk, time_model
    report/       report_builder
  features/       map3d, filters, planner, stepper, science, environment, missions, methodology
  shared/         widgets, badges, legends
tools/            python pipeline + reference router + golden tests
test/             unit, widget, integration
```

---

## 7. Testing strategy

| Area | What we test | How |
|---|---|---|
| Geometry | 1 degree of latitude is about 59.27 km (Mars radius, not Earth); round-trip coordinate conversion | Dart unit tests |
| Terrain | Slope on a tilted synthetic plane equals the plane's angle; flat is 0; nodata becomes impassable; layers stay within 0-1 | Python + Dart tests (synthetic fixtures stay in `test/`, never shipped) |
| Cost model | Edge costs always positive for random weights | Property test |
| Routing | A* and Dijkstra give identical cost on 200 random pairs; A* expands fewer nodes; no path crosses excluded cells; path is continuous; recomputed cost matches | Unit tests |
| Profiles | Safest max slope <= quickest max slope; science route science score >= quickest | Fixture tests |
| Smoothing | Smoothed path stays passable and costs no more than the original | Unit test |
| Parity | Dart router matches Python reference on golden routes | Golden-file test |
| Landmarks | 5-6 landmarks, gaps within limits, ordered along route, every science claim has a citation | Unit tests |
| Risk | Score in 0-100; known synthetic routes produce expected levels | Unit tests |
| Offline | Full flow works in airplane mode, no network permission requested | Manual + integration test |
| 3D/filters | Layers toggle, opacity changes, route and markers render, no crash on rotate/zoom | Widget + integration tests, device checks |
| Stepper | Next/Back updates marker and profile; progress survives restart | Widget test |
| Data integrity | Checksums pass; every layer, target and reading has source, instrument, time, type | Pipeline lint + app startup check |
| Honesty | No UI text calls archived data "live"; pressure/temperature models labelled SIMULATED; radiation labelled Gale/historical | String and UI review checklist |
| Performance | Route under 3 s typical; start under 4 s; memory under 500 MB; 3D map smooth on a mid-range phone and checked on a low-end one | Profiling on real devices |
| Release | Clean install of the signed APK on at least two different phones; 3 demo runs in a row without a crash | Manual |

---

## 8. Main risks

| Risk | Plan |
|---|---|
| 3D terrain in Flutter is unreliable | Early spike; WebView fallback; 2D fallback |
| APK too big | Small study area, 10 m grid, quantized layers, optional data pack |
| Dart routing slow | Typed arrays, corridor search, coarser grid, isolate |
| No spatial temperature or pressure data | Label clearly; modelled/derived layers marked SIMULATED or omitted |
| HiRISE DTM doesn't cover the area | Fallback chain with a visible warning banner |
| Landmarks lack science notes | Use geologic-unit descriptions; never invent claims |
| Earth-radius math creeps in | Own geodesy module and a test |

## 9. Decisions to make early
1. Exact study area and terrain source (HiRISE DTM or CTX DTM).
2. Which 3D approach wins the spike.
3. Whether a real thermal (THEMIS-based) layer is available, or we show only point readings.
4. APK size ceiling and whether an optional data pack is acceptable.
5. Minimum Android version and test phones.

---

## 10. Definition of done
- Whole app works in airplane mode.
- 3D map with contour, slope, temperature/pressure (honestly labelled) and mineral/geology filters.
- Tap start/end gives safest, quickest and most scientific routes with risk scores.
- Landmark stepper (5-6 landmarks) works with science notes and flyover.
- Every layer, target and reading shows its source and data type; simulated items are labelled.
- A* matches Dijkstra and the Python reference; test suite passes.
- Signed release APK installs on clean phones.
