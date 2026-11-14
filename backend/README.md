# MARS-X backend (phase 1 scaffold)
- `app/core.py`: stdlib-only A*/Dijkstra, positive-cost model, validator. Run `python3 -m unittest discover -s tests -t .` (passes without dependencies).
- `app/main.py`: FastAPI per API_CONTRACTS.md. Run `pip install -r requirements.txt && uvicorn app.main:app --reload`; tests: `pytest`.
- Terrain is SYNTHETIC (SIMULATED). `/api/environment` returns 503 and `/api/science-targets` is empty until ETL supplies cited, real data.
- Not yet implemented: rasterio/GDAL pipeline, PostGIS, tiles, real layers catalogue, HTML report, contract fixtures.
