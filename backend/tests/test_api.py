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


def test_environment_unavailable_not_fabricated():
    assert c.get("/api/environment").status_code == 503


def test_mission_roundtrip_404():
    assert c.get("/api/missions/nope").json()["error"]["code"] == "NOT_FOUND"
