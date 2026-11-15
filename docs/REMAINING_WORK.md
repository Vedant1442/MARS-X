# MARS-X: Remaining Work

This is the project-wide checklist of work still needed to move MARS-X from its
current prototype to a reliable offline Jezero terrain-exploration demo. It
focuses on outcomes and dependencies rather than team ownership.

## Current baseline

- A Flutter app and a separate React/Vite prototype exist.
- The current terrain that is actually used for maps and route planning is a
  small landing-site HiRISE DTM window. It is not the full Jezero crater.
- A 20 m CTX DEM and matching 5 m CTX grayscale orthomosaic are present as
  source files, but are not integrated into the running maps or route grids.
- USGS SIM 3464 geology and Mars 2020 PLACES rover localizations have processed
  vector outputs. Flutter currently bundles a 10-point reference/label index
  and 531 rover localization points; it does not bundle the geology overlays
  or traverse lines.
- The 29-name landmark register exists, but only 4 records have coordinates;
  the other 25 remain unresolved. No validated terrain-hazard layer exists.
- Route planning on the current branch uses the local HiRISE grid and has
  simulated science/risk/time elements. The teammate's path-finding algorithms
  are implemented on another branch; merge and integration remain outstanding.
- Data sources, processing and known limitations are documented in
  `docs/DATA_HANDOVER.md`, `docs/DATA_SOURCES.md`,
  `docs/terrain_data_report.md`, and `docs/landmark_register.md`.

## Remaining work

### 1. Bring in and verify the path-finding branch

- [ ] Merge or cherry-pick the teammate's path-finding implementation into the
  main project branch and resolve conflicts with the existing planner.
- [ ] Confirm how the new algorithms consume elevation, slope, roughness,
  NoData, science targets, waypoints, and route profiles.
- [ ] Keep the existing HiRISE planner usable while integrating the changes.
- [ ] Run route correctness and regression checks after integration: passable
  endpoints, no NoData/blocked cells, connected paths, valid costs, and
  expected differences between profiles.
- [ ] Compare the implementation against known simple grids and confirm the
  same route/cost behavior on supported platforms.

**The algorithms themselves are considered implemented on the teammate's
branch; reimplementing them is not part of this checklist.**

### 2. Make the crater-wide terrain usable

- [ ] Verify CTX DEM and orthomosaic CRS, transforms, raster bounds, NoData,
  pixel orientation, image-to-elevation alignment, seams, and vertical
  reference using reproducible geospatial checks.
- [ ] Test representative Mars coordinate-to-pixel and pixel-to-coordinate
  conversions for CTX and HiRISE. Preserve each product's native CRS and
  record explicit transforms between products.
- [ ] Build a windowed or tiled offline CTX DEM reader. Do not load the full
  orthomosaic or DEM into memory as one texture/array.
- [ ] Build a multiresolution image pyramid for the 5 m CTX image and retain
  transparent/unknown margins where its footprint is smaller than the DEM.
- [ ] Produce and document a crater-wide terrain sampling grid suitable for
  route search. Choose its cell size from tested performance and scientific
  use; distinguish it from source pixel resolution.
- [ ] Keep the current HiRISE detail limited to its verified footprint and
  define how map display transitions between CTX and HiRISE resolutions.
- [ ] Test storage, import time, memory, and rendering performance on target
  Android devices. Keep large map data in removable app-managed storage if it
  cannot reasonably ship in the APK.

### 3. Correct and validate the geospatial data pipeline

- [ ] Fix the backend HiRISE loader so source NoData values are masked before
  block averaging and cannot create false elevations, slopes, or routes.
- [ ] Reconcile backend grid dimensions, cell spacing, and AOI mapping with
  `jezero-dem.json` and `src/jezeroGrid.ts`; remove hand-entered transforms
  that do not match the generated grid.
- [ ] Record one canonical project Mars coordinate contract, while retaining
  each product's original CRS, sphere, longitude direction, latitude
  convention, units, transform, valid coverage, and NoData meaning.
- [ ] Add spatial QA for the D6 THEMIS and D8 geology products: source
  provenance, alignment checks, map coverage, valid masks, and categorical
  lookup consistency.
- [ ] Resolve the missing Mars CRS metadata on the cleaned D8
  `*_mars_lonlat.geojson` files or ensure all consumers use the explicitly
  documented Mars-aware format/GeoPackages.
- [ ] Recover and retain the source archives/processing provenance needed to
  reproduce geology and localization outputs on a clean checkout.
- [ ] Keep the SIM 3464 coverage boundary visible. Areas beyond that boundary
  must remain unknown, not be rendered as areas with no geology.

### 4. Finish and validate named scientific locations

- [ ] Find authoritative points or feature geometries for the 25 unresolved
  landmark records. Never derive coordinates from screenshots or descriptive
  prose alone.
- [ ] Store points, lines, and regions with their actual geometry types.
  Representative points must be explicitly identified as such and must not
  replace feature extents.
- [ ] Join Perseverance observations and waypoints to PDS localizations or
  other authoritative mission location products, preserving source IDs and
  location uncertainty.
- [ ] Obtain authoritative coordinates for Three Forks sample drops before
  mapping individual tubes; the local event table contains timestamps but no
  coordinates.
- [ ] Review names whose status is unresolved or informal. Do not treat a
  campaign nickname as an IAU-approved feature or infer a physical process
  from the nickname.
- [ ] Add sourced rover images only when their product labels, time, camera,
  and location/pose support the association. No real rover panorama assets
  are currently integrated.
- [ ] Regenerate JSON, GeoJSON, and CSV from one source of truth and verify
  matching IDs, attributes, coordinates, source URLs, and null handling.

### 5. Build scientifically defensible planning layers

- [ ] Derive slope and terrain metrics from the selected crater-wide planning
  grid with documented methods, units, resolution, edge behavior, and NoData
  propagation.
- [ ] Define a hazard layer only from data that supports it. At minimum,
  identify missing coverage and the limits of 20 m CTX resolution; do not
  portray small rocks or astronaut-scale obstacle detection from these data.
- [ ] Keep scientific importance separate from route safety and mobility
  assumptions.
- [ ] Replace demonstration science targets and weights with cited targets
  and reviewed values, or clearly leave the science-routing mode disabled.
- [ ] Do not use the blank D8 science-weight template as route input.
- [ ] Keep slope limits, walking speed, duration, risk weights, and pressure
  labeled as model assumptions unless validated against an appropriate
  source/model.
- [ ] Add unit/quality/time/location provenance for environmental readings.
  MEDA is archived point data, not a spatial weather forecast; no MEDA subset
  is currently integrated. Radiation observations from Gale Crater must stay
  labeled historical and location-specific.
- [ ] Treat THEMIS as thermal inertia, not surface temperature. Add a
  temperature map only if a real spatial product with valid coverage and
  temporal context is acquired and documented.

### 6. Complete the map and exploration experience

- [ ] Replace the current Flutter map's limited painter/tilt view with a
  tested interactive terrain view supporting orbit/rotate, pan, zoom, north
  reset, and a clear 2D precision mode.
- [ ] Render CTX imagery and elevation as separate layers; add HiRISE detail
  only where available.
- [ ] Add geology, rover traverse, landing ellipse, labels, and named
  landmarks as independently toggleable overlays with legends and coverage
  indicators.
- [ ] Add actual layer controls and explanatory legends for only the layers
  that are available. Keep unsupported temperature/mineral/hazard layers
  marked unavailable rather than showing placeholder data as measurements.
- [ ] Ensure every displayed feature can show name, source, geometry meaning,
  coordinate status, confidence/limits, and scientific context.
- [ ] Complete offline landmark-to-landmark guidance, route progress, and
  elevation profile behavior using verified landmarks where available.
- [ ] Add rover imagery/panoramas only after the image metadata and poses are
  correctly joined; keep observation location separate from the target's
  location.
- [ ] Confirm saved missions, report export, and offline use continue to work
  after the terrain/data package is updated.

### 7. Test, package, and release

- [ ] Add/run unit and integration coverage for coordinate transforms,
  raster-window reads, NoData, GeoJSON/GeoPackage parsing, route search,
  route validation, landmark selection, and offline startup.
- [ ] Confirm route outputs from the merged algorithm branch against fixtures
  and the current local HiRISE implementation before changing defaults.
- [ ] Run the full app test/build pipeline and address lint/build errors.
- [ ] Test airplane-mode operation from a clean install with no mandatory
  network calls.
- [ ] Profile memory, frame rate, startup, route response, and package storage
  on representative devices.
- [ ] Produce a reproducible data-package manifest with versions, checksums,
  sources, licenses/credits, CRS, extents, resolution, units, NoData,
  processing history, and validation status.
- [ ] Review all screens and reports for accurate OBSERVED/DERIVED/MODELED/
  SIMULATED labels and retain the educational/non-operational safety wording.
- [ ] Build and install the release APK on clean devices; complete repeatable
  end-to-end demonstration runs.

## Suggested completion order

1. Merge and validate the teammate's path-finding branch while preserving the
   current HiRISE experience.
2. Correct HiRISE NoData and georeferencing inconsistencies; establish
   coordinate/raster QA checks.
3. Prototype CTX windowed access and a tested crater-wide planning grid.
4. Integrate CTX map rendering and coverage-aware SIM 3464 overlays.
5. Resolve high-priority landmark and sample-location evidence; keep remaining
   records visibly unresolved.
6. Add reviewed science/hazard inputs, then complete experience, performance,
   offline, and release validation.

## Definition of done

- A clean offline install opens a georeferenced Jezero map with source and
  coverage visible.
- CTX and HiRISE data are used only within verified footprints, with valid
  NoData behavior and documented transforms.
- The merged path-finding implementation operates on the intended grid and
  passes the route correctness checks.
- Every mapped named landmark has authoritative geometry/coordinates and
  traceable provenance; unresolved names remain unmapped and marked unknown.
- Scientific value, model assumptions, and route safety are presented as
  separate concepts; no route is described as certified safe.
- Data generation, validation, and app build steps can be reproduced from
  documented sources and commands.
