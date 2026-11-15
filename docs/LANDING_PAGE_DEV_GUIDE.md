# MARS-X · Frontend Landing Page Developer Guide

Welcome to the **MARS-X** frontend team! This guide contains everything you need to start developing and styling the **Landing Page** for our NASA Space Apps Challenge 2026 project.

---

## 1. Project Overview & Live Links

MARS-X is an interplanetary surface planning tool for Jezero Crater on Mars, fusing real NASA HiRISE terrain, Perseverance rover traverses, and MEDA atmospheric weather.

- **Live Web App**: [https://web-production-b9f621c2.up.railway.app](https://web-production-b9f621c2.up.railway.app)
- **Live Backend API**: [https://api-production-14018b03.up.railway.app](https://api-production-14018b03.up.railway.app)
- **GitHub Repository**: [https://github.com/Vedant1442/MARS-X](https://github.com/Vedant1442/MARS-X)
- **Android APK Downloads**: [GitHub Releases (latest)](https://github.com/Vedant1442/MARS-X/releases/tag/latest)

---

## 2. Quickstart & Local Environment Setup

### Prerequisites
- **Node.js** (v20+ or v22 LTS recommended)
- **pnpm** (Install via `npm install -g pnpm` or `corepack enable`)

### Setup Instructions
```bash
# 1. Clone the repository
git clone https://github.com/Vedant1442/MARS-X.git
cd MARS-X

# 2. Switch to your feature branch
git checkout -b frontend-landing

# 3. Install dependencies
pnpm install

# 4. Start the Vite development server
pnpm dev
```
Open **`http://localhost:8443`** in your browser. Hot Module Replacement (HMR) is active, so your changes will update instantly.

---

## 3. Where the Landing Page Lives in Code

The web app uses a lightweight hash/path router implemented in `src/App.tsx`.

### Primary File: `src/App.tsx`
- **Routing Switch** (~Line 2530): Look for `path === "/"` — this renders the `<Landing />` component.
- **`<Landing />` Component** (~Line 544 to 640): This is the main landing page component!
- **`<HeroGlobe />` Component** (~Line 495): Wraps the interactive 3D Mars globe (`src/MarsGlobe.tsx`).
- **Global Navigation Bar (`<Shell />`)** (~Line 425): Contains the top header, logo, navigation links, and "DOWNLOAD APK" button.
- **Footer (`<Footer />`)** (~Line 473): Disclaimer, NASA data attribution, copyright.

```
src/
├── App.tsx          <-- Landing page lives here (function Landing())
├── MarsGlobe.tsx    <-- 3D interactive Three.js Mars sphere
├── api.ts           <-- Pre-configured live Railway backend API client
├── engine.ts        <-- Route computation, EVA model, Jezero science targets
├── index.css        <-- Tailwind CSS v4 styling & theme tokens
└── Terrain3D.tsx    <-- First-person 3D terrain viewer
```

> **Tip for organizing code**: If `src/App.tsx` feels too large, you are encouraged to extract `Landing()` into its own clean file: `src/pages/LandingPage.tsx` and import it into `App.tsx`!

---

## 4. Design System & Theme Tokens

The project uses **Tailwind CSS v4** with a custom sci-fi / mission-control theme defined in `src/index.css`.

### Color Palette
- **Backgrounds**:
  - `bg-ink`: Deep space black (`#070A0F`)
  - `bg-panel` / `bg-paper`: Mission control card slate (`#0D131C` / `#131B26`)
- **Mars Accent Colors**:
  - `text-mars-deep`: Martian rust orange (`#C85D3B` / `#D46238`)
  - `bg-mars`: Primary accent (`#B85232`)
  - `text-mars-bright`: Bright orange highlight (`#F0714B`)
- **Status & Badges**:
  - `emerald-400` / `bg-emerald-500/10`: Online / Verified status
  - `amber-400`: Warnings / Simulated mode
- **Borders & Dividers**:
  - `border-line`: Subtle slate border (`#1E293B`)
  - `border-line-strong`: Card borders (`#334155`)

### Typography
- **Monospace** (`font-mono`): Used for coordinates, numbers, data tags, metrics, and labels.
- **Serif** (`font-serif`): Used for elegant sub-headings (*"Interplanetary Surface Planning"*).
- **Sans-serif**: Clean system font for body copy and descriptions.

### Ready-to-Use UI Primitives in `src/App.tsx`
- `<Btn primary onClick={...}>Label</Btn>`: Styled mission button
- `<Btn onClick={...}>Secondary</Btn>`: Subtle outline button
- `<Eyebrow>CATEGORY</Eyebrow>`: Small uppercase tracking label
- `<Tag l="OBSERVED" />`: Scientific provenance badge (`OBSERVED`, `DERIVED`, `MODELED`, `UNKNOWN`, `SIMULATED`)
- `<Panel title="TITLE" tag="DERIVED">children</Panel>`: Card container

---

## 5. Connecting Live Mars Telemetry (`src/api.ts`)

We already deployed the live FastAPI backend on Railway. You can easily fetch real Mars data on the landing page!

```typescript
import { getBackendHealth, getEnvironmentData } from "./api";

// 1. Check if backend is live
const health = await getBackendHealth();
console.log(health.status); // "ok"

// 2. Fetch real Mars weather (Sol 20 MEDA readings)
const weather = await getEnvironmentData(20);
console.log(weather.air_temperature.mean); // -33.0 °C
console.log(weather.ground_brightness_temperature.mean); // -29.8 °C
```

---

## 6. High-Impact Tasks for the Landing Page

Here are impactful features and improvements you can build:

### 1. Modern Hero Section Upgrade
- Add an animated Mars mission status ticker at the very top (e.g. `PERSEVERANCE: SOL 1320 · JEZERO CRATER · AIR TEMP: -33°C · STATUS: NOMINAL`).
- Highlight call-to-actions:
  - **"LAUNCH MISSION PLANNER"** (`go("/planner")`)
  - **"DOWNLOAD ANDROID APK"** (links directly to latest GitHub release)
  - **"EXPLORE 3D TERRAIN"** (`go("/immersive")`)

### 2. Feature Showcase Cards
Create a visual 3-column feature grid explaining what makes MARS-X unique:
1. **Real NASA HiRISE Terrain**: 1-meter resolution DTM elevation grid of Jezero Crater.
2. **EVA Life Support Simulation**: Calculates real metabolic O2 consumption, battery drain, and emergency abort routes.
3. **Offline Mobile APK**: Android app with local SQLite storage for zero-connectivity Mars exploration.

### 3. Interactive Route Teaser or Live Globe Controls
- Allow users to click preset landmark buttons under the Hero Globe to rotate the globe to key sites:
  - `Octavia E. Butler Landing` (Jezero Crater)
  - `Olympus Mons`
  - `Valles Marineris`
  - `Gale Crater` (Curiosity)

### 4. NASA Space Apps Challenge 2026 Badge
- Add official challenge metadata: *"NASA Space Apps Challenge 2026 · Challenge: Interplanetary Survival Guide: Martian Map"*.
- Team member credits and links to GitHub / project presentation.

---

## 7. Build & Deploy Workflow

Whenever you are ready to test your changes:

```bash
# 1. Verify build and type checking
pnpm build

# 2. Commit your changes
git add .
git commit -m "feat(landing): modernize hero section and add feature cards"

# 3. Push to your branch and create a PR
git push origin frontend-landing
```

When your Pull Request is merged into **`main`**, Railway automatically detects the commit, builds `Dockerfile.web`, and updates the live site at **[https://web-production-b9f621c2.up.railway.app](https://web-production-b9f621c2.up.railway.app)** in ~60 seconds!

---
*Questions or need backend API extensions? Contact Vedant or check `backend/README.md`.*
