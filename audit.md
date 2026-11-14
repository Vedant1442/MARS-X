MARS-X Repository Map & Data Requirements
What is MARS-X?
An offline Mars surface excursion planner for Jezero Crater — built for the NASA Space Apps Challenge 2026. Users explore real NASA terrain, plan routes, compare risk profiles, and follow a traverse landmark-by-landmark without GPS. The project has three delivery surfaces that share one terrain dataset:

Surface	Stack	Status
Web app	React 19 + Three.js + Vite + Tailwind v4	Working prototype
Python API	FastAPI + pure-Python routing engine	Working prototype
Mobile app	Flutter (Android APK, offline-first)	Scaffolded, partial
Architecture Diagram
Flutter Mobile

Python Backend

Web Frontend

Data Pipeline

fetch_datasets.py

build_dem.py + tiff_read.py

block-average 4×4

NASA/USGS STAC APIs

data/raw/ (GeoTIFFs, CSV)

public/jezero-dem.bin
480×304 Int16 decimetres

src/jezeroGrid.ts
120×76 planning grid

engine.ts
A*, risk, landmarks

App.tsx
2D map, planner, stepper

MarsGlobe.tsx
Three.js globe

Terrain3D.tsx
3D terrain view

core.py
Grid, A*, risk, landmarks

main.py
FastAPI REST API

assets/terrain/jezero-dem.bin

terrain_grid.dart

astar.dart

risk.dart + landmark_selector.dart





Directory Structure
MARS-X-main/
├── .github/workflows/
│   └── flutter-apk.yml          # CI: build Flutter APK
├── backend/                     # Python FastAPI server
│   ├── app/
│   │   ├── main.py              # REST API (routes, terrain, missions)
│   │   └── core.py              # Grid loader, A*, Dijkstra, risk, landmarks
│   ├── tests/
│   │   ├── test_api.py
│   │   └── test_core.py
│   ├── requirements.txt
│   └── run.sh
├── data/                        # Build-time data pipeline
│   ├── catalogue/
│   │   ├── datasets.json        # Verified + unverified dataset registry
│   │   └── stac_DTEEC_*.json    # 6 STAC item records for HiRISE DTMs
│   ├── metadata/
│   │   └── hirise_results.json
│   ├── raw/                     # Downloaded NASA data (gitignored)
│   │   ├── D3/                  # HiRISE DTM GeoTIFFs
│   │   └── D9/                  # MEDA environmental CSVs
│   ├── fetch_datasets.py        # Downloads & verifies NASA datasets
│   ├── build_dem.py             # Converts DTM → binary DEM + TS grid
│   ├── tiff_read.py             # Stdlib COG GeoTIFF reader
│   └── README.md
├── mobile/                      # Flutter app (Android APK target)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/                 # providers.dart, theme.dart
│   │   ├── data/                # mission_repo.dart (SQLite)
│   │   ├── domain/
│   │   │   ├── geo/             # mars_geodesy.dart
│   │   │   ├── routing/         # astar.dart
│   │   │   ├── terrain/         # terrain_grid.dart
│   │   │   └── track/           # landmark_selector.dart, risk.dart
│   │   ├── features/
│   │   │   ├── environment/     # environment_screen.dart
│   │   │   ├── map/             # terrain_map_screen.dart
│   │   │   ├── report/          # mission_report_screen.dart
│   │   │   └── stepper/         # follow_screen.dart
│   │   └── shared/widgets/      # data_badge.dart
│   ├── assets/terrain/          # Bundled DEM (in APK)
│   └── pubspec.yaml
├── public/                      # Static assets (web)
│   ├── jezero-dem.bin           # 480×304 Int16 decimetres
│   ├── jezero-dem.json          # Grid metadata
│   ├── mars-color-1k.jpg        # Viking MDIM mosaic (1K)
│   └── mars-color-2k.jpg        # Viking MDIM mosaic (2K)
├── src/                         # React web app
│   ├── App.tsx                  # Full UI: planner, explorer, routes, stepper…
│   ├── engine.ts                # Routing: A*, risk score, landmarks, pressure
│   ├── jezeroGrid.ts            # GENERATED: 120×76 terrain (base64 Int16)
│   ├── MarsGlobe.tsx            # 3D globe (React Three Fiber)
│   ├── Terrain3D.tsx            # Immersive 3D terrain
│   ├── main.tsx                 # Entry
│   └── index.css                # Tailwind v4
├── scripts/
│   └── download_hirise.py
├── PLAN.md                      # Detailed project plan (319 lines)
├── AGENTS.md                    # Agent instructions
├── package.json                 # pnpm / Vite config
├── vite.config.ts
└── Dockerfile

Data Pipeline Flow
HTTP

HTTP

datasets.json
+ raw GeoTIFFs

MEDA CSVs

tiff_read.py
stdlib COG reader

480×304 Int16

120×76 base64

copy

USGS STAC API
astrogeology.usgs.gov

fetch_datasets.py

NMSU PDS
atmos.nmsu.edu

data/raw/D3/

data/raw/D9/

build_dem.py

public/jezero-dem.bin

src/jezeroGrid.ts

Web App

Python API

Flutter APK
assets/terrain/





All 13 Datasets: What's Needed, What's Got, What's Missing
[!IMPORTANT] Only D3 and D9 are verified and downloaded. The other 11 are marked UNVERIFIED — they block key features.

ID	Dataset	Purpose	Status	What You Have	What's Missing
D1	CTX mosaic	Basemap imagery	🔴 UNVERIFIED	Nothing	Need the USGS Murray Lab global CTX mosaic or a Jezero-specific mosaic product for the basemap
D2	HiRISE orthoimage	High-res image overlay	🟡 PARTIAL	Thumbnail & provenance from D3 STAC items	Full orthoimages (available as ortho asset in the D3 STAC items)
D3	HiRISE controlled DTMs	Core terrain (elevation, slope, roughness, routing)	✅ VERIFIED	6 STAC items catalogued, 1 full DTM downloaded (DTEEC_045994…), DEM built	Consider mosaicking multiple DTMs for wider coverage
D4	CTX controlled DTMs	Fallback terrain (lower res)	✅ VERIFIED	5 items catalogued, headers checked	Not downloaded; only needed if HiRISE gaps exist
D5	MOLA shaded relief	Context-only hillshade	🟡 HEAD FAILED	URL known, HTTP 403 on HEAD	Find alternative MOLA elevation DEM (not just hillshade) for coarse fallback
D6	THEMIS thermal products	Temperature layer	🔴 UNVERIFIED	Nothing	THEMIS daytime/nighttime IR mosaic or thermal inertia map over Jezero
D7	CRISM mineral maps	Mineralogy / geology layer	🔴 UNVERIFIED	Nothing	CRISM spectral parameter maps (e.g. olivine, carbonate) for Jezero delta
D8	Jezero geologic map	Geology filter, unit-based science weighting	🔴 UNVERIFIED	Nothing	USGS published geologic map of Jezero (Sun & Stack 2020 or similar) — critical for science routing
D9	MEDA environmental data	Temperature, humidity, pressure readings	✅ VERIFIED	Sols 10, 14, 20, 28 (TIRS + RHS CSVs with PDS4 labels)	Expand to more sols; parse CSVs into observations.json
D10	Perseverance rover traverse	Validation & context	🔴 UNVERIFIED	Nothing	Rover waypoint coordinates (available from Mars2020 mission pages)
D11	Mastcam-Z / Navcam images	Landmark close-ups, rover-eye views	🔴 UNVERIFIED	Nothing	Curated image set near the study area from PDS Imaging Node
D12	SuperCam / PIXL / SHERLOC / RIMFAX	Science target data (spectroscopy, subsurface)	🔴 UNVERIFIED	Nothing	Published observation metadata with coordinates
D13	MSL RAD (Gale)	Radiation context (historical)	🔴 UNVERIFIED	Nothing	Curiosity RAD summary data — clearly labeled "Gale, historical"
Data Needed by Each Feature
Core Terrain (routing works without anything else)
D3 HiRISE DTM ✅ → elevation, slope, roughness, contours, obstacle mask
Basemap Imagery
D1 CTX mosaic 🔴 → regional context basemap draped on 3D terrain
D2 HiRISE orthoimage 🟡 → high-res draped imagery, landmark close-ups
Map Filter Layers
Filter	Data Needed	Status
Contours	D3 (elevation)	✅ Working
Slope	D3 (computed)	✅ Working
Roughness	D3 (computed)	✅ Working
Temperature	D6 (THEMIS spatial) or D9 (point readings)	🔴 Spatial missing, D9 point data ✅
Pressure	Modeled from D3 elevation + D9 MEDA calibration	🟡 Model exists, calibration pending
Minerals/Geology	D7 (CRISM) and/or D8 (geologic map)	🔴 Both missing
Science Routing & Targets
D8 Geologic map 🔴 → unit-based science value weights
D7 CRISM 🔴 → mineral detection locations
D12 SuperCam/PIXL etc. 🔴 → published observation points
Currently: 5 placeholder targets with simulated values (engine.ts lines 45-51)
Landmark Navigation (No-GPS Feature)
D2 HiRISE ortho 🟡 → close-up crops at each landmark
D11 Mastcam-Z / Navcam 🔴 → rover-eye photos near landmarks
Currently: terrain-derived landmarks (crests, lows, slope breaks) work ✅
Environment Screen
D9 MEDA 🟡 → archived temperature, humidity, pressure readings (4 sols ingested, not yet parsed into app format)
D13 RAD 🔴 → radiation context from Gale Crater
Validation & Context
D10 Rover traverse 🔴 → compare computed routes to actual Perseverance path
What the Routing Engine Actually Consumes
The routing engine (engine.ts / core.py) operates on a 120 × 76 grid at ~36 m/cell. Per cell it needs:

Grid Layer	Source	Type	Currently
elev (Float32)	D3 HiRISE DTM	DERIVED	✅ Real data
slope (Float32)	Computed from elev (Horn's method)	DERIVED	✅ Real data
rough (Float32)	Std dev of detrended elevation + noise	DERIVED	✅ Real data + synthetic noise component
unc (Float32)	Modeled from edge proximity + roughness	MODELED	⚠️ Fully modeled (no real confidence data)
nodata (Uint8)	Data gaps in DTM	DERIVED	✅ (no gaps in current window)
science (Float32)	Should come from D7/D8 geologic map	Should be DERIVED	🔴 Currently synthetic noise
Routing weights and algorithm
Three route profiles (A* search on 8-connected grid):

Profile	Slope wt	Roughness wt	Uncertainty wt	Distance wt	Science pull
Safest	50	30	15	5	None
Quickest	15	10	5	70	None
Science	40	25	20	15	Discount near targets
Priority Data Gaps to Close
[!WARNING] These three datasets would have the biggest impact on moving beyond "demo" quality:

D8 — Jezero geologic map 🔴

Unlocks real science-value weighting for routing
Replaces placeholder targets with mapped geologic units
Enables the minerals/geology filter layer
Source: look for USGS SIM-3464 (Sun & Stack, 2020)
D1 — CTX mosaic 🔴

Without it, the 3D terrain has no real imagery draped on it
The 2D map shows derived layers but no actual surface imagery
Source: Murray Lab global CTX mosaic or USGS regional product
D6 — THEMIS thermal data 🔴

Without it, the temperature filter is empty (D9 gives point readings only, not spatial)
Source: ASU THEMIS daytime IR or derived thermal inertia for Jezero
Current State Summary
Aspect	Status
Real terrain loaded?	✅ Yes — USGS HiRISE DTM (DTEEC_045994…), 4.3 × 2.7 km window
Routing works?	✅ Yes — A* on real elevation/slope, three profiles
Risk scoring?	✅ Yes — 5-part breakdown, 0-100 scale
Landmark navigation?	✅ Yes — terrain-derived, 5-6 per route
Science targets real?	🔴 No — 5 placeholders with simulated values
Geology/mineral layer?	🔴 Missing — needs D7 + D8
Temperature layer?	🔴 Spatial missing — only D9 point readings
Basemap imagery?	🔴 Missing — no CTX mosaic or HiRISE ortho
Environment readings?	🟡 Downloaded (4 sols) but not parsed into app
Mobile app?	🟡 Scaffolded — domain logic present, UI screens partial
Flyover video?	🟡 3D terrain view exists, camera-path animation not implemented
