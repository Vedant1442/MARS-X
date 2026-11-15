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

1. **Frontend (Vite + React + Three.js):**
   ```bash
   npm install
   npx tsc --noEmit
   npm run dev
   ```
2. **Backend (FastAPI + Pytest):**
   ```bash
   cd backend
   python -m pytest -v
   python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

---

## Documentation & Provenance

- [Frontend Landing Page Developer Guide](docs/LANDING_PAGE_DEV_GUIDE.md) — quickstart, styling tokens, and landing page tasks for frontend contributors.
- [Data sources and plain-language explanations](docs/DATA_SOURCES.md) — source, coverage, resolution, current status, limitations, and credit for each layer.
- [Data processing notes](data/README.md) — how the original HiRISE PDS elevation product becomes offline terrain assets.
- [Jezero map architecture](docs/terrain_architecture.md) — current rendering and offline-data design.

## Coverage status

The original HiRISE DTM is used for a high-detail patch around Perseverance's landing site (`120×76` planning grid at `35.99 m/cell`, block-averaged from `480×304`). All 15 mapped Jezero landmarks, USGS SIM 3464 geologic units, and Perseverance PLACES traverse localizations are integrated with explicit scientific provenance badges (`OBSERVED`, `DERIVED`, `MODELED`, `UNKNOWN`, `SIMULATED`).
