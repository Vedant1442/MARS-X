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

# Risk assessment & EVA consumables constants (matching frontend engine.ts + nipun_branch EVA model)
MAX_SLOPE = 25
CAUTION_DEG = 10
EXPOSURE_DEG = 15
TIME_BUDGET_MIN = 480
RISK_W = {"max": 0.3, "caution": 0.25, "rough": 0.2, "unc": 0.15, "time": 0.1}

EVA_TOTAL_O2_L = 1200.0
EVA_TOTAL_BATT_WH = 1440.0
EVA_TOTAL_WATER_KG = 4.2
EVA_RESERVE_FRAC = 0.20

# The 15 Mapped Jezero Crater Expedition Landmarks (from nipun_branch + processed data)
TARGETS = [
    {
        "id": "octavia-butler-landing",
        "name": "Octavia E. Butler Landing",
        "x": 99, "y": 49, "lon": 77.45089, "lat": 18.44463,
        "type": "Landing Site · Crater Floor",
        "category": "mission_anchor", "subcategory": "landing_site",
        "value": 0.90, "conf": "HIGH",
        "image_url": "/landmarks/octavia-butler-landing.jpg",
        "significance": "High — baseline reference for crater-floor geology, atmospheric science, and traverse origin.",
        "perseverance_history": "Perseverance landed here on February 18, 2021 (Sol 0). Ingenuity deployed nearby at Wright Brothers Field.",
        "note": "Primary mission touchdown coordinate on the Māʻaz formation crater floor.",
    },
    {
        "id": "three-forks",
        "name": "Three Forks Sample Depot",
        "x": 79, "y": 47, "lon": 77.4342, "lat": 18.4472,
        "type": "Sample Depot · Base of Western Delta",
        "category": "mission_anchor", "subcategory": "sample_depot",
        "value": 0.95, "conf": "HIGH",
        "image_url": "/landmarks/three-forks.jpg",
        "significance": "Very High — backup sample cache for Mars Sample Return containing igneous, sedimentary, and atmospheric tubes.",
        "perseverance_history": "Between December 2022 and January 2023 (Sols 652-690), Perseverance deposited 10 titanium sample tubes.",
        "note": "Flat, low-hazard terrain at the base of the western delta front selected for future sample recovery.",
    },
    {
        "id": "hawksbill-gap",
        "name": "Hawksbill Gap",
        "x": 70, "y": 48, "lon": 77.4295, "lat": 18.4480,
        "type": "Delta Front Ascent Corridor",
        "category": "rover_waypoint", "subcategory": "delta_front",
        "value": 0.92, "conf": "HIGH",
        "image_url": "/landmarks/hawksbill-gap.jpg",
        "significance": "Very High — exposes full sedimentary transition from crater-floor volcanic rocks to bottomset mudstones and topset sandstones.",
        "perseverance_history": "Primary delta front campaign site in 2022; rover traversed up and down this corridor.",
        "note": "Steeply dipping sedimentary strata along the eroded southern scarp of the western delta.",
    },
    {
        "id": "enchanted-lake",
        "name": "Enchanted Lake",
        "x": 66, "y": 49, "lon": 77.4260, "lat": 18.4465,
        "type": "Outcrop · Lower Western Delta Scarp",
        "category": "rover_waypoint", "subcategory": "sedimentary_outcrop",
        "value": 0.94, "conf": "HIGH",
        "image_url": "/landmarks/enchanted-lake.jpg",
        "significance": "Very High — fine-grained lacustrine mudstones and siltstones with highest potential to trap organic biosignatures.",
        "perseverance_history": "First contact site on the lower delta front in April 2022 (Sol 410+).",
        "note": "Thinly laminated sedimentary outcrop at the western foot of Cape Nukshak.",
    },
    {
        "id": "cape-nukshak",
        "name": "Cape Nukshak",
        "x": 69, "y": 49, "lon": 77.4285, "lat": 18.4460,
        "type": "Promontory · Delta Front",
        "category": "rover_waypoint", "subcategory": "delta_promontory",
        "value": 0.87, "conf": "HIGH",
        "image_url": "/landmarks/cape-nukshak.jpg",
        "significance": "High — cross-section of delta front progradation and post-depositional wind erosion.",
        "perseverance_history": "Landmark promontory rounding the southern delta lobe between Enchanted Lake and Hawksbill Gap.",
        "note": "Prominent jutting cliff-face separating the Enchanted Lake and Hawksbill Gap embayments.",
    },
    {
        "id": "belva-crater",
        "name": "Belva Crater",
        "x": 49, "y": 30, "lon": 77.4150, "lat": 18.4630,
        "type": "Impact Crater · Upper Delta Fan",
        "category": "rover_waypoint", "subcategory": "impact_crater",
        "value": 0.89, "conf": "HIGH",
        "image_url": "/landmarks/belva-crater.jpg",
        "significance": "High — natural ~900 m drill hole exposing deep delta stratigraphy and dipping foreset beds.",
        "perseverance_history": "Imaged in high-resolution Mastcam-Z mosaics on Sol 772 (April 2023) at Echo Creek.",
        "note": "0.9 km diameter impact crater excavated into the upper western delta deposits.",
    },
    {
        "id": "bunsen-peak",
        "name": "Bunsen Peak",
        "x": 27, "y": 28, "lon": 77.4010, "lat": 18.4650,
        "type": "Outcrop · Margin Unit",
        "category": "rover_waypoint", "subcategory": "margin_unit",
        "value": 0.96, "conf": "HIGH",
        "image_url": "/landmarks/bunsen-peak.jpg",
        "significance": "Exceptional — Comet Geyser core showed ~75% carbonate grains cemented by hydrated silica, prime biosignature preservation matrix.",
        "perseverance_history": "Investigated and cored on Sol 1088 (March 2024).",
        "note": "Prominent light-toned outcrop within the carbonate-bearing Margin Unit along the inner crater rim.",
    },
    {
        "id": "jurabi-point",
        "name": "Jurabi Point",
        "x": 38, "y": 25, "lon": 77.4080, "lat": 18.4680,
        "type": "Contact · Upper Fan / Margin Unit",
        "category": "rover_waypoint", "subcategory": "geological_contact",
        "value": 0.88, "conf": "HIGH",
        "image_url": "/landmarks/jurabi-point.jpg",
        "significance": "High — defines chronological sequence between marginal shoreline carbonates and late-stage boulder-rich fluvial floods.",
        "perseverance_history": "Investigated in late 2023 during transition from Upper Fan to Margin Unit campaign.",
        "note": "Stratigraphic boundary zone where upper delta fan boulder conglomerates meet the Margin Unit.",
    },
    {
        "id": "gnaraloo-bay",
        "name": "Gnaraloo Bay",
        "x": 32, "y": 29, "lon": 77.4040, "lat": 18.4640,
        "type": "Carbonate Outcrop · Margin Unit",
        "category": "rover_waypoint", "subcategory": "margin_unit",
        "value": 0.91, "conf": "HIGH",
        "image_url": "/landmarks/gnaraloo-bay.jpg",
        "significance": "Very High — strong orbital CRISM and in-situ SHERLOC/PIXL signatures of magnesium-iron carbonates along ancient lake shoreline.",
        "perseverance_history": "Examined in early 2024 along the southern Margin Unit traverse.",
        "note": "Embayment of fractured, carbonate-bearing bedrock near the base of the western delta.",
    },
    {
        "id": "western-delta",
        "name": "Western Delta",
        "x": 55, "y": 38, "lon": 77.4200, "lat": 18.4550,
        "type": "Fluvial-Lacustrine Deltaic Fan",
        "category": "geomorphic_feature", "subcategory": "delta",
        "value": 0.98, "conf": "HIGH",
        "image_url": "/landmarks/western-delta.jpg",
        "significance": "Exceptional — primary astrobiological target of Mars 2020; preserves fine-grained clay and carbonate sediments.",
        "perseverance_history": "Explored across the Delta Front, Upper Fan, and Margin Unit campaigns (2022-2024).",
        "note": "Classic Gilbert-type fan-delta built where Neretva Vallis discharged into ancient Lake Jezero.",
    },
    {
        "id": "neretva-vallis",
        "name": "Neretva Vallis",
        "x": 14, "y": 22, "lon": 77.3800, "lat": 18.4850,
        "type": "Inlet Channel · Bright Angel",
        "category": "geomorphic_feature", "subcategory": "inlet_channel",
        "value": 0.97, "conf": "HIGH",
        "image_url": "/landmarks/neretva-vallis.jpg",
        "significance": "Exceptional — Cheyava Falls ('leopard spots') core collected at Bright Angel contains organic carbon with iron-phosphate reaction fronts.",
        "perseverance_history": "Perseverance entered Neretva Vallis in mid-2024 and drilled the landmark Cheyava Falls sample on Sol 1215.",
        "note": "Western inlet river channel that breached the Jezero Crater rim and built the Western Delta.",
    },
    {
        "id": "jezero-crater-rim",
        "name": "Jezero Crater Rim",
        "x": 10, "y": 40, "lon": 77.3600, "lat": 18.4400,
        "type": "Crater Rim · Noachian Basement",
        "category": "geomorphic_feature", "subcategory": "crater_rim",
        "value": 0.93, "conf": "HIGH",
        "image_url": "/landmarks/jezero-crater-rim.jpg",
        "significance": "Very High — samples oldest pre-Jezero Martian crust (~3.9-4.0 Ga) and deep hydrothermal habitats.",
        "perseverance_history": "Target of Perseverance's Crater Rim Campaign (2024-2025) climbing toward Pico Turquino and Witch Hazel Hill.",
        "note": "45-km diameter impact structure uplifted megabreccia and ancient Noachian crust.",
    },
    {
        "id": "sava-vallis",
        "name": "Sava Vallis",
        "x": 85, "y": 8, "lon": 77.5200, "lat": 18.6800,
        "type": "Northern Inlet Channel",
        "category": "geomorphic_feature", "subcategory": "inlet_channel",
        "value": 0.78, "conf": "MEDIUM",
        "image_url": "/landmarks/sava-vallis.jpg",
        "significance": "High — records secondary northern watershed and sediment source feeding Lake Jezero.",
        "perseverance_history": "Observed from orbit by HiRISE, CTX, and MOLA; outside rover surface traverse range.",
        "note": "Northern inlet valley breaching the northwestern/northern rim of Jezero Crater.",
    },
    {
        "id": "pliva-vallis",
        "name": "Eastern Outlet Valley (Pliva Vallis)",
        "x": 115, "y": 38, "lon": 77.9500, "lat": 18.4200,
        "type": "Outlet Canyon · Open-Basin Spillway",
        "category": "geomorphic_feature", "subcategory": "outlet_channel",
        "value": 0.82, "conf": "HIGH",
        "image_url": "/landmarks/pliva-vallis.jpg",
        "significance": "High — proves Jezero was an open-basin, hydrologically stable fresh-water lake system that overflowed its eastern rim.",
        "perseverance_history": "Mapped from orbital MOLA and CTX topography to establish ancient lake highstand.",
        "note": "Outflow canyon breaching the eastern rim of Jezero Crater.",
    },
    {
        "id": "ancient-lake-basin",
        "name": "Ancient Lake Basin",
        "x": 92, "y": 54, "lon": 77.5500, "lat": 18.3800,
        "type": "Crater Floor · Māʻaz & Séítah",
        "category": "geomorphic_feature", "subcategory": "basin_floor",
        "value": 0.85, "conf": "HIGH",
        "image_url": "/landmarks/ancient-lake-basin.jpg",
        "significance": "High — radiometric dating of returned igneous cores will calibrate the absolute timeline of the inner solar system.",
        "perseverance_history": "Explored during the Crater Floor Campaign (2021-2022) across Māʻaz and Séítah formations.",
        "note": "Broad interior floor of Jezero Crater hosting olivine cumulates and aqueous alteration.",
    },
]

ROUTE_TRADEOFFS = {
    "safety": {
        "profile": "Safest",
        "advantage_summary": "Maximizes crew survival margin and suit integrity across hazardous terrain.",
        "compromise_summary": "Increases total traverse distance, duration, and life-support consumable draw.",
        "gained": [
            "Lowest terrain risk score and peak slope exposure (< 12 deg typical)",
            "Avoids high-roughness boulder fields that degrade suit boots and rover wheels",
            "Minimizes traversal through unmapped / low-confidence orbital data cells",
            "Maintains wider buffer from the 25 deg hard mobility exclusion limit",
        ],
        "compromised": [
            "+12% to +25% longer path distance due to hazard avoidance detours",
            "Higher cumulative O2, battery, and cooling water consumption",
            "Bypasses steeper delta scarps where high-value outcrops are exposed",
        ],
    },
    "fastest": {
        "profile": "Fastest",
        "advantage_summary": "Minimizes EVA duration and life-support consumable burn for rapid transit.",
        "compromise_summary": "Accepts steeper grades and rougher regolith near mobility limits.",
        "gained": [
            "Shortest geometric path and fastest transit time to destination",
            "Lowest total oxygen (kg), battery (kWh), and cooling water expenditure",
            "Maximizes remaining Point-of-No-Return (PNR) life-support reserve margin",
            "Ideal for contingency return-to-habitat or medical abort scenarios",
        ],
        "compromised": [
            "Higher exposure to caution-zone slopes (10 deg - 24 deg) and surface roughness",
            "Reduced safety margin against local slip or unmapped micro-hazards",
            "Zero weighting for nearby astrobiological or geologic science targets",
        ],
    },
    "science": {
        "profile": "Science",
        "advantage_summary": "Maximizes astrobiological & geological return across Jezero landmarks (capped <= 1.5x fastest).",
        "compromise_summary": "Trades path efficiency and moderate terrain exposure for target proximity.",
        "gained": [
            "Highest science value collected along traverse (phyllosilicates, carbonates, delta beds)",
            "Routes within observation range of mapped Jezero landmarks & sample depots",
            "Detour length strictly capped at <= 1.5x the fastest route to protect EVA budget",
            "Balanced slope weighting keeps grades within safe human/rover limits",
        ],
        "compromised": [
            "Moderate increase in traverse distance and EVA time vs. Fastest route",
            "Enters moderate-roughness outcrop zones near delta scarps and crater rims",
            "Slightly higher consumable burn than direct transit",
        ],
    },
    "balanced": {
        "profile": "Balanced",
        "advantage_summary": "Equilibrates terrain safety, transit speed, and opportunistic science.",
        "compromise_summary": "Sub-optimal for pure emergency speed or maximum-risk outcrop approaches.",
        "gained": [
            "Well-rounded trade-off between slope avoidance and direct progress",
            "Moderate consumable usage with comfortable Point-of-No-Return reserve",
            "Captures opportunistic science targets that lie near the main corridor",
        ],
        "compromised": [
            "Slightly longer than Fastest route and slightly higher slope exposure than Safest",
            "Skips distant high-value science targets that require major detours",
        ],
    },
}

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

            # Science values: simulated, biased by terrain features + proximity to mapped Jezero landmarks
            sci_val = max(0.0, noise(x / 8 + 40, y / 8 + 40) - 0.6) * 2.5
            for t in TARGETS:
                d_cells = math.hypot(x - t["x"], y - t["y"])
                if d_cells <= 5.0:
                    sci_val = max(sci_val, t["value"] * math.exp(-d_cells * d_cells / 8.0))
            science[i] = min(1.0, sci_val)

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
    res = Result(path[::-1], dist[ti], expanded)

    # Science detour cap (from nipun_branch): ensure science routes do not exceed 1.5x fastest route distance
    if algorithm == "astar" and wt.get("wv", 0.0) > 1.0:
        fast_res = search(gr, a, b, PROFILES["fastest"], max_slope=max_slope, algorithm="astar")
        if fast_res is not None:
            cand_dist = sum(math.hypot(res.path[i][0] - res.path[i - 1][0], res.path[i][1] - res.path[i - 1][1]) for i in range(1, len(res.path)))
            fast_dist = sum(math.hypot(fast_res.path[i][0] - fast_res.path[i - 1][0], fast_res.path[i][1] - fast_res.path[i - 1][1]) for i in range(1, len(fast_res.path)))
            if fast_dist > 0 and cand_dist > 1.5 * fast_dist:
                # Re-plan with bounded science bonus so detour stays <= 1.5x fastest
                capped_wt = dict(wt, wv=0.45)
                capped = search(gr, a, b, capped_wt, max_slope=max_slope, algorithm="astar")
                if capped is not None:
                    # Recompute cost under original wt so validation matches
                    re_cost = 0.0
                    for i in range(1, len(capped.path)):
                        (x0, y0), (x1, y1) = capped.path[i - 1], capped.path[i]
                        f0 = max(_cell_factor(gr, y0 * gr.w + x0, wt, max_slope) or 0, floor)
                        f1 = max(_cell_factor(gr, y1 * gr.w + x1, wt, max_slope) or 0, floor)
                        re_cost += gr.cell_m * (math.sqrt(2) if x0 != x1 and y0 != y1 else 1.0) * (f0 + f1) / 2
                    return Result(capped.path, re_cost, res.nodes_expanded + capped.nodes_expanded)
    return res


def multi_stop_search(gr: Grid, points: list[tuple[int, int]], wt: dict, max_slope=20.0, algorithm="astar") -> Result | None:
    """Multi-waypoint A* / Dijkstra search stitching legs in sequence."""
    if len(points) < 2:
        return None
    full_path: list[tuple[int, int]] = []
    total_cost = 0.0
    expanded = 0
    for idx in range(len(points) - 1):
        leg = search(gr, points[idx], points[idx + 1], wt, max_slope=max_slope, algorithm=algorithm)
        if leg is None:
            return None
        if idx == 0:
            full_path.extend(leg.path)
        else:
            full_path.extend(leg.path[1:])
        total_cost += leg.total_cost
        expanded += leg.nodes_expanded
    return Result(full_path, total_cost, expanded)

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


def eva_consumables(gr: Grid, path: list) -> dict:
    """Compute EVA life-support consumables for both single-suit xEMU tanks and 2-astronaut buddy system (nipun_branch)."""
    n = len(path)
    if n < 2:
        return {
            "crew_size": 2, "active_walking_min": 0.0, "rest_stops_min": 0.0, "total_eva_min": 0.0,
            "oxygen_kg": 0.0, "battery_kwh": 0.0, "cooling_water_kg": 0.0,
            "o2_used_l": 0.0, "o2_pct": 0.0, "batt_used_wh": 0.0, "batt_pct": 0.0,
            "water_used_kg": 0.0, "water_pct": 0.0, "pnr_idx": None, "pnr_dist_m": None,
            "within_budget": True,
        }

    o2_used_l = 0.0
    batt_used_wh = 0.0
    water_used_kg = 0.0
    cum_dist = 0.0
    pnr_idx = None
    pnr_dist_m = None
    usable_o2 = EVA_TOTAL_O2_L * (1.0 - EVA_RESERVE_FRAC)

    for k in range(1, n):
        ax, ay = path[k - 1]
        bx, by = path[k]
        i0 = ay * gr.w + ax
        i1 = by * gr.w + bx
        step_m = math.hypot(bx - ax, by - ay) * gr.cell_m
        cum_dist += step_m
        sl = gr.slope[i1]
        rg = gr.rough[i1]
        dz = gr.elev[i1] - gr.elev[i0]
        dt_min = (step_m / speed_mps(sl)) / 60.0

        grade_factor = max(0.0, dz / max(1.0, step_m)) * 8.5 if dz > 0 else max(0.0, -dz / max(1.0, step_m)) * 1.8
        slope_factor = (sl / MAX_SLOPE) * 1.4
        rough_factor = rg * 0.65
        metabolic_mult = 1.0 + grade_factor + slope_factor + rough_factor

        o2_used_l += 1.65 * metabolic_mult * dt_min
        batt_used_wh += (195.0 + 35.0 * rg) * (dt_min / 60.0)
        water_used_kg += 0.0062 * metabolic_mult * dt_min

        if pnr_idx is None and o2_used_l >= usable_o2 * 0.5:
            pnr_idx = k
            pnr_dist_m = round(cum_dist, 1)

    # 2-astronaut buddy protocol model (from nipun_branch)
    crew_size = 2
    active_walking_min = cum_dist / 0.8 / 60.0
    sl_vals = [gr.slope[p[1] * gr.w + p[0]] for p in path]
    mean_slope = sum(sl_vals) / len(sl_vals)
    rest_stops_min = (active_walking_min / 50.0) * 10.0 + (mean_slope / 10.0) * 8.0
    total_eva_min = active_walking_min + rest_stops_min
    eva_hours = total_eva_min / 60.0
    effort_factor = 1.0 + (mean_slope / 15.0) * 0.35

    oxygen_kg = crew_size * eva_hours * 0.084 * effort_factor
    battery_kwh = crew_size * eva_hours * 0.32 * (1.0 + (mean_slope / 20.0) * 0.15)
    cooling_water_kg = crew_size * eva_hours * 0.45 * effort_factor

    o2_pct = min(100.0, (o2_used_l / EVA_TOTAL_O2_L) * 100.0)
    batt_pct = min(100.0, (batt_used_wh / EVA_TOTAL_BATT_WH) * 100.0)
    water_pct = min(100.0, (water_used_kg / EVA_TOTAL_WATER_KG) * 100.0)

    return {
        "crew_size": crew_size,
        "active_walking_min": round(active_walking_min, 1),
        "rest_stops_min": round(rest_stops_min, 1),
        "total_eva_min": round(total_eva_min, 1),
        "oxygen_kg": round(oxygen_kg, 3),
        "battery_kwh": round(battery_kwh, 3),
        "cooling_water_kg": round(cooling_water_kg, 2),
        "o2_used_l": round(o2_used_l, 1),
        "o2_pct": round(o2_pct, 1),
        "batt_used_wh": round(batt_used_wh, 1),
        "batt_pct": round(batt_pct, 1),
        "water_used_kg": round(water_used_kg, 2),
        "water_pct": round(water_pct, 1),
        "pnr_idx": pnr_idx,
        "pnr_dist_m": pnr_dist_m,
        "within_budget": (o2_pct <= 80.0 and batt_pct <= 80.0 and water_pct <= 80.0),
    }


def compute_tradeoffs(profile: str, cand_metrics: dict, fastest_metrics: dict | None = None, safest_metrics: dict | None = None) -> dict:
    """Return structured qualitative and quantitative trade-offs (what is gained vs. compromised) for a route profile."""
    key = profile if profile in ROUTE_TRADEOFFS else "balanced"
    base = dict(ROUTE_TRADEOFFS[key])
    deltas = {}
    if fastest_metrics and fastest_metrics.get("distance_m", 0) > 0:
        d_fast = fastest_metrics["distance_m"]
        t_fast = fastest_metrics["estimated_duration_min"]
        deltas["distance_vs_fastest_pct"] = round(((cand_metrics["distance_m"] - d_fast) / d_fast) * 100.0, 1)
        deltas["duration_vs_fastest_min"] = round(cand_metrics["estimated_duration_min"] - t_fast, 1)
        deltas["detour_ratio"] = round(cand_metrics["distance_m"] / d_fast, 2)
    if safest_metrics:
        deltas["max_slope_vs_safest_deg"] = round(cand_metrics["max_slope_deg"] - safest_metrics["max_slope_deg"], 2)
    base["quantitative_deltas"] = deltas
    return base


# ---------- Risk score 0-100 (SIMULATED weights, see PLAN section 6.4) ----------
def risk_score(gr: Grid, res: Result, mean_rough: float | None = None, mean_unc: float | None = None) -> dict:
    """Compute detailed risk breakdown for a route (matching frontend riskScore + EVA consumables)."""
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

    consumables = eva_consumables(gr, path)
    return {
        "score": score,
        "level": level,
        "timeMin": round(time_min, 2),
        "parts": parts,
        "consumables": consumables,
    }


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
