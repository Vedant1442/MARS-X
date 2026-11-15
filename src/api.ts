/**
 * MARS-X Live Backend API Client
 * Connects to the deployed FastAPI backend on Railway.
 */

export const API_BASE = (import.meta.env.VITE_API_BASE_URL as string) || 'https://api-production-14018b03.up.railway.app';

export interface BackendHealth {
  status: string;
  bundle_version: string;
  datasets_loaded: string[];
  terrain_source: string;
  grid: { w: number; h: number; cell_m: number };
  warnings: string[];
}

export interface MedaEnvironment {
  sol: number;
  data_type: string;
  instrument: string;
  citation: string;
  sample_count: number;
  lmst_span: string;
  air_temperature: { min: number; max: number; mean: number; unit: string };
  ground_brightness_temperature: { min: number; max: number; mean: number; unit: string };
  relative_humidity: number | null;
  diurnal_samples: Array<{ lmst: string; air_temp_c: number }>;
}

export async function getBackendHealth(): Promise<BackendHealth | null> {
  try {
    const res = await fetch(`${API_BASE}/api/health`, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

export async function getEnvironmentData(sol = 20): Promise<MedaEnvironment | null> {
  try {
    const res = await fetch(`${API_BASE}/api/environment?sol=${sol}`, { signal: AbortSignal.timeout(6000) });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

export interface RouteTradeoff {
  profile: string;
  advantage_summary: string;
  compromise_summary: string;
  gained: string[];
  compromised: string[];
  quantitative_deltas?: {
    distance_vs_fastest_pct?: number;
    duration_vs_fastest_min?: number;
    detour_ratio?: number;
    max_slope_vs_safest_deg?: number;
  };
}

export interface BackendMappedLandmark {
  id: string;
  name: string;
  x: number;
  y: number;
  lon: number;
  lat: number;
  type: string;
  category: string;
  subcategory: string;
  value: number;
  conf: string;
  image_url: string;
  significance: string;
  perseverance_history: string;
  note: string;
}

export async function getScienceTargets() {
  try {
    const res = await fetch(`${API_BASE}/api/science-targets`, { signal: AbortSignal.timeout(6000) });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

export async function getMappedLandmarks(): Promise<{ landmarks: BackendMappedLandmark[]; count: number } | null> {
  try {
    const res = await fetch(`${API_BASE}/api/landmarks/mapped`, { signal: AbortSignal.timeout(6000) });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

export async function getRoverTraverse() {
  try {
    const res = await fetch(`${API_BASE}/api/rover/traverse`, { signal: AbortSignal.timeout(6000) });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

export async function compareRoutesBackend(
  start = { lon: 77.40672, lat: 18.3820 },
  goal = { lon: 77.42689, lat: 18.3740 },
) {
  try {
    const res = await fetch(`${API_BASE}/api/routes/compare`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        start,
        goal,
        profiles: ['safety', 'fastest', 'science', 'balanced'],
        include_dijkstra: true,
        constraints: { max_slope_deg: 25.0, return_to_base: false, eva_budget_min: 480 },
      }),
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}
