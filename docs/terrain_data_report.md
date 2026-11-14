# Jezero terrain data report

## Scope

This report records data inspection and the subsequent processing of the supplied HiRISE PDS image. For a reader-friendly current inventory with status and citations, see [`DATA_SOURCES.md`](DATA_SOURCES.md).

## Application and local data

- The repository is a mixed React/Vite web app, FastAPI backend, and Flutter Android app.
- Flutter's current Map tab loads `mobile/assets/terrain/jezero-dem.bin` as a 120 x 76 grid. The bundled view is a `CustomPainter` and supports a perspective tilt, but not orbiting 3D, geographic pan/zoom, or raster imagery.
- The Flutter grid metadata describes a roughly 4.1 x 2.65 km HiRISE-derived window and now carries its Mars projected transform.
- The original PDS3 source image is present at `data/raw/D3/DTEEC_045994_1985_046060_1985_U01.IMG`. `data/build_dem.py` reads the embedded label and generated the current web and Flutter terrain assets from it.
- A separate React Three.js scene exists in `src/Terrain3D.tsx`. It uses the same small HiRISE elevation window and adds procedural visual elements; it is not yet a crater-wide, georeferenced CTX terrain map.

## Murray Lab CTX mosaic

Inspected files in `F:\Downlod\MurrayLab_GlobalCTXMosaic_V01_E076_N16\MurrayLab_GlobalCTXMosaic_V01_E076_N16`:

| Property | Result |
|---|---|
| Raster | `MurrayLab_CTX_V01_E076_N16_Mosaic.tif`, 2,249,512,492 bytes |
| Dimensions | 47,420 x 47,420 pixels |
| Bands / type | 1 / unsigned 8-bit grayscale |
| NoData | 0 |
| Compression | None |
| Pixel scale | Approximately 5 m per pixel |
| Projected bounds | X 4,504,877.01 to 4,741,975.80 m; Y 948,395.16 to 1,185,493.95 m |
| Geographic quad | 76 to 80 degrees east, 16 to 20 degrees north |
| Projection | Equidistant cylindrical, central longitude 0 degrees, Mars radii 3,396,190 m and 3,376,200 m, metres |

The raster pixel transform and bounds evaluate to 76 to 80 degrees east and 16 to 20 degrees north. The tile includes Jezero and its landing-site area. It is imagery, not elevation data. The ReadMe describes the quad as blended with neighboring quads near its outer 0.25 degrees.

The ReadMe identifies IAU 49912 and describes the latitude as planetocentric. The GeoTIFF's embedded GeoASCII and supplied `.prj` use the name `Mars_2015_Ocentric_Equirectangular_clon_0`. Both are center-based latitude conventions. Retain the full source WKT and confirm compatibility with each comparison dataset during alignment. Do not substitute an Earth CRS.

## Seam map and tie points

- Seam map: polygon shapefile with 2,512 records and 55 DBF fields, including `MOS_QUAD` and `MOS_IMG` for source provenance.
- Tie points: 3,104 CSV records, all marked `Auto`.
- Recorded residuals: minimum 0.0587 m, median 2.3364 m, mean 2.3957 m, maximum 10.2995 m.

These statistics summarize the supplied tie-point records only. They are not a whole-mosaic positional-accuracy estimate. The ReadMe cautions that tie-point locations are guides and that some adjacent image pairs may not have direct registrations.

## Elevation coverage

The local app bundle currently contains only a small HiRISE-derived window (about 4.1 x 2.65 km), not a crater-wide DTM. The PDS label for `DTEEC_045994_1985_046060_1985_U01` reports a map scale of about 1.0097 m/pixel and a footprint of about 77.3834–77.5011 degrees east and 18.3053–18.5484 degrees north. The application resamples that source to an approximately 8.6 m mesh spacing and an approximately 34.6 m planning grid.

The USGS full-crater CTX DEM at 20 m/pixel and matching CTX orthomosaic at 5 m/pixel have since been downloaded and verified. The source files are in `data/raw/JezeroWide/`; the detailed checksums and transforms are in `data/metadata/jezero_wide_manifest.json`. They are not yet integrated into the app. MOLA remains the planned broad-scale elevation source for global context, not the preferred crater-wide source. A 128 pixels/degree MOLA topography tile, `MEGT44N000HB.IMG`, covers 0 to 90 degrees east and 0 to 44 degrees north; it is about 463 m/pixel near the equator and is too coarse for local hazards.

## Tool limits and validation still needed

The original HiRISE image has been processed by the project builder. The CTX crater-wide rasters are downloaded and verified but remain separate from the current app terrain grid. The SIM 3464 geologic map and PDS PLACES rover localization table have been converted into source-linked GeoJSON under `data/processed/jezero/`; the Flutter APK now bundles the point index and per-sol rover localizations. SIM 3464 covers a smaller area than the crater-wide CTX rasters; the export includes its map boundary. Before raster app integration, validate CTX CRS, crop bounds, NoData behavior, seams, image-to-elevation alignment, map coverage, and MOLA relationships with a planetary-aware geospatial tool. No positional-accuracy claims should be made from tie-point residuals alone.

## Data references

- Murray Lab CTX ReadMe and DataSheet are stored alongside the original mosaic.
- [USGS Planetary Names Gazetteer: Jezero](https://planetarynames.wr.usgs.gov/Feature/14300)
- [USGS SIM 3464 geologic map and GIS database](https://pubs.usgs.gov/publication/sim3464)
- [PDS Mars 2020 Rover PLACES archive](https://pds-geosciences.wustl.edu/missions/mars2020/)
- [PDS Geosciences Node: MOLA MEGDR products](https://pds-geosciences.wustl.edu/missions/mgs/megdr.html)
- [MEGDR 128 pixels/degree archive index](https://pds-geosciences.wustl.edu/mgs/urn-nasa-pds-mgs_mola_topography_derived/meg128/)
