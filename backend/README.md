# MARS-X Backend Service

FastAPI-powered geospatial routing, environmental analysis, and mission planning engine for Jezero Crater, Mars. Built for the NASA Space Apps Challenge 2026.

---

## Capabilities & Architecture

- **Terrain & Elevation**: Loads high-resolution HiRISE DTM (`DTEEC_045994_1985_046060_1985_U01`) from `public/jezero-dem.bin` (480×304 Int16 decimetres block-averaged to 120×76 planning cells at ~35 m resolution).
- **Surface Routing Engine (`app/core.py`)**:
  - Admissible A* and exact Dijkstra shortest-path algorithms on an 8-connected grid.
  - Positive-factor cost model evaluating slope (Horn's method), roughness, and science pull.
  - Four route profiles: **Safety**, **Fastest**, **Science**, **Balanced**.
  - Dynamic programming landmark selector (5–6 waypoints per traverse) and 5-factor risk scoring (0–100).
- **Real Environmental Ingestion (`app/meda_reader.py`)**:
  - Ingests archived NASA Mars 2020 Perseverance MEDA weather data (PDS4 derived TIRS & RHS tables) for Sols 10, 14, 20, and 28.
  - Returns diurnal air temperature, ground brightness temperature, relative humidity, and solar time spans.
- **Geologic Layers & Rover Traverse (`app/geo_layers.py`)**:
  - Serves real USGS SIM 3464 geologic location features and published Jezero landmarks (Octavia E. Butler Landing, Belva Crater, Neretva Vallis).
  - Serves actual Perseverance rover localized positions (531 stops) and ground-truth traverse lines from PDS PLACES tables.
- **Mission Planning & Export**:
  - Creates simulated EVA traverses within strict duration and slope budgets.
  - Generates comprehensive mission summary reports in structured JSON or GitHub-flavored Markdown.

---

## Quickstart

### Prerequisites
- Python 3.10+ (tested on Python 3.11.15)
- `uv` or `pip`

### 1. Setup Virtual Environment & Install Dependencies
```powershell
uv venv
.\.venv\Scripts\activate
uv pip install -r backend/requirements.txt
```
*(Or with standard pip: `python -m venv .venv && .\.venv\Scripts\activate && pip install -r backend/requirements.txt`)*

### 2. Run the Development Server
**Windows (PowerShell):**
```powershell
.\backend\run.ps1
```
**Linux / macOS (Bash):**
```bash
./backend/run.sh
```
The interactive API documentation is available at **http://localhost:8000/docs** (Swagger UI).

### 3. Run Automated Tests
```powershell
.\.venv\Scripts\python -m pytest backend/tests
```
Expect **21 passed** unit and integration tests covering pathfinding, API contracts, and MEDA ingestion.

---

## API Endpoints Reference

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/health` | Service health, loaded HiRISE DTM metadata, and grid dimensions |
| `GET` | `/api/terrain?lon=...&lat=...` | Query elevation, slope, roughness, and passability for a point |
| `GET` | `/api/locations` | Study area (AOI) bounding box and landing reference |
| `GET` | `/api/layers` | Available surface layers (elevation, slope, roughness, pressure) |
| `GET` | `/api/environment?sol=20` | Real Perseverance MEDA weather observations (sols 10, 14, 20, 28) |
| `GET` | `/api/science-targets` | Verified USGS SIM 3464 and Jezero landmark targets |
| `GET` | `/api/rover/traverse` | GeoJSON LineString of actual Perseverance rover path |
| `GET` | `/api/rover/stops?limit=50` | GeoJSON Point features of localized rover stops |
| `GET` | `/api/manifest` | Data provenance and citation records |
| `POST` | `/api/routes/generate` | Plan route between start & goal with constraints & profile |
| `POST` | `/api/routes/compare` | Compare Safety, Fastest, Science, Balanced & A* vs Dijkstra |
| `POST` | `/api/landmarks` | Extract 5–6 navigation landmarks along coordinate path |
| `POST` | `/api/risk` | 5-component risk assessment (0–100) for candidate path |
| `POST` | `/api/missions/create` | Create a planned EVA excursion mission |
| `GET` | `/api/missions/{id}/report` | Generate mission report (supports `?format=markdown`) |
