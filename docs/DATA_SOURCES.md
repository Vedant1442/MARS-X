# MARS-X data sources, in plain language

**Status date: 14 November 2026.** This guide is for judges and readers who do not work with planetary data every day. It records where each dataset comes from, what it actually measures, how much ground it covers, whether it is in MARS-X yet, and what it cannot tell us.

## How to read this guide

- **Elevation model (DEM/DTM):** a grid of measured or stereo-derived ground heights. It supplies the shape of the 3D surface.
- **Image mosaic / orthoimage:** overhead photographs aligned like a map. It supplies the visible surface texture; it does not supply height.
- **Resolution:** the ground distance represented by one source pixel. A 5 m/pixel image can show smaller surface patterns than a 20 m/pixel image, but neither is a guarantee that every object at that size is identifiable.
- **Measured vs. derived:** a sensor measurement is observed by an instrument. A stereo DEM is calculated from matching orbital images. Derived products are useful data, but they are not direct laser measurements of every grid cell.
- **Offline status:** original source files are kept separately from the smaller tiles and grids prepared for the app. Installing the prepared package allows that region to be viewed without a network connection.

## Data that is already in MARS-X

### 1. HiRISE elevation near the Perseverance landing site

| Item | Details |
|---|---|
| Provider and instrument | University of Arizona HiRISE team; HiRISE stereo images from NASA's Mars Reconnaissance Orbiter (MRO). |
| Source product | `DTEEC_045994_1985_046060_1985_U01`, the PDS image downloaded from the [HiRISE Jezero DTM page](https://www.uahirise.org/dtm/ESP_045994_1985). |
| What it contains | Elevation estimates calculated from two overlapping orbital images. The downloaded `.IMG` has an embedded PDS label describing its dimensions, numeric format, map projection, and elevation values. It is a science raster, not a computer disk image. |
| Source scale and coverage | About 1 m per source pixel; the product footprint is approximately 77.3834–77.5011° east and 18.3053–18.5484° north. It covers a limited part of the crater around the landing area, not the whole crater. |
| MARS-X use | The build pipeline reads the original `.IMG` and creates a resampled local surface patch centered on the published landing coordinate. The generated app mesh has 480 × 304 height samples over about 4.1 × 2.65 km, or roughly 8.6 m between mesh samples. The route-planning grid is 120 × 76, about 34.6 m per cell. These are app output resolutions; they are not the original DTM's resolution. |
| Current files | Source: `data/raw/D3/DTEEC_045994_1985_046060_1985_U01.IMG` (local source file, not committed). Generated web and Flutter terrain files are described in [`data/README.md`](../data/README.md). |
| Source-file check | SHA-256: `b40739b4d32516ef9b3cd849f519a6a20df9720b5369a9c141047ced27c57654`. The build output records this digest so later copies can be compared with the source used to make the terrain assets. |
| Limitations | A high-resolution source product does not make the whole crater high resolution. Stereo quality and editing vary by location. The generated planning grid is much coarser than the source and cannot identify every rock or small hazard. The app must not describe a low route score as proof of safety. |
| Credit | HiRISE / NASA / JPL-Caltech / University of Arizona; cite the product page and original product ID. |

### 2. Perseverance landing location and Jezero center

The app's offline index includes these two authoritative reference points, but it is not a complete crater-wide landmark map:

1. **Octavia E. Butler Landing:** 77.4509° east, 18.4446° north. This is the published touchdown point, not the outline of the landing ellipse. It is sourced from the [Mars 2020 Jezero investigation paper](https://curis.ku.dk/ws/portalfiles/portal/334847713/Geological_multispectral_and_meteorological_imaging_results_from_the_Mars_2020_Perseverance_rover_in_Jezero_crater.htm).
2. **Jezero crater center:** 77.69° east, 18.41° north, from [USGS Planetary Names Gazetteer feature 14300](https://planetarynames.wr.usgs.gov/Feature/14300). This is a reference point, not a crater-rim boundary.

The Flutter APK bundles `mobile/assets/terrain/jezero-landmarks.geojson`, an expanded index with the two published reference points and eight USGS map-label anchors. Each anchor is the centroid of printed label geometry; it positions text and does **not** claim to be the feature center. Geologic boundaries and the landing ellipse remain separate layers on disk. The APK also bundles the PDS per-sol rover position file described below; its dots are shown only where the current local HiRISE map has coverage.

### 3. MEDA environmental samples

| Item | Details |
|---|---|
| Provider and instrument | NASA/JPL Mars 2020 Perseverance mission, Mars Environmental Dynamics Analyzer (MEDA). |
| Source products | PDS4 derived tables for the Relative Humidity Sensor (RHS) and Thermal Infrared Sensor (TIRS), currently archived for sols 10, 14, 20, and 28 in `data/raw/D9/`. Each CSV has an XML label. The source archive is the [PDS Mars 2020 MEDA data set](https://atmos.nmsu.edu/PDS/data/PDS4/Mars2020/mars2020_meda/). |
| What it measures | Weather and thermal observations made at the rover. These are time-stamped local measurements, not a temperature or humidity image covering all of Jezero. |
| MARS-X use | Source tables are present in the repository's raw-data folder. They are not yet rendered as an environmental map layer. |
| Limitations | Only four early sols are included in this subset. PDS release notes flag early local relative-humidity data as unreliable before sensor maintenance; MARS-X must preserve that warning and must not draw those samples as crater-wide conditions. |

## Whole-crater datasets downloaded; raster display is not yet integrated into the app

### 4. USGS CTX elevation mosaic for all of Jezero

| Item | Details |
|---|---|
| Provider and instrument | USGS Astrogeology Science Center; stereo imagery from MRO's Context Camera (CTX). |
| Product | [Mars 2020 Science Investigation CTX DEM Mosaic](https://astrogeology.usgs.gov/search/map/mars_2020_science_investigation_ctx_dem_mosaic). Direct file: [`M20_JezeroCrater_CTXDEM_20m.tif`](https://planetarymaps.usgs.gov/mosaic/mars2020_trn/CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXDEM_20m.tif); product label: [`M20_JezeroCrater_CTXDEM_20m.xml`](https://planetarymaps.usgs.gov/mosaic/mars2020_trn/CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXDEM_20m.xml). |
| Coverage and scale | The catalog lists 76.99–78.58° east and 17.58–19.29° north, covering Jezero crater. The DEM is 20 m/pixel, 4,456 columns × 5,067 rows, and listed as about 87 MiB. The checked local file is 90,345,300 bytes. |
| File and map details | Local file: `data/raw/JezeroWide/M20_JezeroCrater_CTXDEM_20m.tif`; XML metadata is alongside it. GDAL reads one Float32 band in metres with NoData `-3.4028235e38`; the valid values range from about −3,504.6 to −475.8 m. GDAL reports 99.94% valid pixels; the remaining cells stay unknown. Its CRS is the Mars 2000 sphere (radius 3,396,190 m), Equidistant Cylindrical, standard parallel 18.4663° planetocentric. SHA-256: `ba7f706ea1b5d63a562f28a7dcf7a7f3c79bce7f048e6974b57e8a33c30d1ba2`. See the [machine-readable manifest](../data/metadata/jezero_wide_manifest.json). |
| What it contains | Elevation calculated from CTX stereo pairs. The product includes the earlier Mars 2020 terrain-relative-navigation DEM and adds DEM areas to extend coverage across the crater. The USGS description says added DEMs were tied vertically to MOLA and some horizontal georeferencing was performed in ArcGIS Pro. |
| MARS-X status | The DEM has been downloaded and its TIFF signature, dimensions, CRS, data type, NoData value, and checksum have been verified. It has **not yet been integrated into the app**. The 20 m file is the crater-wide base; the local HiRISE patch can refine only its verified footprint. |
| Limitations | This is the right scale for crater landforms and broad route terrain, but it cannot resolve small rocks. The catalog does not publish a numeric horizontal error bound for every added area. Alignment and seams must be inspected before claiming precise local positions. |
| Credit | USGS Astrogeology Science Center; cite the catalog entry and its listed source papers. The catalog says public domain and requests citation of authors. |

### 5. Matching CTX surface-image mosaic

| Item | Details |
|---|---|
| Product | [`M20_JezeroCrater_CTXortho_mosaic_5m.tif`](https://asc-pds-services.s3.us-west-2.amazonaws.com/mosaic/mars2020_trn/CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXortho_mosaic_5m.tif), with its [source XML](https://asc-pds-services.s3.us-west-2.amazonaws.com/mosaic/mars2020_trn/CTX/ScienceInvestigationMaps_JPL/M20_JezeroCrater_CTXortho_mosaic_5m.xml). |
| What it contains | A map-aligned CTX image mosaic at 5 m/pixel, intended to pair with the crater-wide CTX DEM. CTX imagery is grayscale; it is not natural-color photography. |
| Verified local file | `data/raw/JezeroWide/M20_JezeroCrater_CTXortho_mosaic_5m.tif`; 359,599,280 bytes; 17,766 × 20,234 pixels; one 8-bit grayscale band; about 5.002 m/pixel. SHA-256: `cd9f4b2154fdd43e8c17abfbae63210b72507db2209d1d7db63f6f855b18d2df`. |
| Coordinate system and coverage | Mars sphere radius 3,396,190 m; Equidistant Cylindrical, standard parallel 18.4663° planetocentric. Its projected bounds are approximately 4,329,192.108–4,418,058.789 m east and 1,042,131.635–1,143,347.424 m north. This is slightly smaller than the DEM footprint: about 192 m less coverage on the west edge, 61 m on the east, 73 m on the north, and 52 m on the south. |
| MARS-X status | Downloaded and verified as a GeoTIFF. It will provide broad visible surface texture while the 20 m DEM supplies terrain height. It is not integrated into the app yet. When aligned to the DEM grid, uncovered margins must remain transparent/unknown instead of stretching the image or inventing pixels. |
| Limitations | Texture and elevation are separate layers and must be aligned using their labels, coordinate systems, and transforms. Image pixels do not measure height. The mosaic cannot show every small rock. |

These crater-wide products are stored as immutable sources under `data/raw/` with metadata and source URLs. Both files are now verified. They still need to be aligned and converted into an offline tile pyramid; they should not be placed as full-size files in the Android APK. The exact installed package size must be recorded after tiling.

### 6. Other HiRISE and CTX stereo coverage

The project catalog contains six candidate USGS HiRISE controlled DTM records and 37 CTX controlled DTM records in [`data/catalogue/datasets.json`](../data/catalogue/datasets.json). These are candidate higher-detail or supplemental regions, not a claim that HiRISE covers every part of Jezero. The catalog records footprints, nominal spacing, product IDs, and download links. Individual products will be added only after checking their footprint, map label, vertical reference, NoData areas, and overlap against the crater-wide CTX product.

## Global context and other planned layers

### 7. MOLA global elevation

- **Source:** NASA Planetary Data System, [MGS MOLA MEGDR archive](https://pds-geosciences.wustl.edu/missions/mgs/megdr.html).
- **What it is:** global topography calculated from Mars Global Surveyor laser-altimeter measurements. The PDS archive provides several pixel-per-degree products and labels describing their values and map coordinates.
- **Planned use:** broad Mars/global shape and as a reference for lower-resolution areas. Use the whole-crater CTX DEM where it provides better detail.
- **Limitations:** global MOLA is hundreds of metres per pixel near the equator, so it cannot resolve small craters, rocks, or rover-scale hazards. It is not currently installed in the app.
- **Local selection already researched:** the 128-pixel-per-degree tile `MEGT44N000HB.IMG` covers 0–90° east and 0–44° north. It is a regional piece of the global archive, not the crater's high-resolution DEM. The PDS archive provides labels alongside image files.

### 8. Murray Lab global CTX mosaic

- **Source:** [Murray Lab global CTX mosaic](https://murray-lab.caltech.edu/CTX/V01/TilePages/), made from MRO Context Camera images.
- **What it is:** near-global grayscale orbital imagery useful for a global-to-regional visual overview. It is imagery, not elevation.
- **Planned use:** optional global image layer, with regional offline packages where users request detail.
- **Limitations:** the full mosaic is too large to bundle in the APK. The project does not currently package it. Gaps and per-tile provenance must be shown rather than filled with invented pixels.

### 9. Rover images and panoramas

- **Discovery:** [NASA Perseverance raw images](https://mars.nasa.gov/mars2020/multimedia/raw-images/) and the [ASU Mastcam-Z public archive and panorama collection](https://mastcamz.asu.edu/mastcam-zs-360-panorama-collection/).
- **Science archive:** [NASA PDS Imaging and Cartography archive](https://pds-imaging.jpl.nasa.gov/), which provides original and calibrated products with labels and camera information.
- **Planned use:** store original frames and labels; make a 360-degree viewer only for real panoramas or compatible image sets with enough camera coverage. Record rover position, camera, sol/time, orientation, and source product identifiers.
- **Limitations:** a single rover image does not have a full panorama pose. We will not invent image positions or stitch unrelated frames into a fake 360 view. No rover panorama is currently integrated into MARS-X.

### 10. Geology, named landforms, and rover localization

- **Geologic map:** Sun and Stack's USGS [Geologic Map of Jezero Crater and Nili Planum](https://pubs.usgs.gov/publication/sim3464), Scientific Investigations Map 3464, scale 1:75,000. The publication includes a 349.3 MB GIS database ZIP with vector geometry, metadata, coordinate systems, and additional imagery/rasters. The source database has been downloaded to `data/raw/JezeroLandmarks/sim3464_database.zip` (SHA-256 `A88BD53A5573743CC4A20036C10E585106D08A433AD2F34AF269E9CEA1529F87`). Only the geodatabase and its coordinate-system/metadata files are used to build the offline vector layers; the other source imagery is not copied into the APK.
- **What was prepared:** the reproducible converter `data/build_jezero_vectors.py` writes Mars-coordinate GeoJSON into `data/processed/jezero/`. The export contains 1,021 geologic-unit polygons clipped to the downloaded CTX DEM footprint, 1,999 geologic contacts, 306 linear landforms (including 5 fluvial channels and 32 delta-lobe fronts), 187 surface-feature polygons, 258 small-crater points, the landing ellipse, the geologic-map coverage boundary, and 8 named map-label anchors. Each output feature retains its SIM 3464 source layer/record ID and source link. Map geometry is simplified by 8 m for display; the map scale does not support astronaut-scale obstacle claims.
- **Coverage limit:** SIM 3464's published boundary is about 76.8–77.8° east and 17.7–18.7° north. The crater-wide CTX DEM spans about 76.9974–78.5826° east and 17.5805–19.2902° north. These footprints differ. The separate `sim3464_map_coverage.geojson` layer identifies where this geological map provides coverage; outside it means “not mapped by this source,” not “no landform exists.” The full crater-wide DEM should not be presented as fully covered by SIM 3464.
- **Named map text:** the 8 map-label anchor coordinates come from centroids of USGS text-annotation polygons. They are useful for placing map labels such as Jezero, Neretva Vallis, and Una Vallis. They are not surveyed feature centers or feature-boundary geometries. Actual geologic extents and mapped channels/fronts are in the companion layers.
- **Rover localizations:** the [PDS Mars 2020 Rover PLACES archive](https://pds-geosciences.wustl.edu/missions/mars2020/places.htm) provides rover location/orientation and ancillary data from the mission operations localization database. The downloaded `best_interp.csv` table has 33,458 rows; 33,370 rover rows fall inside the crater-wide CTX DEM footprint. The processed per-sol layer has 531 localized positions from sols 0–1897, and its display route is split into 120 segments. Source table, PDS label, and Release 16 notes are retained under `data/raw/JezeroLandmarks/`.
- **Position caution:** `best_interp` contains localized/interpolated positions, not a continuous wheel-track survey. PDS Release 16 notes that `ROVER,n,0` rows are omitted. The generated line connects available per-sol archived positions and leaves longer gaps open; it must not be described as the exact rover track. The source table does not provide a numeric position error for each point.
- **Three Forks:** the PDS [Three Forks Depot Bundle](https://pds-geosciences.wustl.edu/missions/mars2020/) provides sample-drop timestamps and associated records. Its `sample_drop_timestamps.csv` contains the ten sample names and event times but not coordinates. Exact tube positions need a documented localization join; the app will not estimate those points from the NASA map image.
- **Map discovery:** the [USGS interactive Mars maps](https://astrogeology-usgs.hub.arcgis.com/pages/interactive-maps-mars) and [NASA Mars Trek](https://trek.nasa.gov/mars/) help discover map layers and locations. Mars Trek offers map tiles; a tile service alone is not an offline package and may have missing coverage.
- **Rover location and camera orientation:** NASA/JPL's [Mars 2020 SPICE archive](https://naif.jpl.nasa.gov/pub/naif/pds/pds4/mars2020/mars2020_spice/document/spiceds_v003.html) contains rover/instrument geometry and position kernels. These are the authoritative inputs for reconstructing camera pointing and time-dependent rover positions; the relevant kernels and source image labels must be retained together.
- **Current app content:** the Flutter assets include the landing and Gazetteer reference points, eight USGS map-label anchors, and 531 per-sol PDS PLACES rover localizations within the CTX raster footprint. Rover localizations display as points when they fall inside the current local HiRISE map. USGS geology vectors and CTX crater-wide rasters are prepared on disk but are not yet drawn or used by the app's route solver.
- **Still required:** exact mission-sourced locations/boundaries for informal campaign names such as Kodiak, Artuby Ridge, Máaz, Séítah, and Three Forks samples, plus a coverage-aware Flutter renderer for points, lines, polygons, and unknown map areas. Every feature must keep its geometry type, coordinate frame, source, and location meaning.
- **Limitations:** an interactive web map is not automatically an offline dataset. We must obtain and preserve its underlying layer or authoritative source data; screenshots and manually eyeballed points are not substitutes for georeferenced feature geometry.

### 11. Sunlight, temperature, and radiation

- **Sun and shadows:** use documented ephemerides/geometry kernels (including [NASA/JPL NAIF SPICE](https://naif.jpl.nasa.gov/pub/naif/pds/pds4/mars2020/mars2020_spice/document/spiceds_v003.html)) for the selected Mars date/time, then ray-test against the installed terrain. This is a model estimate, not a direct sensor reading.
- **Thermal surface properties:** the [USGS THEMIS thermal-inertia mosaic](https://astrogeology.usgs.gov/search/map/mars-themis-derived-global-thermal-inertia-mosaic) is derived from nighttime infrared images and is about 100 m/pixel. Thermal inertia is a material-property estimate, not a live temperature forecast. For regional surface temperatures, use labeled THEMIS observations/products; for local rover measurements use MEDA/TIRS. Keep the source time and spatial footprint visible.
- **Radiation:** use time-dependent mission observations and published radiation models with their actual location and time coverage. Curiosity's [RAD data archive](https://pds-geosciences.wustl.edu/missions/msl/) is at Gale Crater, not Jezero; those measurements must not be labeled as direct Jezero measurements.
- **Current status:** these layers are not yet in the app. The MEDA subset is present as raw data only.

## Hackathon and reference websites

These sites are useful, but they do not all provide Jezero measurements that can be copied directly into the offline map. This distinction prevents a web viewer or an example from being mistaken for a source dataset.

| Website | What it is useful for | How MARS-X treats it |
|---|---|---|
| [NASA Mars Trek](https://trek.nasa.gov/mars/) | A Mars exploration portal with layer search, source metadata, visualization, analysis, and downloads. Its [layer service documentation](https://trek.nasa.gov/tiles/apidoc/trekAPI.html?body=mars) describes map tiles and says missing tiles mean no coverage. | Use it to discover and cross-check available Mars layers. For offline use, acquire and package the underlying data or explicitly cache a bounded tile region with source metadata; do not rely on a live web layer. |
| [USGS interactive maps of Mars](https://astrogeology-usgs.hub.arcgis.com/pages/interactive-maps-mars) | A catalog of planetary maps and interactive map services. The relevant Jezero/Nili Planum source identified here is USGS [Scientific Investigations Map 3464](https://pubs.usgs.gov/publication/sim3464), at 1:75,000 publication scale, with a downloadable GIS database. | Use the georeferenced SIM 3464 vector features where its map boundary covers the terrain. A PDF or screenshot alone is not a GIS overlay, and missing source coverage stays unknown. |
| [NASA Curiosity's proposed path up Mount Sharp](https://science.nasa.gov/resource/curiositys-proposed-path-up-mount-sharp/) | A route-planning and presentation example. NASA says the route is for Curiosity climbing Mount Sharp; that is in Gale Crater, not Jezero. | Reference for how a route can be explained to the public. It is not a Jezero route, hazard layer, or rover-traverse source. |
| [NASA Worldview](https://worldview.earthdata.nasa.gov/) | NASA Earthdata's browser for global Earth-observation imagery and layers. | Not a source for Jezero surface imagery or elevation; exclude it from Mars terrain layers. |
| [MOMAR](https://www.momar.si/) | A Marswalk-planning experience that demonstrates how terrain, named stops, rover images, and explanations can be presented together. | Treat it as a design/reference project, not a primary data authority. For every layer MARS-X uses, record the original dataset, provider, location method, and uncertainty independently. |
| [Murray Lab global CTX mosaic](https://murray-lab.caltech.edu/CTX/V01/TilePages/) | Global grayscale orbital imagery for Mars context. | A visual source only, not terrain height. Its full mosaic is too large for the APK, so use regional offline packages with coverage clearly shown. |

NASA's Perseverance raw-image portal and ASU's Mastcam-Z archive are listed in the rover-image section above because they provide actual rover image products. The NASA website's displayed photo or panorama is a discovery view; preserve the original image products and their labels when building an offline panorama.

## How MARS-X keeps the evidence traceable

For every installed layer, the data package should carry a plain-language source note and a machine-readable manifest containing the product name/ID, provider, source URL, source file name, checksum, license/credit, coordinate system, latitude convention, map bounds, source scale, valid time range (when applicable), NoData meaning, processing steps, software/version, resampling method, and output tile resolution. The viewer should display the active layer's source and resolution and identify uncovered areas.

**What the map can honestly claim today:** the Flutter app displays the real, georeferenced HiRISE-derived terrain patch around Perseverance's landing site, with available PDS rover-localization dots from that patch. The app includes the expanded point index and offline PLACES positions. The crater-wide CTX DEM and matching image mosaic, plus USGS SIM 3464 geology and PDS rover localization vectors, are downloaded and processed, but the raster display and geology layers are not yet integrated into the app and do not drive the route solver. Complete whole-crater detail, exact coordinates for every informal mission landmark, rover panoramas, radiation, sunlight, and crater-wide thermal layers are not yet present. Areas missing source data must be shown as unknown, not silently filled in.
