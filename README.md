# MARS-X · Jezero Crater Surface Planning & Astronaut Survival Engine

An offline-capable Mars exploration and autonomous EVA surface-navigation system for Jezero Crater (NASA Space Apps Challenge 2026). Combines NASA MRO HiRISE stereo terrain (`DTEEC_045994_1985_046060_1985_U01`), 15 georeferenced Jezero Crater landmarks with close-up imagery, USGS SIM 3464 geologic units, Perseverance MEDA atmospheric observations, and 2-astronaut xEMU life-support consumables / Point-of-No-Return (PNR) physics.

---

## Reproducible Demo Route Pairs (For Video & Testing)

Use these two verified landmark pairs on the HiRISE planning grid (120 × 76 cells) to demonstrate clear differentiation between **Safest**, **Quickest**, and **Scientific** route profiles:

### Demo Pair 1: Western Delta to Belva Crater (Delta Scarp Traversal)
- **Start Waypoint**: `(22, 28)` — *Western Delta Fan*
- **Destination Waypoint**: `(84, 16)` — *Belva Crater Rim*
- **What to Observe**:
  - **Quickest** (Atmos Teal): Traverses the direct route climbing straight over the steep delta scarp (Distance: ~2.41 km, Mean Slope: ~7.5°, Max Slope: 22.4°, higher simulated risk).
  - **Safest** (Sage Green): Skirts southward around the scarp base through gentle lacustrine benches (Distance: ~2.59 km, Mean Slope: ~3.2°, Max Slope drops to 8.25°, low simulated risk).
  - **Scientific** (Mars Red): Detours to sample the *Enchanted Lake* mudstone outcrop while strictly respecting the $\le 1.5\times$ distance cap.

### Demo Pair 2: Neretva Vallis to Three Forks Depot (Channel Inflow Traversal)
- **Start Waypoint**: `(12, 38)` — *Neretva Vallis Inflow Canyon*
- **Destination Waypoint**: `(52, 34)` — *Three Forks Sample Depot*
- **What to Observe**:
  - **Quickest**: Direct line across uneven boulder-strewn channel deposit margins (Distance: ~1.50 km, Max Slope: 8.4°).
  - **Safest**: Navigates along the smoothed paleochannel bed (Distance: ~1.53 km, Mean Slope: 2.63°, Max Slope drops to 4.67°).
  - **Scientific**: Routes directly through the first extraterrestrial sample depot cache.

---

## Quick Download & Teammate Integration Locations

All rectified backend files, the standalone Landing Page component, and the downloadable integration kit are available both **in the repository** and **via direct HTTP download** from the deployed web app (`#download` section on the Landing Page):

| Deliverable | Repository Path | Live Web App Download Path | Description |
| :--- | :--- | :--- | :--- |
| **Standalone Landing Page (React/TS)** | [`src/pages/LandingPage.tsx`](src/pages/LandingPage.tsx) | [`/downloads/LandingPage.tsx`](public/downloads/LandingPage.tsx) | Drop-in React component wired to `src/api.ts`, `src/processedDataLayers.ts` (15 mapped Jezero landmarks), live MEDA Sol telemetry, interactive Route Trade-Off Comparator, and Download Station. |
| **Full Backend + UI Integration Kit (ZIP)** | [`public/downloads/mars-x-backend-integration-kit.zip`](public/downloads/mars-x-backend-integration-kit.zip) | `/downloads/mars-x-backend-integration-kit.zip` | Single ZIP archive bundling the rectified `backend/app/*` (`core.py`, `main.py`, `geo_layers.py`, `meda_reader.py`), `backend/tests/test_api.py`, `src/api.ts`, and `src/pages/LandingPage.tsx`. |
| **Rectified FastAPI Routing & EVA Core** | [`backend/app/core.py`](backend/app/core.py) | Included in Integration ZIP | Unified Python routing core with all **15 mapped Jezero landmarks**, **Science route detour cap (`<= 1.5x` fastest)**, **2-astronaut buddy-system EVA consumables** (`oxygen_kg`, `battery_kwh`, `cooling_water_kg`, `pnr_dist_m`), and **Route Trade-Off Analysis** (`gained` vs. `compromised`). |
| **FastAPI Endpoints & Geo Layers** | [`backend/app/main.py`](backend/app/main.py), [`backend/app/geo_layers.py`](backend/app/geo_layers.py) | Included in Integration ZIP | Serves `/api/health`, `/api/environment`, `/api/science-targets`, `/api/landmarks/mapped`, `/api/landmarks-register`, `/api/routes/generate`, `/api/routes/compare`, `/api/risk`, `/api/missions/*` (23/23 `pytest` tests passing). |
| **15 Mapped Jezero Landmark Close-Up Images** | [`public/landmarks/`](public/landmarks/) & [`mobile/assets/landmarks/`](mobile/assets/landmarks/) | `/landmarks/<id>.jpg` | Optimized close-up imagery for all 15 mapped Jezero Crater landmarks (`octavia-butler-landing.jpg`, `three-forks.jpg`, `hawksbill-gap.jpg`, `enchanted-lake.jpg`, `cape-nukshak.jpg`, `belva-crater.jpg`, `bunsen-peak.jpg`, `jurabi-point.jpg`, `gnaraloo-bay.jpg`, `western-delta.jpg`, `neretva-vallis.jpg`, `jezero-crater-rim.jpg`, `sava-vallis.jpg`, `pliva-vallis.jpg`, `ancient-lake-basin.jpg`). |
| **Android Release APK (`arm64-v8a`)** | [GitHub Releases (`latest`)](https://github.com/Vedant1442/MARS-X/releases/download/latest/app-arm64-v8a-release.apk) | Direct button in navbar & `#download` | Standalone offline-capable Flutter Android APK (`app-arm64-v8a-release.apk`). |

---

## How to Integrate `LandingPage.tsx` on `main`

`src/App.tsx` is already wired to render `src/pages/LandingPage.tsx` on the root route (`/`):

```tsx
import LandingPage from "./pages/LandingPage";

// Inside Landing() in src/App.tsx:
<LandingPage
  renderGlobe={(f, st) => <HeroGlobe fly={f ?? fly} stage={st ?? stage} />}
  onNavigate={go}
  onExplore={explore}
/>
```

## Running & Verifying Locally

1. **Mobile Android App (Flutter 3.4+ / 3.50+):**
   ```bash
   cd mobile
   flutter create --platforms=android --org com.marsx.pro --project-name mars_x .
   flutter pub get
   flutter test test/mars_x_test.dart
   flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64
   ```
2. **Frontend (Vite + React + Three.js):**
   ```bash
   npm install
   npx tsc --noEmit
   npm run dev
   ```
3. **Backend (FastAPI + Pytest):**
   ```bash
   cd backend
   python -m pytest -v
   python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```
4. **Offline Data Pipeline Scripts (Python 3):**
   ```bash
   python3 tools/preprocess_meda.py       # Recompresses PDS4 MEDA tables to 20 KB
   python3 tools/validate_traverse.py     # Benchmarks against Perseverance traverse
   python3 tools/sensitivity_analysis.py  # Generates +/-20% parameter sensitivity report
   ```

---

## Scientific Data Provenance & Badging System

Every numerical figure, map layer, and hazard notification in MARS-X displays one of four scientific provenance labels:

- `[OBSERVED]`: Direct calibrated in-situ or orbital sensor measurements (e.g. MRO HiRISE optical orthoimages, Perseverance MEDA calibrated temperature tables, PDS PLACES rover localizations).
- `[DERIVED]`: Deterministic spatial and topographic calculations computed directly from verified orbital models without predictive heuristics (e.g. slope, aspect, roughness, 9 m corridor elevation cross-sections from HiRISE stereo DTM).
- `[MODELED]`: Physics-based extrapolations derived from peer-reviewed mission literature (e.g. MSL RAD surface radiation dose rate of $0.445\ \mu\text{Sv/min}$ [Hassler et al., 2014, *Science*], barometric pressure elevation lapse $P(z) = P_0 e^{-(z-z_0)/H}$, Tobler walking speed curve).
- `[SIMULATED]`: Heuristic planning algorithms for operational exploration (e.g. relative risk scoring 0–100, xEMU buddy-system life support burn rates).

---

## Known Scientific & Operational Limitations

1. **Orbital DTM Resolution vs. Sub-Meter Obstacles**: HiRISE stereo DTMs provide ground sample distances down to 1 m/pixel (downsampled to 9 m/cell in our high-resolution buffer and 36 m/cell in the route grid). Discrete rocks, meter-scale boulders, and narrow cracks below 1 m cannot be resolved from orbit; astronaut visual vigilance and onboard rover sensors remain necessary.
2. **Coverage Extent**: The high-resolution HiRISE stereo DTM covers a 4.1 km × 2.6 km corridor centered over the landing site and Western Delta. Whole-crater route exploration uses the 100 m USGS CTX elevation mosaic.
3. **THEMIS Thermal Inertia Exclusion**: Thermal inertia GeoTIFFs in the repository are Git LFS pointer stubs without cached binary payloads in this environment. In compliance with Challenge Rule 1 (strict zero data fabrication), thermal inertia was excluded from active map layers until the user provides the raw GeoTIFF payload.
4. **Radiation Weather**: The modeled radiation dose ($26.7\ \mu\text{Sv/hr}$) assumes a quiet-Sun Galactic Cosmic Ray (GCR) background measured by MSL RAD; it does not model sudden Solar Particle Events (SPEs), which require immediate shelter in a regolith-shielded habitat.

---

## Pitch Deck Slide-by-Slide Guidance (NASA Space Apps 2026)

If presenting MARS-X to the challenge judges, highlight the following core differentiators across your presentation slides:

| Slide # | Slide Title | What to Show & Say Differently |
| :--- | :--- | :--- |
| **Slide 1** | **Title & Mission Challenge** | State that MARS-X is a **100% offline-first Android excursion planner** designed for human astronauts on Mars. Highlight that it operates with zero network connectivity and zero internet permissions in the Android manifest. |
| **Slide 2** | **Multi-Mission NASA Data Integration** | Show that MARS-X integrates data across **multiple missions and instruments**: MRO HiRISE stereo DTM (topography/optics), Mars 2020 Perseverance MEDA (hourly temperature and barometric pressure), Mars 2020 PLACES (rover traverse), and MSL RAD (surface radiation baseline). Emphasize the 4-tier labeling system (`OBSERVED`, `DERIVED`, `MODELED`, `SIMULATED`). |
| **Slide 3** | **Differentiated Routing Engine** | Present the three distinct route profiles (**Safest**, **Quickest**, **Scientific**) using **Demo Pair 1 (Western Delta to Belva Crater)**: show how Quickest climbs the 22.4° scarp, while Safest skirts around it through gentle 3.2° terrain, dropping maximum slope to 8.25°. |
| **Slide 4** | **Hyperlocal Hazard Corridor (P2)** | Showcase the **9 m/pixel corridor elevation cross-section**: explain how the app keeps an efficient 36 m grid for crater-wide planning, but instantly unpacks a full-resolution 9 m profile along the chosen path to flag local scarps > 15° with **zero additional APK weight**. |
| **Slide 5** | **Validation Against Perseverance (P3)** | Display the empirical benchmark against Perseverance's actual traverse: explain why the rover took a longer path (robotic coring detours into South Séítah) versus the human astronaut path, citing the 90 authentic NASA PDS coordinate positions. |
| **Slide 6** | **Scientific Campaign Objectives (P4)** | Demonstrate the 3 Jezero science campaigns (*Delta Lacustrine*, *Crater Basement*, *Fluvial Hydrology*) and the **Explainable Science Score** showing exact target contributions (+pts, distances, geological significance). |
| **Slide 7** | **Grounded Safety Model & Consumables (P5)** | Present the 2-astronaut buddy-system EVA consumables ($O_2$, battery, water, PNR margin) and cite the $\pm 20\%$ sensitivity analysis in `ASSUMPTIONS.md` proving the mathematical stability of the Safest route. |
| **Slide 8** | **Offline Performance & Delivery (P6)** | End with the verified technical footprint: **19.5 MB standalone release APK**, running completely in flight mode, tested with pure-Dart routing, and verified with GitHub Actions CI. |

---

## Documentation & Provenance

- [Frontend Landing Page Developer Guide](docs/LANDING_PAGE_DEV_GUIDE.md) — quickstart, styling tokens, and landing page tasks for frontend contributors.
- [Data sources and plain-language explanations](docs/DATA_SOURCES.md) — source, coverage, resolution, current status, limitations, and credit for each layer.
- [Route Validation Report against NASA Perseverance](docs/VALIDATION.md) — empirical comparison between MARS-X routes and the rover traverse.
- [Safety Model Assumptions & Sensitivity Analysis](docs/ASSUMPTIONS.md) — parameter inventory, citations, and +/-20% sensitivity testing.
- [Data processing notes](data/README.md) — how the original HiRISE PDS elevation product becomes offline terrain assets.
- [Jezero map architecture](docs/terrain_architecture.md) — current rendering and offline-data design.

## Coverage status

The original HiRISE DTM is used for a high-detail patch around Perseverance's landing site (`120×76` planning grid at `35.99 m/cell`, block-averaged from `480×304`). All 15 mapped Jezero landmarks, USGS SIM 3464 geologic units, and Perseverance PLACES traverse localizations are integrated with explicit scientific provenance badges (`OBSERVED`, `DERIVED`, `MODELED`, `UNKNOWN`, `SIMULATED`).
