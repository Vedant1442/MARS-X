# Jezero terrain data report

## Scope

This report records the local inspection for a crater-scale, offline 3D map in the existing Flutter app. No terrain data was modified during inspection.

## Application and local data

- The repository is a mixed React/Vite web app, FastAPI backend, and Flutter Android app. The supplied checkout has no `.git` metadata, so Git history and status could not be inspected.
- Flutter's current Map tab loads `mobile/assets/terrain/jezero-dem.bin` as a 120 x 76 grid. The bundled view is a `CustomPainter` and supports a perspective tilt, but not orbiting 3D, geographic pan/zoom, or raster imagery.
- The checked-in grid metadata describes a 4.318 x 2.733 km HiRISE-derived window. The source raster is absent locally. Its georeferencing was not carried into the bundled grid.
- A separate React Three.js scene exists in `src/Terrain3D.tsx`. It uses the same small HiRISE elevation window and adds procedural visual elements; it is not a crater-wide, georeferenced CTX terrain map.

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

The local app bundle contains only a small HiRISE-derived window (4.318 x 2.733 km according to its metadata), not a crater-wide DTM. The catalogue item for source DTM `DTEEC_045994_1985_046060_1985_U01` lists a footprint of 77.3834 to 77.5008 degrees east and 18.3055 to 18.548 degrees north, with approximately 1.0166 m source spacing. The source TIFF itself is not present in the local `data/raw/D3` directory, and the current app grid does not retain its geographic transform.

The official USGS Planetary Names Gazetteer gives Jezero's center as 18.41 degrees north, 77.69 degrees east. For a crater-scale 3D surface, use the MOLA MEGDR topography product as the broad elevation layer, then add HiRISE elevation only over its verified footprint if that source is restored. The official PDS MEGDR 128 pixels/degree topography tile `MEGT44N000HB.IMG` covers 0 to 90 degrees east and 0 to 44 degrees north. Its label specifies 11,520 samples by 5,632 lines, signed 16-bit big-endian values in metres, a spherical Mars radius of 3,396 km, and planetocentric coordinates. The full tile is about 129.8 MB; a crater-centered crop can be fetched as a small contiguous row range.

## Tool limits and validation still needed

GDAL, Rasterio, QGIS, and Flutter were not available in this environment. Metadata was inspected without decoding the full CTX raster. Before production processing, use GDAL/QGIS to validate the CRS, crop bounds, nodata behavior, seam geometry, and MOLA-to-CTX alignment. No screenshots or raster-to-raster accuracy claims have been produced yet.

## Data references

- Murray Lab CTX ReadMe and DataSheet are stored alongside the original mosaic.
- [USGS Planetary Names Gazetteer: Jezero](https://planetarynames.wr.usgs.gov/Feature/14300)
- [PDS Geosciences Node: MOLA MEGDR products](https://pds-geosciences.wustl.edu/missions/mgs/megdr.html)
- [MEGDR 128 pixels/degree archive index](https://pds-geosciences.wustl.edu/mgs/urn-nasa-pds-mgs_mola_topography_derived/meg128/)
