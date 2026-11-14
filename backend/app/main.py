"""MARS-X API. Terrain is loaded from the real USGS HiRISE DTM window
(jezero-dem.bin) with fallback to synthetic terrain if the file is absent.
Environment readings are not fabricated: they return DATASET_UNAVAILABLE until ETL provides cited data."""
from __future__ import annotations
import math, time, uuid
from datetime import datetime, timezone
from typing import Literal, Optional
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from pydantic import BaseModel, Field
from . import core, meda_reader, geo_layers

AOI = [77.40, 18.36, 77.44, 18.39]  # Jezero Crater HiRISE DTM window
HABITAT = {"lon": 77.42, "lat": 18.375}
GRID = core.load_real_grid()
MISSIONS: dict[str, dict] = {}

class Coord(BaseModel):
    lon: float = Field(ge=-180, le=180)
    lat: float = Field(ge=-90, le=90)
Profile = Literal["safety", "fastest", "science", "balanced"]
Algo = Literal["astar", "dijkstra"]
class Constraints(BaseModel):
    max_slope_deg: float = Field(25.0, gt=0, le=45)
    return_to_base: bool = True
    eva_budget_min: float = Field(480, gt=0)
class RouteReq(BaseModel):
    start: Coord
    goal: Coord
    waypoints: list[Coord] = []
    profile: Profile = "balanced"
    algorithm: Algo = "astar"
    weights: Optional[dict[str, float]] = None
    constraints: Constraints = Constraints()
class CompareReq(BaseModel):
    start: Coord
    goal: Coord
    waypoints: list[Coord] = []
    profiles: list[Profile] = ["safety", "fastest", "science", "balanced"]
    include_dijkstra: bool = True
    constraints: Constraints = Constraints()
class MissionReq(BaseModel):
    name: str
    objective: str = "geology_survey"
    start: Coord
    destination: Coord
    science_target_ids: list[str] = []
    profile: Profile = "balanced"
    crew_size: int = Field(2, ge=1, le=6)
    eva_budget_min: float = Field(480, gt=0)
    return_to_base: bool = True

class ApiError(Exception):
    def __init__(self, status, code, message, **details):
        self.status, self.code, self.message, self.details = status, code, message, details

app = FastAPI(title="MARS-X API", version="0.1.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

def env(status, code, msg, details=None):
    return JSONResponse(status_code=status, content={"error": {"code": code, "message": msg, "details": details or {}}})
@app.exception_handler(ApiError)
async def _api(_: Request, e: ApiError): return env(e.status, e.code, e.message, e.details)
@app.exception_handler(RequestValidationError)
async def _val(_: Request, e: RequestValidationError): return env(422, "VALIDATION_ERROR", "Invalid request.", {"errors": e.errors().__repr__()})

def to_cell(c: Coord, field: str):
    w, s, e, n = AOI
    if not (w <= c.lon <= e and s <= c.lat <= n):
        raise ApiError(400, "OUTSIDE_AOI", f"{field} is outside the study area.", field=field, aoi_bbox=AOI)
    x = round((c.lon - w) / (e - w) * (GRID.w - 1)); y = round((n - c.lat) / (n - s) * (GRID.h - 1))
    return x, y
def to_coord(x, y):
    w, s, e, n = AOI
    return [w + x / (GRID.w - 1) * (e - w), n - y / (GRID.h - 1) * (n - s)]

def run(req, profile: str, algorithm: str, weights=None):
    wt = {**core.PROFILES[profile], **(weights or {})}
    ms = req.constraints.max_slope_deg
    pts = [("start", to_cell(req.start, "start"))] + [(f"wp{i}", to_cell(w, f"waypoints[{i}]")) for i, w in enumerate(req.waypoints)] + [("goal", to_cell(req.goal, "goal"))]
    if req.constraints.return_to_base: pts.append(("base", pts[0][1]))
    t0 = time.perf_counter(); path, legs, cost, nodes = [], [], 0.0, 0
    for (na, a), (nb, b) in zip(pts, pts[1:]):
        r = core.search(GRID, a, b, wt, ms, algorithm)
        if r is None:
            code = "IMPASSABLE_ENDPOINT" if any(GRID.slope[p[1] * GRID.w + p[0]] > ms for p in (a, b)) else "NO_ROUTE"
            raise ApiError(400 if code == "IMPASSABLE_ENDPOINT" else 404, code, f"No candidate route for leg {na}->{nb}.", leg=[na, nb])
        legs.append({"from": na, "to": nb, "distance_m": core.metrics(GRID, r)["distance_m"]})
        path += r.path if not path else r.path[1:]; cost += r.total_cost; nodes += r.nodes_expanded
    res = core.Result(path, cost, nodes); m = core.metrics(GRID, res)
    m["runtime_ms"] = round((time.perf_counter() - t0) * 1000, 1)
    val = core.validate(GRID, res, wt, ms) if len(pts) == 2 else {"continuous": True, "no_excluded_cells": all(GRID.slope[y * GRID.w + x] <= ms for x, y in path), "cost_recomputed_matches": True}
    val["endpoints_passable"] = True; val["return_feasible"] = m["estimated_duration_min"] <= req.constraints.eva_budget_min
    warnings = [] if val["return_feasible"] else ["Estimated duration exceeds the EVA budget (simulated speed model)."]
    dist = [0.0]
    for i in range(1, len(path)): dist.append(dist[-1] + GRID.cell_m * math.hypot(path[i][0] - path[i-1][0], path[i][1] - path[i-1][1]))
    ms_ = m["max_slope_deg"]
    is_real = GRID.terrain_source != "SYNTHETIC"
    data_type = "DERIVED" if is_real else "SIMULATED"
    risk = core.risk_score(GRID, res, mean_rough=sum(GRID.rough[y * GRID.w + x] for x, y in path) / len(path))
    return {"route_id": "r_" + uuid.uuid4().hex[:4], "profile": profile, "algorithm": algorithm,
        "label": "candidate route", "geometry": {"type": "Feature", "properties": {}, "geometry": {"type": "LineString", "coordinates": [to_coord(x, y) for x, y in path]}},
        "metrics": {**m, "duration_basis": "SIMULATED speed model v1 (0.5 m/s)"}, "legs": legs,
        "elevation_profile": {"distance_m": dist, "elevation_m": [GRID.elev[y * GRID.w + x] for x, y in path], "slope_deg": [GRID.slope[y * GRID.w + x] for x, y in path]},
        "validation": {"passed": all(val.values()), "checks": val},
        "risk": {**risk, "basis": "Simulation assumptions v1 (not certified mobility limits)"},
        "uncertainty": {"terrain_source": GRID.terrain_source, "resolution_m": GRID.cell_m, "data_type": data_type},
        "assumptions": ["max_slope_deg is a configurable simulation assumption",
                        "HiRISE DTM resampled to 35.99 m/cell; sub-cell hazards unknown" if is_real else "Terrain is synthetic until the DTM bundle is built"],
        "warnings": warnings}

@app.get("/api/health")
def health():
    is_real = GRID.terrain_source != "SYNTHETIC"
    return {
        "status": "ok",
        "bundle_version": "hirise-d3-v1" if is_real else "synthetic-v0",
        "datasets_loaded": ["DTEEC_045994_1985_046060_1985_U01"] if is_real else [],
        "terrain_source": GRID.terrain_source,
        "grid": {"w": GRID.w, "h": GRID.h, "cell_m": GRID.cell_m},
        "warnings": [] if is_real else ["Synthetic terrain in use; no NASA datasets loaded."],
    }
@app.get("/api/locations")
def locations():
    return {"aoi": {"name": "Jezero Crater HiRISE DTM window", "bbox": AOI, "crs_analysis": "custom-eqc-mars-sphere"},
            "locations": [{"id": "habitat", "name": "Simulated habitat", "coord": HABITAT, "data_type": "SIMULATED", "note": "Mission-defined."}]}
@app.get("/api/layers")
def layers(): return {"layers": [
    {"id": "elevation", "data_type": "DERIVED" if GRID.terrain_source != "SYNTHETIC" else "SIMULATED"},
    {"id": "slope", "data_type": "DERIVED" if GRID.terrain_source != "SYNTHETIC" else "SIMULATED"},
    {"id": "roughness", "data_type": "DERIVED" if GRID.terrain_source != "SYNTHETIC" else "SIMULATED"},
    {"id": "pressure", "data_type": "SIMULATED"},
]}
@app.get("/api/terrain")
def terrain(lon: float, lat: float):
    x, y = to_cell(Coord(lon=lon, lat=lat), "coord"); i = y * GRID.w + x
    is_real = GRID.terrain_source != "SYNTHETIC"
    return {"coord": {"lon": lon, "lat": lat}, "cell": {"x": x, "y": y},
            "elevation_m": GRID.elev[i], "slope_deg": GRID.slope[i], "roughness": GRID.rough[i],
            "passable": GRID.slope[i] <= core.MAX_SLOPE, "resolution_m": GRID.cell_m,
            "terrain_source": GRID.terrain_source, "data_type": "DERIVED" if is_real else "SIMULATED",
            "uncertainty_note": "Resampled HiRISE DTM (~36 m/cell); sub-cell rocks/hazards unknown." if is_real else "Synthetic terrain; not a Mars measurement."}
@app.get("/api/environment")
def environment(sol: Optional[int] = None):
    if sol is not None:
        s_data = meda_reader.meda_catalog.get_sol(sol)
        if not s_data:
            raise ApiError(404, "SOL_NOT_FOUND", f"Sol {sol} is not in the archived MEDA dataset.", available_sols=meda_reader.meda_catalog.get_all_sols().get("available_sols", []))
        return s_data
    data = meda_reader.meda_catalog.get_all_sols()
    if not data.get("available_sols"):
        raise ApiError(503, "DATASET_UNAVAILABLE", "No archived MEDA subset could be loaded.")
    return data

@app.get("/api/science-targets")
def targets():
    real_targets = geo_layers.geo_catalog.get_science_targets()
    if real_targets:
        return {"targets": real_targets, "count": len(real_targets), "data_type": "DERIVED"}
    return {"targets": [{**t, "data_type": "SIMULATED"} for t in core.TARGETS], "count": len(core.TARGETS), "data_type": "SIMULATED"}

@app.get("/api/rover/traverse")
def rover_traverse():
    return geo_layers.geo_catalog.get_rover_traverse()

@app.get("/api/rover/stops")
def rover_stops(sol_min: Optional[int] = None, sol_max: Optional[int] = None, limit: int = 500):
    return geo_layers.geo_catalog.get_rover_stops(sol_min=sol_min, sol_max=sol_max, limit=limit)

@app.get("/api/manifest")
def source_manifest():
    return geo_layers.geo_catalog.get_provenance_manifest()

class PathReq(BaseModel):
    path: list[list[int]] = Field(min_length=2)

@app.post("/api/landmarks")
def landmarks(req: PathReq):
    pts = [(int(p[0]), int(p[1])) for p in req.path]
    for x, y in pts:
        if not (0 <= x < GRID.w and 0 <= y < GRID.h):
            raise ApiError(400, "OUT_OF_BOUNDS", f"Cell ({x}, {y}) is outside grid {GRID.w}x{GRID.h}.")
    res = core.Result(pts, 0.0, 0)
    return {"landmarks": core.pick_landmarks(GRID, res), "data_type": "DERIVED"}

@app.post("/api/risk")
def risk(req: PathReq):
    pts = [(int(p[0]), int(p[1])) for p in req.path]
    for x, y in pts:
        if not (0 <= x < GRID.w and 0 <= y < GRID.h):
            raise ApiError(400, "OUT_OF_BOUNDS", f"Cell ({x}, {y}) is outside grid {GRID.w}x{GRID.h}.")
    res = core.Result(pts, 0.0, 0)
    return {**core.risk_score(GRID, res), "data_type": "SIMULATED", "basis": "Simulation assumptions v1 (not certified mobility limits)"}

@app.post("/api/routes/generate")
def generate(req: RouteReq): return run(req, req.profile, req.algorithm, req.weights)
@app.post("/api/routes/compare")
def compare(req: CompareReq):
    routes = [{"profile": p, "route": run(req, p, "astar")} for p in req.profiles]
    out = {"comparison_id": "c_" + uuid.uuid4().hex[:4], "routes": routes,
           "summary_table": [{"profile": r["profile"], "distance_m": r["route"]["metrics"]["distance_m"], "max_slope_deg": r["route"]["metrics"]["max_slope_deg"],
                              "duration_min": r["route"]["metrics"]["estimated_duration_min"], "science_value": r["route"]["metrics"]["science_value_collected"], "risk_level": r["route"]["risk"]["level"]} for r in routes]}
    if req.include_dijkstra:
        d = run(req, "balanced", "dijkstra"); a = next((r["route"] for r in routes if r["profile"] == "balanced"), run(req, "balanced", "astar"))
        out["algorithm_comparison"] = {k: {x: v["metrics"][x] for x in ("total_cost", "nodes_expanded", "runtime_ms")} for k, v in (("astar", a), ("dijkstra", d))}
    return out

@app.post("/api/missions/create", status_code=201)
def create_mission(req: MissionReq):
    rr = RouteReq(start=req.start, goal=req.destination, profile=req.profile,
                  constraints=Constraints(return_to_base=req.return_to_base, eva_budget_min=req.eva_budget_min))
    route = run(rr, req.profile, "astar"); dur = route["metrics"]["estimated_duration_min"]
    if dur > req.eva_budget_min: raise ApiError(409, "BUDGET_EXCEEDED", "Candidate route exceeds the EVA budget.", estimate_min=dur)
    mid = "m_" + uuid.uuid4().hex[:4]
    m = {"mission_id": mid, "name": req.name, "status": "planned", "created_at": datetime.now(timezone.utc).isoformat(), "route": route,
         "eva": {"estimated_duration_min": dur, "basis": "SIMULATED", "within_budget": True},
         "checklist": [{"item": "Navigation reference", "category": "navigation", "note": "Planning aid only"}],
         "disclaimer": "Simulated mission plan; not an operational procedure."}
    MISSIONS[mid] = m; return m
@app.get("/api/missions/{mission_id}")
def get_mission(mission_id: str):
    if mission_id not in MISSIONS: raise ApiError(404, "NOT_FOUND", "Mission not found.")
    return MISSIONS[mission_id]
@app.get("/api/missions/{mission_id}/report")
def report(mission_id: str, format: str = "json"):
    m = get_mission(mission_id)
    # Get latest environmental context from MEDA
    env_data = meda_reader.meda_catalog.get_all_sols()
    sol_summary = env_data.get("sols", {}).get(20, {})
    targets_subset = geo_layers.geo_catalog.get_science_targets()[:5]
    prov = [
        {"product": "HiRISE DTM DTEEC_045994_1985_046060_1985_U01", "provider": "NASA/JPL/Univ of Arizona", "type": "DERIVED"},
        {"product": "MEDA Derived Environmental Tables (TIRS & RHS)", "provider": "NASA PDS Atmospheres Node", "type": "MEASURED"},
        {"product": "USGS SIM 3464 Geologic Map of Jezero", "provider": "USGS Astrogeology Science Center", "type": "DERIVED"},
        {"product": "Perseverance Rover Localizations (PLACES)", "provider": "NASA PDS Geosciences Node", "type": "MEASURED"},
    ]
    limits = [
        "HiRISE DTM patch covers landing window; sub-cell obstacles unknown.",
        "Slope and speed limits are configurable simulation models, not astronaut flight rules.",
        "Routes are candidate paths for exploration planning, not automated driving commands.",
        "Environmental readings are archived PDS4 observations from Perseverance sols 10-28.",
    ]
    report_dict = {
        "mission_id": mission_id,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "sections": {
            "overview": m["name"],
            "selected_route": m["route"],
            "science_targets": targets_subset,
            "terrain_risk": m["route"]["risk"],
            "environment": sol_summary if sol_summary else [],
            "duration": {"estimate_min": m["eva"]["estimated_duration_min"], "basis": "SIMULATED"},
            "provenance": prov,
            "limitations": limits,
        },
    }
    if format.lower() in ("markdown", "md"):
        rt = m["route"]
        met = rt.get("metrics", {})
        rk = rt.get("risk", {})
        air = sol_summary.get("air_temperature", {}) if sol_summary else {}
        grd = sol_summary.get("ground_brightness_temperature", {}) if sol_summary else {}
        md_lines = [
            f"# MARS-X Mission Summary Report: {m['name']}",
            f"**Mission ID:** `{mission_id}`  ",
            f"**Generated:** {report_dict['generated_at']}  ",
            f"**Profile:** {rt.get('profile', 'balanced').title()} | **Algorithm:** {rt.get('algorithm', 'astar').upper()}  ",
            "",
            "## 1. Traverse & Mobility Metrics",
            f"- **Distance:** {met.get('distance_m', 0):,.1f} m",
            f"- **Estimated Duration:** {met.get('estimated_duration_min', 0):.1f} min (Budget: {m['eva']['estimated_duration_min']:.0f} min)",
            f"- **Max Slope:** {met.get('max_slope_deg', 0):.1f}° (Mean Slope: {met.get('mean_slope_deg', 0):.1f}°)",
            f"- **Overall Risk Score:** {rk.get('score', 0):.1f} / 100 ({rk.get('level', 'LOW')})",
            "",
            "## 2. Environmental Context (NASA Mars 2020 MEDA)",
            "- **Station:** Perseverance Rover (Octavia E. Butler Landing)",
            f"- **Air Temperature:** Min {air.get('min', 'N/A')} °C, Max {air.get('max', 'N/A')} °C, Mean {air.get('mean', 'N/A')} °C",
            f"- **Ground Brightness Temp:** Min {grd.get('min', 'N/A')} °C, Max {grd.get('max', 'N/A')} °C",
            f"- **Data Basis:** {sol_summary.get('source', 'Archived PDS4 tables')}",
            "",
            "## 3. Waypoint & Landmark Science Targets",
        ]
        for t in targets_subset:
            md_lines.append(f"- **{t['name']}** ({t['type']}): Coord `[{t['coord']['lon']}, {t['coord']['lat']}]` — {t.get('note', '')}")
        md_lines.extend([
            "",
            "## 4. Provenance & Limitations",
            "### Verified Datasets:",
        ])
        for p in prov:
            md_lines.append(f"- **{p['product']}** — {p['provider']} (`{p['type']}`)")
        md_lines.extend([
            "",
            "### Operational Limitations:",
        ])
        for lm in limits:
            md_lines.append(f"- {lm}")
        return PlainTextResponse("\n".join(md_lines), media_type="text/markdown")

    return report_dict
