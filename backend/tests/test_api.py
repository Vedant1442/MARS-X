import pytest
from fastapi.testclient import TestClient
from app.main import app

c = TestClient(app)
S = {"lon": 77.40672, "lat": 18.38200}
G = {"lon": 77.42689, "lat": 18.37400}


def test_health_real_terrain():
    r = c.get("/api/health")
    assert r.status_code == 200
    data = r.json()
    assert data["status"] == "ok"
    assert data["grid"] == {"w": 120, "h": 76, "cell_m": 35.99}
    assert data["terrain_source"] == "HiRISE_DTM"


def test_terrain_point():
    r = c.get("/api/terrain", params={"lon": 77.42, "lat": 18.375})
    assert r.status_code == 200
    data = r.json()
    assert -2600 < data["elevation_m"] < -2350
    assert data["terrain_source"] == "HiRISE_DTM"


def test_generate_and_validate():
    r = c.post("/api/routes/generate", json={"start": S, "goal": G, "constraints": {"return_to_base": False}}).json()
    assert r["validation"]["passed"] and r["label"] == "candidate route"
    assert "parts" in r["risk"] and 0 <= r["risk"]["score"] <= 100


def test_outside_aoi():
    r = c.post("/api/routes/generate", json={"start": {"lon": 0, "lat": 0}, "goal": G})
    assert r.status_code == 400 and r.json()["error"]["code"] == "OUTSIDE_AOI"


def test_compare_astar_dijkstra_agree():
    r = c.post("/api/routes/compare", json={"start": S, "goal": G, "constraints": {"return_to_base": False}}).json()
    a = r["algorithm_comparison"]
    assert abs(a["astar"]["total_cost"] - a["dijkstra"]["total_cost"]) < 1e-6


def test_landmarks_and_risk_endpoints():
    path = [[x, 38] for x in range(10, 90)]
    lm = c.post("/api/landmarks", json={"path": path})
    assert lm.status_code == 200
    lms = lm.json()["landmarks"]
    assert 5 <= len(lms) <= 6
    assert lms[0]["kind"] == "start" and lms[-1]["kind"] == "dest"

    rk = c.post("/api/risk", json={"path": path})
    assert rk.status_code == 200
    assert 0 <= rk.json()["score"] <= 100


def test_environment_measured_data():
    r = c.get("/api/environment")
    assert r.status_code == 200
    data = r.json()
    assert data["data_type"] == "MEASURED"
    assert 10 in data["available_sols"] and 20 in data["available_sols"]
    assert "provenance" in data


def test_environment_single_sol():
    r = c.get("/api/environment", params={"sol": 20})
    assert r.status_code == 200
    data = r.json()
    assert data["sol"] == 20
    assert data["air_temperature"]["mean"] < 0  # Mars temperatures are subzero
    assert data["data_type"] == "MEASURED"


def test_environment_unknown_sol():
    r = c.get("/api/environment", params={"sol": 9999})
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "SOL_NOT_FOUND"


def test_science_targets():
    r = c.get("/api/science-targets")
    assert r.status_code == 200
    data = r.json()
    assert data["count"] > 0
    names = [t["name"] for t in data["targets"]]
    assert "Octavia E. Butler Landing" in names


def test_rover_traverse_and_stops():
    trav = c.get("/api/rover/traverse")
    assert trav.status_code == 200
    assert trav.json()["type"] == "FeatureCollection"

    stops = c.get("/api/rover/stops", params={"limit": 10})
    assert stops.status_code == 200
    assert len(stops.json()["features"]) <= 10
    assert stops.json()["data_type"] == "MEASURED"


def test_mission_roundtrip_with_report():
    # 404 check
    assert c.get("/api/missions/nope").json()["error"]["code"] == "NOT_FOUND"

    # Create mission
    m = c.post("/api/missions/create", json={
        "name": "Delta Survey Sol 1",
        "start": S,
        "destination": G,
        "profile": "balanced",
        "return_to_base": False,
        "eva_budget_min": 480
    })
    assert m.status_code == 201
    mid = m.json()["mission_id"]

    # Fetch report
    rep = c.get(f"/api/missions/{mid}/report")
    assert rep.status_code == 200
    report_data = rep.json()
    assert report_data["sections"]["overview"] == "Delta Survey Sol 1"
    assert len(report_data["sections"]["provenance"]) > 0
    assert "environment" in report_data["sections"]

    # Fetch markdown report
    rep_md = c.get(f"/api/missions/{mid}/report", params={"format": "markdown"})
    assert rep_md.status_code == 200
    assert "# MARS-X Mission Summary Report" in rep_md.text
    assert "Traverse & Mobility Metrics" in rep_md.text
