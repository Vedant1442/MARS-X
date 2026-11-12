# MARS-X data
`python3 data/fetch_datasets.py` (add `--full` to also re-download the 157 MB DTM) queries live USGS STAC / PDS endpoints and writes `catalogue/datasets.json`.

Verified (HTTP-checked, with `verified_on`):
- **D3** HiRISE controlled DTMs over the AOI (6 STAC items; `DTEEC_045994_1985_046060_1985_U01`, ~1 m GSD, CC0, COG GeoTIFF, downloaded to `raw/D3/`, gitignored).
- **D4** CTX controlled DTMs (37 items; large footprints, fallback only).
- **D5** MOLA colorized shaded relief 463 m: a colour hillshade, not a raw elevation DEM; context only.
- **D9** MEDA derived TIRS + RHS tables for sols 10, 14, 20, 28 (archived, not live) in `raw/D9/` with PDS4 labels.

Everything else (D1, D2, D6-D8, D10-D13) is marked `UNVERIFIED` and must not be cited until resolved. The geologic map (D8) was not found automatically.
Note: the AOI bbox in the API is a contract example and still needs confirming against the DTM footprint (77.3834-77.5008E, 18.3055-18.548N).

## 3D terrain
`python3 data/build_dem.py` (needs `data/raw/D3/*.tif` from `fetch_datasets.py --full`) decodes the HiRISE DTM with the stdlib reader in `tiff_read.py`, crops a data-complete 4.3 x 2.7 km window, and writes `public/jezero-dem.bin` (480x304 Int16 decimetres, used by the 3D view) and `src/jezeroGrid.ts` (120x76 planning grid used by the router).
