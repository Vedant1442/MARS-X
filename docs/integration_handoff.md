# Jezero data handoff for parallel integration

**Status:** Crater-wide CTX is the primary map target. Integration should start on the CTX base now, in parallel with D6/D8 review. Spatial science sign-off remains pending for transformations and derived layers.

This handoff separates facts recorded in the files from checks the teams still need to perform. It is intended to let backend and frontend work proceed without treating an unchecked overlay as scientifically validated.

## 1. Current data inventory

The machine-readable inventory, file sizes, checksums, sources and known limitations are in [`data/metadata/integration_handoff_manifest.json`](../data/metadata/integration_handoff_manifest.json).

| Data | Files available | Safe integration work now | Pending before scientific sign-off |
|---|---|---|---|
| D6 THEMIS thermal inertia | Source-grid TIFF, Mars TM TIFF, app-EQC TIFF, metadata and source citation in `data/MARSX_D6_THEMIS_CLEANED/` | Build a continuous-raster layer reader and legend using the app-EQC raster. Display its units and NoData. | Obtain the teammate's processing script/source download record; audit valid mask and values; validate spatial alignment independently. Never label it temperature. |
| D8 SIM 3464 geology | Mars TM and app-EQC GeoPackages; Mars lon/lat GeoJSON; categorical TIFFs; unit lookup and blank science-weight template in `data/MARSX_D8_GEOLOGY_CLEANED/` | Build a categorical layer reader using the app-EQC unit-ID raster and its lookup. Build vector queries from the GeoPackage with its declared CRS. | Obtain processing code; document the Mars CRS on lon/lat GeoJSON; validate geometries, rasterization, map coverage and alignment. Do not use the blank weights for routing. |
| CTX crater-wide base (PRIMARY MAP) | 20 m DEM and 5 m grayscale orthoimage under `data/raw/JezeroWide/` | Start the offline tile/package pipeline, crater-wide coverage overlay, and viewer integration immediately. This is the base map for the whole crater. | Confirm georeferencing/NoData/seams and viewer transformation before claiming scientific alignment. Not yet used by the Flutter map. |
| Current HiRISE and rover points | Small HiRISE patch and point GeoJSON are declared Flutter assets. | Keep the existing screen working while adding a separate layer/package interface. | Do not assume the custom HiRISE grid is in the D6/D8 app-EQC CRS. Verify its transform before overlaying. |

## 2. Coordinate and raster contract

Use the term **Mars coordinates** explicitly. Never label Mars longitude/latitude as WGS 84 or silently send them through an Earth map projection.

The app-oriented D6 THEMIS TIFF and D8 geology unit-ID TIFF both declare a 563 × 594 grid at 100 m, with the same local equirectangular parameters and top-left transform:

- Sphere radius: 3,396,190 m.
- Central meridian: 77.5° east.
- Standard parallel: 18.4°.
- Affine transform: 100 m pixels, top-left `(-39,400 m, 1,108,500 m)`, rows advancing south.
- D6 values: continuous thermal inertia in `J m-2 K-1 s-1/2`; zero is NoData.
- D8 values: categorical `unit_id`; zero is NoData; labels come from `geologic_unit_lookup.json`.

The matching grid metadata makes these two raster files suitable for a **prototype overlay**. It does not prove that every pixel is correctly aligned to its source or that the files align to CTX/HiRISE. Pixel coordinates must use the full affine transform and pixel-center convention consistently. Leave NoData transparent or visibly unknown. Use bilinear resampling only for continuous values when reprojecting; use nearest-neighbor for geology IDs.

The D8 app-EQC GeoPackage records the same local CRS parameters, but its internal CRS names are generic. The `*_mars_lonlat.geojson` files have no explicit Mars CRS declaration. Do not ingest those files into a generic GeoJSON map widget until their coordinate convention is supplied in the package manifest or the GeoPackage is used instead.

CTX uses a different Equidistant Cylindrical definition (central meridian 0°, standard parallel 18.4663°), and the existing HiRISE app grid has its own derived transform. Reprojection between these datasets is a separate, explicit operation. Never align them by matching image dimensions or stretching extents.

### Required package layer metadata

Every installed layer must have a manifest entry with:

- Stable dataset and layer IDs, title, source citation/URL, version/date, checksum and license/credit.
- Data kind: continuous raster, categorical raster, point, line or polygon.
- Mars body, datum/sphere radius, full CRS definition, axis/longitude convention, and latitude convention.
- Raster dimensions, pixel type, units, affine transform, resolution, NoData meaning, and resampling method; or vector geometry type and attribute schema.
- Coverage geometry/bounds, source coverage limits, processing history, temporal validity where applicable, uncertainty/QA state, and known limitations.

The coordinate API passed between UI and data layer should use a named Mars coordinate type (east-positive longitude plus planetocentric latitude) and let the data repository transform into each layer's native CRS. Avoid bare `LatLng` values whose Earth assumptions are unclear.

## 3. Work that can proceed in parallel

### Backend / data integration

1. Define a versioned regional-package manifest following the fields above.
2. Implement local package import, checksum verification, version listing, install status and removal. Install into app-managed storage; use a temporary staging directory and only mark a package installed after verification completes.
3. Define repository operations such as `listPackages`, `listLayers`, `readRasterWindow`, `sampleRaster(MarsCoordinate)`, and `queryFeatures(layerId, MarsBounds)`.
4. Return value **and** coverage/source metadata. A missing raster value must remain `unknown`/NoData, not zero or a guessed value.
5. Use the app-EQC D6/D8 files as a development fixture. Keep the large source GeoJSON and duplicate CRS variants out of the APK; package the selected processed layer files for optional offline import.
6. Do not require network access for opening already installed packages or computing a route over installed data.

**Backend acceptance:** a test package can be imported offline, checksums detect corrupted files, the manifest survives app restart, D6 numeric samples preserve units/NoData, D8 unit IDs resolve through the lookup, and query coordinates are transformed by the repository rather than reinterpreted by the screen.

### Frontend

1. Make the crater-wide CTX DEM and orthoimage the first map view and data integration target. Show the footprint and available/unknown regions at startup; provide tiled or windowed access so the 5 m mosaic is not loaded as one giant texture.
2. Add a coverage panel/map with separate toggles for CTX DEM, CTX orthoimage, SIM 3464 geology, THEMIS thermal inertia, and the current HiRISE planner window. Distinguish each layer's footprint from the crater outline and from the data's scientifically valid pixels.
3. In parallel, add a 2D D6/D8 app-EQC preview, separate from the CTX view until their transformation is validated.
4. Add independent layer toggles and legends for thermal inertia and geology. Explain thermal inertia in plain language and label it “derived; not temperature.”
5. Show source, native resolution, installed/offline state, coverage boundary, and unknown areas for the selected layer.
6. For geology, show unit name/symbol from the lookup. Never display category number as a science score.
7. Implement tap inspection to report a thermal-inertia value or geology unit, source, and whether that pixel is NoData.
8. Keep 2D north-up selection functional; make 3D rendering consume the same coordinate-aware repository rather than adding a second projection implementation in the widget.

**Frontend acceptance:** the D6 and D8 test layers align with each other in the app-EQC view, their legends use the correct data types and units, NoData is apparent, and tapping a cell returns the matching stored value/category. Passing this fixture does not certify CTX/HiRISE alignment.

### Data team (in parallel)

1. Ask the contributing teammate for the D6/D8 scripts or notebook, exact source archive member names, tool versions, and processing commands. Keep the manifest's provenance status pending until these arrive.
2. Confirm whether the D6 app-EQC output's valid mask is preserved and document its valid-pixel count. Its current metadata does not give that count.
3. Confirm D8 GeoJSON coordinate order and exact Mars CRS; add explicit CRS metadata or direct the app to the GeoPackages.
4. Validate the D6/D8 raster overlap and D8 vector-to-raster alignment using independent coordinates/features. Report numerical transform precision separately from source positional accuracy.
5. Produce small expected-value fixtures at a few documented map locations, including at least one NoData cell and each categorical raster behavior needed by the UI.
6. Do not assign science weights or identify astronaut hazards from SIM 3464 geology alone.

### Route-planning team

1. Stub against the repository API now. Build the route grid across the crater-wide CTX DEM footprint as soon as its coordinate-aware window reader is available; until then use only a clearly labeled synthetic fixture.
2. Do not route from the geology category IDs or thermal-inertia layer until the data meanings, resolution, coverage, and weighting policy are reviewed.
3. Keep hard constraints separate from optimization costs; show modeled route metrics and unknown coverage. Never label an output route “safe.”
4. Do not advertise scientific route metrics until CTX transforms, NoData handling, and route-grid sampling pass validation. Route UI and data flow can be developed in parallel against the crater-wide footprint.

## 4. Gated integration order

```text
Now, in parallel:
  CTX crater-wide package + coverage/viewer ─┐
  Backend windowed raster/package API ───────┼─> crater-wide base integration
  Frontend crater-wide map + coverage UI ────┘

Also in parallel:
  D6/D8 preview + provenance/alignment QA ───> supplemental regional layers

After CTX transform/NoData/seam QA:
  enable validated crater-wide elevation/imagery and terrain route sampling

After rover image + camera geometry QA:
  enable only panoramas with verified pose/location
```

## 5. Explicit non-goals for this handoff

- Do not bundle all 5 m CTX pixels, all D8 GeoJSON, or source TIFFs in the APK.
- Do not reproject Mars data to Web Mercator or use Earth XYZ tile assumptions.
- Do not treat the 100 m THEMIS layer as temperature or a real-time forecast.
- Do not treat geology IDs as priority values or the regional geologic map as a small-rock hazard survey.
- Do not treat the current 531 per-sol PDS localizations as a complete rover track or camera/panorama poses.
- Do not confuse the tiny current HiRISE planner window with the crater-wide target. Do not advertise scientific route metrics until the crater-wide CTX terrain is loaded and validated.
