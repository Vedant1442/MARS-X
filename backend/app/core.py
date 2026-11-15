"""Pure-Python routing core.  Operates on a cost grid.

Default terrain is REAL HiRISE DTM data (block-averaged from 480x304 → 120x76).
Falls back to synthetic terrain if the DEM file is unavailable.
Cost model is positive-factor: cost = cell_m * (EPS + ws*S + wr*R + wo*O + wv*V),
so Dijkstra/A* assumptions (non-negative edges, admissible heuristic) hold.
"""
from __future__ import annotations
import heapq, math, os, random, struct, warnings
from dataclasses import dataclass

EPS = 1.0  # base cost per metre; guarantees heuristic admissibility
MARS_RADIUS_M = 3_389_500.0

# Grid metadata matching the frontend's JEZERO_META
GRID_W, GRID_H = 120, 76
CELL_M = 35.99
HI_W, HI_H = 480, 304  # high-res render grid dimensions (Int16 LE decimetres)

PROFILES = {  # SIMULATION ASSUMPTIONS, not certified mobility limits
    "safety":   dict(ws=3.0, wr=1.5, we=0.5, wo=3.0, wv=0.0),
    "fastest":  dict(ws=0.3, wr=0.2, we=0.5, wo=1.0, wv=0.0),
    "science":  dict(ws=1.0, wr=0.5, we=0.5, wo=2.0, wv=1.5),
    "balanced": dict(ws=1.0, wr=0.5, we=0.5, wo=2.0, wv=0.6),
}

# Risk assessment constants (matching frontend engine.ts)
MAX_SLOPE = 25
CAUTION_DEG = 10
EXPOSURE_DEG = 15
TIME_BUDGET_MIN = 480
RISK_W = {"max": 0.3, "caution": 0.25, "rough": 0.2, "unc": 0.15, "time": 0.1}

# Science targets (simulated, matching frontend TARGETS)
TARGETS = [
    {"id": "T1", "name": "Demo target A", "x": 44, "y": 34, "type": "Placeholder, sedimentary-type", "value": 0.86, "conf": "MEDIUM", "note": "Placeholder science target at a demonstration location. Not a mapped or published feature."},
    {"id": "T2", "name": "Demo target B", "x": 66, "y": 41, "type": "Placeholder, spectral-type", "value": 0.92, "conf": "LOW", "note": "Placeholder science target. No spectral data has been ingested; value is an expert-style weight for the demo."},
    {"id": "T3", "name": "Demo target C", "x": 86, "y": 60, "type": "Placeholder, impact-type", "value": 0.61, "conf": "HIGH", "note": "Placeholder science target at a demonstration location. Not a mapped or published feature."},
    {"id": "T4", "name": "Demo target D", "x": 26, "y": 42, "type": "Placeholder, fluvial-type", "value": 0.78, "conf": "MEDIUM", "note": "Placeholder science target at a demonstration location. Not a mapped or published feature."},
    {"id": "T5", "name": "Demo target E", "x": 98, "y": 30, "type": "Placeholder, thermal-type", "value": 0.55, "conf": "LOW", "note": "Placeholder science target. No thermal product has been ingested."},
]

@dataclass
class Grid:
    w: int
    h: int
    cell_m: float
    elev: list  # row-major metres
    slope: list  # degrees
    rough: list  # 0..1
    science: list  # 0..1 value (simulated)
    terrain_source: str = "SYNTHETIC"


def _find_dem_path() -> str | None:
    """Locate the binary DEM file using the priority chain."""
    candidates = []
    env_path = os.environ.get("MARSX_DEM_PATH")
    if env_path:
        candidates.append(env_path)
    candidates.append(os.path.join(os.path.dirname(__file__), "..", "data", "jezero-dem.dat"))
    candidates.append(os.path.join(os.path.dirname(__file__), "..", "data", "jezero-dem.bin"))
    candidates.append(os.path.join(os.path.dirname(__file__), "..", "..", "public", "jezero-dem.bin"))
    for p in candidates:
        ap = os.path.abspath(p)
        if os.path.isfile(ap):
            return ap
    return None


def load_real_grid(dem_path: str | None = None) -> Grid:
    """Load real HiRISE DTM data from the binary DEM file.

    The DEM file contains Int16 little-endian values in decimetres,
    480×304 samples. Block-average 4×4 to get the 120×76 planning grid.
    Computes slope (Horn's method) and roughness from the real elevation.
    Science values are simulated on top of real terrain positions.
    """
    if dem_path is None:
        dem_path = _find_dem_path()
    if dem_path is None:
        warnings.warn("DEM file not found; falling back to synthetic grid.", stacklevel=2)
        return synthetic_grid(w=GRID_W, h=GRID_H, cell_m=CELL_M)

    # Read raw Int16 LE decimetres from the hi-res grid
    with open(dem_path, "rb") as f:
        raw = f.read()
    expected = HI_W * HI_H * 2
    if len(raw) != expected:
        warnings.warn(f"DEM file size mismatch: expected {expected}, got {len(raw)}. Falling back to synthetic grid.", stacklevel=2)
        return synthetic_grid(w=GRID_W, h=GRID_H, cell_m=CELL_M)

    # Unpack to hi-res elevation in metres (decimetres / 10)
    hi_elev = [0.0] * (HI_W * HI_H)
    for i in range(HI_W * HI_H):
        v = struct.unpack_from("<h", raw, i * 2)[0]
        hi_elev[i] = v / 10.0  # decimetres → metres

    # Block-average 4×4 to get the planning grid (120×76)
    elev = [0.0] * (GRID_W * GRID_H)
    for gy in range(GRID_H):
        for gx in range(GRID_W):
            total = 0.0
            for by in range(4):
                for bx in range(4):
                    hx = gx * 4 + bx
                    hy = gy * 4 + by
                    total += hi_elev[hy * HI_W + hx]
            elev[gy * GRID_W + gx] = total / 16.0

    # Compute slope using central differences (Horn's method)
    def g(x: int, y: int) -> float:
        return elev[min(GRID_H - 1, max(0, y)) * GRID_W + min(GRID_W - 1, max(0, x))]

    slope = [0.0] * (GRID_W * GRID_H)
    rough = [0.0] * (GRID_W * GRID_H)
    science = [0.0] * (GRID_W * GRID_H)

    # Simple seeded noise for roughness perturbation and science values
    rnd = random.Random(19)
    noise_grid = [rnd.random() for _ in range(64 * 64)]
    def noise(x: float, y: float) -> float:
        xi, yi = int(x) & 63, int(y) & 63
        xf = x - int(x)
        yf = y - int(y)
        s = lambda t: t * t * (3 - 2 * t)
        a = noise_grid[yi * 64 + xi]
        b = noise_grid[yi * 64 + ((xi + 1) & 63)]
        c = noise_grid[((yi + 1) & 63) * 64 + xi]
        d = noise_grid[((yi + 1) & 63) * 64 + ((xi + 1) & 63)]
        return a + (b - a) * s(xf) + (c - a) * s(yf) + (a - b - c + d) * s(xf) * s(yf)

    for y in range(GRID_H):
        for x in range(GRID_W):
            i = y * GRID_W + x
            # Slope via central differences
            dzdx = (g(x + 1, y) - g(x - 1, y)) / (2 * CELL_M)
            dzdy = (g(x, y + 1) - g(x, y - 1)) / (2 * CELL_M)
            slope[i] = math.degrees(math.atan(math.hypot(dzdx, dzdy)))

            # Roughness: mean absolute deviation from center in 3×3 window, normalized
            s_val = 0.0
            for k in range(-1, 2):
                for l in range(-1, 2):
                    s_val += abs(g(x + k, y + l) - elev[i])
            rough[i] = min(1.0, s_val / 9 / 60 + noise(x / 5, y / 5) * 0.35)

            # Science values: simulated, biased by terrain features
            science[i] = max(0.0, noise(x / 8 + 40, y / 8 + 40) - 0.6) * 2.5

    return Grid(GRID_W, GRID_H, CELL_M, elev, slope, rough, science, terrain_source="HiRISE_DTM")


def synthetic_grid(w=80, h=60, cell_m=100.0, seed=7) -> Grid:
    """Generate a synthetic terrain grid as fallback."""
    rnd = random.Random(seed)
    k = 8
    lat = [[rnd.random() for _ in range(w // k + 8)] for _ in range(h // k + 8)]
    def noise(x, y):
        gx, gy = x / k, y / k; x0, y0 = int(gx), int(gy); fx, fy = gx - x0, gy - y0
        s = lambda t: t * t * (3 - 2 * t)
        a, b, c, d = lat[y0][x0], lat[y0][x0 + 1], lat[y0 + 1][x0], lat[y0 + 1][x0 + 1]
        return (a + (b - a) * s(fx)) * (1 - s(fy)) + (c + (d - c) * s(fx)) * s(fy)
    elev = [noise(x, y) * 300 - 2600 for y in range(h) for x in range(w)]
    g = lambda x, y: elev[min(h - 1, max(0, y)) * w + min(w - 1, max(0, x))]
    slope, rough, sci = [], [], []
    for y in range(h):
        for x in range(w):
            dzdx = (g(x + 1, y) - g(x - 1, y)) / (2 * cell_m)
            dzdy = (g(x, y + 1) - g(x, y - 1)) / (2 * cell_m)
            slope.append(math.degrees(math.atan(math.hypot(dzdx, dzdy))))
            rough.append(min(1.0, sum(abs(g(x + i, y + j) - g(x, y)) for i in (-1, 0, 1) for j in (-1, 0, 1)) / 9 / 20))
            sci.append(max(0.0, noise(x + 40, y + 40) - 0.6) * 2.5)
    return Grid(w, h, cell_m, elev, slope, rough, sci, terrain_source="SYNTHETIC")

@dataclass
class Result:
    path: list
    total_cost: float
    nodes_expanded: int

def _cell_factor(gr: Grid, i: int, wt: dict, max_slope: float):
    if gr.slope[i] > max_slope:
        return None  # hard constraint: excluded cell
    s = gr.slope[i] / max_slope
    return EPS + wt["ws"] * s + wt["wr"] * gr.rough[i] + wt["wo"] * 0.0 - wt["wv"] * min(gr.science[i], 1.0) * 0.5

def search(gr: Grid, a, b, wt: dict, max_slope=20.0, algorithm="astar") -> Result | None:
    # science bonus is capped (<= 0.5*wv) and EPS floor keeps every edge positive
    floor = 0.05
    def fac(i):
        f = _cell_factor(gr, i, wt, max_slope)
        return None if f is None else max(f, floor)
    n = gr.w * gr.h
    si, ti = a[1] * gr.w + a[0], b[1] * gr.w + b[0]
    if fac(si) is None or fac(ti) is None:
        return None
    hmin = floor * gr.cell_m
    h = (lambda x, y: 0.0) if algorithm == "dijkstra" else (lambda x, y: math.hypot(x - b[0], y - b[1]) * hmin)
    dist = [math.inf] * n; prev = [-1] * n; done = [False] * n
    dist[si] = 0.0; pq = [(h(*a), si)]; expanded = 0
    while pq:
        _, i = heapq.heappop(pq)
        if done[i]: continue
        done[i] = True; expanded += 1
        if i == ti: break
        x, y = i % gr.w, i // gr.w
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if not dx and not dy: continue
                nx, ny = x + dx, y + dy
                if not (0 <= nx < gr.w and 0 <= ny < gr.h): continue
                j = ny * gr.w + nx
                if done[j]: continue
                fj = fac(j)
                if fj is None: continue
                step = gr.cell_m * (math.sqrt(2) if dx and dy else 1.0)
                nd = dist[i] + step * (fac(i) + fj) / 2
                if nd < dist[j]:
                    dist[j] = nd; prev[j] = i
                    heapq.heappush(pq, (nd + h(nx, ny), j))
    if prev[ti] == -1 and si != ti: return None
    path, k = [], ti
    while k != -1:
        path.append((k % gr.w, k // gr.w)); k = prev[k]
    return Result(path[::-1], dist[ti], expanded)

def validate(gr: Grid, res: Result, wt: dict, max_slope: float) -> dict:
    p = res.path
    cont = all(max(abs(p[i][0] - p[i - 1][0]), abs(p[i][1] - p[i - 1][1])) == 1 for i in range(1, len(p)))
    excl = all(gr.slope[y * gr.w + x] <= max_slope for x, y in p)
    cost = 0.0
    for i in range(1, len(p)):
        (x0, y0), (x1, y1) = p[i - 1], p[i]
        f0 = max(_cell_factor(gr, y0 * gr.w + x0, wt, max_slope) or 0, 0.05)
        f1 = max(_cell_factor(gr, y1 * gr.w + x1, wt, max_slope) or 0, 0.05)
        cost += gr.cell_m * (math.sqrt(2) if x0 != x1 and y0 != y1 else 1) * (f0 + f1) / 2
    return {"continuous": cont, "no_excluded_cells": excl,
            "cost_recomputed_matches": abs(cost - res.total_cost) < 1e-6 * max(1, cost)}

def metrics(gr: Grid, res: Result) -> dict:
    p = res.path; d = gain = loss = 0.0
    for i in range(1, len(p)):
        (x0, y0), (x1, y1) = p[i - 1], p[i]
        d += gr.cell_m * math.hypot(x1 - x0, y1 - y0)
        dz = gr.elev[y1 * gr.w + x1] - gr.elev[y0 * gr.w + x0]
        gain += max(dz, 0); loss += max(-dz, 0)
    sl = [gr.slope[y * gr.w + x] for x, y in p]
    return dict(distance_m=d, elevation_gain_m=gain, elevation_loss_m=loss, max_slope_deg=max(sl),
                mean_slope_deg=sum(sl) / len(sl), total_cost=res.total_cost, nodes_expanded=res.nodes_expanded,
                science_value_collected=sum(gr.science[y * gr.w + x] for x, y in p) / len(p),
                estimated_duration_min=d / 0.5 / 60)  # SIMULATED speed model v1: 0.5 m/s


# ---------- Speed model (SIMULATED, matching frontend) ----------
def speed_mps(slope_deg: float) -> float:
    """Walking speed falls with slope. A planning assumption, not a certified EVA mobility limit."""
    return max(0.2, 1.4 * (1 - slope_deg / (MAX_SLOPE * 1.3)))

def leg_time_min(gr: Grid, path: list) -> float:
    """Estimated traverse time for a path segment in minutes."""
    s = 0.0
    for k in range(1, len(path)):
        ax, ay = path[k - 1]
        bx, by = path[k]
        i = by * gr.w + bx
        s += (math.hypot(bx - ax, by - ay) * gr.cell_m) / speed_mps(gr.slope[i])
    return s / 60.0


# ---------- Risk score 0-100 (SIMULATED weights, see PLAN section 6.4) ----------
def risk_score(gr: Grid, res: Result, mean_rough: float | None = None, mean_unc: float | None = None) -> dict:
    """Compute detailed risk breakdown for a route (matching frontend riskScore)."""
    path = res.path
    n = len(path)
    idx = [p[1] * gr.w + p[0] for p in path]

    # Compute route length and caution-zone length
    route_len = 0.0
    caution_len = 0.0
    for k in range(1, n):
        d = math.hypot(path[k][0] - path[k - 1][0], path[k][1] - path[k - 1][1])
        route_len += d
        if gr.slope[idx[k]] > CAUTION_DEG:
            caution_len += d

    # Compute statistics
    max_slope_deg = max(gr.slope[i] for i in idx)
    if mean_rough is None:
        mean_rough = sum(gr.rough[i] for i in idx) / n
    if mean_unc is None:
        # Compute uncertainty analogous to frontend: lower near edges, higher on rough ground
        unc_values = []
        noise_rnd = random.Random(19)
        noise_g = [noise_rnd.random() for _ in range(64 * 64)]
        for x, y in path:
            i = y * gr.w + x
            edge = min(x, y, gr.w - 1 - x, gr.h - 1 - y) / 12.0
            unc_val = min(1.0, 0.12 + 0.25 * (1 - min(1.0, edge)) + gr.rough[i] * 0.4)
            unc_values.append(unc_val)
        mean_unc = sum(unc_values) / n
        low_conf_share = sum(1 for u in unc_values if u > 0.5) / n
    else:
        low_conf_share = 0.0

    time_min = leg_time_min(gr, path)

    parts = [
        {"k": "max", "label": "Peak slope vs limit", "v": round(min(1.0, max_slope_deg / MAX_SLOPE), 4), "w": RISK_W["max"]},
        {"k": "caution", "label": f"Length above {CAUTION_DEG}°", "v": round(caution_len / route_len if route_len else 0, 4), "w": RISK_W["caution"]},
        {"k": "rough", "label": "Mean roughness", "v": round(min(1.0, mean_rough), 4), "w": RISK_W["rough"]},
        {"k": "unc", "label": "Low-confidence share", "v": round(low_conf_share, 4), "w": RISK_W["unc"]},
        {"k": "time", "label": "Time vs budget", "v": round(min(1.0, time_min / TIME_BUDGET_MIN), 4), "w": RISK_W["time"]},
    ]

    score = round(100 * sum(p["v"] * p["w"] for p in parts))
    if score < 25:
        level = "LOW"
    elif score < 50:
        level = "MODERATE"
    elif score < 75:
        level = "HIGH"
    else:
        level = "VERY HIGH"

    return {"score": score, "level": level, "timeMin": round(time_min, 2), "parts": parts}


# ---------- Landmarks (no-GPS navigation, PLAN section 6.5) ----------
def _cardinal(bearing: float) -> str:
    dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    return dirs[round(bearing / 45) % 8]

def pick_landmarks(gr: Grid, res: Result) -> list[dict]:
    """Pick 5-6 landmarks along a route for no-GPS navigation (matching frontend pickLandmarks)."""
    path = res.path
    n = len(path)
    at = lambda k: path[k][1] * gr.w + path[k][0]

    # Cumulative distance along path
    s = [0.0]
    for k in range(1, n):
        s.append(s[k - 1] + math.hypot(path[k][0] - path[k - 1][0], path[k][1] - path[k - 1][1]) * gr.cell_m)
    L = s[n - 1]
    K = 5 if L < 6000 else 6  # total landmarks including start/dest
    legs = K - 1

    def head(k: int):
        a = path[max(0, k - 2)]
        b = path[min(n - 1, k + 2)]
        d = math.hypot(b[0] - a[0], b[1] - a[1]) or 1
        return [(b[0] - a[0]) / d, (b[1] - a[1]) / d]

    def side(k: int) -> str:
        px, py = path[k]
        gf = lambda xx, yy: gr.elev[min(gr.h - 1, max(0, yy)) * gr.w + min(gr.w - 1, max(0, xx))]
        dx = -(gf(px + 2, py) - gf(px - 2, py))
        dy = -(gf(px, py + 2) - gf(px, py - 2))
        hx, hy = head(k)
        cr = hx * dy - hy * dx
        mag = math.hypot(dx, dy)
        if mag < 8:
            return ""
        return "ground drops to your right" if cr > 0 else "ground drops to your left"

    # Build candidate landmarks
    cands: dict[int, dict] = {}

    # Science targets within ~4 cells of the route
    for t in TARGETS:
        best_k, best_d = -1, 99.0
        for k, p in enumerate(path):
            d = math.hypot(p[0] - t["x"], p[1] - t["y"])
            if d < best_d:
                best_d = d
                best_k = k
        if best_d <= 4 and 0 < best_k < n - 1:
            score = 0.6 * t["value"] + 0.4 * 0.5 - best_d * 0.04
            if best_k not in cands or cands[best_k]["score"] < score:
                offset_str = "On the route" if best_d < 1.5 else f"About {best_d * gr.cell_m:.0f} m off the route"
                cands[best_k] = {
                    "k": best_k, "score": score, "kind": "science",
                    "name": t["name"],
                    "desc": f'{t["type"]}. {offset_str}; {side(best_k) or "gentle terrain"}.',
                    "why": f'{t["note"]} Importance {t["value"]:.2f} (simulated expert weight).',
                    "target": t,
                }

    # Terrain landmarks: crests, lows, slope breaks
    for k in range(4, n - 4):
        e = gr.elev[at(k)]
        win = [gr.elev[at(k - 4 + j)] for j in range(9)]
        mx, mn = max(win), min(win)
        brk = abs(gr.slope[at(k)] - gr.slope[at(k - 3)])
        name = desc = ""
        d_score = 0.0
        if e == mx and mx - mn > 25:
            name = "Ridge crest"
            d_score = min(1.0, (mx - mn) / 150)
            desc = f"Local high point, {side(k) or 'ground falls away'}."
        elif e == mn and mx - mn > 25:
            name = "Local low"
            d_score = min(1.0, (mx - mn) / 150)
            desc = "Local low point; ground rises ahead."
        elif brk > 7:
            name = "Slope break"
            d_score = min(1.0, brk / 15)
            desc = f"Slope changes from {gr.slope[at(k - 3)]:.0f}° to {gr.slope[at(k)]:.0f}°."
        if name and k not in cands:
            cands[k] = {
                "k": k, "score": 0.4 * d_score, "kind": "terrain",
                "name": name, "desc": desc,
                "why": "Terrain landmark derived from the elevation model.",
            }

    cand_list = sorted(cands.values(), key=lambda c: c["k"])

    # DP over ordered candidates to pick m = K-2 interior landmarks
    m = K - 2
    lo = (0.5 * L) / legs
    hi = (1.8 * L) / legs

    if cand_list and m > 0:
        best_dp = [[{"v": float("-inf"), "prev": -1} for _ in cand_list] for _ in range(m + 1)]
        for i, c in enumerate(cand_list):
            if lo <= s[c["k"]] <= hi:
                best_dp[1][i] = {"v": c["score"], "prev": -1}
        for j in range(2, m + 1):
            for i, c in enumerate(cand_list):
                for h_idx, q in enumerate(cand_list):
                    gap = s[c["k"]] - s[q["k"]]
                    if lo <= gap <= hi and best_dp[j - 1][h_idx]["v"] > float("-inf"):
                        new_v = best_dp[j - 1][h_idx]["v"] + c["score"]
                        if new_v > best_dp[j][i]["v"]:
                            best_dp[j][i] = {"v": new_v, "prev": h_idx}

        # Trace back
        bv, bi = float("-inf"), -1
        for i, c in enumerate(cand_list):
            gap = L - s[c["k"]]
            if lo <= gap <= hi and best_dp[m][i]["v"] > bv:
                bv = best_dp[m][i]["v"]
                bi = i
        picked_idx = []
        if bi >= 0:
            j_val, i_val = m, bi
            while j_val >= 1:
                picked_idx.append(i_val)
                i_val = best_dp[j_val][i_val]["prev"]
                j_val -= 1
            picked_idx.reverse()
        mids = [cand_list[i] for i in picked_idx]
    else:
        mids = []

    if len(mids) < m:
        # Fallback: evenly spaced waypoints
        mids = []
        for j in range(m):
            target_dist = (L * (j + 1)) / legs
            k = 1
            while k < n and s[k] < target_dist:
                k += 1
            k = max(1, min(n - 2, k))
            # Check if there's a nearby candidate
            near = None
            for c in cand_list:
                if abs(s[c["k"]] - target_dist) < lo * 0.6:
                    near = c
                    break
            if near:
                mids.append(near)
            else:
                mids.append({
                    "k": k, "score": 0, "kind": "terrain",
                    "name": "Waypoint",
                    "desc": f"Evenly spaced waypoint; {side(k) or 'gentle terrain'}.",
                    "why": "Evenly spaced fallback landmark.",
                })

    # Build output
    out = []
    # Start
    out.append({
        "n": 1, "idx": 0, "pt": list(path[0]), "sM": 0.0,
        "name": "Start", "kind": "start",
        "desc": "Your starting cell. Note the surroundings before you set off.",
        "why": "Reference point for the traverse.",
    })
    # Mids
    for j, c in enumerate(mids):
        entry = {
            "n": j + 2, "idx": c["k"], "pt": list(path[c["k"]]), "sM": s[c["k"]],
            "name": c["name"], "kind": c["kind"],
            "desc": c["desc"], "why": c["why"],
        }
        if "target" in c:
            entry["target"] = c["target"]
        out.append(entry)
    # Destination
    out.append({
        "n": K, "idx": n - 1, "pt": list(path[n - 1]), "sM": s[n - 1],
        "name": "Destination", "kind": "dest",
        "desc": "End of the candidate route.",
        "why": "Planned end point. Reaching it is not a safety guarantee.",
    })

    # Compute legs between consecutive landmarks
    for j in range(len(out) - 1):
        a_lm = out[j]
        b_lm = out[j + 1]
        seg = path[a_lm["idx"]:b_lm["idx"] + 1]
        ap, bp = path[a_lm["idx"]], path[b_lm["idx"]]
        dx_val = bp[0] - ap[0]
        dy_val = bp[1] - ap[1]
        bearing = (math.atan2(dx_val, -dy_val) * 180 / math.pi + 360) % 360
        sl_seg = [gr.slope[p[1] * gr.w + p[0]] for p in seg]
        a_lm["next"] = {
            "bearing": round(bearing, 1),
            "bearingCardinal": _cardinal(bearing),
            "distM": round(b_lm["sM"] - a_lm["sM"], 1),
            "dElev": round(gr.elev[bp[1] * gr.w + bp[0]] - gr.elev[ap[1] * gr.w + ap[0]], 2),
            "slopeMin": round(min(sl_seg), 2) if sl_seg else 0,
            "slopeMax": round(max(sl_seg), 2) if sl_seg else 0,
            "timeMin": round(leg_time_min(gr, seg), 2),
        }

    return out
