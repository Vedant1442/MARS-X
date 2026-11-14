// ---------- Terrain: real USGS HiRISE DTM window (DERIVED), see data/build_dem.py ----------
import { JEZERO_B64, JEZERO_META } from "./jezeroGrid";
export const W = JEZERO_META.w, H = JEZERO_META.h;
export const CELL_M = JEZERO_META.cellM; // metres per planning cell
export const MAP_W_KM = JEZERO_META.widthM / 1000, MAP_H_KM = JEZERO_META.heightM / 1000;
export type Label = "OBSERVED" | "DERIVED" | "MODELED" | "UNKNOWN" | "SIMULATED";

function rng(seed: number) {
  return () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
function makeNoise(seed: number) {
  const r = rng(seed); const g: number[] = [];
  for (let i = 0; i < 64 * 64; i++) g.push(r());
  const v = (x: number, y: number) => g[((y & 63) * 64) + (x & 63)];
  const sm = (t: number) => t * t * (3 - 2 * t);
  return (x: number, y: number) => {
    const xi = Math.floor(x), yi = Math.floor(y), xf = sm(x - xi), yf = sm(y - yi);
    const a = v(xi, yi), b = v(xi + 1, yi), c = v(xi, yi + 1), d = v(xi + 1, yi + 1);
    return a + (b - a) * xf + (c - a) * yf + (a - b - c + d) * xf * yf;
  };
}
export type Terrain = { elev: Float32Array; slope: Float32Array; rough: Float32Array; unc: Float32Array; nodata: Uint8Array; min: number; max: number };
export function buildTerrain(): Terrain {
  const n2 = makeNoise(19);
  const bin = atob(JEZERO_B64), elev = new Float32Array(W * H);
  for (let i = 0; i < W * H; i++) { const lo = bin.charCodeAt(i * 2), hi = bin.charCodeAt(i * 2 + 1); let v = lo | (hi << 8); if (v > 32767) v -= 65536; elev[i] = v / 10; }
  const slope = new Float32Array(W * H), rough = new Float32Array(W * H), unc = new Float32Array(W * H), nodata = new Uint8Array(W * H);
  let min = Infinity, max = -Infinity;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = y * W + x, g = (xx: number, yy: number) => elev[Math.min(H - 1, Math.max(0, yy)) * W + Math.min(W - 1, Math.max(0, xx))];
    const dzdx = (g(x + 1, y) - g(x - 1, y)) / (2 * CELL_M), dzdy = (g(x, y + 1) - g(x, y - 1)) / (2 * CELL_M);
    slope[i] = Math.atan(Math.hypot(dzdx, dzdy)) * 180 / Math.PI;
    let s = 0; for (let k = -1; k <= 1; k++) for (let l = -1; l <= 1; l++) s += Math.abs(g(x + k, y + l) - elev[i]);
    rough[i] = Math.min(1, s / 9 / 60 + n2(x / 5, y / 5) * 0.35);
    // Modeled confidence: lower near window edges and on rough ground. No data gaps exist in this window.
    const edge = Math.min(x, y, W - 1 - x, H - 1 - y) / 12;
    unc[i] = Math.min(1, 0.12 + 0.25 * (1 - Math.min(1, edge)) + rough[i] * 0.4 + n2(x / 9 + 30, y / 9) * 0.15);
    min = Math.min(min, elev[i]); max = Math.max(max, elev[i]);
  }
  return { elev, slope, rough, unc, nodata, min, max };
}

// ---------- Science targets: Verified Jezero Crater Features (DERIVED / OBSERVED) ----------
export type Target = { id: string; name: string; x: number; y: number; type: string; value: number; conf: "LOW" | "MEDIUM" | "HIGH"; note: string };
export const TARGETS: Target[] = [
  { id: "T1", name: "Octavia E. Butler Landing", x: 60, y: 38, type: "Perseverance Touchdown Regolith", value: 0.98, conf: "HIGH", note: "Published Mars 2020 landing site (Stack et al. 2023). Reference datum for Jezero crater exploration." },
  { id: "T2", name: "Séítah North Rim Outcrop", x: 44, y: 34, type: "Layered Igneous/Olivine Bedrock", value: 0.92, conf: "HIGH", note: "USGS SIM 3464 crater floor unit (Nf_cf). Ancient igneous floor showing aqueous alteration." },
  { id: "T3", name: "Neretva Delta Scarp Entry", x: 26, y: 42, type: "Fluvial Sedimentary Delta Fan", value: 0.95, conf: "HIGH", note: "Delta front bottomset beds deposited by ancient inflow from Neretva Vallis into Jezero crater lake." },
  { id: "T4", name: "East Crater Rampart", x: 84, y: 20, type: "Impact Ejecta / Deep Bedrock", value: 0.76, conf: "MEDIUM", note: "Mapped impact crater in USGS SIM 3464. Exposes deep sub-surface bedrock strata." },
  { id: "T5", name: "Crater Floor Dune Field", x: 43, y: 20, type: "Active Aeolian Dunes & Ripples", value: 0.82, conf: "HIGH", note: "Active sand ripples; key context for wind transport, grain size, and rover mobility hazards." },
];

// ---------- Routing ----------
export type Mode = "SAFEST" | "FASTEST" | "SCIENCE";
export type Weights = { s: number; r: number; u: number; h: number };
export const DEFAULT_W: Weights = { s: 40, r: 25, u: 20, h: 15 };
export const MODE_W: Record<Mode, Weights> = { SAFEST: { s: 50, r: 30, u: 15, h: 5 }, FASTEST: { s: 15, r: 10, u: 5, h: 70 }, SCIENCE: DEFAULT_W };
export const MAX_SLOPE = 25;
export const EXPOSURE_DEG = 15; // planning assumption: cells above this are counted as slope exposure
export type Pt = { x: number; y: number };
export type Route = { mode: Mode; path: Pt[]; dist: number; cost: number; maxSlope: number; meanSlope: number; meanRough: number; meanUnc: number; sciHits: Target[]; elevGain: number; confidence: string; exposure: number; sciValue: number; risk: Risk };

export function astar(T: Terrain, a: Pt, b: Pt, w: Weights, mode: Mode): Route | null {
  const sum = w.s + w.r + w.u + w.h || 1;
  const ws = w.s / sum, wr = w.r / sum, wu = w.u / sum, wh = w.h / sum;
  const cellCost = (i: number, x: number, y: number) => {
    if (T.nodata[i] || T.slope[i] > MAX_SLOPE) return Infinity; // unknown ≠ safe
    let c = ws * (T.slope[i] / MAX_SLOPE) + wr * T.rough[i] + wu * T.unc[i] + wh;
    if (mode === "SCIENCE") for (const t of TARGETS) { const d = Math.hypot(x - t.x, y - t.y); if (d < 6) c *= 1 - 0.55 * t.value * (1 - d / 6); }
    return c;
  };
  const N = W * H, g = new Float32Array(N).fill(Infinity), from = new Int32Array(N).fill(-1), closed = new Uint8Array(N);
  const heap: [number, number][] = []; const push = (f: number, i: number) => { heap.push([f, i]); let k = heap.length - 1; while (k > 0) { const p = (k - 1) >> 1; if (heap[p][0] <= heap[k][0]) break; [heap[p], heap[k]] = [heap[k], heap[p]]; k = p; } };
  const pop = () => { const top = heap[0], last = heap.pop()!; if (heap.length) { heap[0] = last; let k = 0; for (;;) { const l = 2 * k + 1, r = l + 1; let m = k; if (l < heap.length && heap[l][0] < heap[m][0]) m = l; if (r < heap.length && heap[r][0] < heap[m][0]) m = r; if (m === k) break; [heap[m], heap[k]] = [heap[k], heap[m]]; k = m; } } return top; };
  const si = a.y * W + a.x, ti = b.y * W + b.x;
  if (!isFinite(cellCost(si, a.x, a.y)) || !isFinite(cellCost(ti, b.x, b.y))) return null;
  const minC = mode === "SCIENCE" ? wh * 0.45 : wh;
  const hfn = (x: number, y: number) => Math.hypot(x - b.x, y - b.y) * minC;
  g[si] = 0; push(hfn(a.x, a.y), si);
  while (heap.length) {
    const [, i] = pop(); if (closed[i]) continue; closed[i] = 1; if (i === ti) break;
    const x = i % W, y = (i / W) | 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      if (!dx && !dy) continue; const nx = x + dx, ny = y + dy; if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
      const j = ny * W + nx; if (closed[j]) continue; const c = cellCost(j, nx, ny); if (!isFinite(c)) continue;
      const ng = g[i] + c * (dx && dy ? Math.SQRT2 : 1);
      if (ng < g[j]) { g[j] = ng; from[j] = i; push(ng + hfn(nx, ny), j); }
    }
  }
  if (from[ti] === -1) return null;
  const path: Pt[] = []; for (let k = ti; k !== -1; k = from[k]) path.push({ x: k % W, y: (k / W) | 0 }); path.reverse();
  let dist = 0, ms = 0, ss = 0, rr = 0, uu = 0, gain = 0;
  path.forEach((p, k) => { const i = p.y * W + p.x; ms = Math.max(ms, T.slope[i]); ss += T.slope[i]; rr += T.rough[i]; uu += T.unc[i]; if (k) { const q = path[k - 1]; dist += Math.hypot(p.x - q.x, p.y - q.y) * CELL_M; gain += Math.max(0, T.elev[i] - T.elev[q.y * W + q.x]); } });
  const n = path.length, mu = uu / n;
  const exposure = path.filter((p) => T.slope[p.y * W + p.x] > EXPOSURE_DEG).length / n;
  const sciHits = TARGETS.filter((t) => path.some((p) => Math.hypot(p.x - t.x, p.y - t.y) < 4));
  const route: Route = { mode, path, dist, cost: g[ti], maxSlope: ms, meanSlope: ss / n, meanRough: rr / n, meanUnc: mu, sciHits, elevGain: gain, exposure, sciValue: sciHits.reduce((a, t) => a + t.value, 0), confidence: mu < 0.3 ? "MEDIUM" : mu < 0.5 ? "LOW" : "VERY LOW" , risk: undefined as unknown as Risk };
  route.risk = riskScore(T, route);
  return route;
}

// ---------- Time model (SIMULATED) ----------
// Walking speed falls with slope. A planning assumption, not a certified EVA mobility limit.
export const TIME_BUDGET_MIN = 480;
export const speedMps = (slopeDeg: number) => Math.max(0.2, 1.4 * (1 - slopeDeg / (MAX_SLOPE * 1.3)));
export function legTimeMin(T: Terrain, path: Pt[]) {
  let s = 0;
  for (let k = 1; k < path.length; k++) { const a = path[k - 1], b = path[k], i = b.y * W + b.x; s += (Math.hypot(b.x - a.x, b.y - a.y) * CELL_M) / speedMps(T.slope[i]); }
  return s / 60;
}

// ---------- Risk score 0-100 (SIMULATED weights, see PLAN section 6.4) ----------
export const CAUTION_DEG = 10;
export const RISK_W = { max: 0.3, caution: 0.25, rough: 0.2, unc: 0.15, time: 0.1 };
export type Risk = { score: number; level: "LOW" | "MODERATE" | "HIGH" | "VERY HIGH"; timeMin: number; parts: { k: string; label: string; v: number; w: number }[] };
export function riskScore(T: Terrain, r: Route): Risk {
  const idx = r.path.map((p) => p.y * W + p.x), n = idx.length;
  let len = 0, cautionLen = 0;
  for (let k = 1; k < n; k++) { const d = Math.hypot(r.path[k].x - r.path[k - 1].x, r.path[k].y - r.path[k - 1].y); len += d; if (T.slope[idx[k]] > CAUTION_DEG) cautionLen += d; }
  const timeMin = legTimeMin(T, r.path);
  const parts = [
    { k: "max", label: "Peak slope vs limit", v: Math.min(1, r.maxSlope / MAX_SLOPE), w: RISK_W.max },
    { k: "caution", label: `Length above ${CAUTION_DEG}°`, v: len ? cautionLen / len : 0, w: RISK_W.caution },
    { k: "rough", label: "Mean roughness", v: Math.min(1, r.meanRough), w: RISK_W.rough },
    { k: "unc", label: "Low-confidence share", v: idx.filter((i) => T.unc[i] > 0.5).length / n, w: RISK_W.unc },
    { k: "time", label: "Time vs budget", v: Math.min(1, timeMin / TIME_BUDGET_MIN), w: RISK_W.time },
  ];
  const score = Math.round(100 * parts.reduce((a, p) => a + p.v * p.w, 0));
  return { score, level: score < 25 ? "LOW" : score < 50 ? "MODERATE" : score < 75 ? "HIGH" : "VERY HIGH", timeMin, parts };
}
/** Science score 0-100: simulated cell values along the path plus targets passed. */
export function scienceScore(r: Route) { return Math.min(100, Math.round(r.sciValue * 45)); }

// ---------- Simulated pressure layer ----------
// P(h) = P_ref * exp(-(h - h_ref)/H). H is a documented assumption (VERIFY). P_ref would come from
// archived MEDA data; it is not ingested here, so values are RELATIVE (1.00 = lowest cell). SIMULATED.
export const SCALE_HEIGHT_M = 11100;
export const pressureRel = (T: Terrain, i: number) => Math.exp(-(T.elev[i] - T.min) / SCALE_HEIGHT_M);

// ---------- Landmarks (no-GPS navigation, PLAN section 6.5) ----------
export type Leg = { bearing: number; distM: number; dElev: number; slopeMin: number; slopeMax: number; timeMin: number };
export type Landmark = { n: number; idx: number; pt: Pt; sM: number; name: string; kind: "start" | "dest" | "science" | "terrain"; desc: string; why: string; target?: Target; next?: Leg };
const cardinal = (b: number) => ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(b / 45) % 8];
export { cardinal };

export function pickLandmarks(T: Terrain, r: Route): Landmark[] {
  const p = r.path, n = p.length, at = (k: number) => p[k].y * W + p[k].x;
  const s: number[] = [0];
  for (let k = 1; k < n; k++) s.push(s[k - 1] + Math.hypot(p[k].x - p[k - 1].x, p[k].y - p[k - 1].y) * CELL_M);
  const L = s[n - 1], K = L < 6000 ? 5 : 6, legs = K - 1;
  const head = (k: number) => { const a = p[Math.max(0, k - 2)], b = p[Math.min(n - 1, k + 2)]; const d = Math.hypot(b.x - a.x, b.y - a.y) || 1; return [(b.x - a.x) / d, (b.y - a.y) / d]; };
  const side = (k: number) => { // which side the ground drops toward, relative to heading
    const g = (x: number, y: number) => T.elev[Math.min(H - 1, Math.max(0, y)) * W + Math.min(W - 1, Math.max(0, x))];
    const dx = -(g(p[k].x + 2, p[k].y) - g(p[k].x - 2, p[k].y)), dy = -(g(p[k].x, p[k].y + 2) - g(p[k].x, p[k].y - 2));
    const [hx, hy] = head(k), cr = hx * dy - hy * dx, mag = Math.hypot(dx, dy);
    return mag < 8 ? "" : cr > 0 ? "ground drops to your right" : "ground drops to your left";
  };
  type C = { k: number; score: number; kind: "science" | "terrain"; name: string; desc: string; why: string; target?: Target };
  const cands = new Map<number, C>();
  for (const t of TARGETS) { // science targets within ~4 cells (800 m) of the route
    let best = -1, bd = 99; p.forEach((q, k) => { const d = Math.hypot(q.x - t.x, q.y - t.y); if (d < bd) { bd = d; best = k; } });
    if (bd <= 4 && best > 0 && best < n - 1) { const score = 0.6 * t.value + 0.4 * 0.5 - bd * 0.04; if (!cands.has(best) || cands.get(best)!.score < score) cands.set(best, { k: best, score, kind: "science", name: t.name, desc: `${t.type}. ${bd < 1.5 ? "On the route" : `About ${(bd * CELL_M).toFixed(0)} m off the route`}; ${side(best) || "gentle terrain"}.`, why: `${t.note} Importance ${t.value.toFixed(2)} (simulated expert weight, no published citation: the terrain is synthetic).`, target: t }); }
  }
  for (let k = 4; k < n - 4; k++) { // terrain landmarks: crests, lows, slope breaks
    const e = T.elev[at(k)], win = p.slice(k - 4, k + 5).map((_, j) => T.elev[at(k - 4 + j)]), mx = Math.max(...win), mn = Math.min(...win);
    const brk = Math.abs(T.slope[at(k)] - T.slope[at(k - 3)]);
    let name = "", desc = "", d = 0;
    if (e === mx && mx - Math.min(...win) > 25) { name = "Ridge crest"; d = Math.min(1, (mx - mn) / 150); desc = `Local high point, ${side(k) || "ground falls away"}.`; }
    else if (e === mn && mx - mn > 25) { name = "Local low"; d = Math.min(1, (mx - mn) / 150); desc = "Local low point; ground rises ahead."; }
    else if (brk > 7) { name = "Slope break"; d = Math.min(1, brk / 15); desc = `Slope changes from ${T.slope[at(k - 3)].toFixed(0)}° to ${T.slope[at(k)].toFixed(0)}°.`; }
    if (name && !cands.has(k)) cands.set(k, { k, score: 0.4 * d, kind: "terrain", name, desc, why: "Terrain landmark derived from the synthetic elevation model. No science claim is made for it." });
  }
  const list = [...cands.values()].sort((a, b) => a.k - b.k);
  const lo = (0.5 * L) / legs, hi = (1.8 * L) / legs, m = K - 2;
  // DP over ordered candidates: maximise score with gap limits between consecutive landmarks
  const best: { v: number; prev: number }[][] = Array.from({ length: m + 1 }, () => list.map(() => ({ v: -Infinity, prev: -1 })));
  list.forEach((c, i) => { if (s[c.k] >= lo && s[c.k] <= hi) best[1][i] = { v: c.score, prev: -1 }; });
  for (let j = 2; j <= m; j++) list.forEach((c, i) => list.forEach((q, h) => { const g = s[c.k] - s[q.k]; if (g >= lo && g <= hi && best[j - 1][h].v > -Infinity && best[j - 1][h].v + c.score > best[j][i].v) best[j][i] = { v: best[j - 1][h].v + c.score, prev: h }; }));
  let pickedIdx: number[] = []; let bv = -Infinity, bi = -1;
  list.forEach((c, i) => { const g = L - s[c.k]; if (g >= lo && g <= hi && best[m][i].v > bv) { bv = best[m][i].v; bi = i; } });
  if (bi >= 0) { for (let j = m, i = bi; j >= 1; j--) { pickedIdx.unshift(i); i = best[j][i].prev; } }
  let mids: C[] = pickedIdx.map((i) => list[i]);
  if (mids.length < m) { // relax: evenly spaced terrain landmarks
    mids = Array.from({ length: m }, (_, j) => { const target = (L * (j + 1)) / legs; let k = s.findIndex((v) => v >= target); k = Math.max(1, Math.min(n - 2, k)); const near = list.find((c) => Math.abs(s[c.k] - target) < lo * 0.6); return near ?? { k, score: 0, kind: "terrain" as const, name: "Waypoint", desc: `Evenly spaced waypoint; ${side(k) || "gentle terrain"}.`, why: "Evenly spaced fallback landmark. No science claim is made for it." }; });
  }
  const mk = (n_: number, c: Omit<C, "score"> & { score?: number }, kind: Landmark["kind"]): Landmark => ({ n: n_, idx: c.k, pt: p[c.k], sM: s[c.k], name: c.name, kind, desc: c.desc, why: c.why, target: c.target });
  const out: Landmark[] = [
    mk(1, { k: 0, kind: "terrain", name: "Start", desc: "Your starting cell. Note the surroundings before you set off.", why: "Reference point for the traverse." }, "start"),
    ...mids.map((c, j) => mk(j + 2, c, c.kind)),
    mk(K, { k: n - 1, kind: "terrain", name: "Destination", desc: "End of the candidate route.", why: "Planned end point. Reaching it is not a safety guarantee." }, "dest"),
  ];
  out.forEach((a, j) => {
    const b = out[j + 1]; if (!b) return;
    const seg = p.slice(a.idx, b.idx + 1), dx = b.pt.x - a.pt.x, dy = b.pt.y - a.pt.y, sl = seg.map((q) => T.slope[q.y * W + q.x]);
    a.next = { bearing: (Math.atan2(dx, -dy) * 180 / Math.PI + 360) % 360, distM: b.sM - a.sM, dElev: T.elev[b.pt.y * W + b.pt.x] - T.elev[a.pt.y * W + a.pt.x], slopeMin: Math.min(...sl), slopeMax: Math.max(...sl), timeMin: legTimeMin(T, seg) };
  });
  return out;
}
