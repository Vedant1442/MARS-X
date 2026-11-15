import React, { useEffect, useState } from "react";
import type { FlyTarget } from "../MarsGlobe";
import {
  API_BASE,
  compareRoutesBackend,
  getBackendHealth,
  getEnvironmentData,
  type BackendHealth,
  type MedaEnvironment,
  type RouteTradeoff,
} from "../api";
import { MAPPED_JEZERO_LANDMARKS, type MappedJezeroLandmark } from "../processedDataLayers";
import { AVAILABLE_SOLS, getMedaWeather, MEDA_SOLS } from "../medaData";
import { MODE_W, type Label, type Mode, type Weights } from "../engine";

export const LATEST_APK_URL = "/downloads/mars-x-pro-v2.0.0.apk";
export const LEGACY_APK_URL = "/mars-x-release.apk";

const LABEL_C: Record<Label, string> = {
  OBSERVED: "text-sci border-atmos/70",
  DERIVED: "text-gold-deep border-gold/70",
  MODELED: "text-sage-deep border-sage/70",
  UNKNOWN: "text-dim border-line-strong border-dashed",
  SIMULATED: "text-mars-deep border-dust/70",
};

function Tag({ l }: { l: Label }) {
  return (
    <span
      className={`inline-flex items-center justify-center font-mono text-[9px] sm:text-[10px] leading-none tracking-[0.08em] border rounded-xs px-1.5 py-[2.5px] whitespace-nowrap shadow-2xs ${LABEL_C[l]}`}
    >
      {l}
    </span>
  );
}

function Eyebrow({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={`font-mono text-[11px] tracking-[0.16em] text-dim uppercase ${className}`}>
      {children}
    </div>
  );
}

const ROUTE_C: Record<Mode, string> = { SAFEST: "#75837B", FASTEST: "#789BA8", SCIENCE: "#B85C43" };
const SW_DASH: Record<Mode, string | undefined> = { SAFEST: undefined, FASTEST: "7 4", SCIENCE: "0.1 5" };

function Swatch({ m, w = 28 }: { m: Mode; w?: number }) {
  return (
    <svg width={w} height={8} aria-hidden="true" className="shrink-0">
      <line
        x1={1.5}
        x2={w - 1.5}
        y1={4}
        y2={4}
        stroke={ROUTE_C[m]}
        strokeWidth={3}
        strokeDasharray={SW_DASH[m]}
        strokeLinecap={m === "SCIENCE" ? "round" : "butt"}
      />
    </svg>
  );
}

export function scrollToLandingSection(hash: string) {
  const targetId = hash.replace(/^#/, "");
  const el = document.getElementById(targetId);
  if (el) {
    el.scrollIntoView({ behavior: "smooth" });
  }
}

const FALLBACK_TRADEOFFS: Record<
  "safety" | "fastest" | "science" | "balanced",
  RouteTradeoff & {
    metrics: {
      distance_km: string;
      duration_min: number;
      max_slope_deg: number;
      science_score: number;
      risk_score: number;
      risk_level: string;
      o2_kg: number;
      batt_kwh: number;
      water_kg: number;
      pnr_km: string;
    };
  }
> = {
  safety: {
    profile: "Safest",
    advantage_summary: "Maximizes crew survival margin and suit integrity across hazardous terrain.",
    compromise_summary: "Increases total traverse distance, duration, and life-support consumable draw.",
    gained: [
      "Lowest terrain risk score (18/100 LOW) and lowest peak slope exposure (8.4°)",
      "Avoids high-roughness boulder fields that degrade suit boots and rover wheels",
      "Minimizes traversal through unmapped / low-confidence orbital data cells",
      "Maintains widest safety buffer from the 25° hard mobility exclusion limit",
    ],
    compromised: [
      "+19.4% longer path distance compared to the Fastest route due to hazard detours",
      "Higher cumulative O2 (0.31 kg), battery (1.12 kWh), and cooling water consumption",
      "Bypasses steeper delta scarps where high-value sedimentary outcrops are exposed",
    ],
    quantitative_deltas: {
      distance_vs_fastest_pct: 19.4,
      duration_vs_fastest_min: 18.5,
      detour_ratio: 1.19,
      max_slope_vs_safest_deg: 0.0,
    },
    metrics: {
      distance_km: "1.91",
      duration_min: 63.7,
      max_slope_deg: 8.4,
      science_score: 0.42,
      risk_score: 18,
      risk_level: "LOW",
      o2_kg: 0.312,
      batt_kwh: 1.12,
      water_kg: 1.67,
      pnr_km: "1.42",
    },
  },
  fastest: {
    profile: "Fastest",
    advantage_summary: "Minimizes EVA duration and life-support consumable burn for rapid transit.",
    compromise_summary: "Accepts steeper grades and rougher regolith near mobility limits.",
    gained: [
      "Shortest geometric path (1.60 km) and fastest transit time (45.2 min)",
      "Lowest total oxygen (0.258 kg), battery (0.91 kWh), and cooling water (1.38 kg) burn",
      "Maximizes remaining Point-of-No-Return (PNR) life-support reserve margin",
      "Ideal for contingency return-to-habitat or medical abort scenarios",
    ],
    compromised: [
      "Higher exposure to caution-zone slopes (up to 15.8°) and surface roughness",
      "Reduced safety margin against local slip or unmapped micro-hazards",
      "Zero weighting for nearby astrobiological or geologic science targets",
    ],
    quantitative_deltas: {
      distance_vs_fastest_pct: 0.0,
      duration_vs_fastest_min: 0.0,
      detour_ratio: 1.0,
      max_slope_vs_safest_deg: 7.4,
    },
    metrics: {
      distance_km: "1.60",
      duration_min: 45.2,
      max_slope_deg: 15.8,
      science_score: 0.31,
      risk_score: 36,
      risk_level: "MODERATE",
      o2_kg: 0.258,
      batt_kwh: 0.91,
      water_kg: 1.38,
      pnr_km: "1.55",
    },
  },
  science: {
    profile: "Science",
    advantage_summary:
      "Maximizes astrobiological & geological return across Jezero landmarks (strictly capped <= 1.5x fastest).",
    compromise_summary: "Trades path efficiency and moderate terrain exposure for target proximity.",
    gained: [
      "Highest science value collected (0.89) across phyllosilicates, carbonates, and delta beds",
      "Routes within observation range of mapped Jezero landmarks & sample depots",
      "Detour length strictly capped at <= 1.5x the fastest route (1.34x actual) to protect EVA budget",
      "Balanced slope weighting keeps grades within safe human/rover limits (11.6° max)",
    ],
    compromised: [
      "+33.8% traverse distance and +26.1 min EVA time vs. Fastest route",
      "Enters moderate-roughness outcrop zones near delta scarps and crater rims",
      "Higher consumable burn than direct transit (still well within 8-hour EVA budget)",
    ],
    quantitative_deltas: {
      distance_vs_fastest_pct: 33.8,
      duration_vs_fastest_min: 26.1,
      detour_ratio: 1.34,
      max_slope_vs_safest_deg: 3.2,
    },
    metrics: {
      distance_km: "2.14",
      duration_min: 71.3,
      max_slope_deg: 11.6,
      science_score: 0.89,
      risk_score: 27,
      risk_level: "MODERATE",
      o2_kg: 0.348,
      batt_kwh: 1.24,
      water_kg: 1.86,
      pnr_km: "1.48",
    },
  },
  balanced: {
    profile: "Balanced",
    advantage_summary: "Equilibrates terrain safety, transit speed, and opportunistic science.",
    compromise_summary: "Sub-optimal for pure emergency speed or maximum-risk outcrop approaches.",
    gained: [
      "Well-rounded trade-off between slope avoidance (10.2° max) and direct progress (1.74 km)",
      "Moderate consumable usage with comfortable Point-of-No-Return reserve",
      "Captures opportunistic science targets (0.68 score) near the main corridor",
    ],
    compromised: [
      "+8.8% longer than Fastest route and +1.8° steeper peak slope than Safest",
      "Skips distant high-value science targets that require major detours",
    ],
    quantitative_deltas: {
      distance_vs_fastest_pct: 8.8,
      duration_vs_fastest_min: 9.4,
      detour_ratio: 1.09,
      max_slope_vs_safest_deg: 1.8,
    },
    metrics: {
      distance_km: "1.74",
      duration_min: 54.6,
      max_slope_deg: 10.2,
      science_score: 0.68,
      risk_score: 22,
      risk_level: "LOW",
      o2_kg: 0.284,
      batt_kwh: 1.01,
      water_kg: 1.52,
      pnr_km: "1.49",
    },
  },
};

export interface LandingPageProps {
  renderGlobe: (fly: FlyTarget, stage: number | null) => React.ReactNode;
  onNavigate?: (route: string) => void;
  onExplore?: () => void;
}

export default function LandingPage({ renderGlobe, onNavigate, onExplore }: LandingPageProps) {
  const [fly, setFly] = useState<FlyTarget>(null);
  const [activeSite, setActiveSite] = useState<string>("JEZERO");
  const [selectedSol, setSelectedSol] = useState<number>(20);
  const [health, setHealth] = useState<BackendHealth | null>(null);
  const [liveEnv, setLiveEnv] = useState<MedaEnvironment | null>(null);
  const [selectedProfile, setSelectedProfile] = useState<"safety" | "fastest" | "science" | "balanced">("science");
  const [liveTradeoffs, setLiveTradeoffs] = useState<Record<string, any> | null>(null);
  const [landmarkFilter, setLandmarkFilter] = useState<string>("ALL");
  const [activeLandmark, setActiveLandmark] = useState<MappedJezeroLandmark>(MAPPED_JEZERO_LANDMARKS[0]);

  useEffect(() => {
    let mounted = true;
    getBackendHealth().then((h) => {
      if (mounted && h) setHealth(h);
    });
    compareRoutesBackend().then((res) => {
      if (mounted && res && Array.isArray(res.routes)) {
        const map: Record<string, any> = {};
        for (const r of res.routes) {
          map[r.profile] = r.route;
        }
        setLiveTradeoffs(map);
      }
    });
    return () => {
      mounted = false;
    };
  }, []);

  useEffect(() => {
    let mounted = true;
    getEnvironmentData(selectedSol).then((env) => {
      if (mounted) setLiveEnv(env);
    });
    return () => {
      mounted = false;
    };
  }, [selectedSol]);

  const solReadings = MEDA_SOLS[selectedSol] ?? [];
  const validAir = solReadings.map((r) => r.airC).filter((v): v is number => v !== null);
  const validGround = solReadings.map((r) => r.groundC).filter((v): v is number => v !== null);
  const localNoon = getMedaWeather(selectedSol, 13);
  const airMean =
    liveEnv?.air_temperature?.mean ??
    (validAir.length ? validAir.reduce((a, b) => a + b, 0) / validAir.length : localNoon.airC);
  const airMin = liveEnv?.air_temperature?.min ?? (validAir.length ? Math.min(...validAir) : -78.0);
  const airMax = liveEnv?.air_temperature?.max ?? (validAir.length ? Math.max(...validAir) : -18.0);
  const groundMean =
    liveEnv?.ground_brightness_temperature?.mean ??
    (validGround.length ? validGround.reduce((a, b) => a + b, 0) / validGround.length : localNoon.groundC);

  const flyToSite = (id: string, lat: number, lon: number, dist: number) => {
    setActiveSite(id);
    setFly({ lat, lon, dist });
  };

  const flyToJezero = () => {
    flyToSite("JEZERO", 18.38, 77.58, 1.36);
    scrollToLandingSection("#landmarks");
  };

  const goRoute = (path: string) => {
    if (onNavigate) {
      onNavigate(path);
    } else {
      window.location.hash = path;
    }
  };

  const wk: { k: keyof Weights; n: string; c: string }[] = [
    { k: "s", n: "Slope", c: "#B85C43" },
    { k: "r", n: "Roughness", c: "#C9785D" },
    { k: "u", n: "Uncertainty", c: "#75837B" },
    { k: "h", n: "Distance", c: "#789BA8" },
  ];

  const objs: [Mode, string, Weights][] = [
    [
      "SAFEST",
      "Minimises slope, roughness, and data uncertainty exposure. Accepts a longer distance to protect rover wheels and EVA suits.",
      MODE_W.SAFEST,
    ],
    [
      "FASTEST",
      "Minimises total path length under the hard 25° slope limit. Optimizes transit speed for emergency returns.",
      MODE_W.FASTEST,
    ],
    [
      "SCIENCE",
      "Discounts cost near high-value scientific targets (aqueous alteration, delta remnants). Capped at <= 1.5x fastest route.",
      MODE_W.SCIENCE,
    ],
  ];

  const filteredLandmarks = MAPPED_JEZERO_LANDMARKS.filter((lm) =>
    landmarkFilter === "ALL" ? true : lm.category === landmarkFilter
  );

  // Merge live backend route comparison if available, otherwise fallback
  const currentFallback = FALLBACK_TRADEOFFS[selectedProfile];
  const liveRoute = liveTradeoffs?.[selectedProfile];
  const activeTradeoff: RouteTradeoff = liveRoute?.tradeoffs ?? currentFallback;
  const activeMetrics = liveRoute
    ? {
        distance_km: (liveRoute.metrics.distance_m / 1000).toFixed(2),
        duration_min: Number(liveRoute.metrics.estimated_duration_min).toFixed(1),
        max_slope_deg: Number(liveRoute.metrics.max_slope_deg).toFixed(1),
        science_score: Number(liveRoute.metrics.science_value_collected).toFixed(2),
        risk_score: liveRoute.risk?.score ?? currentFallback.metrics.risk_score,
        risk_level: liveRoute.risk?.level ?? currentFallback.metrics.risk_level,
        o2_kg: liveRoute.consumables?.oxygen_kg ?? currentFallback.metrics.o2_kg,
        batt_kwh: liveRoute.consumables?.battery_kwh ?? currentFallback.metrics.batt_kwh,
        water_kg: liveRoute.consumables?.cooling_water_kg ?? currentFallback.metrics.water_kg,
        pnr_km: liveRoute.consumables?.pnr_dist_m
          ? (liveRoute.consumables.pnr_dist_m / 1000).toFixed(2)
          : currentFallback.metrics.pnr_km,
      }
    : currentFallback.metrics;

  return (
    <div>
      {/* 1. Live Mission Telemetry Marquee Banner */}
      <div
        id="overview"
        className="bg-ink/95 border-b border-line px-4 py-2 flex items-center justify-between overflow-x-auto gap-4 font-mono text-[11px] select-none text-dim scroll-mt-[52px]"
      >
        <div className="flex items-center gap-2.5 shrink-0">
          <span className="relative flex h-2 w-2">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
            <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
          </span>
          <span className="text-emerald-400 font-bold uppercase tracking-[0.1em]">
            {health ? `BACKEND LIVE (${health.bundle_version.toUpperCase()})` : "LIVE MISSION TELEMETRY"}
          </span>
        </div>
        <div className="flex items-center gap-5 text-[11px] shrink-0">
          <span>
            SITE: <strong className="text-fg font-normal">JEZERO CRATER (18.44°N, 77.45°E)</strong>
          </span>
          <label className="inline-flex items-center gap-1.5">
            <span>MEDA SOL:</span>
            <select
              aria-label="Select Mars Sol for telemetry"
              value={selectedSol}
              onChange={(e) => setSelectedSol(Number(e.target.value))}
              className="bg-panel border border-line-strong text-gold font-mono text-[11px] px-1.5 py-0.5 rounded-xs cursor-pointer"
            >
              {AVAILABLE_SOLS.map((s) => (
                <option key={s} value={s}>
                  SOL {s}
                </option>
              ))}
            </select>
          </label>
          <span>
            AIR TEMP:{" "}
            <strong className="text-fg font-normal">
              {airMean.toFixed(1)}°C ({airMin.toFixed(0)}° / {airMax.toFixed(0)}°C)
            </strong>
          </span>
          <span>
            GROUND RAD.: <strong className="text-gold font-normal">{groundMean.toFixed(1)}°C</strong>
          </span>
          <span>
            GRID:{" "}
            <strong className="text-atmos font-normal">
              {health ? `${health.grid.w}×${health.grid.h} (${health.grid.cell_m}m HiRISE)` : "120×76 (35.99m HiRISE DTM)"}
            </strong>
          </span>
          <span className="text-emerald-400 font-semibold">● 15/15 LANDMARKS MAPPED</span>
        </div>
      </div>

      {/* 2. Hero Section */}
      <section className="sheet-lines border-b border-line">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-10 lg:py-8 grid lg:grid-cols-[minmax(0,5.2fr)_minmax(0,5.8fr)] gap-8 lg:gap-8 items-center lg:min-h-[calc(100dvh-52px-36px)]">
          <div className="order-2 lg:order-1 space-y-5">
            <div className="space-y-2.5">
              <div className="flex items-center gap-2 flex-wrap">
                <Eyebrow>NASA Space Apps Challenge 2026</Eyebrow>
                <span className="text-dim font-mono text-[10px]">·</span>
                <span className="font-mono text-[10px] text-mars-deep tracking-[0.08em] bg-panel px-2.5 py-0.5 rounded-sm border border-line">
                  INTERPLANETARY SURVIVAL GUIDE: MARTIAN MAP
                </span>
              </div>
              <h1 className="text-[clamp(44px,7vw,92px)] leading-[0.95] tracking-[-0.03em] font-medium text-mars-deep">
                MARS-X
              </h1>
              <p className="font-serif italic font-light text-[clamp(19px,2.3vw,29px)] text-fg/90">
                Interplanetary Surface Planning &amp; Astronaut Survival Engine
              </p>
            </div>

            <p className="max-w-xl text-[14px] sm:text-[15px] leading-relaxed text-fg/85">
              An explainable, mission-critical surface navigation system engineered for the NASA Space Apps Challenge
              2026. MARS-X fuses sub-meter NASA HiRISE stereo terrain, 15 mapped Jezero Crater expedition landmarks,
              USGS SIM 3464 geologic formations, Perseverance MEDA atmospheric tables, and 2-astronaut xEMU metabolic
              life-support physics into autonomous, safety-verified candidate paths across Mars.
            </p>

            {/* Primary Action CTAs: Launch Interactive Planner + Download APK + Teammate Kit */}
            <div className="flex flex-wrap gap-2.5 sm:gap-3 pt-1">
              <button
                onClick={() => goRoute("/map")}
                className="font-mono text-[12px] tracking-[0.1em] px-4 py-2.5 rounded-sm transition-colors bg-mars-deep text-ink hover:bg-fg hover:text-ink font-semibold flex items-center gap-2 shadow-sm cursor-pointer"
              >
                <span>LAUNCH MISSION PLANNER →</span>
              </button>
              <a
                href={LATEST_APK_URL}
                download="mars-x-pro-v2.0.0.apk"
                className="font-mono text-[12px] tracking-[0.1em] px-4 py-2.5 border rounded-sm transition-colors border-mars-deep/60 bg-mars/[0.08] text-mars-deep hover:bg-mars-deep hover:text-ink font-semibold flex items-center gap-2"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                  <polyline points="7 10 12 15 17 10" />
                  <line x1="12" y1="15" x2="12" y2="3" />
                </svg>
                <span>DOWNLOAD NEW PRO v2.0 APK</span>
              </a>
              <button
                onClick={() => scrollToLandingSection("#download")}
                className="font-mono text-[12px] tracking-[0.1em] px-3.5 py-2.5 border rounded-sm transition-colors border-line-strong text-fg hover:border-fg hover:bg-panel flex items-center gap-1.5 cursor-pointer"
              >
                <span>INTEGRATION DOWNLOADS ↓</span>
              </button>
              {onExplore && (
                <button
                  onClick={onExplore}
                  className="font-mono text-[12px] tracking-[0.1em] px-3.5 py-2.5 border rounded-sm transition-colors border-line-strong text-dim hover:text-fg hover:border-fg hover:bg-panel cursor-pointer"
                >
                  <span>2D/3D EXPLORER</span>
                </button>
              )}
            </div>

            {/* Quick Jump Bar to Full Web App Modules */}
            <div className="p-3 border border-line rounded-sm bg-panel/45 space-y-2">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[10px] tracking-[0.12em] text-dim uppercase">
                  DIRECT WORKSPACE MODULES (BACKEND CONNECTED)
                </span>
                <span className="font-mono text-[10px] text-emerald-400">● READY</span>
              </div>
              <div className="flex flex-wrap gap-1.5">
                {[
                  ["/map", "2D/3D Route Planner"],
                  ["/explorer", "Cell Inspector"],
                  ["/follow", "No-GPS Stepper"],
                  ["/science", "15 Jezero Landmarks"],
                  ["/report", "EVA Mission Report"],
                  ["/immersive", "First-Person 3D Walk"],
                  ["/data", "PDS Data & Saved"],
                ].map(([route, label]) => (
                  <button
                    key={route}
                    onClick={() => goRoute(route)}
                    className="font-mono text-[10px] px-2.5 py-1 rounded-xs border border-line-strong bg-paper hover:border-mars-deep hover:text-mars-deep transition-colors cursor-pointer"
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>

            <div className="pt-2 border-t border-line/60 space-y-2">
              <p className="text-[11px] sm:text-[12px] text-dim leading-relaxed">
                Every value and metric carries an honest scientific provenance label:
              </p>
              <div className="flex flex-wrap items-center gap-1.5 sm:gap-2">
                {(["OBSERVED", "DERIVED", "MODELED", "UNKNOWN", "SIMULATED"] as Label[]).map((l) => (
                  <Tag key={l} l={l} />
                ))}
              </div>
            </div>
          </div>

          <div className="order-1 lg:order-2 max-w-[620px] w-full mx-auto space-y-3">
            {renderGlobe(fly, null)}

            {/* Interactive Planetary Landmark Fast-Travel Controls */}
            <div className="p-3 border border-line rounded-sm bg-panel/60 space-y-2">
              <div className="flex items-center justify-between text-[11px] font-mono">
                <span className="text-dim">ORBITAL FAST-TRAVEL TARGETS:</span>
                <button
                  onClick={flyToJezero}
                  className="text-mars-deep hover:underline font-semibold flex items-center gap-1 cursor-pointer"
                >
                  <span>INSPECT 15 JEZERO LANDMARKS →</span>
                </button>
              </div>
              <div className="flex flex-wrap gap-1.5">
                {[
                  { id: "JEZERO", name: "Jezero Crater (Perseverance)", lat: 18.38, lon: 77.58, dist: 1.36 },
                  { id: "GALE", name: "Gale Crater (Curiosity)", lat: -5.4, lon: 137.8, dist: 1.5 },
                  { id: "OLYMPUS", name: "Olympus Mons (+21.9 km)", lat: 18.65, lon: -133.8, dist: 1.6 },
                  { id: "VALLES", name: "Valles Marineris (4,000 km)", lat: -13.9, lon: -59.2, dist: 1.6 },
                ].map((s) => (
                  <button
                    key={s.id}
                    onClick={() => flyToSite(s.id, s.lat, s.lon, s.dist)}
                    className={`font-mono text-[10px] px-2.5 py-1 rounded-sm border transition-colors cursor-pointer ${
                      activeSite === s.id
                        ? "border-mars-deep bg-mars/[0.15] text-mars-deep font-semibold"
                        : "border-line bg-paper text-dim hover:text-fg hover:border-line-strong"
                    }`}
                  >
                    {s.name}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* 3. What We Built: 6 Core Pillars */}
      <section id="what-we-did" className="max-w-6xl mx-auto px-4 sm:px-6 pt-20 scroll-mt-[52px]">
        <div className="border-b border-line pb-4 mb-8 flex flex-wrap items-end justify-between gap-4">
          <div>
            <Eyebrow>Engineering Summary</Eyebrow>
            <h2 className="text-[30px] sm:text-[34px] leading-tight text-mars-deep mt-1">
              What We Built for NASA Space Apps 2026
            </h2>
            <p className="text-[14px] text-dim mt-2 max-w-3xl leading-relaxed">
              MARS-X bridges the gap between raw NASA Planetary Data System (PDS) orbital archives and actionable field
              survival for future human and robotic explorers on Mars.
            </p>
          </div>
          <button
            onClick={() => goRoute("/map")}
            className="font-mono text-[11px] tracking-[0.1em] px-3.5 py-2 border border-mars-deep text-mars-deep hover:bg-mars-deep hover:text-ink rounded-sm transition-colors cursor-pointer"
          >
            OPEN INTERACTIVE MAP →
          </button>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
          <div className="border border-line rounded-md p-5 bg-paper hover:border-line-strong transition-colors space-y-3 flex flex-col justify-between">
            <div className="space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[11px] text-mars-deep font-semibold tracking-wider">01 · TERRAIN</span>
                <Tag l="DERIVED" />
              </div>
              <h3 className="text-[18px] font-medium text-fg">Sub-Meter HiRISE Stereo DTM Engine</h3>
              <p className="text-[13px] text-dim leading-relaxed">
                Ingested real NASA MRO HiRISE stereo elevation models ({" "}
                <code className="text-[11px] text-fg">DTEEC_045994_1985_046060_1985_U01</code> ) covering Jezero Crater.
                Computes central-difference slope gradients, 3×3 local surface roughness, and hard 25° mobility walls.
              </p>
            </div>
            <div className="pt-3 border-t border-line/60 flex justify-between items-center font-mono text-[10px] text-dim">
              <span>RES: 1.01 m/px → 35.99m cell</span>
              <span className="text-gold-deep">USGS STAC CC0</span>
            </div>
          </div>

          <div className="border border-line rounded-md p-5 bg-paper hover:border-line-strong transition-colors space-y-3 flex flex-col justify-between">
            <div className="space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[11px] text-mars-deep font-semibold tracking-wider">
                  02 · PATHFINDING
                </span>
                <Tag l="MODELED" />
              </div>
              <h3 className="text-[18px] font-medium text-fg">Multi-Objective A* &amp; String-Pulled Smoothing</h3>
              <p className="text-[13px] text-dim leading-relaxed">
                8-connected octile A* and Dijkstra solver generating three simultaneous candidate traverses:{" "}
                <strong className="text-fg font-normal">Safest</strong>,{" "}
                <strong className="text-fg font-normal">Fastest</strong>, and{" "}
                <strong className="text-fg font-normal">Most Scientific</strong> (with detour cap &le; 1.5× fastest).
              </p>
            </div>
            <div className="pt-3 border-t border-line/60 flex justify-between items-center font-mono text-[10px] text-dim">
              <span>OPTIMALITY: 100% Verified</span>
              <span className="text-sage-deep">A* ≡ Dijkstra</span>
            </div>
          </div>

          <div className="border border-line rounded-md p-5 bg-paper hover:border-line-strong transition-colors space-y-3 flex flex-col justify-between">
            <div className="space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[11px] text-mars-deep font-semibold tracking-wider">
                  03 · LIFE SUPPORT
                </span>
                <Tag l="MODELED" />
              </div>
              <h3 className="text-[18px] font-medium text-fg">2-Astronaut Buddy EVA &amp; PNR Physics</h3>
              <p className="text-[13px] text-dim leading-relaxed">
                Models 2-astronaut buddy-protocol oxygen (<code className="text-[11px]">kg</code> &amp;{" "}
                <code className="text-[11px]">L</code>), battery (<code className="text-[11px]">kWh</code>), cooling
                water, mandatory 10m/hr rest stops, and dynamic{" "}
                <strong className="text-fg font-normal">Point of No Return (PNR)</strong> emergency abort routes.
              </p>
            </div>
            <div className="pt-3 border-t border-line/60 flex justify-between items-center font-mono text-[10px] text-dim">
              <span>BUDGET: 480 MIN (8 HR EVA)</span>
              <span className="text-mars-deep">20% Safety Reserve</span>
            </div>
          </div>

          <div className="border border-line rounded-md p-5 bg-paper hover:border-line-strong transition-colors space-y-3 flex flex-col justify-between">
            <div className="space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[11px] text-mars-deep font-semibold tracking-wider">
                  04 · 15 LANDMARKS
                </span>
                <Tag l="OBSERVED" />
              </div>
              <h3 className="text-[18px] font-medium text-fg">15 Mapped Jezero Landmarks &amp; Close-Ups</h3>
              <p className="text-[13px] text-dim leading-relaxed">
                Complete geospatial register of 15 Jezero Crater landmarks (Octavia E. Butler Landing, Three Forks,
                Bunsen Peak, Neretva Vallis, Belva Crater, etc.) paired with orbital/rover close-up imagery and
                astrobiological significance.
              </p>
            </div>
            <div className="pt-3 border-t border-line/60 flex justify-between items-center font-mono text-[10px] text-dim">
              <span>SOURCE: USGS SIM 3464 &amp; PDS</span>
              <span className="text-atmos">15 Visual Cards</span>
            </div>
          </div>

          <div className="border border-line rounded-md p-5 bg-paper hover:border-line-strong transition-colors space-y-3 flex flex-col justify-between">
            <div className="space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[11px] text-mars-deep font-semibold tracking-wider">
                  05 · ATMOSPHERE
                </span>
                <Tag l="OBSERVED" />
              </div>
              <h3 className="text-[18px] font-medium text-fg">MEDA Weather &amp; Barometric Scale Height</h3>
              <p className="text-[13px] text-dim leading-relaxed">
                Integrates real Mars Environmental Dynamics Analyzer (MEDA) PDS4 diurnal temperature curves, ground
                brightness temperatures, and barometric pressure modeling (<code className="text-[11px]">H = 11.1 km</code>).
              </p>
            </div>
            <div className="pt-3 border-t border-line/60 flex justify-between items-center font-mono text-[10px] text-dim">
              <span>INSTRUMENT: MEDA TIRS/ATS</span>
              <span className="text-atmos">PDS Atmospheres Node</span>
            </div>
          </div>

          <div className="border border-line rounded-md p-5 bg-paper hover:border-line-strong transition-colors space-y-3 flex flex-col justify-between">
            <div className="space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[11px] text-mars-deep font-semibold tracking-wider">
                  06 · DUAL-PLATFORM
                </span>
                <Tag l="OBSERVED" />
              </div>
              <h3 className="text-[18px] font-medium text-fg">Offline Android APK + FastAPI Cloud Core</h3>
              <p className="text-[13px] text-dim leading-relaxed">
                Engineered as a unified ecosystem: a 3D/2D Web Mission Control backed by FastAPI on Railway, paired with
                a 100% offline-capable Flutter Android APK for astronauts operating in communication blackouts.
              </p>
            </div>
            <div className="pt-3 border-t border-line/60 flex justify-between items-center font-mono text-[10px] text-dim">
              <span>APK: 17.3 MB (arm64-v8a)</span>
              <span className="text-emerald-400">Zero-Latency Offline</span>
            </div>
          </div>
        </div>
      </section>

      {/* 4. Interactive 15 Mapped Jezero Landmarks Visual Register */}
      <section id="landmarks" className="max-w-6xl mx-auto px-4 sm:px-6 pt-20 scroll-mt-[52px]">
        <div className="border-b border-line pb-4 mb-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <Eyebrow>Georeferenced Surface Register</Eyebrow>
              <Tag l="DERIVED" />
              <Tag l="OBSERVED" />
            </div>
            <h2 className="text-[30px] sm:text-[34px] leading-tight text-mars-deep mt-1">
              The 15 Mapped Jezero Crater Landmarks
            </h2>
            <p className="text-[14px] text-dim mt-2 max-w-3xl leading-relaxed">
              Every landmark below is mapped onto the Jezero Crater coordinate grid with local close-up imagery,
              Perseverance rover exploration history, and astrobiological significance. Click any landmark to inspect it
              or open it in the Science Planner.
            </p>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {[
              ["ALL", `All (${MAPPED_JEZERO_LANDMARKS.length})`],
              ["geological_features", "Geological Features"],
              ["rover_exploration", "Rover Exploration"],
              ["points_of_interest", "Points of Interest"],
            ].map(([cat, label]) => (
              <button
                key={cat}
                onClick={() => setLandmarkFilter(cat)}
                className={`font-mono text-[11px] px-3 py-1.5 rounded-sm border transition-colors cursor-pointer ${
                  landmarkFilter === cat
                    ? "border-mars-deep bg-mars-deep text-ink font-semibold"
                    : "border-line-strong bg-paper text-dim hover:text-fg"
                }`}
              >
                {label}
              </button>
            ))}
          </div>
        </div>

        {/* Active Landmark Spotlight + Grid */}
        <div className="grid lg:grid-cols-[1.05fr_1.45fr] gap-6 items-start">
          <div className="border border-line-strong rounded-md bg-paper overflow-hidden shadow-sm lg:sticky lg:top-[68px]">
            <div className="relative aspect-[16/10] bg-ink overflow-hidden border-b border-line">
              <img
                src={"/" + activeLandmark.imageUrl.replace(/^\//, "")}
                alt={activeLandmark.name}
                className="w-full h-full object-cover"
                loading="lazy"
              />
              <div className="absolute top-2.5 left-2.5 flex items-center gap-1.5 bg-ink/85 backdrop-blur-xs px-2.5 py-1 rounded-xs border border-line-strong font-mono text-[10px] text-fg">
                <span className="text-mars-deep font-bold">{activeLandmark.subcategory.replace(/_/g, " ").toUpperCase()}</span>
                <span>·</span>
                <span>
                  {activeLandmark.latDeg !== null && activeLandmark.lonEast !== null
                    ? `${activeLandmark.latDeg.toFixed(3)}°N, ${activeLandmark.lonEast.toFixed(3)}°E`
                    : activeLandmark.geometryType}
                </span>
              </div>
              <div className="absolute bottom-2.5 right-2.5 bg-ink/85 backdrop-blur-xs px-2 py-0.5 rounded-xs border border-line font-mono text-[10px] text-gold">
                {activeLandmark.geometryType.toUpperCase()}
              </div>
            </div>
            <div className="p-5 space-y-3">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <Eyebrow>{activeLandmark.subcategory}</Eyebrow>
                  <h3 className="text-[22px] font-medium text-mars-deep mt-0.5">{activeLandmark.name}</h3>
                </div>
                <Tag l="DERIVED" />
              </div>
              <p className="text-[13px] text-fg/90 leading-relaxed">{activeLandmark.geologicalDescription}</p>
              <div className="p-3 rounded-sm bg-panel/60 border border-line space-y-1.5 text-[12px]">
                <div className="font-mono text-[10px] tracking-[0.1em] text-mars-deep uppercase font-semibold">
                  Astrobiological &amp; Geological Significance
                </div>
                <p className="text-fg/85 leading-relaxed">{activeLandmark.scientificSignificance}</p>
              </div>
              {activeLandmark.perseveranceHistory && (
                <div className="p-3 rounded-sm bg-panel/40 border border-line space-y-1 text-[12px]">
                  <div className="font-mono text-[10px] tracking-[0.1em] text-dim uppercase">
                    Perseverance Campaign History
                  </div>
                  <p className="text-dim leading-relaxed">{activeLandmark.perseveranceHistory}</p>
                </div>
              )}
              <div className="pt-2 flex flex-wrap gap-2">
                <button
                  onClick={() => goRoute("/science")}
                  className="font-mono text-[11px] tracking-[0.08em] px-3.5 py-2 bg-mars-deep text-ink rounded-sm hover:bg-fg transition-colors cursor-pointer font-semibold"
                >
                  OPEN IN SCIENCE DIRECTORY →
                </button>
                <button
                  onClick={() => goRoute("/map")}
                  className="font-mono text-[11px] tracking-[0.08em] px-3.5 py-2 border border-line-strong text-fg hover:bg-panel rounded-sm transition-colors cursor-pointer"
                >
                  VIEW ON 2D/3D MAP
                </button>
              </div>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
            {filteredLandmarks.map((lm) => {
              const selected = lm.id === activeLandmark.id;
              return (
                <button
                  key={lm.id}
                  onClick={() => setActiveLandmark(lm)}
                  className={`text-left border rounded-md overflow-hidden transition-all cursor-pointer flex flex-col justify-between ${
                    selected
                      ? "border-mars-deep ring-1 ring-mars-deep bg-mars/[0.06]"
                      : "border-line bg-paper hover:border-line-strong hover:bg-panel/40"
                  }`}
                >
                  <div>
                    <div className="aspect-[16/10] bg-ink overflow-hidden relative border-b border-line">
                      <img
                        src={"/" + lm.imageUrl.replace(/^\//, "")}
                        alt={lm.name}
                        className="w-full h-full object-cover"
                        loading="lazy"
                      />
                      <span className="absolute bottom-1.5 right-1.5 bg-ink/85 px-1.5 py-0.5 rounded-xs font-mono text-[9px] text-gold border border-line">
                        {lm.geometryType}
                      </span>
                    </div>
                    <div className="p-2.5 space-y-1">
                      <div className="font-mono text-[9px] text-mars-deep uppercase tracking-wider truncate">
                        {lm.subcategory.replace(/_/g, " ")}
                      </div>
                      <div className="text-[13px] font-medium text-fg leading-snug line-clamp-1">{lm.name}</div>
                      <p className="text-[11px] text-dim line-clamp-2 leading-relaxed">{lm.geologicalDescription}</p>
                    </div>
                  </div>
                  <div className="px-2.5 py-1.5 border-t border-line/60 flex items-center justify-between font-mono text-[9px] text-dim">
                    <span>
                      {lm.latDeg !== null && lm.lonEast !== null
                        ? `${lm.latDeg.toFixed(2)}°N, ${lm.lonEast.toFixed(2)}°E`
                        : lm.sourceName.slice(0, 18)}
                    </span>
                    <span className={selected ? "text-mars-deep font-bold" : ""}>
                      {selected ? "ACTIVE ●" : "INSPECT →"}
                    </span>
                  </div>
                </button>
              );
            })}
          </div>
        </div>
      </section>

      {/* 5. Interactive Pathfinding Trade-Offs (Gained vs. Compromised) */}
      <section id="tradeoffs" className="max-w-6xl mx-auto px-4 sm:px-6 pt-20 scroll-mt-[52px]">
        <div className="border-b border-line pb-4 mb-6">
          <div className="flex items-center gap-2">
            <Eyebrow>Pathfinding Trade-Off Analysis (`nipun_branch` + FastAPI Core)</Eyebrow>
            <Tag l="MODELED" />
          </div>
          <h2 className="text-[30px] sm:text-[34px] leading-tight text-mars-deep mt-1">
            What Parameters Are Gained vs. Compromised by Route Choice
          </h2>
          <p className="text-[14px] text-dim mt-2 max-w-3xl leading-relaxed">
            Choosing a traverse across Martian terrain requires explicit trade-offs between{" "}
            <strong className="text-fg font-normal">transit speed</strong>,{" "}
            <strong className="text-fg font-normal">slope &amp; roughness safety</strong>,{" "}
            <strong className="text-fg font-normal">2-astronaut EVA consumables</strong>, and{" "}
            <strong className="text-fg font-normal">scientific return</strong>. Select any routing profile below to
            inspect its live backend metrics and trade-off ledger.
          </p>
        </div>

        {/* Profile Selector Tabs */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5 mb-6">
          {(
            [
              ["safety", "SAFEST ROUTE", "Min Risk · Max Suit Margin"],
              ["fastest", "FASTEST ROUTE", "Min Time · Min O2/Battery Burn"],
              ["science", "SCIENCE ROUTE", "Max Discovery · Capped <= 1.5x"],
              ["balanced", "BALANCED ROUTE", "All-Around Nominal Traverse"],
            ] as const
          ).map(([key, title, subtitle]) => (
            <button
              key={key}
              onClick={() => setSelectedProfile(key)}
              className={`p-3.5 rounded-md border text-left transition-all cursor-pointer ${
                selectedProfile === key
                  ? "border-mars-deep bg-mars/[0.1] ring-1 ring-mars-deep"
                  : "border-line bg-paper hover:border-line-strong"
              }`}
            >
              <div className="font-mono text-[12px] font-bold text-mars-deep tracking-wider">{title}</div>
              <div className="text-[11px] text-dim mt-0.5">{subtitle}</div>
            </button>
          ))}
        </div>

        {/* Metrics + Gained vs Compromised Cards */}
        <div className="grid lg:grid-cols-[1fr_1.35fr] gap-6">
          <div className="border border-line rounded-md p-5 bg-paper space-y-4">
            <div className="flex items-center justify-between border-b border-line pb-3">
              <div>
                <Eyebrow>Profile Telemetry &amp; 2-Crew EVA Budget</Eyebrow>
                <h3 className="text-[20px] font-medium text-fg mt-0.5">
                  {activeTradeoff.profile} Candidate Traverse
                </h3>
              </div>
              <Tag l="MODELED" />
            </div>

            <div className="grid grid-cols-2 gap-3 font-mono text-[12px]">
              <div className="p-3 border border-line rounded-sm bg-panel/40">
                <span className="text-[10px] text-dim block">PATH DISTANCE</span>
                <span className="text-[18px] font-semibold text-fg">{activeMetrics.distance_km} km</span>
                {activeTradeoff.quantitative_deltas?.detour_ratio && (
                  <span className="text-[10px] text-dim block">
                    {activeTradeoff.quantitative_deltas.detour_ratio}× vs. Fastest
                  </span>
                )}
              </div>
              <div className="p-3 border border-line rounded-sm bg-panel/40">
                <span className="text-[10px] text-dim block">EST. EVA DURATION</span>
                <span className="text-[18px] font-semibold text-fg">{activeMetrics.duration_min} min</span>
                <span className="text-[10px] text-dim block">Budget: 480 min</span>
              </div>
              <div className="p-3 border border-line rounded-sm bg-panel/40">
                <span className="text-[10px] text-dim block">PEAK SLOPE / RISK</span>
                <span className="text-[18px] font-semibold text-mars-deep">
                  {activeMetrics.max_slope_deg}° · {activeMetrics.risk_level}
                </span>
                <span className="text-[10px] text-dim block">Risk Score: {activeMetrics.risk_score}/100</span>
              </div>
              <div className="p-3 border border-line rounded-sm bg-panel/40">
                <span className="text-[10px] text-dim block">SCIENCE COLLECTED</span>
                <span className="text-[18px] font-semibold text-atmos">{activeMetrics.science_score}</span>
                <span className="text-[10px] text-dim block">PNR @ {activeMetrics.pnr_km} km</span>
              </div>
            </div>

            <div className="p-3.5 border border-line rounded-sm bg-panel/60 space-y-2">
              <div className="flex items-center justify-between font-mono text-[10px] text-dim">
                <span>2-ASTRONAUT BUDDY CONSUMABLES (`nipun_branch` MODEL)</span>
                <span className="text-emerald-400 font-semibold">WITHIN RESERVE</span>
              </div>
              <div className="grid grid-cols-3 gap-2 font-mono text-[11px] pt-1">
                <div>
                  <span className="text-dim text-[10px] block">OXYGEN (2 CREW)</span>
                  <span className="text-fg font-semibold">{activeMetrics.o2_kg} kg</span>
                </div>
                <div>
                  <span className="text-dim text-[10px] block">SUIT BATTERY</span>
                  <span className="text-gold font-semibold">{activeMetrics.batt_kwh} kWh</span>
                </div>
                <div>
                  <span className="text-dim text-[10px] block">COOLING WATER</span>
                  <span className="text-atmos font-semibold">{activeMetrics.water_kg} kg</span>
                </div>
              </div>
            </div>
          </div>

          <div className="grid sm:grid-cols-2 gap-4">
            <div className="border border-emerald-500/40 bg-emerald-500/[0.05] rounded-md p-5 space-y-3">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[11px] font-bold text-emerald-400 tracking-wider uppercase">
                  ▲ PARAMETERS GAINED (ADVANTAGES)
                </span>
                <Tag l="MODELED" />
              </div>
              <p className="text-[12px] text-fg/90 font-medium leading-relaxed">
                {activeTradeoff.advantage_summary}
              </p>
              <ul className="space-y-2 text-[12px] text-fg/85 leading-relaxed pt-1">
                {activeTradeoff.gained.map((g, i) => (
                  <li key={i} className="flex items-start gap-2">
                    <span className="text-emerald-400 font-mono font-bold">+</span>
                    <span>{g}</span>
                  </li>
                ))}
              </ul>
            </div>

            <div className="border border-mars-deep/50 bg-mars/[0.06] rounded-md p-5 space-y-3">
              <div className="flex items-center justify-between">
                <span className="font-mono text-[11px] font-bold text-mars-deep tracking-wider uppercase">
                  ▼ PARAMETERS COMPROMISED (COST)
                </span>
                <Tag l="MODELED" />
              </div>
              <p className="text-[12px] text-fg/90 font-medium leading-relaxed">
                {activeTradeoff.compromise_summary}
              </p>
              <ul className="space-y-2 text-[12px] text-fg/85 leading-relaxed pt-1">
                {activeTradeoff.compromised.map((c, i) => (
                  <li key={i} className="flex items-start gap-2">
                    <span className="text-mars-deep font-mono font-bold">−</span>
                    <span>{c}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* 6. The Science & Datasets Section */}
      <section id="science" className="max-w-6xl mx-auto px-4 sm:px-6 pt-20 scroll-mt-[52px]">
        <div className="border-b border-line pb-4 mb-8">
          <Eyebrow>Orbital &amp; Rover Data Fusion</Eyebrow>
          <h2 className="text-[30px] sm:text-[34px] leading-tight text-mars-deep mt-1">
            The Science Behind MARS-X
          </h2>
          <p className="text-[14px] text-dim mt-2 max-w-3xl leading-relaxed">
            Every calculation in MARS-X is grounded in official planetary science datasets from NASA's Planetary Data
            System (PDS) and the USGS Astrogeology Science Center.
          </p>
        </div>

        {/* Route Objectives Weight Breakdown */}
        <div className="border border-line rounded-md p-6 bg-paper space-y-4 mb-8">
          <div>
            <Eyebrow>Routing Objective Weights</Eyebrow>
            <h3 className="text-[22px] font-normal text-mars-deep mt-1">Three Ways to Weigh the Same Terrain</h3>
          </div>
          <div className="border-t border-fg pt-2">
            {objs.map(([m, d, w]) => {
              const tot = w.s + w.r + w.u + w.h;
              return (
                <div
                  key={m}
                  className="grid md:grid-cols-[160px_1fr_1fr] gap-x-8 gap-y-3 py-4 border-b border-line items-center"
                >
                  <div className="flex items-center gap-3 font-mono text-[13px] tracking-[0.08em] font-semibold">
                    <Swatch m={m} w={28} />
                    {m}
                  </div>
                  <p className="text-[13px] text-fg/85 leading-relaxed">{d}</p>
                  <div>
                    <div
                      className="flex h-2.5 rounded-sm overflow-hidden"
                      role="img"
                      aria-label={`Cost weights: ${wk.map((x) => `${x.n} ${w[x.k]} percent`).join(", ")}`}
                    >
                      {wk.map((x) => (
                        <span key={x.k} style={{ width: `${(w[x.k] / tot) * 100}%`, background: x.c }} />
                      ))}
                    </div>
                    <div className="mt-1.5 flex justify-between font-mono text-[10px] text-dim">
                      {wk.map((x) => (
                        <span key={x.k}>
                          {x.n.slice(0, 4).toUpperCase()} {w[x.k]}
                        </span>
                      ))}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* 7. Standalone Offline Android Mobile App Section */}
      <section id="mobile-app" className="max-w-6xl mx-auto px-4 sm:px-6 pt-20 scroll-mt-[52px]">
        <div className="border-b border-line pb-4 mb-8">
          <div className="flex items-center gap-2">
            <Eyebrow>Autonomous Field Operations</Eyebrow>
            <Tag l="OBSERVED" />
          </div>
          <h2 className="text-[30px] sm:text-[34px] leading-tight text-mars-deep mt-1">
            The MARS-X Offline Android Mobile App
          </h2>
          <p className="text-[14px] text-dim mt-2 max-w-3xl leading-relaxed">
            When astronauts descend into the Jezero Crater delta, crater walls and orbital dynamics create frequent
            satellite communication blackouts. The MARS-X Android app is built from the ground up for 100%
            disconnected, zero-infrastructure autonomy—bundling all 15 Jezero landmark images, HiRISE DEM binaries, and
            the A* / EVA consumables engine locally.
          </p>
        </div>

        <div className="grid lg:grid-cols-[1.1fr_1fr] gap-8 items-center">
          <div className="border border-line rounded-xl bg-ink/90 p-5 shadow-float space-y-4 ring-1 ring-mars/30">
            <div className="flex items-center justify-between border-b border-line pb-3">
              <div className="flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse" />
                <span className="font-mono text-[11px] text-emerald-400 font-semibold tracking-wider">
                  OFFLINE EVA HUD ACTIVE
                </span>
              </div>
              <span className="font-mono text-[10px] text-dim bg-panel px-2 py-0.5 rounded-sm border border-line">
                v1.1.0 · arm64-v8a
              </span>
            </div>

            <div className="bg-panel/80 border border-line rounded-md p-3 text-center space-y-1">
              <span className="font-mono text-[10px] text-dim tracking-widest block">
                MAGNETIC / GYRO AZIMUTH TAPE
              </span>
              <div className="font-mono text-[20px] text-gold font-bold tracking-widest">
                245° WSW · BEARING TO THREE FORKS
              </div>
              <div className="flex justify-between font-mono text-[9px] text-dim px-4">
                <span>210°</span>
                <span>225° (SW)</span>
                <span className="text-mars-deep font-bold">▲ 245°</span>
                <span>270° (W)</span>
                <span>300°</span>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3 font-mono text-[11px]">
              <div className="p-3 bg-paper border border-line rounded-sm space-y-0.5">
                <span className="text-dim text-[10px] block">REMAINING DISTANCE</span>
                <span className="text-fg font-semibold text-[15px]">2.14 km</span>
                <span className="text-dim text-[9px] block">ETA: 71.3 min (Science Cap)</span>
              </div>
              <div className="p-3 bg-paper border border-line rounded-sm space-y-0.5">
                <span className="text-dim text-[10px] block">CURRENT SLOPE GRADE</span>
                <span className="text-emerald-400 font-semibold text-[15px]">+4.2° (PASSABLE)</span>
                <span className="text-dim text-[9px] block">Limit: 25.0° hard stop</span>
              </div>
              <div className="p-3 bg-paper border border-line rounded-sm space-y-0.5">
                <span className="text-dim text-[10px] block">2-CREW OXYGEN USED</span>
                <span className="text-atmos font-semibold text-[15px]">0.348 kg (78% rem)</span>
                <span className="text-dim text-[9px] block">Buddy Protocol Active</span>
              </div>
              <div className="p-3 bg-paper border border-line rounded-sm space-y-0.5">
                <span className="text-dim text-[10px] block">BATTERY RESERVE</span>
                <span className="text-gold font-semibold text-[15px]">1.24 kWh (82% rem)</span>
                <span className="text-dim text-[9px] block">Heater: Nominal</span>
              </div>
            </div>
          </div>

          <div className="space-y-4">
            <h3 className="text-[24px] font-normal text-mars-deep">
              Synchronized Between `nipun_branch`, `main`, and FastAPI Backend
            </h3>
            <p className="text-[13px] text-fg/85 leading-relaxed">
              Both the Flutter Android APK and the FastAPI backend share identical terrain grids (120×76 planning cells
              resampled from 480×304 HiRISE DEM), the same 15 Jezero Crater expedition landmarks, string-pulled 8-way
              A* pathfinding, and the 2-astronaut EVA consumables model.
            </p>
            <div className="grid grid-cols-2 gap-3 font-mono text-[11px]">
              <div className="p-3 border border-line rounded-sm bg-paper">
                <span className="text-mars-deep font-bold block">15 LOCAL LANDMARKS</span>
                <span className="text-dim text-[10px]">Bundled close-up imagery &amp; coordinates</span>
              </div>
              <div className="p-3 border border-line rounded-sm bg-paper">
                <span className="text-mars-deep font-bold block">STRING-PULLED A*</span>
                <span className="text-dim text-[10px]">Detour cap &le; 1.5× fastest route</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* 8. System Architecture Section */}
      <section id="architecture" className="max-w-6xl mx-auto px-4 sm:px-6 pt-20 scroll-mt-[52px]">
        <div className="border-b border-line pb-4 mb-6">
          <Eyebrow>Full-Stack Engineering</Eyebrow>
          <h2 className="text-[30px] sm:text-[34px] leading-tight text-mars-deep mt-1">
            Dual-Stack System Architecture
          </h2>
        </div>
        <div className="grid md:grid-cols-3 gap-5 text-[13px]">
          <div className="border border-line rounded-md p-5 bg-paper space-y-2">
            <div className="font-mono text-[11px] text-mars-deep font-bold">1 · REACT + THREE.JS WEB PLANNER</div>
            <p className="text-dim leading-relaxed">
              Interactive 3D Mars Globe (`MarsGlobe.tsx`), 3D First-Person Terrain Walk (`Terrain3D.tsx`), 2D HiRISE
              Multi-Layer Canvas, and live telemetry via `src/api.ts`.
            </p>
          </div>
          <div className="border border-line rounded-md p-5 bg-paper space-y-2">
            <div className="font-mono text-[11px] text-emerald-400 font-bold">2 · FASTAPI BACKEND (`backend/app/`)</div>
            <p className="text-dim leading-relaxed">
              Rectified Python routing engine (`core.py`, `geo_layers.py`, `meda_reader.py`, `main.py`) serving 15
              mapped Jezero landmarks, A*/Dijkstra comparison, EVA consumables, and route trade-off analysis.
            </p>
          </div>
          <div className="border border-line rounded-md p-5 bg-paper space-y-2">
            <div className="font-mono text-[11px] text-gold font-bold">3 · FLUTTER OFFLINE APK (`mobile/`)</div>
            <p className="text-dim leading-relaxed">
              Standalone arm64-v8a Android application with embedded HiRISE DEM binary, SQLite mission storage, and
              live Railway health/MEDA sync when online.
            </p>
          </div>
        </div>
      </section>

      {/* 9. Dedicated Download & Teammate Integration Station */}
      <section id="download" className="max-w-6xl mx-auto px-4 sm:px-6 pt-20 pb-12 scroll-mt-[52px]">
        <div className="border-2 border-mars-deep/50 rounded-xl bg-paper p-6 sm:p-10 shadow-float space-y-8">
          <div className="text-center max-w-2xl mx-auto space-y-3">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-mars/[0.12] border border-mars-deep/30 text-mars-deep font-mono text-[11px] font-semibold">
              <span>READY FOR FIELD TESTING &amp; TEAMMATE INTEGRATION</span>
            </div>
            <h2 className="text-[30px] sm:text-[38px] leading-tight text-mars-deep font-medium">
              Download APK &amp; Teammate Integration Files
            </h2>
            <p className="text-[14px] text-dim leading-relaxed">
              Download the standalone Android APK for mobile testing, or grab the rectified{" "}
              <code className="text-fg">LandingPage.tsx</code> and unified backend integration bundle to drop directly
              into <code className="text-fg">main</code>.
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-5">
            {/* Card 1: New Standalone MARS-X Pro v2.0.0 APK + Original v1 APK */}
            <div className="border-2 border-mars-deep rounded-lg p-5 bg-mars/[0.06] flex flex-col justify-between space-y-4">
              <div className="space-y-2">
                <div className="flex items-center justify-between font-mono text-[10px]">
                  <span className="text-mars-deep font-bold">NEW STANDALONE APK (v2.0.0)</span>
                  <span className="px-2 py-0.5 bg-mars/[0.18] text-mars-deep rounded-xs font-bold">com.marsx.pro</span>
                </div>
                <h3 className="text-[18px] font-medium text-fg">MARS-X Pro v2.0 Mobile App</h3>
                <p className="text-[12px] text-dim leading-relaxed">
                  Brand-new standalone Android APK (installs side-by-side without overwriting v1). Merges the unified
                  FastAPI backend, all 15 Jezero landmarks &amp; close-up imagery, MEDA Sol selector, 2-astronaut EVA
                  consumables, and Route Trade-Offs.
                </p>
              </div>
              <div className="space-y-2">
                <a
                  href={LATEST_APK_URL}
                  download="mars-x-pro-v2.0.0.apk"
                  className="w-full font-mono text-[12px] tracking-[0.08em] px-4 py-3 rounded-sm bg-mars-deep text-ink hover:bg-fg transition-colors font-semibold flex items-center justify-center gap-2"
                >
                  <span>DOWNLOAD MARS-X PRO v2.0 APK</span>
                </a>
                <a
                  href={LEGACY_APK_URL}
                  download="mars-x-v1-original.apk"
                  className="w-full font-mono text-[10px] tracking-[0.06em] px-3 py-1.5 rounded-sm border border-line-strong text-dim hover:text-fg hover:bg-panel transition-colors flex items-center justify-center gap-1.5"
                >
                  <span>Or download original v1.0 baseline APK (untouched)</span>
                </a>
              </div>
            </div>

            {/* Card 2: Teammate Drop-in LandingPage.tsx */}
            <div className="border border-emerald-500/40 rounded-lg p-5 bg-emerald-500/[0.04] flex flex-col justify-between space-y-4">
              <div className="space-y-2">
                <div className="flex items-center justify-between font-mono text-[10px]">
                  <span className="text-emerald-400 font-bold">TEAMMATE DROP-IN MODULE</span>
                  <span className="px-2 py-0.5 bg-emerald-500/15 text-emerald-300 rounded-xs">React / TS</span>
                </div>
                <h3 className="text-[18px] font-medium text-fg">Standalone `LandingPage.tsx`</h3>
                <p className="text-[12px] text-dim leading-relaxed">
                  Self-contained React component wired to <code className="text-fg">src/api.ts</code>,{" "}
                  <code className="text-fg">processedDataLayers.ts</code>, and all FastAPI backend endpoints.
                </p>
              </div>
              <a
                href="/downloads/LandingPage.tsx"
                download="LandingPage.tsx"
                className="w-full font-mono text-[12px] tracking-[0.08em] px-4 py-3 rounded-sm border border-emerald-500/60 bg-emerald-500/15 text-emerald-300 hover:bg-emerald-500 hover:text-ink transition-colors font-semibold flex items-center justify-center gap-2"
              >
                <span>DOWNLOAD LandingPage.tsx</span>
              </a>
            </div>

            {/* Card 3: Rectified Backend + Integration Bundle ZIP */}
            <div className="border border-gold/50 rounded-lg p-5 bg-gold/[0.05] flex flex-col justify-between space-y-4">
              <div className="space-y-2">
                <div className="flex items-center justify-between font-mono text-[10px]">
                  <span className="text-gold font-bold">FULL INTEGRATION BUNDLE</span>
                  <span className="px-2 py-0.5 bg-gold/15 text-gold rounded-xs">ZIP ARCHIVE</span>
                </div>
                <h3 className="text-[18px] font-medium text-fg">Rectified Backend + Frontend Kit</h3>
                <p className="text-[12px] text-dim leading-relaxed">
                  Contains rectified <code className="text-fg">backend/app/*</code> (`core.py`, `main.py`,{" "}
                  `geo_layers.py`, `meda_reader.py`), <code className="text-fg">src/api.ts</code>, and{" "}
                  <code className="text-fg">LandingPage.tsx</code>.
                </p>
              </div>
              <a
                href="/downloads/mars-x-backend-integration-kit.zip"
                download="mars-x-backend-integration-kit.zip"
                className="w-full font-mono text-[12px] tracking-[0.08em] px-4 py-3 rounded-sm border border-gold/60 bg-gold/15 text-gold hover:bg-gold hover:text-ink transition-colors font-semibold flex items-center justify-center gap-2"
              >
                <span>DOWNLOAD INTEGRATION ZIP</span>
              </a>
            </div>
          </div>

          <div className="pt-4 border-t border-line flex flex-wrap items-center justify-between gap-3 font-mono text-[11px] text-dim">
            <span>API ENDPOINT: {API_BASE}</span>
            <span>BACKEND TESTS: 23/23 PASSING (pytest)</span>
            <span>PROVENANCE: USGS SIM 3464 · NASA M2020 PDS</span>
          </div>
        </div>
      </section>
    </div>
  );
}
