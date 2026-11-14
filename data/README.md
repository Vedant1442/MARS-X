# MARS-X data

See [`docs/DATA_SOURCES.md`](../docs/DATA_SOURCES.md) for the plain-language source register required for the hackathon. It distinguishes data already processed from data identified but still waiting to be downloaded, and records coverage, resolution, limits, and citations.

`python3 data/fetch_datasets.py` queries live USGS STAC / PDS endpoints and writes `catalogue/datasets.json`.

Catalogue records that were HTTP-checked, with verification dates:
- **D3** HiRISE controlled DTM catalogue (6 USGS STAC items). The original PDS3 `.IMG` for `DTEEC_045994_1985_046060_1985_U01` is now in `raw/D3/` (gitignored) and is the source used by the terrain builder.
- **D4** CTX controlled DTMs (37 items; large footprints, fallback only).
- **D9** MEDA derived TIRS + RHS tables for sols 10, 14, 20, 28 (archived, not live) in `raw/D9/` with PDS4 labels.

**D5 caveat:** the catalogue entry for the 463 m colorized MOLA shaded-relief product returned HTTP 403 during the last check. It is a rendered hillshade, not raw elevation, and is not the MOLA DEM planned for terrain height.

The full-crater 20 m CTX DEM is now downloaded and verified; its matching 5 m orthomosaic is currently downloading and has not yet been verified. Neither is integrated into the app yet. See the [source register](../docs/DATA_SOURCES.md) and [machine-readable manifest](metadata/jezero_wide_manifest.json) for exact product details, checksums, projection, and status. The local HiRISE DTM footprint is 77.3834-77.5011E, 18.3053-18.5484N.

## 3D terrain
`python3 data/build_dem.py` reads the original PDS3 HiRISE product `data/raw/D3/DTEEC_045994_1985_046060_1985_U01.IMG` directly, using its embedded label and little-endian 32-bit elevations. It builds a deterministic ~4.1 x 2.7 km ground patch centered on the published Perseverance landing location. It writes `public/jezero-dem.bin` (480x304 Int16 decimetres, used by the 3D view), `src/jezeroGrid.ts` (120x76 web planning grid), and matching Flutter terrain binary/metadata under `mobile/assets/terrain/`. The output preserves NoData and includes Mars projected grid-cell centers.
