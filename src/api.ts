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

export async function getScienceTargets() {
  try {
    const res = await fetch(`${API_BASE}/api/science-targets`, { signal: AbortSignal.timeout(6000) });
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
