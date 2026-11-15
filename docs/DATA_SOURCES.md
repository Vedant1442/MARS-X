# MARS-X data sources, explained simply

This page explains what the project’s data is, where it came from, what the app can use now, and what is still only a file on disk. The processing steps are described in more detail in [DATA_PIPELINE.md](DATA_PIPELINE.md).

## The short version

The app uses two terrain scales:

- **Crater-wide map (Flutter):** a USGS elevation model with 20 m source pixels is reduced to a 100 m route grid. A grayscale CTX image is lined up with that grid as a background. This works offline in the Flutter app.
- **Landing-area detail (web, backend, and Flutter assets):** a smaller, higher-resolution HiRISE elevation patch around Perseverance’s landing site. It does not cover the whole crater.

Geology, rover positions, and named landmarks are separate map layers. Some are already displayed in Flutter; the larger GIS collections and the 29-name research register are not all connected to the app. Fourteen names in the register still have no geometry. Blank locations are deliberately left blank.

## A few words in everyday language

| Term | Meaning |
|---|---|
| **DEM / DTM** | A grid of ground heights. It gives the terrain its shape. |
| **Orthomosaic** | Many overhead images joined and map-aligned. It shows appearance, not height. |
| **Raster** | A grid of pixels, such as an elevation or image file. |
| **Vector** | Points, lines, or filled shapes, such as a rover position or a crater outline. |
| **Resolution** | How much ground one pixel or grid cell represents. Smaller numbers show finer detail. |
| **NoData** | A cell where no trustworthy value is available. It must stay unknown; it is not zero elevation. |
| **Raw / processed / app asset** | Original source / converted project data / a compact copy prepared for the app. |

## Mars coordinates are different from Earth coordinates

MARS-X uses Mars east longitude and planetocentric latitude, usually measured on a Mars sphere with a radius of 3,396,190 m. Coordinates are ordered **longitude, latitude**. They are not Earth GPS coordinates (WGS 84), even when a file uses the GeoJSON format. The crater-wide project bounds are approximately **76.99744°E to 78.58256°E and 17.58052°N to 19.29019°N**.

Different source products use different Mars map projections. The coordinate metadata and transforms must be used when combining them; two layers looking similar or having the same pixel size does not prove they line up.

## Data the app uses now

| Data | What it is and where it is | Current use |
|---|---|---|
| **HiRISE landing-area heights** | Original source: `data/raw/D3/DTEEC_045994_1985_046060_1985_U01.IMG`. The build script uses its embedded PDS label. The source is roughly 1 m per pixel and covers only the landing-area region. | Web 3D terrain and local web/backend planning use generated files; Flutter also keeps the local terrain files. These are not crater-wide. See [the pipeline guide](DATA_PIPELINE.md#1-local-hirise-terrain-around-the-landing-site). |
| **CTX crater-wide heights** | `data/raw/JezeroWide/M20_JezeroCrater_CTXDEM_20m.tif`, a USGS stereo-derived elevation mosaic at 20 m per pixel. | Flutter uses its compact 100 m grid from `mobile/assets/terrain/jezero-ctx-100m-elevation.bin` and companion JSON. The route grid covers the rectangular source raster, including land outside the crater rim. |
| **CTX image mosaic** | `data/raw/JezeroWide/M20_JezeroCrater_CTXortho_mosaic_5m.tif`, a grayscale image at about 5 m per pixel. | Flutter uses a smaller aligned overview at `mobile/assets/terrain/jezero-ctx-overview.png`. Areas not covered by the image remain transparent. The app does not package all 5 m source pixels. |
| **Crater-rim lines** | Partial rim-crest line segments from the USGS geology map. | Flutter displays `mobile/assets/terrain/jezero-ctx-crater-rim.geojson`. These segments are not a complete crater outline. |
| **Published reference points and map labels** | `data/processed/jezero/jezero_landmarks.geojson` and app copy `mobile/assets/terrain/jezero-landmarks.geojson`. Contains the landing point, crater reference point, and USGS map-label anchors. | Flutter loads the points. Label anchors place text on the map; they are not surveyed centers or boundaries of the named features. |
| **Perseverance positions** | PDS PLACES source table: `data/raw/JezeroLandmarks/best_interp.csv`. Processed per-sol points: `data/processed/jezero/perseverance_rover_stops.geojson`; Flutter copy: `mobile/assets/terrain/perseverance-rover-stops.geojson`. | Flutter displays archived positions on the crater-wide map. They are localized rover positions, not a camera pose or complete wheel-track record. |

The active Flutter map and route grid load the CTX assets. The web terrain and backend still use the local HiRISE patch. See [the detailed repository handover](DATA_HANDOVER.md) for code-level integration details and caveats.

## Data prepared in the repository, but not all shown in the app

### USGS geology map

The source is the [USGS Geologic Map of Jezero Crater and Nili Planum, SIM 3464](https://pubs.usgs.gov/publication/sim3464). Its GIS database and coordinate information are under `data/raw/JezeroLandmarks/`. Converted map layers are under `data/processed/jezero/`, including:

- `sim3464_geologic_units.geojson` — mapped geology polygons.
- `sim3464_geologic_contacts.geojson` — boundaries between mapped units.
- `sim3464_linear_landforms.geojson` — mapped lines, including channels and some rim/delta features.
- `sim3464_surface_features.geojson` and `sim3464_location_features.geojson` — mapped surface shapes and small crater points.
- `sim3464_landing_ellipse.geojson` — landing ellipse.
- `sim3464_map_coverage.geojson` — where this USGS map actually has coverage.
- `sim3464_named_label_anchors.geojson` — text-label positions only.

These are converted to Mars longitude/latitude and clipped to the crater-wide CTX raster bounds. The USGS map itself covers only part of those bounds. Outside its coverage, the correct meaning is “this map has no data here,” not “there is no geology here.” The processed collections are available for GIS previews or backend work, but the full geology collections are not active Flutter layers.

### Requested landmark register

The 29-name research register is exported in three formats:

- `data/processed/jezero/landmarks.json`
- `data/processed/jezero/landmarks.geojson`
- `data/processed/jezero/landmarks.csv`

They contain a mixture of points, lines, polygons, and null geometries. Fifteen records currently have geometry and fourteen remain null. A point may represent a rover visit, a sample localization, or an observation viewpoint; its properties explain which. In particular, Three Forks has two panorama viewpoints in the register, **not** the individual sample-tube positions. Read [landmark_register.md](landmark_register.md) before using this dataset.

The exported landmark register is **not currently an app layer**. Never treat a missing geometry as zero or make up a position to fill it.

### FU Berlin map layers

Snapshots from the [FU Berlin Jezero map](https://maps.planet.fu-berlin.de/jezero/) are stored in `data/raw/JezeroLandmarks/FUBerlin/`. They include map annotations, panorama points, a possible lake-level polygon, and channel lines. The raw coordinates are projected Mars metres, not longitude/latitude; the register builder converts selected shapes to Mars degrees. The channel-line source has no names in its attributes, so the links to Neretva, Sava, and Pliva are documented spatial matches. The ancient-lake shape is one possible reconstruction, not a definitive lake boundary. No standalone FU Berlin fetch script is currently provided.

### Other prepared raster files

| Files | Plain-language meaning | Current status |
|---|---|---|
| `data/MARSX_D6_THEMIS_CLEANED/` | THEMIS-derived thermal inertia: an estimate of how quickly the surface heats and cools. It is **not** a live temperature map. | Files are present, not an active app layer. The full source-to-output recipe is not included with the project scripts. |
| `data/MARSX_D8_GEOLOGY_CLEANED/` | 100 m categorical geology rasters, lookups, GeoPackages, and longitude/latitude exports based on USGS map data. The raster values are unit IDs, not science scores. | Files are present, not active app layers. Check each file’s CRS and NoData metadata before using it. The full cleaning recipe is not included with the project scripts. |

## Data that is available only in part or still planned

- **HiRISE coverage:** detailed local terrain is available near the landing area; it does not cover all of Jezero.
- **CTX detail:** the original 20 m elevation and 5 m image are present. The Flutter app uses compact 100 m/overview derivatives; full-resolution, windowed viewing is not implemented.
- **Landmarks:** fourteen of the requested names still have no source-backed geometry. Three Forks tube positions are also missing. See [remaining work](REMAINING_WORK.md).
- **Terrain hazards:** no complete, validated named hazard dataset is supplied. A 100 m route grid cannot resolve small rocks or local obstacles.
- **MOLA:** there is a helper script, `scripts/fetch_mola_jezero_crop.py`, but no MOLA crop is present in this checkout.
- **MEDA weather:** a small set of archived sensor tables exists under `data/raw/D9/`. These are measurements at the rover for selected early sols, not crater-wide weather. They are not displayed as a map layer.
- **Panoramas:** rover imagery is available from NASA and mission archives, but this project does not yet provide a fully georeferenced offline panorama viewer.

## Where to look next

- [DATA_PIPELINE.md](DATA_PIPELINE.md) — how source files become processed layers and app assets, with reproduction commands.
- [DATA_HANDOVER.md](DATA_HANDOVER.md) — formats, layer use, integration status, and known technical caveats.
- [landmark_register.md](landmark_register.md) — what each named feature means and how its location was verified.
- [machine-readable dataset manifest](../data/metadata/data_handover_manifest.json) — paths, sources, coordinate systems, and integration notes.
- [validation report](../data/metadata/data_handover_validation.json) — the last recorded file and geometry checks. Its checks do not prove that all raster pixels align correctly.
