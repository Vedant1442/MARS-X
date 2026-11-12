import { Component, createContext, lazy, Suspense, useContext, useEffect, useId, useMemo, useRef, useState } from "react";
import {
  astar, buildTerrain, cardinal, CELL_M, MAP_H_KM, MAP_W_KM, DEFAULT_W, EXPOSURE_DEG, H, MAX_SLOPE, MODE_W, pickLandmarks, pressureRel, SCALE_HEIGHT_M, scienceScore, TARGETS, TIME_BUDGET_MIN, W,
  type Landmark, type Label, type Mode, type Pt, type Route, type Target, type Terrain, type Weights,
} from "./engine";
import type { FlyTarget, GlobeApi } from "./MarsGlobe";
import { JEZERO_META } from "./jezeroGrid";
import type { Cam, Probe, View3D } from "./Terrain3D";

/* ============================================================
   MARS-X: Mission planner. All terrain in this build is SYNTHETIC
   (procedurally generated) and labeled as such. The Mars globe uses
   the USGS/NASA Viking MDIM 2.1 color mosaic for orientation only.
   ============================================================ */

const MarsGlobe = lazy(() => import("./MarsGlobe"));
const Terrain3D = lazy(() => import("./Terrain3D"));

// ---------- Router (hash based) ----------
function useHashRoute() {
  const [path, setPath] = useState(() => window.location.hash.slice(1) || "/");
  useEffect(() => {
    const on = () => { setPath(window.location.hash.slice(1) || "/"); window.scrollTo(0, 0); };
    window.addEventListener("hashchange", on);
    return () => window.removeEventListener("hashchange", on);
  }, []);
  return path;
}
const go = (p: string) => { window.location.hash = p; };
let arrivedFromGlobe = false;
function A({ to, className, children }: { to: string; className?: string; children: React.ReactNode }) {
  return <a href={"#" + to} className={className}>{children}</a>;
}
function useReducedMotion() {
  const [r, setR] = useState(() => typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  useEffect(() => {
    const m = window.matchMedia("(prefers-reduced-motion: reduce)");
    const on = () => setR(m.matches);
    m.addEventListener("change", on);
    return () => m.removeEventListener("change", on);
  }, []);
  return r;
}
function useDelay(ms: number) {
  const [done, setDone] = useState(false);
  useEffect(() => { const id = setTimeout(() => setDone(true), ms); return () => clearTimeout(id); }, [ms]);
  return done;
}

// ---------- Store ----------
type Store = {
  T: Terrain; start: Pt | null; end: Pt | null; setStart: (p: Pt | null) => void; setEnd: (p: Pt | null) => void;
  mode: Mode; setMode: (m: Mode) => void; weights: Weights; setWeights: (w: Weights) => void;
  routes: Partial<Record<Mode, Route | null>>; setRoutes: (r: Partial<Record<Mode, Route | null>>) => void;
  mission: Target[]; toggleTarget: (t: Target) => void;
};
const Ctx = createContext<Store>(null!);
const useStore = () => useContext(Ctx);

// ---------- Palette helpers ----------
const MODE_NAME: Record<Mode, string> = { SAFEST: "Safest", FASTEST: "Quickest", SCIENCE: "Most scientific" };
const RISK_C = { LOW: "text-sage-deep border-sage", MODERATE: "text-gold-deep border-gold", HIGH: "text-mars-deep border-mars", "VERY HIGH": "text-mars-deep border-mars" } as const;
const ROUTE_C: Record<Mode, string> = { SAFEST: "#75837B", FASTEST: "#789BA8", SCIENCE: "#B85C43" };
const ROUTE_DEEP: Record<Mode, string> = { SAFEST: "#56655d", FASTEST: "#46697a", SCIENCE: "#964630" };
const MAP_DASH: Record<Mode, string | undefined> = { SAFEST: undefined, FASTEST: "1.3 0.7", SCIENCE: "0.01 0.85" };
const SW_DASH: Record<Mode, string | undefined> = { SAFEST: undefined, FASTEST: "7 4", SCIENCE: "0.1 5" };

// ---------- UI atoms ----------
const LABEL_C: Record<Label, string> = {
  OBSERVED: "text-sci border-atmos/70",
  DERIVED: "text-gold-deep border-gold/70",
  MODELED: "text-sage-deep border-sage/70",
  UNKNOWN: "text-dim border-line-strong border-dashed",
  SIMULATED: "text-mars-deep border-dust/70",
};
function Tag({ l }: { l: Label }) { return <span className={`font-mono text-[10px] leading-none tracking-[0.1em] border rounded-sm px-1.5 py-[3px] whitespace-nowrap ${LABEL_C[l]}`}>{l}</span>; }
function Eyebrow({ children, className = "" }: { children: React.ReactNode; className?: string }) { return <div className={`font-mono text-[11px] tracking-[0.16em] text-dim uppercase ${className}`}>{children}</div>; }
function Btn({ children, onClick, primary, disabled, className = "", ...rest }: { children: React.ReactNode; onClick?: () => void; primary?: boolean; disabled?: boolean; className?: string } & Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, "onClick" | "children" | "className" | "disabled">) {
  return <button {...rest} disabled={disabled} onClick={onClick} className={`font-mono text-[12px] tracking-[0.12em] px-4 py-2.5 border rounded-sm transition-colors disabled:opacity-45 disabled:cursor-not-allowed ${primary ? "bg-mars-deep text-ink border-mars-deep hover:bg-fg hover:border-fg" : "border-line-strong text-fg hover:border-fg hover:bg-panel"} ${className}`}>{children}</button>;
}
function Panel({ title, tag, children, className = "" }: { title: string; tag?: Label; children: React.ReactNode; className?: string }) {
  return <section className={`border border-line bg-paper rounded-md ${className}`}><header className="flex items-center justify-between gap-2 border-b border-line px-3 py-2"><Eyebrow>{title}</Eyebrow>{tag && <Tag l={tag} />}</header><div className="p-3">{children}</div></section>;
}
function Row({ k, v, l }: { k: string; v: React.ReactNode; l?: Label }) {
  return <div className="flex items-center justify-between gap-3 py-1.5 border-b border-line/70 last:border-0 text-[13px]"><span className="text-dim">{k}</span><span className="flex items-center gap-2 font-mono text-[12px] text-fg text-right">{v}{l && <Tag l={l} />}</span></div>;
}
const fmtKm = (m: number) => (m / 1000).toFixed(2) + " km";
const SynthBanner = () => <div role="note" className="font-mono text-[11px] tracking-[0.08em] text-mars-deep border-b border-dust/40 bg-mars/[0.07] px-3 py-1.5">TERRAIN: USGS HiRISE DTM (DERIVED) · MISSION, TARGETS, RISK AND TIME ARE SIMULATED · ROUTES ARE CANDIDATES, SAFETY NOT CERTIFIED</div>;

function Swatch({ m, w = 28 }: { m: Mode; w?: number }) {
  return <svg width={w} height={8} aria-hidden="true" className="shrink-0"><line x1={1.5} x2={w - 1.5} y1={4} y2={4} stroke={ROUTE_C[m]} strokeWidth={3} strokeDasharray={SW_DASH[m]} strokeLinecap={m === "SCIENCE" ? "round" : "butt"} /></svg>;
}
type GlyphKind = "start" | "way" | "dest" | "warn" | "sci" | "nodata" | "site";
function Glyph({ k }: { k: GlyphKind }) {
  const s = { stroke: "#263238", strokeWidth: 1.2, fill: "none" };
  return (
    <svg width={14} height={14} viewBox="-7 -7 14 14" aria-hidden="true" className="shrink-0">
      {k === "start" && <><circle r={4.5} {...s} /><circle r={1.4} fill="#263238" /></>}
      {k === "way" && <circle r={3} {...s} />}
      {k === "dest" && <rect x={-4} y={-4} width={8} height={8} {...s} fill="#B85C43" />}
      {k === "warn" && <path d="M0 -5 L5 4 L-5 4 Z" {...s} fill="#D3A24C" />}
      {k === "sci" && <rect x={-3.6} y={-3.6} width={7.2} height={7.2} {...s} transform="rotate(45)" stroke="#46697a" />}
      {k === "site" && <circle r={3.4} {...s} fill="#D3A24C" />}
      {k === "nodata" && <><rect x={-5} y={-5} width={10} height={10} {...s} /><path d="M-5 0 L0 -5 M-5 5 L5 -5 M0 5 L5 0" stroke="#263238" strokeWidth={1} /></>}
    </svg>
  );
}
function BrandMark() {
  return <svg width={20} height={20} viewBox="-10 -10 20 20" aria-hidden="true"><circle r={8.5} fill="none" stroke="#263238" strokeWidth={1.2} /><ellipse rx={3.6} ry={8.5} fill="none" stroke="#263238" strokeWidth={0.9} /><path d="M-8.5 0 H8.5" stroke="#263238" strokeWidth={0.9} /><circle cx={3.6} cy={-2.6} r={1.7} fill="#B85C43" /></svg>;
}
function Skeleton({ className = "" }: { className?: string }) { return <div className={`skeleton rounded-sm ${className}`} aria-hidden="true" />; }
function LoadingNote({ children }: { children: React.ReactNode }) { return <p role="status" className="font-mono text-[12px] tracking-[0.06em] text-dim">{children}</p>; }

function Sheet({ open, onClose, title, children, className = "" }: { open: boolean; onClose: () => void; title: string; children: React.ReactNode; className?: string }) {
  useEffect(() => {
    if (!open) return;
    const k = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, [open, onClose]);
  return (
    <>
      {open && <div className="fixed inset-0 z-40 bg-fg/30 lg:hidden" onClick={onClose} aria-hidden="true" />}
      <aside aria-label={title} role={open ? "dialog" : undefined} className={`fixed inset-x-0 bottom-0 z-50 max-h-[78dvh] overflow-y-auto overscroll-contain bg-ink border-t border-line-strong rounded-t-md shadow-float p-3 space-y-3 transition-transform duration-300 ${open ? "translate-y-0" : "translate-y-full invisible"} lg:visible lg:static lg:z-auto lg:max-h-none lg:translate-y-0 lg:rounded-none lg:shadow-none lg:border-t-0 lg:overflow-y-auto ${className}`}>
        <div className="lg:hidden flex items-center justify-between"><Eyebrow>{title}</Eyebrow><button onClick={onClose} className="font-mono text-[12px] tracking-[0.1em] px-2 py-1 border border-line-strong rounded-sm">CLOSE</button></div>
        {children}
      </aside>
    </>
  );
}
function MobileBar({ items }: { items: { label: string; on: () => void; active: boolean }[] }) {
  return <div className="lg:hidden fixed bottom-0 inset-x-0 z-30 h-14 grid bg-ink border-t border-line-strong no-print" style={{ gridTemplateColumns: `repeat(${items.length}, 1fr)` }}>{items.map((i) => <button key={i.label} onClick={i.on} aria-expanded={i.active} className="font-mono text-[12px] tracking-[0.14em] text-fg border-r border-line last:border-0 hover:bg-panel">{i.label}</button>)}</div>;
}

// ---------- Map colour ramps ----------
type Layer = "hillshade" | "slope" | "rough" | "unc" | "elev" | "pressure";
const CONTOUR_M = 100;
type RGB = [number, number, number];
const hex = (h: string): RGB => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const RAMPS: Record<Layer, string[]> = {
  hillshade: ["#2a211c", "#5a4336", "#8a6a52", "#c2a284"],
  elev: ["#2f3540", "#4d5b66", "#8a7a66", "#c9a77c", "#efe2c8"],
  slope: ["#2b2724", "#5c4c40", "#b85c43", "#f1d9bd"],
  rough: ["#2b2724", "#5a5346", "#b89a5a", "#f1e4bd"],
  unc: ["#2b2724", "#4d5a60", "#789ba8", "#dbe8ec"],
  pressure: ["#2a2f3d", "#46697a", "#789ba8", "#dbe8ec"],
};
function ramp(stops: string[], t: number): RGB {
  const n = stops.length - 1, x = Math.min(1, Math.max(0, t)) * n, i = Math.min(n - 1, Math.floor(x)), f = x - i;
  const a = hex(stops[i]), b = hex(stops[i + 1]);
  return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
}
function colorFor(T: Terrain, i: number, layer: Layer, x: number, y: number): RGB {
  if (T.nodata[i]) return ((x + y) % 4 < 2) ? [52, 46, 42] : [34, 29, 26];
  const g = (xx: number, yy: number) => T.elev[Math.min(H - 1, Math.max(0, yy)) * W + Math.min(W - 1, Math.max(0, xx))];
  const shade = Math.max(0, Math.min(1, 0.55 + (g(x - 1, y - 1) - g(x + 1, y + 1)) / 260));
  const t = layer === "slope" ? Math.min(1, T.slope[i] / MAX_SLOPE) : layer === "rough" ? T.rough[i] : layer === "unc" ? T.unc[i] : layer === "pressure" ? (pressureRel(T, i) - Math.exp(-(T.max - T.min) / SCALE_HEIGHT_M)) / (1 - Math.exp(-(T.max - T.min) / SCALE_HEIGHT_M)) : (T.elev[i] - T.min) / (T.max - T.min);
  const c = ramp(RAMPS[layer], t);
  const k = layer === "hillshade" ? 0.55 + shade * 0.75 : 0.72 + shade * 0.5;
  return [c[0] * k, c[1] * k, c[2] * k];
}
const rampCss = (l: Layer) => `linear-gradient(90deg, ${RAMPS[l].join(", ")})`;

// ---------- Map ----------
function RouteLine({ route, focus, animate, uid }: { route: Route; focus: boolean; animate: boolean; uid: string }) {
  const { T } = useStore();
  const m = route.mode;
  const pts = route.path.map((p) => `${p.x + 0.5},${p.y + 0.5}`).join(" ");
  const mid = useMemo(() => [0.25, 0.5, 0.75].map((f) => route.path[Math.floor(f * (route.path.length - 1))]), [route]);
  const warns = useMemo(() => {
    const out: Pt[] = []; let last = -99;
    const idx = route.path.map((p, k) => [k, T.slope[p.y * W + p.x]] as const).filter(([, s]) => s > EXPOSURE_DEG).sort((a, b) => b[1] - a[1]);
    for (const [k] of idx) { if (out.length >= 3) break; if (out.every((_, j) => Math.abs(route.path.indexOf(out[j]) - k) > 10)) { out.push(route.path[k]); last = k; } }
    void last; return out;
  }, [route, T]);
  const mid_id = `${uid}-${m}`;
  return (
    <g opacity={focus ? 1 : 0.6}>
      <defs>
        <mask id={mid_id} maskUnits="userSpaceOnUse" x={0} y={0} width={W} height={H}>
          <polyline points={pts} fill="none" stroke="#fff" strokeWidth={2.2} pathLength={1} className={animate ? "draw" : undefined} style={animate ? undefined : { strokeDasharray: 1 }} />
        </mask>
      </defs>
      <g mask={`url(#${mid_id})`}>
        <polyline points={pts} fill="none" stroke="#f5f1e8" strokeWidth={0.95} strokeLinejoin="round" strokeLinecap="round" opacity={0.92} />
        <polyline points={pts} fill="none" stroke={ROUTE_C[m]} strokeWidth={0.5} strokeLinejoin="round" strokeLinecap={m === "SCIENCE" ? "round" : "butt"} strokeDasharray={MAP_DASH[m]} />
      </g>
      {focus && <g className="fade-in" style={{ animationDelay: animate ? "1.2s" : "0s" }}>
        {mid.map((p, k) => <circle key={k} cx={p.x + 0.5} cy={p.y + 0.5} r={0.7} fill="#f5f1e8" stroke={ROUTE_C[m]} strokeWidth={0.3} />)}
        {warns.map((p, k) => <path key={k} d={`M${p.x + 0.5} ${p.y - 1.1} L${p.x + 1.7} ${p.y + 1.2} L${p.x - 0.7} ${p.y + 1.2} Z`} fill="#D3A24C" stroke="#241b17" strokeWidth={0.22} />)}
      </g>}
    </g>
  );
}
function MarsMap({ layer = "hillshade", onPick, showTargets = true, highlight, inspect, loadingLabel = "Loading terrain…", contours = false, landmarks, current, marker }: { layer?: Layer; onPick?: (p: Pt) => void; showTargets?: boolean; highlight?: Mode | "ALL"; inspect?: Pt | null; loadingLabel?: string; contours?: boolean; landmarks?: Landmark[]; current?: number; marker?: Pt | null }) {
  const { T, start, end, routes, mission, mode } = useStore();
  const ref = useRef<HTMLCanvasElement>(null);
  const uid = useId().replace(/:/g, "");
  const [hover, setHover] = useState<Pt | null>(null);
  const ready = useDelay(650);
  useEffect(() => {
    const c = ref.current!; const ctx = c.getContext("2d")!; const img = ctx.createImageData(W, H);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const i = y * W + x, [r, g, b] = colorFor(T, i, layer, x, y); img.data.set([r, g, b, 255], i * 4); }
    if (contours) { // DERIVED contour lines every CONTOUR_M metres where the band changes
      const band = (xx: number, yy: number) => Math.floor(T.elev[Math.min(H - 1, yy) * W + Math.min(W - 1, xx)] / CONTOUR_M);
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const b0 = band(x, y); if (b0 !== band(x + 1, y) || b0 !== band(x, y + 1)) { const o = (y * W + x) * 4; const major = b0 % 5 === 0; img.data.set(major ? [245, 241, 232, 255] : [226, 200, 160, 255], o); } }
    }
    ctx.putImageData(img, 0, 0);
  }, [T, layer, contours]);
  const toPt = (e: React.MouseEvent) => { const r = (e.currentTarget as HTMLElement).getBoundingClientRect(); return { x: Math.min(W - 1, Math.max(0, Math.floor(((e.clientX - r.left) / r.width) * W))), y: Math.min(H - 1, Math.max(0, Math.floor(((e.clientY - r.top) / r.height) * H))) }; };
  const onKey = (e: React.KeyboardEvent) => {
    const d: Record<string, [number, number]> = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
    if (d[e.key]) { e.preventDefault(); const s = e.shiftKey ? 5 : 1; setHover((h) => { const c = h ?? { x: 60, y: 38 }; return { x: Math.min(W - 1, Math.max(0, c.x + d[e.key][0] * s)), y: Math.min(H - 1, Math.max(0, c.y + d[e.key][1] * s)) }; }); }
    else if ((e.key === "Enter" || e.key === " ") && hover) { e.preventDefault(); onPick?.(hover); }
  };
  const hi = hover ? hover.y * W + hover.x : -1;
  const focusMode = highlight && highlight !== "ALL" ? highlight : mode;
  const modes = (Object.keys(routes) as Mode[]).filter((m) => routes[m] && (highlight === "ALL" || !highlight || highlight === m));
  const outline = "#241b17";
  return (
    <div className="on-dark relative w-full h-full bg-map overflow-hidden select-none">
      <div className="absolute inset-0 flex items-center justify-center">
        <div className="relative w-full" style={{ aspectRatio: `${W}/${H}`, maxHeight: "100%" }}>
          <canvas key={layer} ref={ref} width={W} height={H} tabIndex={0} role="application" aria-label={`HiRISE terrain map, ${layer} layer. ${onPick ? "Use arrow keys to move the cursor and Enter to select a cell." : "Use arrow keys to read cell values."}`} className="layer-in absolute inset-0 w-full h-full [image-rendering:pixelated] cursor-crosshair" onMouseMove={(e) => setHover(toPt(e))} onMouseLeave={() => setHover(null)} onClick={(e) => onPick?.(toPt(e))} onKeyDown={onKey} />
          <svg viewBox={`0 0 ${W} ${H}`} className="absolute inset-0 w-full h-full pointer-events-none" preserveAspectRatio="none" aria-hidden="true">
            {Array.from({ length: 11 }).map((_, k) => <line key={"v" + k} x1={(k * W) / 10} x2={(k * W) / 10} y1={0} y2={H} stroke="#f5f1e8" strokeOpacity={0.1} strokeWidth={0.1} />)}
            {Array.from({ length: 7 }).map((_, k) => <line key={"h" + k} y1={(k * H) / 6} y2={(k * H) / 6} x1={0} x2={W} stroke="#f5f1e8" strokeOpacity={0.1} strokeWidth={0.1} />)}
            {modes.map((m) => <RouteLine key={`${m}-${routes[m]!.cost}`} route={routes[m]!} focus={m === focusMode} animate uid={uid} />)}
            {showTargets && TARGETS.map((t) => { const sel = mission.some((m) => m.id === t.id); return <g key={t.id}><rect x={t.x - 1.1} y={t.y - 1.1} width={2.2} height={2.2} fill={sel ? "#9EC0CD" : outline} fillOpacity={sel ? 1 : 0.55} stroke="#9EC0CD" strokeWidth={0.3} transform={`rotate(45 ${t.x} ${t.y})`} /><text x={t.x + 2} y={t.y + 0.8} fontSize={2.2} fill="#cfe2e9" stroke={outline} strokeWidth={0.5} paintOrder="stroke" fontFamily="IBM Plex Mono">{t.id}</text></g>; })}
            {landmarks?.map((l, k) => { const on = k === current; return <g key={l.n}><circle cx={l.pt.x + 0.5} cy={l.pt.y + 0.5} r={on ? 2.6 : 1.9} fill={on ? "#B85C43" : outline} stroke="#f5f1e8" strokeWidth={on ? 0.5 : 0.35} /><text x={l.pt.x + 0.5} y={l.pt.y + 1.5} fontSize={2.6} textAnchor="middle" fill="#f5f1e8" fontFamily="IBM Plex Mono">{l.n}</text></g>; })}
            {marker && <g><circle cx={marker.x + 0.5} cy={marker.y + 0.5} r={2.4} fill="#D3A24C" fillOpacity={0.35} /><circle cx={marker.x + 0.5} cy={marker.y + 0.5} r={1} fill="#D3A24C" stroke={outline} strokeWidth={0.3} /></g>}
            {start && !landmarks && <g><circle cx={start.x + 0.5} cy={start.y + 0.5} r={1.5} fill={outline} stroke="#f5f1e8" strokeWidth={0.4} /><circle cx={start.x + 0.5} cy={start.y + 0.5} r={0.45} fill="#f5f1e8" /><text x={start.x + 2.6} y={start.y - 0.8} fontSize={2.2} fill="#f5f1e8" stroke={outline} strokeWidth={0.5} paintOrder="stroke" fontFamily="IBM Plex Mono">START</text></g>}
            {end && !landmarks && <g><circle className="pulse-ring" cx={end.x + 0.5} cy={end.y + 0.5} r={1.6} fill="none" stroke="#f5f1e8" strokeWidth={0.25} /><rect x={end.x - 0.8} y={end.y - 0.8} width={2.6} height={2.6} fill="#B85C43" stroke="#f5f1e8" strokeWidth={0.35} /><text x={end.x + 2.8} y={end.y - 0.8} fontSize={2.2} fill="#f5f1e8" stroke={outline} strokeWidth={0.5} paintOrder="stroke" fontFamily="IBM Plex Mono">DEST</text></g>}
            {(inspect ?? hover) && <g stroke="#D3A24C" strokeWidth={0.22}>{(() => { const p = (inspect ?? hover)!; return <><line x1={p.x + 0.5} x2={p.x + 0.5} y1={p.y - 3} y2={p.y + 4} /><line y1={p.y + 0.5} y2={p.y + 0.5} x1={p.x - 3} x2={p.x + 4} /></>; })()}</g>}
          </svg>
          <div className="absolute bottom-0 left-0 right-0 flex justify-between px-1 font-mono text-[10px] text-ink/75 pointer-events-none" aria-hidden="true">{[0, 1, 2, 3, 4].map((k) => <span key={k} className="[text-shadow:0_0_3px_#241b17]">{(MAP_W_KM * k / 4).toFixed(1)}</span>)}<span className="[text-shadow:0_0_3px_#241b17]">km</span></div>
          <div className="absolute top-0 bottom-0 left-0 flex flex-col justify-between py-1 pl-1 font-mono text-[10px] text-ink/75 pointer-events-none" aria-hidden="true">{[0, 1, 2, 3].map((k) => <span key={k} className="[text-shadow:0_0_3px_#241b17]">{(MAP_H_KM * k / 3).toFixed(1)}</span>)}</div>
        </div>
      </div>
      <div className="absolute top-2 left-7 flex items-center gap-2 font-mono text-[10px] text-ink/85 pointer-events-none" aria-hidden="true"><svg width={14} height={18} viewBox="-7 -9 14 18"><path d="M0 -8 L3.5 4 L0 2 L-3.5 4 Z" fill="#f5f1e8" /></svg>N · HiRISE DTM · {CELL_M.toFixed(0)} m/cell</div>
      <div className="absolute top-2 right-2 font-mono text-[11px] bg-ink/92 text-fg border border-line-strong rounded-sm px-2 py-1.5 min-w-44 pointer-events-none">
        {hover ? (T.nodata[hi] ? <div className="text-dim">x{hover.x} y{hover.y} · UNKNOWN / insufficient data</div> : <div className="grid grid-cols-2 gap-x-3"><span className="text-dim">CELL</span><span>{hover.x},{hover.y}</span><span className="text-dim">ELEVATION</span><span>{T.elev[hi].toFixed(0)} m</span><span className="text-dim">DERIVED SLOPE</span><span>{T.slope[hi].toFixed(1)}°</span><span className="text-dim">ROUGHNESS</span><span>{T.rough[hi].toFixed(2)}</span><span className="text-dim">UNCERTAINTY</span><span>{T.unc[hi].toFixed(2)}</span></div>) : <span className="text-dim">HOVER OR USE ARROW KEYS</span>}
      </div>
      {!ready && <div className="absolute inset-0 bg-map flex flex-col items-center justify-center gap-4 z-10"><div className="skeleton-dark w-[70%] max-w-xl aspect-[120/76] rounded-sm" /><p role="status" className="font-mono text-[12px] tracking-[0.08em] text-ink/80">{loadingLabel}</p></div>}
    </div>
  );
}

// ---------- Charts ----------
function Profile({ route, kind, h = 96 }: { route: Route; kind: "elev" | "slope" | "cost"; h?: number }) {
  const { T, weights } = useStore();
  const vals = route.path.map((p) => { const i = p.y * W + p.x; if (kind === "elev") return T.elev[i]; if (kind === "slope") return T.slope[i]; const s = weights.s + weights.r + weights.u + weights.h; return (weights.s * T.slope[i] / MAX_SLOPE + weights.r * T.rough[i] + weights.u * T.unc[i] + weights.h) / s; });
  const mn = Math.min(...vals), mx = Math.max(...vals), n = vals.length;
  const y = (v: number) => h - 6 - ((v - mn) / (mx - mn || 1)) * (h - 14);
  const pts = vals.map((v, k) => `${(k / (n - 1)) * 100},${y(v)}`).join(" ");
  const d = (dp: number) => (kind === "cost" ? mn.toFixed(dp) : mn.toFixed(0));
  return (
    <figure>
      <figcaption className="flex justify-between font-mono text-[11px] text-dim mb-1"><span>{kind === "elev" ? "ELEVATION (m)" : kind === "slope" ? "DERIVED SLOPE (°)" : "CELL COST C_i"}</span><span>{d(2)} to {kind === "cost" ? mx.toFixed(2) : mx.toFixed(0)}</span></figcaption>
      <svg key={route.cost} viewBox={`0 0 100 ${h}`} preserveAspectRatio="none" className="reveal w-full border border-line bg-ink rounded-sm" style={{ height: h }} role="img" aria-label={`${kind} profile along the ${route.mode} candidate route`}>
        {[0.25, 0.5, 0.75].map((f) => <line key={f} x1={0} x2={100} y1={h * f} y2={h * f} stroke="#d9d4c9" strokeWidth={1} vectorEffect="non-scaling-stroke" />)}
        {kind === "slope" && MAX_SLOPE >= mn && MAX_SLOPE <= mx && <line x1={0} x2={100} y1={y(MAX_SLOPE)} y2={y(MAX_SLOPE)} stroke="#964630" strokeDasharray="4 3" strokeWidth={1} vectorEffect="non-scaling-stroke" />}
        <polyline points={`0,${h} ${pts} 100,${h}`} fill={ROUTE_C[route.mode]} fillOpacity={0.18} stroke="none" />
        <polyline points={pts} fill="none" stroke={ROUTE_DEEP[route.mode]} strokeWidth={1.6} vectorEffect="non-scaling-stroke" strokeDasharray={route.mode === "SAFEST" ? undefined : route.mode === "FASTEST" ? "6 3" : "1 4"} strokeLinecap="round" />
      </svg>
      <div className="flex justify-between font-mono text-[10px] text-dim mt-1"><span>0 km</span><span>{(route.dist / 2000).toFixed(1)}</span><span>{(route.dist / 1000).toFixed(1)} km</span></div>
    </figure>
  );
}

// ---------- Datasets ----------
type Dataset = { id: string; mission: string; instrument: string; purpose: string; res: string; coverage: string; processing: string; source: string; version: string; limits: string };
const DATASETS: Dataset[] = [
  { id: "MOLA", mission: "Mars Global Surveyor", instrument: "Mars Orbiter Laser Altimeter", purpose: "Global elevation", res: "~463 m/px gridded", coverage: "Global", processing: "Reproject, resample, slope derivation", source: "PDS Geosciences Node", version: "MEGDR (to be pinned)", limits: "Too coarse for rover-scale hazards." },
  { id: "HiRISE", mission: "Mars Reconnaissance Orbiter", instrument: "High Resolution Imaging Science Experiment", purpose: "Hazard mapping, DTMs", res: "~0.25 to 0.5 m/px", coverage: "Small fraction of surface", processing: "Stereo DTM, roughness", source: "PDS Imaging Node / UA HiRISE", version: "To be pinned per product", limits: "Sparse coverage; gaps are UNKNOWN." },
  { id: "CTX", mission: "Mars Reconnaissance Orbiter", instrument: "Context Camera", purpose: "Regional context", res: "~6 m/px", coverage: "Near-global", processing: "Mosaic, co-registration", source: "PDS Imaging Node", version: "To be pinned", limits: "Imagery only unless stereo processed." },
  { id: "THEMIS", mission: "Mars Odyssey", instrument: "Thermal Emission Imaging System", purpose: "Thermal inertia", res: "~100 m/px (IR)", coverage: "Near-global", processing: "Thermal inertia proxy", source: "ASU / PDS", version: "To be pinned", limits: "Indirect proxy for surface properties." },
  { id: "CRISM", mission: "Mars Reconnaissance Orbiter", instrument: "Compact Reconnaissance Imaging Spectrometer", purpose: "Mineralogy", res: "~18 to 36 m/px", coverage: "Targeted", processing: "Spectral parameter maps", source: "PDS Geosciences Node", version: "To be pinned", limits: "Detections need expert validation." },
  { id: "ROVER", mission: "MSL / Mars 2020", instrument: "Traverse & engineering data", purpose: "Validation", res: "Path-level", coverage: "Gale, Jezero", processing: "Comparison to modeled cost", source: "PDS / mission archives", version: "To be pinned", limits: "Only two sites; limited generalisation." },
];
const SYNTH: Dataset = { id: "D3-WINDOW", mission: "MRO", instrument: "HiRISE (stereo DTM, USGS controlled)", purpose: "Terrain for slope, roughness and routing", res: `${CELL_M.toFixed(0)} m planning cell (from ~4 m resampling of a ~1 m DTM)`, coverage: `${W} × ${H} cells, ${MAP_W_KM.toFixed(1)} × ${MAP_H_KM.toFixed(1)} km window of DTEEC_045994_1985_046060_1985_U01 near Jezero Crater`, processing: "Decoded with a stdlib COG reader, overview-resampled, cropped to a data-complete window, 4x4 block-averaged. Slope (central differences) and roughness derived; uncertainty is modeled.", source: "USGS Astrogeology STAC, mro_hirise_socet_dtms (CC0)", version: "DTEEC_045994_1985_046060_1985_U01", limits: "Not a hazard-grade product: coarse resampling hides rocks and small slopes. Mission, targets, risk, time and pressure are simulated." };
const PROV_FIELDS: [string, keyof Dataset][] = [["NASA source", "source"], ["Mission", "mission"], ["Instrument", "instrument"], ["Resolution", "res"], ["Coverage", "coverage"], ["Processing", "processing"], ["Version", "version"], ["Limitations", "limits"]];
function Provenance({ d, tag }: { d: Dataset; tag?: Label }) {
  return (
    <div>
      <div className="flex items-center justify-between gap-2 mb-2"><span className="font-mono text-[13px] text-mars-deep">{d.id}</span>{tag && <Tag l={tag} />}</div>
      <dl className="text-[13px]">{PROV_FIELDS.map(([k, f]) => <div key={k} className="grid grid-cols-[92px_1fr] gap-2 py-1.5 border-b border-line/70 last:border-0"><dt className="font-mono text-[11px] tracking-[0.08em] text-dim uppercase pt-[2px]">{k}</dt><dd className="text-fg/90">{d[f]}</dd></div>)}</dl>
    </div>
  );
}

// ---------- Shell ----------
const NAV: [string, string][] = [["/planner", "Planner"], ["/explorer", "Explorer"], ["/routes", "Routes"], ["/follow", "Follow"], ["/immersive", "3D Map"], ["/science", "Science"], ["/mission/ARES-01", "Mission"], ["/data", "Data"], ["/methodology", "Method"], ["/about", "About"]];
function Shell({ path, children }: { path: string; children: React.ReactNode }) {
  const [menu, setMenu] = useState(false);
  useEffect(() => setMenu(false), [path]);
  const isOn = (p: string) => path.startsWith(p.split("/").slice(0, 2).join("/"));
  const full = path.startsWith("/planner") || path.startsWith("/explorer") || path.startsWith("/immersive");
  return (
    <div className="min-h-full flex flex-col">
      <nav aria-label="Primary" className="h-[52px] shrink-0 border-b border-line flex items-center px-4 gap-6 bg-ink/95 backdrop-blur-sm sticky top-0 z-30">
        <A to="/" className="flex items-center gap-2.5" ><BrandMark /><span className="font-mono font-medium tracking-[0.18em] text-[14px]">MARS-X</span></A>
        <div className="hidden md:flex gap-0.5">{NAV.map(([p, n]) => <A key={p} to={p} className={`font-mono text-[12px] tracking-[0.1em] uppercase px-2.5 py-1.5 border-b-2 ${isOn(p) ? "border-mars text-fg" : "border-transparent text-dim hover:text-fg"}`}>{n}</A>)}</div>
        <div className="ml-auto hidden lg:block font-mono text-[11px] tracking-[0.06em] text-mars-deep">HiRISE DTM · SIMULATED MISSION</div>
        <button className="md:hidden ml-auto font-mono text-[12px] tracking-[0.12em] border border-line-strong rounded-sm px-3 py-1.5" aria-expanded={menu} aria-controls="mobile-menu" onClick={() => setMenu((m) => !m)}>{menu ? "CLOSE" : "MENU"}</button>
      </nav>
      {menu && <div id="mobile-menu" className="md:hidden fixed inset-x-0 top-[52px] z-30 bg-ink border-b border-line-strong shadow-float grid grid-cols-2">{NAV.map(([p, n]) => <A key={p} to={p} className={`font-mono text-[13px] tracking-[0.1em] uppercase px-4 py-3.5 border-b border-line ${isOn(p) ? "text-mars-deep" : "text-fg"}`}>{n}</A>)}</div>}
      <div className="flex-1 flex flex-col">{children}</div>
      {full ? <div className="hidden lg:flex no-print border-t border-line px-4 py-1.5 font-mono text-[10px] text-dim gap-4"><span>Terrain: USGS HiRISE DTM (DERIVED), mission layers simulated</span><A to="/data" className="underline underline-offset-2 hover:text-fg">Data provenance</A><span className="ml-auto">Candidate routes only. Safety not certified.</span></div> : <Footer />}
    </div>
  );
}
function Footer() {
  return (
    <footer className="border-t border-line bg-panel mt-16 no-print">
      <div className="max-w-6xl mx-auto px-6 py-10 grid md:grid-cols-3 gap-8 text-[13px] leading-relaxed text-fg/85">
        <div><Eyebrow className="mb-2">Data attribution</Eyebrow><p>Globe imagery: Viking MDIM 2.1 colorized global mosaic, NASA / USGS Astrogeology Science Center, public domain. Instrument metadata on the <A to="/data" className="underline underline-offset-2">Data page</A> is credited to the NASA Planetary Data System and mission teams. Terrain in the planner is synthetic.</p></div>
        <div><Eyebrow className="mb-2">Privacy</Eyebrow><p>No accounts, cookies or analytics. Routes are computed in your browser and nothing you select is sent anywhere. Typefaces are requested from Google Fonts, which receives your IP address as any font host would.</p></div>
        <div><Eyebrow className="mb-2">Scope</Eyebrow><p>Built for NASA Space Apps Challenge 2026. Not affiliated with or endorsed by NASA. All routes are candidate routes for research and education. Safety is not certified.</p></div>
      </div>
    </footer>
  );
}

// ---------- Landing ----------
function hasWebGL() { try { const c = document.createElement("canvas"); return !!(c.getContext("webgl2") || c.getContext("webgl")); } catch { return false; } }
class GlobeBoundary extends Component<{ fallback: React.ReactNode; children: React.ReactNode }, { err: boolean }> {
  state = { err: false };
  static getDerivedStateFromError() { return { err: true }; }
  render() { return this.state.err ? this.props.fallback : this.props.children; }
}
const STAGES: [string, string][] = [["PLANET", "Global mosaic"], ["REGION", "Jezero region"], ["TERRAIN", "HiRISE terrain model"], ["MISSION", "Opening the explorer"]];
const ANNOT = "font-mono text-[11px] tracking-[0.12em] text-fg";

function HeroGlobe({ fly, stage }: { fly: FlyTarget; stage: number | null }) {
  const reduce = useReducedMotion();
  const [ready, setReady] = useState(false);
  const [active, setActive] = useState(true);
  const [gl] = useState(hasWebGL);
  const box = useRef<HTMLDivElement>(null);
  const api = useRef<GlobeApi | null>(null);
  useEffect(() => {
    const el = box.current; if (!el || !("IntersectionObserver" in window)) return;
    const io = new IntersectionObserver(([e]) => setActive(e.isIntersecting), { threshold: 0.05 });
    io.observe(el); return () => io.disconnect();
  }, []);
  const still = <div role="img" aria-label="Mars, Viking color mosaic" className="w-[82%] aspect-square rounded-full bg-[url(/mars-color-1k.jpg)] bg-[length:300%_auto] bg-[position:30%_42%] shadow-float" />;
  const compact = typeof window !== "undefined" && window.innerWidth < 768;
  return (
    <figure className="relative w-full">
      <div ref={box} className="relative aspect-square max-h-[76vh] w-full mx-auto">
        {["top-0 left-0 border-t border-l", "top-0 right-0 border-t border-r", "bottom-0 left-0 border-b border-l", "bottom-0 right-0 border-b border-r"].map((c) => <span key={c} aria-hidden="true" className={`absolute w-4 h-4 border-line-strong ${c}`} />)}
        <div className="absolute inset-3 flex items-center justify-center">
          {gl ? (
            <GlobeBoundary fallback={still}>
              <Suspense fallback={null}>
                <MarsGlobe active={active} reduce={reduce} fly={fly} apiRef={api} onReady={() => setReady(true)} compact={compact} />
              </Suspense>
            </GlobeBoundary>
          ) : still}
          {gl && !ready && <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 pointer-events-none"><div className="skeleton rounded-full w-[70%] aspect-square" /><LoadingNote>Loading orbital imagery…</LoadingNote></div>}
        </div>
        <div className="absolute top-4 left-5 pointer-events-none"><div className={ANNOT}>MOLA</div><div className="text-[11px] text-dim">Global elevation, ~463 m/px</div></div>
        <div className="absolute top-4 right-5 text-right pointer-events-none"><div className={ANNOT}>CTX</div><div className="text-[11px] text-dim">Context imagery, ~6 m/px</div></div>
        <div className="absolute bottom-10 left-5 pointer-events-none"><div className={ANNOT}>ROVER DATA</div><div className="text-[11px] text-dim">Jezero, Gale</div></div>
        <div className="absolute bottom-10 right-5 text-right pointer-events-none"><div className={ANNOT}>SCIENCE TARGETS</div><div className="text-[11px] text-dim">Simulated in this build</div></div>
        {gl && !stage && stage !== 0 && <div className="absolute bottom-3 left-1/2 -translate-x-1/2 flex items-center gap-1 no-print">
          <button aria-label="Zoom out" onClick={() => api.current?.zoom(1.25)} className="w-8 h-8 font-mono text-[15px] border border-line-strong rounded-sm bg-ink/80 hover:bg-panel">−</button>
          <span className="font-mono text-[10px] tracking-[0.1em] text-dim px-2">DRAG TO ROTATE</span>
          <button aria-label="Zoom in" onClick={() => api.current?.zoom(0.8)} className="w-8 h-8 font-mono text-[15px] border border-line-strong rounded-sm bg-ink/80 hover:bg-panel">+</button>
        </div>}
        {stage !== null && <div role="status" aria-live="polite" className="absolute bottom-3 inset-x-6 fade-in">
          <ol className="flex justify-between gap-2 font-mono text-[11px] tracking-[0.12em]">{STAGES.map(([n], k) => <li key={n} className={`flex-1 border-t-2 pt-1.5 ${k <= stage ? "border-mars text-fg" : "border-line text-dim"}`}>{String(k + 1).padStart(2, "0")} {n}</li>)}</ol>
          <p className="mt-2 text-[12px] text-dim">{STAGES[stage][1]}</p>
        </div>}
      </div>
      <figcaption className="mt-3 text-[11px] leading-relaxed text-dim max-w-md">
        <span className="font-mono text-fg">FIG. 1</span> Viking MDIM 2.1 color mosaic (NASA / USGS) on a sphere. Gold dots are published landing sites; gold outlines are approximate regions; the thin arc is an illustrative trajectory, not a real traverse.
      </figcaption>
    </figure>
  );
}

function Landing() {
  const [fly, setFly] = useState<FlyTarget>(null);
  const [stage, setStage] = useState<number | null>(null);
  const [cover, setCover] = useState(false);
  const timers = useRef<number[]>([]);
  const reduce = useReducedMotion();
  useEffect(() => () => timers.current.forEach(clearTimeout), []);
  const explore = () => {
    if (stage !== null) return;
    if (reduce || !hasWebGL()) { arrivedFromGlobe = false; go("/explorer"); return; }
    setStage(0); setFly({ lat: 18.38, lon: 77.58, dist: 1.36 });
    const at = (ms: number, fn: () => void) => timers.current.push(window.setTimeout(fn, ms));
    at(650, () => setStage(1)); at(1300, () => setStage(2)); at(1900, () => setStage(3));
    at(2100, () => setCover(true));
    at(2450, () => { arrivedFromGlobe = true; go("/explorer"); });
  };
  const flow: [string, string, string][] = [
    ["Discover Mars", "/", "Orient on the globe: landing sites, regions and the data that covers them."],
    ["Explore terrain", "/explorer", "Read elevation, derived slope and roughness cell by cell in 2D."],
    ["Select a destination", "/planner", "Place a start and destination on the map."],
    ["Analyze science", "/science", "Browse candidate observation sites and add them to a mission."],
    ["Compare routes", "/routes", "Weigh safest, fastest and science-weighted candidates side by side."],
    ["Understand risks", "/methodology", "See the cost model, assumptions and what is treated as unknown."],
    ["Generate a mission plan", "/mission/ARES-01", "An explainable report for one candidate traverse."],
  ];
  const wk: { k: keyof Weights; n: string; c: string }[] = [{ k: "s", n: "Slope", c: "#B85C43" }, { k: "r", n: "Roughness", c: "#C9785D" }, { k: "u", n: "Uncertainty", c: "#75837B" }, { k: "h", n: "Distance", c: "#789BA8" }];
  const objs: [Mode, string, Weights][] = [["SAFEST", "Minimises slope, roughness and uncertainty exposure. Accepts a longer distance.", MODE_W.SAFEST], ["FASTEST", "Minimises path length under the hard slope constraint. Carries more terrain exposure.", MODE_W.FASTEST], ["SCIENCE", "Discounts cost near high-value targets. Trades distance for observation opportunity.", MODE_W.SCIENCE]];
  return (
    <div>
      <section className="sheet-lines border-b border-line">
        <div className="max-w-7xl mx-auto px-6 py-10 lg:py-6 grid lg:grid-cols-[minmax(0,5fr)_minmax(0,6fr)] gap-10 lg:gap-6 items-center lg:min-h-[calc(100dvh-52px)]">
          <div className="order-2 lg:order-1">
            <Eyebrow>NASA Space Apps Challenge 2026 · Interplanetary Survival Guide: Martian Map</Eyebrow>
            <h1 className="mt-6 text-[clamp(52px,7.5vw,104px)] leading-[0.95] tracking-[-0.03em]">MARS-X</h1>
            <p className="mt-3 font-serif italic font-light text-[clamp(20px,2.2vw,28px)] text-mars-deep">Interplanetary Surface Planning</p>
            <p className="mt-6 max-w-md text-[16px] leading-relaxed text-fg/85">Fuse NASA terrain, science, and exploration data into explainable candidate routes across Mars.</p>
            <div className="mt-9 flex flex-wrap gap-3">
              <Btn primary onClick={() => go("/planner")} disabled={stage !== null}>PLAN A MISSION</Btn>
              <Btn onClick={explore} disabled={stage !== null}>EXPLORE MARS</Btn>
            </div>
            <p className="mt-10 text-[12px] text-dim max-w-md leading-relaxed">Every value carries a provenance label.</p>
            <div className="mt-2 flex flex-wrap gap-1.5">{(["OBSERVED", "DERIVED", "MODELED", "UNKNOWN", "SIMULATED"] as Label[]).map((l) => <Tag key={l} l={l} />)}</div>
          </div>
          <div className="order-1 lg:order-2 max-w-[640px] w-full mx-auto"><HeroGlobe fly={fly} stage={stage} /></div>
        </div>
      </section>
      <div className={`fixed inset-0 z-[60] bg-ink pointer-events-none transition-opacity duration-300 ${cover ? "opacity-100" : "opacity-0"}`} aria-hidden="true" />

      <section className="max-w-6xl mx-auto px-6 pt-24 grid lg:grid-cols-[1fr_1.5fr] gap-12">
        <div><Eyebrow>From orbit to decision</Eyebrow><h2 className="mt-4 text-[34px] leading-tight">One workflow, seven steps.</h2><p className="mt-4 text-dim text-[14px] leading-relaxed max-w-sm">The globe is for orientation. Measurement, selection and routing happen on the 2D map, where distances and cells can be read precisely.</p></div>
        <ol className="border-t border-line">{flow.map(([t, p, d], k) => <li key={t} className="border-b border-line"><A to={p} className="grid grid-cols-[36px_1fr] sm:grid-cols-[36px_200px_1fr] gap-x-4 gap-y-1 py-4 hover:bg-panel px-1"><span className="font-mono text-[12px] text-dim pt-0.5">{String(k + 1).padStart(2, "0")}</span><span className="text-[15px] font-medium">{t}</span><span className="col-start-2 sm:col-start-3 text-[13px] text-dim leading-relaxed">{d}</span></A></li>)}</ol>
      </section>

      <section className="max-w-6xl mx-auto px-6 pt-24">
        <div className="grid lg:grid-cols-[1fr_1.5fr] gap-12">
          <div><Eyebrow>Why terrain is hard</Eyebrow><h2 className="mt-4 text-[34px] leading-tight">A rover drives between images it cannot fully trust.</h2></div>
          <dl className="grid sm:grid-cols-2 gap-x-10 gap-y-7 self-end">{[["Steep slopes", "Above 25° in this model a cell is impassable. The limit is a planning assumption."], ["Rough ground", "Wheel damage is a documented risk on Mars, so roughness is a cost term."], ["Data gaps", "Missing high-resolution coverage is UNKNOWN, never treated as safe."], ["Uneven science", "Valuable targets are scattered and compete with terrain risk."]].map(([a, b]) => <div key={a}><dt className="font-mono text-[12px] tracking-[0.1em] uppercase text-mars-deep">{a}</dt><dd className="mt-1.5 text-[14px] text-fg/85 leading-relaxed">{b}</dd></div>)}</dl>
        </div>
      </section>

      <section className="max-w-6xl mx-auto px-6 pt-24">
        <div className="flex items-end justify-between flex-wrap gap-3"><div><Eyebrow>Target datasets</Eyebrow><h2 className="mt-4 text-[34px] leading-tight">Built around NASA orbital data.</h2></div><A to="/data" className="font-mono text-[12px] tracking-[0.1em] underline underline-offset-4 decoration-line-strong hover:decoration-fg">FULL PROVENANCE</A></div>
        <div className="mt-8 overflow-x-auto border-t border-fg"><table className="w-full text-[13px]"><thead><tr className="text-left font-mono text-[11px] tracking-[0.1em] text-dim"><th className="font-normal py-2 pr-4">DATASET</th><th className="font-normal py-2 pr-4">MISSION</th><th className="font-normal py-2 pr-4">RESOLUTION</th><th className="font-normal py-2">USED FOR</th></tr></thead><tbody>{DATASETS.map((d) => <tr key={d.id} className="border-t border-line"><td className="py-2.5 pr-4 font-mono text-mars-deep">{d.id}</td><td className="py-2.5 pr-4 text-fg/85">{d.mission}</td><td className="py-2.5 pr-4 font-mono text-[12px]">{d.res}</td><td className="py-2.5 text-fg/85">{d.purpose}</td></tr>)}</tbody></table></div>
        <p className="mt-3 text-[12px] text-dim">This prototype plans on a real HiRISE terrain window. Most datasets above are not yet ingested; see the Data page for status and limitations.</p>
      </section>

      <section className="max-w-6xl mx-auto px-6 pt-24">
        <Eyebrow>Route objectives</Eyebrow>
        <h2 className="mt-4 text-[34px] leading-tight max-w-xl">Three ways to weigh the same terrain.</h2>
        <div className="mt-8 border-t border-fg">{objs.map(([m, d, w]) => { const tot = w.s + w.r + w.u + w.h; return (
          <div key={m} className="grid md:grid-cols-[180px_1fr_1fr] gap-x-8 gap-y-3 py-5 border-b border-line items-center">
            <div className="flex items-center gap-3 font-mono text-[14px] tracking-[0.08em]"><Swatch m={m} w={32} />{m}</div>
            <p className="text-[14px] text-fg/85 leading-relaxed">{d}</p>
            <div><div className="flex h-2.5 rounded-sm overflow-hidden" role="img" aria-label={`Cost weights: ${wk.map((x) => `${x.n} ${w[x.k]} percent`).join(", ")}`}>{wk.map((x) => <span key={x.k} style={{ width: `${(w[x.k] / tot) * 100}%`, background: x.c }} />)}</div><div className="mt-1.5 flex justify-between font-mono text-[10px] text-dim">{wk.map((x) => <span key={x.k}>{x.n.slice(0, 4).toUpperCase()} {w[x.k]}</span>)}</div></div>
          </div>); })}</div>
        <p className="mt-3 text-[12px] text-dim">Cost weights are planning assumptions, not validated parameters. SCIENCE also applies a cost discount near targets.</p>
      </section>
      <Footer />
    </div>
  );
}

// ---------- Planner ----------
const TERRAIN_LAYERS: [Layer, string][] = [["hillshade", "Hillshade"], ["elev", "Elevation"], ["slope", "Slope"], ["rough", "Roughness"], ["pressure", "Pressure (simulated)"]];
function Planner() {
  const S = useStore();
  const [busy, setBusy] = useState(false); const [stage, setStage] = useState(0); const [err, setErr] = useState("");
  const [sheet, setSheet] = useState<"setup" | "results" | null>(null);
  const [layer, setLayer] = useState<Layer>("hillshade");
  const timers = useRef<number[]>([]);
  useEffect(() => () => timers.current.forEach(clearTimeout), []);
  const pick = (p: Pt) => { if (!S.start || (S.start && S.end)) { S.setStart(p); S.setEnd(null); S.setRoutes({}); } else S.setEnd(p); setErr(""); };
  const run = () => {
    if (!S.start || !S.end) return; setBusy(true); setErr(""); setStage(0); setSheet(null);
    timers.current.push(window.setTimeout(() => setStage(1), 350), window.setTimeout(() => setStage(2), 700));
    timers.current.push(window.setTimeout(() => {
      const out: Partial<Record<Mode, Route | null>> = {};
      (["SAFEST", "FASTEST", "SCIENCE"] as Mode[]).forEach((m) => { out[m] = astar(S.T, S.start!, S.end!, m === "SCIENCE" ? S.weights : MODE_W[m], m); });
      S.setRoutes(out); setBusy(false); setSheet("results");
      if (!out[S.mode]) setErr("No valid route found in the selected terrain model.");
    }, 900));
  };
  const r = S.routes[S.mode];
  const cellInfo = (p: Pt | null) => p ? (S.T.nodata[p.y * W + p.x] ? "UNKNOWN" : `${p.x},${p.y} · ${S.T.elev[p.y * W + p.x].toFixed(0)} m`) : "not set";
  const stages = ["Processing elevation…", "Calculating candidate routes…", "Scoring science value…"];
  return (
    <div className="flex-1 flex flex-col lg:grid lg:grid-cols-[288px_minmax(0,1fr)_320px] lg:h-[calc(100dvh-52px-29px)]">
      <Sheet open={sheet === "setup"} onClose={() => setSheet(null)} title="Mission setup" className="lg:border-r lg:border-line">
        <Panel title="Mission setup">
          <Row k="Start" v={cellInfo(S.start)} />
          <Row k="Destination" v={cellInfo(S.end)} />
          <p className="text-[12px] text-dim mt-2" aria-live="polite">{!S.start ? "Select the map to place START." : !S.end ? "Select the map to place DESTINATION." : "Select again to reset."}</p>
        </Panel>
        <Panel title="Route objective">
          <div role="radiogroup" aria-label="Route objective" className="grid grid-cols-3 gap-1 lg:grid-cols-1">{(["SAFEST", "FASTEST", "SCIENCE"] as Mode[]).map((m) => <button key={m} role="radio" aria-checked={S.mode === m} onClick={() => S.setMode(m)} className={`border rounded-sm px-2.5 py-2 font-mono text-[11px] tracking-[0.08em] flex flex-col lg:flex-row items-center gap-1.5 lg:gap-2.5 ${S.mode === m ? "border-fg bg-fg text-ink" : "border-line-strong text-fg hover:bg-panel"}`}><span className={S.mode === m ? "rounded-sm bg-ink px-1 py-0.5" : ""}><Swatch m={m} w={26} /></span>{MODE_NAME[m]}</button>)}</div>
          <p className="text-[12px] text-dim mt-2">Candidates for all three objectives are computed together; the selected one is highlighted.</p>
        </Panel>
        <Panel title="Base layer">
          <label className="sr-only" htmlFor="planner-layer">Base layer</label>
          <select id="planner-layer" value={layer} onChange={(e) => setLayer(e.target.value as Layer)} className="w-full border border-line-strong rounded-sm bg-ink px-2 py-2 font-mono text-[12px]">{TERRAIN_LAYERS.map(([k, n]) => <option key={k} value={k}>{n}</option>)}</select>
        </Panel>
        <Panel title="Constraints" tag="MODELED">
          <Row k="Max slope" v={`${MAX_SLOPE}°`} />
          <Row k="Data gaps" v="impassable" />
          <Row k="Cell size" v={`${CELL_M} m`} />
        </Panel>
        <Btn primary className="w-full" disabled={!S.start || !S.end || busy} onClick={run}>{busy ? "CALCULATING…" : "GENERATE MISSION PLAN"}</Btn>
      </Sheet>
      <main className="relative flex flex-col min-h-0 h-[calc(100dvh-52px-56px)] lg:h-auto">
        <SynthBanner />
        <div className="relative flex-1 min-h-0"><MarsMap layer={layer} onPick={pick} highlight="ALL" loadingLabel="Loading terrain…" />
          {busy && <div className="absolute inset-0 bg-map/80 flex flex-col items-center justify-center gap-3 z-20 on-dark"><div className="w-56 h-[3px] skeleton-dark rounded-full" /><p role="status" className="font-mono text-[13px] tracking-[0.06em] text-ink">{stages[stage]}</p></div>}
        </div>
        <div className="border-t border-line px-3 py-2 flex flex-wrap gap-x-5 gap-y-1.5 font-mono text-[11px] text-fg">
          {(["SAFEST", "FASTEST", "SCIENCE"] as Mode[]).map((m) => <span key={m} className="flex items-center gap-1.5"><Swatch m={m} />{MODE_NAME[m]}</span>)}
          <span className="flex items-center gap-1.5"><Glyph k="way" />WAYPOINT</span><span className="flex items-center gap-1.5"><Glyph k="warn" />TERRAIN WARNING</span><span className="flex items-center gap-1.5"><Glyph k="sci" />SCIENCE TARGET (SIM)</span><span className="flex items-center gap-1.5"><Glyph k="nodata" />NO DATA</span>
        </div>
      </main>
      <Sheet open={sheet === "results"} onClose={() => setSheet(null)} title="Candidate route analysis" className="lg:border-l lg:border-line">
        {busy && <div className="space-y-3" aria-hidden="true"><Skeleton className="h-40" /><Skeleton className="h-24" /></div>}
        {!busy && err && <div className="border border-line rounded-md bg-paper p-3 text-[13px]">{err}<div className="text-dim mt-1 text-[12px]">Try different endpoints or a different objective. Endpoints inside data gaps or above max slope are rejected.</div></div>}
        {!busy && r && <>
          <Panel title={`Candidate route · ${r.mode}`} tag="MODELED">
            <Row k="Distance" v={fmtKm(r.dist)} l="DERIVED" />
            <Row k="Path cost J(P)" v={r.cost.toFixed(2)} l="MODELED" />
            <Row k="Max slope" v={r.maxSlope.toFixed(1) + "°"} l="DERIVED" />
            <Row k="Slope exposure" v={`${(r.exposure * 100).toFixed(0)} % > ${EXPOSURE_DEG}°`} l="DERIVED" />
            <Row k="Mean roughness" v={r.meanRough.toFixed(2)} l="DERIVED" />
            <Row k="Data confidence" v={r.confidence} l="MODELED" />
            <Row k="Safety" v={<span className="text-mars-deep">NOT CERTIFIED</span>} />
          </Panel>
          <Panel title="Elevation profile" tag="DERIVED"><Profile route={r} kind="elev" /></Panel>
          <Panel title="Science along route" tag="SIMULATED">{r.sciHits.length ? r.sciHits.map((t) => <Row key={t.id} k={t.name} v={t.value.toFixed(2)} />) : <p className="text-[13px] text-dim">No targets near the route.</p>}</Panel>
          <div className="flex gap-2"><Btn className="flex-1" onClick={() => go("/routes")}>COMPARE</Btn><Btn className="flex-1" onClick={() => go("/mission/ARES-01")}>REPORT</Btn></div>
        </>}
        {!busy && !r && !err && <Panel title="Route analysis"><p className="text-[13px] text-dim leading-relaxed">Place a start and destination, choose an objective, then generate. Distance, terrain cost, slope exposure, roughness, science value and data confidence appear here.</p></Panel>}
      </Sheet>
      <MobileBar items={[{ label: "SETUP", on: () => setSheet("setup"), active: sheet === "setup" }, { label: "RESULTS", on: () => setSheet("results"), active: sheet === "results" }]} />
    </div>
  );
}

// ---------- Explorer ----------
type LayerItem = { k: Layer | "targets" | "contours"; name: string; tag: Label; off?: string };
const LAYER_GROUPS: { g: string; items: LayerItem[] }[] = [
  { g: "Terrain", items: [{ k: "hillshade", name: "Hillshade", tag: "DERIVED" }, { k: "elev", name: "Elevation", tag: "DERIVED" }, { k: "slope", name: "Slope", tag: "DERIVED" }, { k: "rough", name: "Roughness", tag: "DERIVED" }, { k: "unc", name: "Data uncertainty", tag: "MODELED" }, { k: "pressure", name: "Pressure (relative)", tag: "SIMULATED" }, { k: "contours", name: "Contour lines (100 m)", tag: "DERIVED" }] },
  { g: "Imagery", items: [{ k: "hillshade", name: "CTX", tag: "UNKNOWN", off: "CTX" }, { k: "hillshade", name: "HiRISE", tag: "UNKNOWN", off: "HiRISE" }] },
  { g: "Science", items: [{ k: "targets", name: "Science targets", tag: "SIMULATED" }, { k: "hillshade", name: "Mineralogy", tag: "UNKNOWN", off: "CRISM" }, { k: "hillshade", name: "Observations", tag: "UNKNOWN", off: "mission data" }] },
  { g: "Exploration", items: [{ k: "hillshade", name: "Rover tracks", tag: "UNKNOWN", off: "ROVER" }, { k: "hillshade", name: "Landing sites", tag: "UNKNOWN", off: "mission data" }] },
  { g: "Environment", items: [{ k: "hillshade", name: "Temperature map", tag: "UNKNOWN", off: "THEMIS thermal; rover MEDA readings are point data only" }] },
];
const LAYER_NAME: Record<Layer, string> = { hillshade: "Hillshade", elev: "Elevation", slope: "Slope", rough: "Roughness", unc: "Data uncertainty", pressure: "Pressure (simulated)" };
const LAYER_UNITS: Record<Layer, [string, string]> = { hillshade: ["LOW ELEV", "HIGH ELEV"], elev: ["LOW", "HIGH"], slope: ["0°", `${MAX_SLOPE}°`], rough: ["SMOOTH", "ROUGH"], unc: ["LOW", "HIGH"], pressure: ["LOWER P", "HIGHER P"] };
function Explorer() {
  const { T } = useStore();
  const reduce = useReducedMotion();
  const arrive = useRef(arrivedFromGlobe && !reduce); useEffect(() => { arrivedFromGlobe = false; }, []);
  const [layer, setLayer] = useState<Layer>("hillshade"); const [targets, setTargets] = useState(true); const [contours, setContours] = useState(false);
  const [p, setP] = useState<Pt | null>({ x: 60, y: 38 });
  const [sheet, setSheet] = useState<"layers" | "inspector" | null>(null);
  const i = p ? p.y * W + p.x : 0, nd = p && T.nodata[i];
  const near = p ? TARGETS.filter((t) => Math.hypot(t.x - p.x, t.y - p.y) < 8) : [];
  const target = layer === "unc" ? null : DATASETS[0];
  return (
    <div className={`flex-1 flex flex-col lg:grid lg:grid-cols-[256px_minmax(0,1fr)_320px] lg:h-[calc(100dvh-52px-29px)] ${arrive.current ? "arrive" : ""}`}>
      <Sheet open={sheet === "layers"} onClose={() => setSheet(null)} title="Map layers" className="lg:border-r lg:border-line">
        <div role="group" aria-label="Map layers" className="space-y-3">{LAYER_GROUPS.map(({ g, items }) => (
          <div key={g}><Eyebrow className="mb-1">{g}</Eyebrow>
            {items.map((it) => {
              const off = !!it.off; const on = it.k === "targets" ? targets : it.k === "contours" ? contours : !off && layer === it.k;
              return <button key={g + it.name} disabled={off} aria-pressed={!off ? on : undefined} title={off ? `Target dataset: ${it.off}. Not ingested in this build.` : undefined}
                onClick={() => (it.k === "targets" ? setTargets((t) => !t) : it.k === "contours" ? setContours((c) => !c) : setLayer(it.k))}
                className={`w-full flex items-center justify-between gap-2 px-2 py-1.5 text-[13px] rounded-sm ${off ? "text-dim/80 cursor-not-allowed" : on ? "bg-fg text-ink" : "text-fg hover:bg-panel"}`}>
                <span className="flex items-center gap-2"><span aria-hidden="true" className={`w-2.5 h-2.5 border ${it.k === "targets" ? "rounded-none rotate-45" : "rounded-full"} ${on ? "bg-ink border-ink" : "border-line-strong"}`} />{it.name}</span>
                {off ? <span className="font-mono text-[10px] tracking-[0.08em] text-dim">NOT INGESTED</span> : <span className={on ? "opacity-80" : ""}><Tag l={it.tag} /></span>}
              </button>;
            })}
          </div>))}</div>
        <div className="border-t border-line pt-3"><Eyebrow className="mb-2">Legend · {LAYER_NAME[layer]}</Eyebrow><div className="h-2.5 rounded-sm border border-line" style={{ background: rampCss(layer) }} aria-hidden="true" /><div className="flex justify-between font-mono text-[10px] text-dim mt-1"><span>{LAYER_UNITS[layer][0]}</span><span>{LAYER_UNITS[layer][1]}</span></div><div className="flex items-center gap-2 mt-3 text-[12px] text-dim"><Glyph k="nodata" />Unknown / insufficient data</div></div>
      </Sheet>
      <main className="relative flex flex-col min-h-0 h-[calc(100dvh-52px-56px)] lg:h-auto"><SynthBanner /><div className="relative flex-1 min-h-0"><MarsMap layer={layer} onPick={setP} inspect={p} showTargets={targets} contours={contours} loadingLabel="Processing elevation…" /></div></main>
      <Sheet open={sheet === "inspector"} onClose={() => setSheet(null)} title="Inspector" className="lg:border-l lg:border-line">
        <Panel title="Location inspector" tag={nd ? "UNKNOWN" : "MODELED"}>
          {!p ? <p className="text-dim text-[13px]">Select a cell.</p> : nd ? <><Row k="Cell" v={`${p.x}, ${p.y}`} /><p className="text-[13px] mt-2">Unknown / insufficient data.</p><p className="text-[12px] text-dim mt-1">This cell is excluded from routing. Absence of data is not treated as safe.</p></> : <>
            <Row k="Cell" v={`${p.x}, ${p.y}`} />
            <Row k="Elevation" v={T.elev[i].toFixed(0) + " m"} l="DERIVED" />
            <Row k="Rel. pressure" v={pressureRel(T, i).toFixed(3)} l="SIMULATED" />
            <Row k="Derived slope" v={T.slope[i].toFixed(1) + "°"} l="DERIVED" />
            <Row k="Roughness" v={T.rough[i].toFixed(2)} l="DERIVED" />
            <Row k="Uncertainty" v={T.unc[i].toFixed(2)} l="MODELED" />
            <Row k="Traversable" v={T.slope[i] > MAX_SLOPE ? <span className="text-mars-deep">NO (slope)</span> : "within limits"} l="MODELED" />
          </>}
        </Panel>
        <Panel title="Nearby targets" tag="SIMULATED">{near.length ? near.map((t) => <Row key={t.id} k={`${t.id} ${t.name}`} v={t.value.toFixed(2)} />) : <p className="text-[13px] text-dim">None nearby.</p>}</Panel>
        <Panel title={`Data provenance · ${LAYER_NAME[layer]}`}>
          <Provenance d={SYNTH} tag="DERIVED" />
          {target && <details className="mt-3 border-t border-line pt-3"><summary className="cursor-pointer font-mono text-[12px] tracking-[0.08em] text-fg">TARGET DATASET: {target.id}</summary><div className="mt-3"><Provenance d={target} tag="UNKNOWN" /></div></details>}
        </Panel>
      </Sheet>
      <MobileBar items={[{ label: "LAYERS", on: () => setSheet("layers"), active: sheet === "layers" }, { label: "INSPECTOR", on: () => setSheet("inspector"), active: sheet === "inspector" }]} />
    </div>
  );
}

// ---------- Routes ----------
type Metric = { label: string; l: Label; note: string; get: (r: Route) => number; txt: (r: Route) => string; max?: number };
const METRICS: Metric[] = [
  { label: "Risk score (0-100)", l: "SIMULATED", note: "Weighted from peak slope, steep share, roughness, low confidence and time. Lower is better.", get: (r) => r.risk.score, txt: (r) => `${r.risk.score} · ${r.risk.level}`, max: 100 },
  { label: "Science score (0-100)", l: "SIMULATED", note: "Simulated target value passed along the route. Higher is better.", get: (r) => scienceScore(r), txt: (r) => String(scienceScore(r)), max: 100 },
  { label: "Est. time", l: "SIMULATED", note: `Slope-dependent walking speed model against a ${TIME_BUDGET_MIN} min budget.`, get: (r) => r.risk.timeMin, txt: (r) => `${r.risk.timeMin.toFixed(0)} min`, max: TIME_BUDGET_MIN },
  { label: "Distance", l: "DERIVED", note: "Shorter costs less time and energy.", get: (r) => r.dist, txt: (r) => fmtKm(r.dist) },
  { label: "Terrain cost J(P)", l: "MODELED", note: "Weighted sum of cell costs. Lower is easier.", get: (r) => r.cost, txt: (r) => r.cost.toFixed(2) },
  { label: "Slope exposure", l: "DERIVED", note: `Share of path cells steeper than ${EXPOSURE_DEG}°. Lower is better.`, get: (r) => r.exposure * 100, txt: (r) => `${(r.exposure * 100).toFixed(0)} %`, max: 100 },
  { label: "Mean roughness", l: "DERIVED", note: "Index from 0 to 1. Lower is better.", get: (r) => r.meanRough, txt: (r) => r.meanRough.toFixed(2), max: 1 },
  { label: "Science value", l: "SIMULATED", note: "Sum of simulated target values passed near the route. Higher is better.", get: (r) => r.sciValue, txt: (r) => r.sciValue.toFixed(2) },
  { label: "Data confidence", l: "MODELED", note: "One minus mean uncertainty along the route. Higher is better.", get: (r) => 1 - r.meanUnc, txt: (r) => `${(1 - r.meanUnc).toFixed(2)} · ${r.confidence}`, max: 1 },
];
function RoutesPage() {
  const S = useStore();
  const modes: Mode[] = ["SAFEST", "FASTEST", "SCIENCE"];
  const [sel, setSel] = useState<Mode>(S.mode);
  const [calc, setCalc] = useState(false);
  const recompute = () => { if (S.start && S.end) { setCalc(true); window.setTimeout(() => { S.setRoutes({ ...S.routes, SCIENCE: astar(S.T, S.start!, S.end!, S.weights, "SCIENCE") }); setCalc(false); }, 450); } };
  const r = S.routes[sel];
  const has = modes.some((m) => S.routes[m]);
  const why = (r: Route) => {
    const o: string[] = [];
    if (r.mode === "SAFEST") o.push(`Weighted to keep mean slope at ${r.meanSlope.toFixed(1)}° and avoid rough cells (mean ${r.meanRough.toFixed(2)}).`);
    if (r.mode === "FASTEST") o.push(`Distance term dominates; the route is ${fmtKm(r.dist)} with more terrain exposure (max ${r.maxSlope.toFixed(1)}°).`);
    if (r.mode === "SCIENCE") o.push(`Cost is discounted near targets; the route passes ${r.sciHits.length} candidate target(s).`);
    o.push(`Mean uncertainty ${r.meanUnc.toFixed(2)} gives data confidence ${r.confidence}.`);
    o.push("Cells with slope above 25° or no data are excluded as hard constraints.");
    return o;
  };
  return (
    <div className="max-w-6xl w-full mx-auto px-6 py-10 space-y-8">
      <div className="flex items-end justify-between flex-wrap gap-4"><div><Eyebrow>Route comparison</Eyebrow><h1 className="text-[34px] mt-2 leading-tight">Candidate routes</h1></div></div>
      <SynthBanner />
      {!has ? <Panel title="No routes"><p className="text-dim text-[14px]">Generate a plan in the <A to="/planner" className="text-mars-deep underline underline-offset-2">Planner</A> first.</p></Panel> : <>
        <section aria-label="Comparison">
          <div className="grid md:grid-cols-2 gap-x-12 gap-y-7">{METRICS.map((m) => {
            const vals = modes.map((k) => (S.routes[k] ? m.get(S.routes[k]!) : 0)); const mx = m.max ?? Math.max(...vals, 1e-9);
            return (
              <div key={m.label}>
                <div className="flex items-center justify-between gap-2"><h3 className="font-sans text-[14px] font-medium tracking-normal">{m.label}</h3><Tag l={m.l} /></div>
                <p className="text-[12px] text-dim mb-2">{m.note}</p>
                <div className="space-y-1.5">{modes.map((k, j) => { const x = S.routes[k]; return (
                  <button key={k} onClick={() => setSel(k)} aria-pressed={sel === k} className={`w-full grid grid-cols-[88px_1fr_104px] items-center gap-2 text-left rounded-sm px-1 py-0.5 ${sel === k ? "bg-panel" : "hover:bg-panel/60"}`}>
                    <span className="flex items-center gap-1.5 font-mono text-[11px]"><Swatch m={k} w={18} />{MODE_NAME[k]}</span>
                    <span className="h-3 bg-line/70 rounded-sm overflow-hidden">{x && <span className="block h-full rounded-sm transition-[width] duration-700" style={{ width: `${Math.max(2, (vals[j] / mx) * 100)}%`, background: ROUTE_C[k] }} />}</span>
                    <span className="font-mono text-[11px] text-right">{x ? m.txt(x) : "no route"}</span>
                  </button>); })}</div>
              </div>);
          })}</div>
        </section>
        <div className="overflow-x-auto border-t border-fg">
          <table className="w-full text-[12px] font-mono">
            <caption className="sr-only">Candidate route metrics</caption>
            <thead className="text-dim text-[11px] tracking-[0.1em]"><tr>{["OBJECTIVE", "DISTANCE", "COST J(P)", "MAX SLOPE", "MEAN ROUGH", "GAIN", "TARGETS", "CONFIDENCE", "SAFETY"].map((h) => <th key={h} scope="col" className="text-left px-3 py-2 font-normal">{h}</th>)}</tr></thead>
            <tbody>{modes.map((m) => { const x = S.routes[m]; return <tr key={m} onClick={() => setSel(m)} className={`border-t border-line cursor-pointer ${sel === m ? "bg-panel" : "hover:bg-panel/60"}`}><th scope="row" className="px-3 py-2.5 text-left font-normal"><span className="inline-flex items-center gap-2"><Swatch m={m} w={22} />{m}</span></th>{x ? <><td className="px-3">{fmtKm(x.dist)}</td><td className="px-3">{x.cost.toFixed(2)}</td><td className="px-3">{x.maxSlope.toFixed(1)}°</td><td className="px-3">{x.meanRough.toFixed(2)}</td><td className="px-3">{x.elevGain.toFixed(0)} m</td><td className="px-3">{x.sciHits.length}</td><td className="px-3">{x.confidence}</td><td className="px-3 text-mars-deep">NOT CERTIFIED</td></> : <td colSpan={8} className="px-3 text-dim">No valid route found in the selected terrain model.</td>}</tr>; })}</tbody>
          </table>
        </div>
        {r && <div className="grid lg:grid-cols-[1.5fr_1fr] gap-8">
          <div className="space-y-5">
            <div className="h-80 border border-line rounded-md overflow-hidden"><MarsMap highlight={sel} loadingLabel="Loading terrain…" /></div>
            <div className="grid md:grid-cols-3 gap-4"><div><Eyebrow className="mb-1">Elevation</Eyebrow><Profile route={r} kind="elev" /></div><div><Eyebrow className="mb-1">Terrain slope</Eyebrow><Profile route={r} kind="slope" /></div><div><Eyebrow className="mb-1">Cell cost</Eyebrow><Profile route={r} kind="cost" /></div></div>
          </div>
          <div className="space-y-5">
            <Panel title="Why this route?" tag="MODELED"><ul className="space-y-2 text-[13px] text-fg/90 leading-relaxed">{why(r).map((s) => <li key={s} className="pl-3 relative before:content-['–'] before:absolute before:left-0 before:text-dim">{s}</li>)}</ul></Panel>
            <Panel title="Cost weights · assumptions" tag="MODELED">
              <p className="text-[12px] text-dim mb-3">Planning assumptions, not validated parameters. Applied to the SCIENCE objective.</p>
              {([["s", "Slope"], ["r", "Roughness"], ["u", "Uncertainty"], ["h", "Distance"]] as [keyof Weights, string][]).map(([k, n]) => <div key={k} className="mb-3"><div className="flex justify-between text-[13px]"><label htmlFor={"w-" + k}>{n}</label><span className="font-mono">{S.weights[k]}</span></div><input id={"w-" + k} type="range" min={0} max={100} value={S.weights[k]} onChange={(e) => S.setWeights({ ...S.weights, [k]: +e.target.value })} className="w-full accent-mars-deep" /></div>)}
              <div className="flex gap-2"><Btn primary className="flex-1" disabled={calc} onClick={recompute}>{calc ? "CALCULATING…" : "RECOMPUTE"}</Btn><Btn onClick={() => S.setWeights(DEFAULT_W)}>RESET</Btn></div>
              {calc && <div className="mt-2"><LoadingNote>Calculating candidate routes…</LoadingNote></div>}
            </Panel>
          </div>
        </div>}
      </>}
    </div>
  );
}

// ---------- Science ----------
function SciencePage() {
  const S = useStore();
  const ready = useDelay(500);
  return (
    <div className="max-w-6xl w-full mx-auto px-6 py-10">
      <div className="flex items-end justify-between flex-wrap gap-4 mb-6"><div><Eyebrow>Science targets</Eyebrow><h1 className="text-[34px] mt-2 leading-tight">Candidate observation sites</h1></div><Tag l="SIMULATED" /></div>
      <p className="text-[13px] text-dim max-w-xl mb-6">All targets are simulated placeholders at demonstration locations on the real terrain. They illustrate how science value enters the route cost; they are not detections or published features.</p>
      {!ready ? <div className="space-y-3"><LoadingNote>Loading science observations…</LoadingNote>{Array.from({ length: 5 }).map((_, k) => <Skeleton key={k} className="h-16" />)}</div> : (
        <div className="border-t border-fg fade-in">{TARGETS.map((t) => { const on = S.mission.some((m) => m.id === t.id); return (
          <div key={t.id} className="grid md:grid-cols-[56px_1.4fr_1fr_120px] gap-x-6 gap-y-2 py-4 border-b border-line items-center">
            <span className="font-mono text-[13px] text-sci">{t.id}</span>
            <div><h3 className="font-sans text-[16px] font-medium tracking-normal">{t.name}</h3><div className="text-[12px] text-dim">{t.type}</div><p className="mt-1.5 text-[13px] text-fg/80 leading-relaxed">{t.note}</p></div>
            <div><div className="flex justify-between font-mono text-[11px] text-dim"><span>VALUE {t.value.toFixed(2)}</span><span>CONF {t.conf}</span><span>CELL {t.x},{t.y}</span></div><div className="mt-1.5 h-1.5 bg-line rounded-full" role="img" aria-label={`Science value ${t.value.toFixed(2)} of 1`}><div className="h-full bg-atmos rounded-full" style={{ width: `${t.value * 100}%` }} /></div></div>
            <Btn primary={!on} aria-pressed={on} onClick={() => S.toggleTarget(t)}>{on ? "REMOVE" : "ADD"}</Btn>
          </div>); })}</div>)}
    </div>
  );
}

// ---------- Mission ----------
function MissionPage({ id }: { id: string }) {
  const S = useStore(); const r = S.routes[S.mode];
  return (
    <div className="max-w-5xl w-full mx-auto px-6 py-10 space-y-6">
      <div className="flex flex-wrap justify-between gap-4 items-end border-b border-fg pb-5">
        <div><Eyebrow>Mission report</Eyebrow><h1 className="font-mono text-[44px] font-normal mt-2 tracking-tight">{id}</h1><div className="mt-1 text-dim text-[13px]">Objective: {S.mode} · Generated {new Date().toISOString().slice(0, 10)}</div></div>
        <div className="text-right"><div className="font-mono text-[12px] tracking-[0.14em] border border-fg px-3 py-1.5 rounded-sm">CANDIDATE ROUTE</div><div className="font-mono text-[11px] text-mars-deep mt-2">SAFETY NOT CERTIFIED</div></div>
      </div>
      <SynthBanner />
      {!r ? <Panel title="No route"><p className="text-dim text-[14px]">No candidate route computed. Use the <A to="/planner" className="text-mars-deep underline underline-offset-2">Planner</A>.</p></Panel> : <>
        <dl className="grid grid-cols-2 md:grid-cols-4 border-y border-line">{([["Distance", fmtKm(r.dist), "DERIVED"], ["Max slope", r.maxSlope.toFixed(1) + "°", "DERIVED"], ["Elevation gain", r.elevGain.toFixed(0) + " m", "DERIVED"], ["Data confidence", r.confidence, "MODELED"]] as [string, string, Label][]).map(([k, v, l], n) => <div key={k} className={`py-4 px-3 ${n ? "md:border-l border-line" : ""}`}><dt className="flex justify-between gap-2 items-start"><Eyebrow>{k}</Eyebrow></dt><dd className="font-mono text-[22px] mt-2">{v}</dd><div className="mt-2"><Tag l={l} /></div></div>)}</dl>
        <div className="h-96 border border-line rounded-md overflow-hidden"><MarsMap highlight={S.mode} loadingLabel="Loading terrain…" /></div>
        <div className="grid md:grid-cols-2 gap-6">
          <Panel title="Elevation profile" tag="DERIVED"><Profile route={r} kind="elev" h={120} /></Panel>
          <Panel title="Science objectives" tag="SIMULATED">{[...new Map([...r.sciHits, ...S.mission].map((t) => [t.id, t])).values()].map((t) => <Row key={t.id} k={`${t.id} ${t.name}`} v={r.sciHits.includes(t) ? "on route" : <span className="text-dim">off route</span>} />)}{!r.sciHits.length && !S.mission.length && <p className="text-dim text-[13px]">None.</p>}</Panel>
        </div>
        <div className="grid md:grid-cols-2 gap-6">
          <RiskPanel r={r} />
          <Panel title="Landmarks" tag="SIMULATED">{pickLandmarks(S.T, r).map((l) => <Row key={l.n} k={`${l.n}. ${l.name}`} v={l.next ? `${fmtKm(l.next.distM)} ${cardinal(l.next.bearing)}` : "end"} />)}<div className="mt-3"><A to="/follow" className="font-mono text-[12px] text-mars-deep underline underline-offset-2">FOLLOW THIS ROUTE</A></div></Panel>
        </div>
        <Panel title="Risks & limitations">
          <ul className="text-[13px] space-y-1.5 text-fg/90 list-disc pl-5 leading-relaxed">
            <li>Terrain is a ~{CELL_M.toFixed(0)} m resampling of a USGS HiRISE DTM window. Science targets, risk, time and pressure are simulated.</li>
            <li>Sub-cell hazards (rocks, sand traps) below {CELL_M} m resolution are UNKNOWN.</li>
            <li>Mean uncertainty along the route: {r.meanUnc.toFixed(2)}. Higher-resolution data would be required before any operational use.</li>
            <li>Risk, time and pressure values are simulation assumptions. The pressure layer is relative and modelled from elevation, not measured.</li>
            <li>The route is a candidate for human review. It is not a safe or certified path.</li>
          </ul>
        </Panel>
        <div className="flex gap-2 no-print"><Btn onClick={() => window.print()}>PRINT REPORT</Btn><Btn onClick={() => go("/routes")}>COMPARE ROUTES</Btn></div>
      </>}
    </div>
  );
}

function RiskPanel({ r }: { r: Route }) {
  const k = r.risk;
  return <Panel title="Risk score" tag="SIMULATED">
    <div className="flex items-baseline gap-3"><span className="font-mono text-[34px]">{k.score}</span><span className="font-mono text-[11px] text-dim">/ 100</span><span className={`font-mono text-[11px] tracking-[0.1em] border rounded-sm px-1.5 py-0.5 ${RISK_C[k.level]}`}>{k.level}</span></div>
    <div className="mt-3 space-y-2">{k.parts.map((p) => <div key={p.k}><div className="flex justify-between text-[12px]"><span>{p.label}</span><span className="font-mono text-dim">{(p.v * 100).toFixed(0)}% × {p.w}</span></div><div className="h-1.5 bg-line/70 rounded-sm"><div className="h-full rounded-sm bg-mars" style={{ width: `${p.v * 100}%` }} /></div></div>)}</div>
    <p className="text-[11px] text-dim mt-3">Weights and thresholds are simulation assumptions, not certified limits. Science score {scienceScore(r)}/100.</p>
  </Panel>;
}

// ---------- Immersive 3D map ----------
const VIEWS: [View3D, string, Label][] = [["natural", "Natural", "DERIVED"], ["slope", "Slope", "DERIVED"], ["contours", "Contours", "DERIVED"], ["pressure", "Pressure", "SIMULATED"]];
function ImmersivePage() {
  const S = useStore();
  const [view, setView] = useState<View3D>("natural"), [cam, setCam] = useState<Cam>(() => (window.location.hash.includes("walk") ? "walk" : "orbit")), [exag, setExag] = useState(2.5);
  const [sunEl, setSunEl] = useState(24), [sunAz, setSunAz] = useState(250), [playing, setPlaying] = useState(false), [speed, setSpeed] = useState(40);
  const [step, setStep] = useState(() => +(window.location.hash.match(/step=(\d)/)?.[1] ?? 0)), [probe, setProbe] = useState<Probe | null>(null), [ready, setReady] = useState(false), [hud, setHud] = useState(true), [resetKey, setResetKey] = useState(0);
  const demo = useMemo(() => {
    if (S.routes[S.mode]) return null;
    const ok = (x: number, y: number) => S.T.slope[y * W + x] < MAX_SLOPE;
    const near = (x: number, y: number) => { for (let r = 0; r < 14; r++) for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) { const a = x + dx, b = y + dy; if (a >= 0 && b >= 0 && a < W && b < H && ok(a, b)) return { x: a, y: b }; } return { x, y }; };
    return astar(S.T, near(8, 38), near(110, 40), MODE_W[S.mode], S.mode);
  }, [S.T, S.routes, S.mode]);
  const route = S.routes[S.mode] ?? demo;
  const lms = useMemo(() => (route ? pickLandmarks(S.T, route) : []), [S.T, route]);
  const prevRoute = useRef(route);
  useEffect(() => { if (prevRoute.current !== route) { prevRoute.current = route; setStep(0); } }, [route]);
  const walk = cam === "walk" && !!route;
  const i = probe ? Math.min(H - 1, Math.round(probe.fy * (H - 1))) * W + Math.min(W - 1, Math.round(probe.fx * (W - 1))) : -1;
  const cur = lms[step];
  const chip = (on: boolean) => `px-2.5 py-1.5 font-mono text-[11px] tracking-[0.08em] rounded-sm border ${on ? "bg-fg text-ink border-fg" : "border-line-strong text-fg bg-ink/80 hover:bg-panel"}`;
  return (
    <div className="relative flex-1 min-h-[560px] lg:h-[calc(100dvh-52px-29px)] bg-map overflow-hidden">
      <div className="absolute inset-0">
        <Suspense fallback={<div role="status" className="absolute inset-0 flex items-center justify-center font-mono text-[12px] text-ink/85">Preparing 3D renderer…</div>}>
          <Terrain3D meta={JEZERO_META} T={S.T} view={view} exag={walk ? 1 : exag} sunEl={sunEl} sunAz={sunAz} cam={walk ? "walk" : "orbit"} playing={playing} speed={speed} route={route} landmarks={lms} step={step} onReach={(k) => setStep(k)} onProbe={setProbe} resetKey={resetKey} onReady={() => setReady(true)} />
        </Suspense>
      </div>
      <div className="absolute top-0 inset-x-0"><SynthBanner /></div>
      <button className="lg:hidden absolute top-10 left-2 z-20 font-mono text-[11px] tracking-[0.1em] bg-ink border border-line-strong rounded-sm px-2.5 py-1.5" aria-expanded={hud} onClick={() => setHud((v) => !v)}>{hud ? "HIDE CONTROLS" : "CONTROLS"}</button>
      {hud && <div className="absolute top-14 lg:top-10 left-2 z-10 w-[min(92vw,300px)] max-h-[calc(100%-7rem)] overflow-y-auto bg-ink/92 backdrop-blur-sm border border-line-strong rounded-md shadow-float p-3 space-y-3">
        <div><Eyebrow className="mb-1.5">Camera</Eyebrow><div className="flex gap-1.5"><button className={chip(!walk)} aria-pressed={!walk} onClick={() => { setCam("orbit"); setPlaying(false); }}>ORBIT</button><button className={chip(walk)} aria-pressed={walk} disabled={!route} onClick={() => { setCam("walk"); setResetKey((k) => k + 1); }}>SURFACE WALK</button><button className={chip(false)} onClick={() => setResetKey((k) => k + 1)}>RESET</button></div>
          <p className="text-[11px] text-dim mt-1.5">{walk ? "Drag to look around. Walk follows the candidate route at eye height." : "Drag to rotate, scroll to zoom, right-drag to pan, click terrain to inspect."}</p></div>
        <div><Eyebrow className="mb-1.5">Route</Eyebrow><div className="flex gap-1.5">{(["SAFEST", "FASTEST", "SCIENCE"] as Mode[]).map((m) => <button key={m} className={chip(S.mode === m)} aria-pressed={S.mode === m} onClick={() => S.setMode(m)}>{MODE_NAME[m].split(" ")[0].toUpperCase()}</button>)}</div>
          <p className="text-[11px] text-dim mt-1.5">{S.routes[S.mode] ? "Your planned route." : "Practice route. Plan your own in the Planner."}{route ? ` Risk ${route.risk.score} · ${route.risk.level}.` : ""}</p></div>
        <div><Eyebrow className="mb-1.5">Surface layer</Eyebrow><div className="flex flex-wrap gap-1.5">{VIEWS.map(([k, n]) => <button key={k} className={chip(view === k)} aria-pressed={view === k} onClick={() => setView(k)}>{n.toUpperCase()}</button>)}</div>
          <div className="mt-1.5"><Tag l={VIEWS.find((v) => v[0] === view)![2]} /></div></div>
        <div className="space-y-2.5">
          {!walk && <div><div className="flex justify-between text-[12px]"><label htmlFor="ex">Vertical exaggeration</label><span className="font-mono">{exag.toFixed(1)}×</span></div><input id="ex" type="range" min={1} max={6} step={0.1} value={exag} onChange={(e) => setExag(+e.target.value)} className="w-full accent-mars-deep" /></div>}
          <div><div className="flex justify-between text-[12px]"><label htmlFor="se">Sun elevation</label><span className="font-mono">{sunEl}°</span></div><input id="se" type="range" min={4} max={70} value={sunEl} onChange={(e) => setSunEl(+e.target.value)} className="w-full accent-mars-deep" /></div>
          <div><div className="flex justify-between text-[12px]"><label htmlFor="sa">Sun direction</label><span className="font-mono">{sunAz}°</span></div><input id="sa" type="range" min={0} max={360} value={sunAz} onChange={(e) => setSunAz(+e.target.value)} className="w-full accent-mars-deep" /></div>
          <p className="text-[11px] text-dim">Lighting is a visual aid, not a model of the real illumination at a given Martian time.</p>
        </div>
        {walk && <div className="space-y-2 border-t border-line pt-3">
          <div className="flex gap-1.5"><button className={chip(playing)} aria-pressed={playing} onClick={() => setPlaying((v) => !v)}>{playing ? "PAUSE" : "AUTO-WALK"}</button><button className={chip(false)} disabled={step === 0} onClick={() => { setPlaying(false); setStep((v) => v - 1); }}>BACK</button><button className={chip(false)} disabled={step >= lms.length - 1} onClick={() => { setPlaying(false); setStep((v) => v + 1); }}>NEXT</button></div>
          <div><div className="flex justify-between text-[12px]"><label htmlFor="sp">Playback speed</label><span className="font-mono">{speed} m/s</span></div><input id="sp" type="range" min={10} max={150} step={5} value={speed} onChange={(e) => setSpeed(+e.target.value)} className="w-full accent-mars-deep" /></div>
          <p className="text-[11px] text-dim">Playback is accelerated for viewing; the time model assumes about 1 m/s (SIMULATED).</p>
        </div>}
      </div>}
      {cur && walk && <div className="absolute bottom-3 left-1/2 -translate-x-1/2 z-10 w-[min(94vw,560px)] bg-ink/94 border border-line-strong rounded-md shadow-float p-3.5">
        <div className="flex items-center justify-between gap-2"><div className="font-mono text-[12px] tracking-[0.08em]">LANDMARK {cur.n} OF {lms.length} · {cur.name.toUpperCase()}</div><Tag l={cur.kind === "science" ? "SIMULATED" : "DERIVED"} /></div>
        <p className="text-[13px] mt-1.5 leading-relaxed">{cur.desc}</p>
        {cur.next && <p className="font-mono text-[11px] text-dim mt-1.5">NEXT: {cur.next.bearing.toFixed(0)}° {cardinal(cur.next.bearing)} · {fmtKm(cur.next.distM)} · {cur.next.dElev >= 0 ? "+" : ""}{cur.next.dElev.toFixed(0)} m</p>}
      </div>}
      <div className="absolute top-10 right-2 z-10 bg-ink/92 border border-line-strong rounded-sm px-3 py-2 font-mono text-[11px] min-w-48">
        {probe && i >= 0 ? <div className="grid grid-cols-2 gap-x-3"><span className="text-dim">ELEVATION</span><span>{S.T.elev[i].toFixed(0)} m</span><span className="text-dim">SLOPE</span><span>{S.T.slope[i].toFixed(1)}°</span><span className="text-dim">ROUGHNESS</span><span>{S.T.rough[i].toFixed(2)}</span><span className="text-dim">REL. PRESSURE</span><span>{pressureRel(S.T, i).toFixed(3)}</span><span className="col-span-2 mt-1 text-dim">DERIVED · pressure SIMULATED</span></div> : <span className="text-dim">{ready ? "CLICK TERRAIN TO INSPECT" : "LOADING…"}</span>}
      </div>
      <div className="absolute bottom-1.5 right-2 z-10 font-mono text-[10px] text-ink/80 pointer-events-none text-right max-w-xs">Shape: USGS HiRISE DTM. Colour, boulders, sky and dust are visual treatment, not measurements.</div>
    </div>
  );
}

// ---------- Follow (landmark-to-landmark, no GPS) ----------
function FollowPage() {
  const S = useStore(); const r = S.routes[S.mode];
  const lms = useMemo(() => (r ? pickLandmarks(S.T, r) : []), [S.T, r]);
  const key = r ? `marsx.follow.${S.mode}.${r.path[0].x},${r.path[0].y}.${r.path[r.path.length - 1].x},${r.path[r.path.length - 1].y}` : "";
  const [step, setStep] = useState(0); const [lost, setLost] = useState(false);
  const [fly, setFly] = useState<{ k: number } | null>(null);
  useEffect(() => { if (key) setStep(Math.min(lms.length - 1, +(localStorage.getItem(key) ?? 0))); }, [key, lms.length]);
  useEffect(() => { if (key) localStorage.setItem(key, String(step)); }, [key, step]);
  useEffect(() => { // simulated flyover: a marker follows the route and pauses at each landmark
    if (!fly || !r) return;
    const n = r.path.length, stops = new Set(lms.map((l) => l.idx)); let hold = 0;
    const id = window.setInterval(() => {
      if (hold > 0) { hold--; return; }
      setFly((f) => { if (!f) return f; const k = f.k + 1; if (k >= n) return null; if (stops.has(k)) hold = 8; return { k }; });
    }, 110);
    return () => clearInterval(id);
  }, [fly === null, r, lms]);
  if (!r) return <div className="max-w-3xl w-full mx-auto px-6 py-10"><Panel title="No route"><p className="text-dim text-[14px]">Generate a plan in the <A to="/planner" className="text-mars-deep underline underline-offset-2">Planner</A> first, then follow it here landmark by landmark.</p></Panel></div>;
  const cur = lms[step], nxt = lms[step + 1];
  const vals = r.path.map((p) => S.T.elev[p.y * W + p.x]), mn = Math.min(...vals), mx = Math.max(...vals), n = vals.length, hh = 120;
  const y = (v: number) => hh - 8 - ((v - mn) / (mx - mn || 1)) * (hh - 18), xk = (k: number) => (k / (n - 1)) * 100;
  const here = fly ? fly.k : cur?.idx ?? 0;
  const lostList = [...lms].filter((l) => l.n !== cur?.n).sort((a, b) => Math.abs(a.sM - cur.sM) - Math.abs(b.sM - cur.sM)).slice(0, 3);
  return (
    <div className="max-w-6xl w-full mx-auto px-6 py-8 space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3"><div><Eyebrow>Follow without GPS</Eyebrow><h1 className="text-[32px] mt-2 leading-tight">{MODE_NAME[S.mode]} route · landmark {step + 1} of {lms.length}</h1></div><div className="flex items-center gap-2"><span className={`font-mono text-[11px] border rounded-sm px-1.5 py-0.5 ${RISK_C[r.risk.level]}`}>RISK {r.risk.score} · {r.risk.level}</span><Tag l="SIMULATED" /></div></div>
      <SynthBanner />
      <div className="grid lg:grid-cols-[1.4fr_1fr] gap-6">
        <div className="space-y-3">
          <div className="h-[380px] border border-line rounded-md overflow-hidden"><MarsMap highlight={S.mode} landmarks={lms} current={step} marker={fly ? r.path[fly.k] : null} showTargets={false} loadingLabel="Loading terrain…" /></div>
          <div className="flex flex-wrap gap-2"><Btn onClick={() => setFly(fly ? null : { k: 0 })}>{fly ? "STOP FLYOVER" : "PLAY SIMULATED FLYOVER"}</Btn><Btn onClick={() => go("/immersive")}>WALK IN 3D</Btn><span className="font-mono text-[11px] text-dim self-center">Marker flies the route and pauses at each landmark. Simulated from synthetic terrain.</span></div>
          <figure>
            <figcaption className="flex justify-between font-mono text-[11px] text-dim mb-1"><span>ELEVATION (m) · DERIVED</span><span>{mn.toFixed(0)} to {mx.toFixed(0)}</span></figcaption>
            <svg viewBox={`0 0 100 ${hh}`} preserveAspectRatio="none" className="w-full border border-line bg-ink rounded-sm" style={{ height: hh }} role="img" aria-label="Elevation profile with landmarks and current position">
              <polyline points={`0,${hh} ${vals.map((v, k) => `${xk(k)},${y(v)}`).join(" ")} 100,${hh}`} fill={ROUTE_C[S.mode]} fillOpacity={0.18} stroke={ROUTE_DEEP[S.mode]} strokeWidth={1.4} vectorEffect="non-scaling-stroke" />
              {lms.map((l, k) => <line key={l.n} x1={xk(l.idx)} x2={xk(l.idx)} y1={0} y2={hh} stroke={k === step ? "#B85C43" : "#b9b2a3"} strokeWidth={k === step ? 1.6 : 1} strokeDasharray="3 3" vectorEffect="non-scaling-stroke" />)}
              <line x1={xk(here)} x2={xk(here)} y1={0} y2={hh} stroke="#D3A24C" strokeWidth={2.2} vectorEffect="non-scaling-stroke" />
            </svg>
            <div className="relative h-4 font-mono text-[10px] text-dim">{lms.map((l) => <span key={l.n} className="absolute -translate-x-1/2" style={{ left: `${xk(l.idx)}%` }}>{l.n}</span>)}</div>
          </figure>
        </div>
        <div className="space-y-4">
          <Panel title={`${cur.n}. ${cur.name}`} tag={cur.kind === "science" ? "SIMULATED" : "DERIVED"}>
            <p className="text-[13px] leading-relaxed">{cur.desc}</p>
            <div className="mt-3 border-t border-line pt-3"><Eyebrow className="mb-1">Why it matters</Eyebrow><p className="text-[13px] leading-relaxed text-fg/90">{cur.why}</p></div>
          </Panel>
          {nxt && cur.next ? <Panel title={`Next: ${nxt.n}. ${nxt.name}`} tag="DERIVED">
            <div className="flex items-center gap-4">
              <svg width={64} height={64} viewBox="-32 -32 64 64" role="img" aria-label={`Bearing ${cur.next.bearing.toFixed(0)} degrees ${cardinal(cur.next.bearing)} from map north`}><circle r={29} fill="none" stroke="#d9d4c9" /><text y={-20} fontSize={8} textAnchor="middle" fill="#5b676c" fontFamily="IBM Plex Mono">N</text><g transform={`rotate(${cur.next.bearing})`}><path d="M0 -22 L7 8 L0 3 L-7 8 Z" fill="#B85C43" /></g></svg>
              <div className="flex-1"><div className="font-mono text-[22px]">{cur.next.bearing.toFixed(0)}° {cardinal(cur.next.bearing)}</div><div className="text-[12px] text-dim">relative to map north</div></div>
            </div>
            <div className="mt-3"><Row k="Distance" v={fmtKm(cur.next.distM)} /><Row k="Elevation change" v={`${cur.next.dElev >= 0 ? "+" : ""}${cur.next.dElev.toFixed(0)} m`} /><Row k="Slope on leg" v={`${cur.next.slopeMin.toFixed(0)}–${cur.next.slopeMax.toFixed(0)}°`} /><Row k="Leg time" v={`${cur.next.timeMin.toFixed(0)} min`} l="SIMULATED" /></div>
          </Panel> : <Panel title="Destination reached"><p className="text-[13px]">End of the candidate route. This is a simulation: reaching it is not a safety guarantee. <A to={`/mission/ARES-01`} className="text-mars-deep underline underline-offset-2">Open the mission report</A>.</p></Panel>}
          <div className="flex gap-2"><Btn className="flex-1" disabled={step === 0} onClick={() => setStep((v) => v - 1)}>BACK</Btn><Btn primary className="flex-1" disabled={step >= lms.length - 1} onClick={() => setStep((v) => v + 1)}>NEXT LANDMARK</Btn></div>
          <button className="font-mono text-[12px] tracking-[0.08em] underline underline-offset-2 text-dim hover:text-fg" aria-expanded={lost} onClick={() => setLost((v) => !v)}>I&apos;M LOST</button>
          {lost && <Panel title="Re-anchor" tag="DERIVED"><p className="text-[12px] text-dim mb-2">Nearest landmarks along the route. Match one to what you can see.</p>{lostList.map((l) => <button key={l.n} onClick={() => { setStep(l.n - 1); setLost(false); }} className="w-full text-left"><Row k={`${l.n}. ${l.name}`} v={`${Math.abs(l.sM - cur.sM).toFixed(0)} m along route`} /></button>)}</Panel>}
          <RiskPanel r={r} />
        </div>
      </div>
    </div>
  );
}

// ---------- Data ----------
function DataPage() {
  const all = [...DATASETS, SYNTH];
  const [sel, setSel] = useState(all[0].id);
  const d = all.find((x) => x.id === sel)!;
  const synth = d.id === SYNTH.id;
  return (
    <div className="max-w-6xl w-full mx-auto px-6 py-10">
      <Eyebrow>Data provenance</Eyebrow><h1 className="text-[34px] mt-2 leading-tight">Dataset explorer</h1>
      <p className="text-dim mt-3 max-w-2xl text-[14px] leading-relaxed">Target datasets for the full pipeline. <span className="text-mars-deep">This prototype does not ingest them</span>; the terrain shown in the app is one real HiRISE DTM window (D3). Resolutions are approximate, taken from public instrument descriptions. Confirm against PDS product labels before use.</p>
      <div className="mt-8 grid md:grid-cols-[220px_1fr] gap-8">
        <div role="tablist" aria-label="Datasets" aria-orientation="vertical" className="flex md:flex-col overflow-x-auto md:overflow-visible border-b md:border-b-0 md:border-r border-line">{all.map((x) => (
          <button key={x.id} role="tab" aria-selected={sel === x.id} onClick={() => setSel(x.id)} className={`text-left px-3 py-2.5 font-mono text-[13px] whitespace-nowrap border-b-2 md:border-b-0 md:border-r-2 -mb-px md:mb-0 md:-mr-px ${sel === x.id ? "border-mars text-fg bg-panel" : "border-transparent text-dim hover:text-fg"}`}>
            {x.id}<span className="block text-[11px] text-dim font-sans">{x.purpose}</span>
          </button>))}</div>
        <div role="tabpanel" className="fade-in" key={d.id}>
          <div className="flex items-center gap-3 flex-wrap"><h2 className="font-mono text-[26px] font-normal">{d.id}</h2><Tag l={synth ? "DERIVED" : "UNKNOWN"} /><span className="text-[12px] text-dim">{synth ? "used by this demo" : "not ingested in this build"}</span></div>
          <p className="mt-1 text-[14px] text-fg/85">{d.purpose}</p>
          <div className="mt-5 border-t border-fg"><Provenance d={d} /></div>
        </div>
      </div>
      <details className="mt-12 border-t border-line pt-4"><summary className="cursor-pointer font-mono text-[12px] tracking-[0.1em]">ALL DATASETS AS A TABLE</summary>
        <div className="mt-4 overflow-x-auto"><table className="w-full text-[12px]"><thead className="text-dim font-mono text-[11px] tracking-[0.08em]"><tr>{["DATASET", "MISSION", "INSTRUMENT", "PURPOSE", "RESOLUTION", "COVERAGE", "PROCESSING", "SOURCE", "VERSION", "LIMITATIONS"].map((h) => <th key={h} scope="col" className="text-left font-normal px-3 py-2 whitespace-nowrap">{h}</th>)}</tr></thead>
          <tbody>{all.map((x) => <tr key={x.id} className="border-t border-line align-top"><th scope="row" className="px-3 py-3 font-mono text-left font-normal text-mars-deep">{x.id}</th>{[x.mission, x.instrument, x.purpose, x.res, x.coverage, x.processing, x.source, x.version, x.limits].map((v, k) => <td key={k} className="px-3 py-3 text-fg/85 min-w-32">{v}</td>)}</tr>)}</tbody></table></div>
      </details>
    </div>
  );
}

// ---------- Methodology ----------
function Eq({ children, note }: { children: React.ReactNode; note?: string }) {
  return <div className="my-4"><div className="font-serif font-light text-[22px] md:text-[26px] border-y border-line py-4 px-2 overflow-x-auto whitespace-nowrap">{children}</div>{note && <div className="font-mono text-[11px] text-dim mt-1.5">{note}</div>}</div>;
}
type Stage = { n: string; sub: string; body: string; io: string; status: "prototype" | "planned"; eq?: React.ReactNode; assume: string[]; label: Label };
const STAGES_M: Stage[] = [
  { n: "NASA DATA", sub: "MOLA · CTX · HiRISE · CRISM · THEMIS", label: "OBSERVED", status: "planned", body: "Orbital products from the Planetary Data System, each with a pinned version and a recorded source.", io: "In: PDS products. Out: raw rasters with provenance.", assume: ["Not ingested in this build; the prototype uses SYNTH-01.", "Resolutions are approximate and vary by product."] },
  { n: "GEOSPATIAL PROCESSING", sub: "Reproject · resample · co-register", label: "DERIVED", status: "planned", body: "Rasters are brought onto a common grid. Each resampling step records the source resolution so later stages know what was interpolated.", io: "In: raw rasters. Out: aligned grid stack.", assume: ["Resampling never adds information; it is tracked as uncertainty.", "Gaps stay UNKNOWN rather than being filled."] },
  { n: "TERRAIN MODEL", sub: "Elevation · slope · roughness", label: "DERIVED", status: "prototype", body: "Slope is derived from elevation with central differences. Roughness is the mean absolute elevation difference in a 3×3 window.", io: "In: elevation grid. Out: slope, roughness, uncertainty.", eq: <>θ = arctan √( (∂z/∂x)² + (∂z/∂y)² )</>, assume: ["Slope is derived, not a direct NASA measurement.", "Prototype roughness also includes a synthetic texture term."] },
  { n: "TRAVERSABILITY", sub: "Hard limits · cell cost", label: "MODELED", status: "prototype", body: "Cells above the slope limit, or with no data, get infinite cost. All other cells get a weighted sum of slope, roughness, uncertainty and distance terms.", io: "In: terrain model. Out: cost grid.", eq: <>C<sub>i</sub> = w<sub>s</sub>S<sub>i</sub> + w<sub>r</sub>R<sub>i</sub> + w<sub>u</sub>U<sub>i</sub> + w<sub>h</sub>H<sub>i</sub></>, assume: ["S = slope / 25°, R and U in [0, 1].", "Default weights 40/25/20/15 are assumptions.", "The output is modeled terrain risk, not actual hazard to any crew or vehicle."] },
  { n: "SCIENCE SCORE", sub: "Targets · value · confidence", label: "SIMULATED", status: "prototype", body: "Each target has a value and a confidence. In SCIENCE mode cost is reduced near targets, up to 55% × value within 1.2 km.", io: "In: targets. Out: discounted cost grid.", eq: <>Score = α·Science − β·TerrainCost − γ·Distance</>, assume: ["Targets are simulated in this build.", "α, β, γ are unvalidated planning weights."] },
  { n: "ROUTE OPTIMIZATION", sub: "A* on an 8-connected grid", label: "MODELED", status: "prototype", body: "A* minimises total cost. The heuristic multiplies Euclidean distance by the minimum attainable cell cost, so it never overestimates.", io: "In: cost grid, endpoints. Out: candidate paths.", eq: <>J(P) = Σ d<sub>i</sub> C<sub>i</sub></>, assume: ["d is 1 or √2 cells.", "Three objectives are solved independently."] },
  { n: "MISSION PLAN", sub: "Explainable candidate report", label: "MODELED", status: "prototype", body: "The report lists distance, slope exposure, science passed and data confidence, with the reasons the route differs from its alternatives.", io: "In: candidate paths. Out: report for human review.", assume: ["Every route is a candidate, never certified safe.", "Human review is required before any use."] },
];
function Methodology() {
  const [k, setK] = useState(3);
  const s = STAGES_M[k];
  return (
    <div className="max-w-6xl w-full mx-auto px-6 py-10">
      <Eyebrow>Methodology</Eyebrow><h1 className="text-[34px] mt-2 leading-tight max-w-2xl">From NASA data to a candidate mission plan.</h1>
      <p className="mt-3 text-[14px] text-dim max-w-2xl leading-relaxed">Select a stage to read what it consumes, what it produces, and which assumptions it carries.</p>
      <div className="mt-8 grid lg:grid-cols-[320px_1fr] gap-10">
        <ol aria-label="Pipeline stages" className="relative">{STAGES_M.map((x, n) => (
          <li key={x.n} className="relative pl-9 pb-5 last:pb-0">
            {n < STAGES_M.length - 1 && <span aria-hidden="true" className="absolute left-[11px] top-6 bottom-0 w-px bg-line-strong" />}
            <span aria-hidden="true" className={`absolute left-0 top-1 w-[23px] h-[23px] rounded-full border flex items-center justify-center font-mono text-[10px] ${n === k ? "bg-mars-deep border-mars-deep text-ink" : "bg-ink border-line-strong text-dim"}`}>{n + 1}</span>
            <button onClick={() => setK(n)} aria-current={n === k} className="text-left w-full group"><span className={`block font-mono text-[12px] tracking-[0.1em] ${n === k ? "text-fg" : "text-dim group-hover:text-fg"}`}>{x.n}</span><span className="block text-[12px] text-dim">{x.sub}</span></button>
          </li>))}</ol>
        <div key={k} className="fade-in border-t border-fg pt-5 self-start">
          <div className="flex items-center gap-3 flex-wrap"><h2 className="font-mono text-[20px] font-normal tracking-[0.04em]">{s.n}</h2><Tag l={s.label} /><span className={`font-mono text-[11px] tracking-[0.08em] ${s.status === "prototype" ? "text-sage-deep" : "text-dim"}`}>{s.status === "prototype" ? "IMPLEMENTED IN PROTOTYPE" : "PLANNED, NOT IMPLEMENTED"}</span></div>
          <p className="mt-4 text-[15px] leading-relaxed text-fg/90 max-w-2xl">{s.body}</p>
          <p className="mt-3 font-mono text-[12px] text-dim">{s.io}</p>
          {s.eq && <Eq>{s.eq}</Eq>}
          <h3 className="font-mono text-[11px] tracking-[0.14em] text-dim uppercase mt-5 font-normal">Assumptions</h3>
          <ul className="mt-2 space-y-1.5 text-[13px] text-fg/85 leading-relaxed">{s.assume.map((a) => <li key={a} className="pl-3 relative before:content-['–'] before:absolute before:left-0 before:text-dim">{a}</li>)}</ul>
        </div>
      </div>

      <section className="mt-20 grid lg:grid-cols-[320px_1fr] gap-10">
        <div><Eyebrow>Multi-resolution routing</Eyebrow><h2 className="mt-3 text-[26px] leading-tight">Coarse to fine.</h2><p className="mt-3 text-[13px] text-dim leading-relaxed">Planned, not implemented in this build. Where finer data is missing, the segment is flagged UNKNOWN rather than assumed safe.</p></div>
        <div className="space-y-2" role="img" aria-label="Three resolution tiers: MOLA corridor search, CTX corridor refinement, HiRISE local hazard check">{[["MOLA", "~463 m/px", "Corridor search", "100%"], ["CTX", "~6 m/px", "Corridor refinement", "62%"], ["HiRISE", "~0.25 m/px", "Local hazard check", "28%"]].map(([a, b, c, w]) => <div key={a} style={{ width: w }} className="min-w-56 border border-fg/70 rounded-sm bg-paper px-3 py-2.5"><div className="font-mono text-[13px] text-mars-deep">{a} <span className="text-dim text-[11px]">{b}</span></div><div className="text-[12px]">{c}</div></div>)}</div>
      </section>

      <section className="mt-16">
        <Eyebrow>Label system</Eyebrow>
        <div className="mt-4 border-t border-fg">{([["OBSERVED", "Direct instrument measurement."], ["DERIVED", "Computed deterministically from observed data (slope, roughness)."], ["MODELED", "Result of a model with assumptions (cost, data confidence, routes)."], ["UNKNOWN", "Insufficient data. Never treated as safe."], ["SIMULATED", "Synthetic placeholder for demonstration."]] as [Label, string][]).map(([l, d]) => <div key={l} className="grid grid-cols-[110px_1fr] gap-3 items-center py-2.5 border-b border-line text-[13px]"><span><Tag l={l} /></span><span className="text-fg/85">{d}</span></div>)}</div>
      </section>
    </div>
  );
}

// ---------- About ----------
function About() {
  return (
    <div className="max-w-3xl w-full mx-auto px-6 py-16">
      <Eyebrow>About</Eyebrow><h1 className="text-[40px] leading-tight mt-3">Built for NASA Space Apps Challenge 2026</h1>
      <p className="mt-6 text-fg/85 leading-relaxed">MARS-X responds to the challenge "Interplanetary Survival Guide: Martian Map". It explores how open planetary data could be fused into explainable traverse planning for rovers and future crews.</p>
      <section className="mt-10 border-t border-fg pt-5 text-[14px] space-y-2 leading-relaxed"><Eyebrow>Disclaimer</Eyebrow><p>This project is not affiliated with, endorsed by, or sponsored by NASA. NASA data, when used, is credited to its original sources.</p><p>All routes are candidate routes for research and education. Safety is NOT CERTIFIED. The demo terrain and science targets are simulated.</p></section>
      <section className="mt-8 border-t border-line pt-5 text-[14px] space-y-2 leading-relaxed"><Eyebrow>Attribution</Eyebrow><p>Globe texture: Viking MDIM 2.1 colorized global mosaic, NASA / USGS Astrogeology Science Center, public domain, downsampled for the web. Landing-site coordinates are published mission values; region outlines and the globe trajectory are approximate or illustrative.</p></section>
      <section className="mt-8 border-t border-line pt-5 text-[14px] space-y-2 leading-relaxed"><Eyebrow>Privacy</Eyebrow><p>This build has no accounts, cookies, trackers or analytics. Routing runs entirely in your browser. Fonts are loaded from Google Fonts, which can see your IP address and user agent.</p></section>
      <dl className="mt-8 grid grid-cols-2 border-t border-line text-[14px]">{[["Frontend", "React · Tailwind · React Three Fiber · client-side A*"], ["Planned backend", "FastAPI · PostGIS (credentials via .env)"], ["Planned pipeline", "GDAL raster fusion"], ["License", "Open source (TBD)"]].map(([a, b]) => <div key={a} className="py-3 pr-4 border-b border-line"><dt className="text-dim text-[11px] font-mono tracking-[0.08em] uppercase">{a}</dt><dd className="mt-1">{b}</dd></div>)}</dl>
    </div>
  );
}

// ---------- App ----------
function TerrainLoading() {
  return (
    <div className="flex-1 grid lg:grid-cols-[288px_1fr_320px] gap-px p-3 lg:p-0">
      <div className="hidden lg:block p-3 space-y-3"><Skeleton className="h-28" /><Skeleton className="h-32" /><Skeleton className="h-20" /></div>
      <div className="min-h-[50vh] flex flex-col items-center justify-center gap-3"><Skeleton className="w-[70%] max-w-xl aspect-[120/76]" /><LoadingNote>Loading terrain…</LoadingNote></div>
      <div className="hidden lg:block p-3 space-y-3"><Skeleton className="h-44" /><Skeleton className="h-28" /></div>
    </div>
  );
}
export default function App() {
  const path = useHashRoute();
  const [T, setT] = useState<Terrain | null>(null);
  useEffect(() => { const id = window.setTimeout(() => setT(buildTerrain()), 0); return () => clearTimeout(id); }, []);
  const [start, setStart] = useState<Pt | null>(null);
  const [end, setEnd] = useState<Pt | null>(null);
  const [mode, setMode] = useState<Mode>("SAFEST");
  const [weights, setWeights] = useState<Weights>(DEFAULT_W);
  const [routes, setRoutes] = useState<Partial<Record<Mode, Route | null>>>({});
  const [mission, setMission] = useState<Target[]>([]);
  const store: Store = { T: T as Terrain, start, end, setStart, setEnd, mode, setMode, weights, setWeights, routes, setRoutes, mission, toggleTarget: (t) => setMission((m) => m.some((x) => x.id === t.id) ? m.filter((x) => x.id !== t.id) : [...m, t]) };
  const needsTerrain = ["/planner", "/explorer", "/routes", "/follow", "/immersive", "/mission"].some((p) => path.startsWith(p));
  let page: React.ReactNode;
  if (needsTerrain && !T) page = <TerrainLoading />;
  else if (path === "/") page = <Landing />;
  else if (path.startsWith("/planner")) page = <Planner />;
  else if (path.startsWith("/explorer")) page = <Explorer />;
  else if (path.startsWith("/routes")) page = <RoutesPage />;
  else if (path.startsWith("/follow")) page = <FollowPage />;
  else if (path.startsWith("/immersive")) page = <ImmersivePage />;
  else if (path.startsWith("/science")) page = <SciencePage />;
  else if (path.startsWith("/mission/")) page = <MissionPage id={decodeURIComponent(path.split("/")[2] || "ARES-01")} />;
  else if (path.startsWith("/data")) page = <DataPage />;
  else if (path.startsWith("/methodology")) page = <Methodology />;
  else if (path.startsWith("/about")) page = <About />;
  else page = <div className="p-10 font-mono text-dim">404 · Unknown route. <A to="/" className="text-mars-deep underline">Return</A></div>;
  return <Ctx.Provider value={store}><Shell path={path}>{page}</Shell></Ctx.Provider>;
}
