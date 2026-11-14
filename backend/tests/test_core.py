import math, unittest
from app.core import synthetic_grid, load_real_grid, search, validate, metrics, risk_score, pick_landmarks, PROFILES, Grid

class CoreTests(unittest.TestCase):
    def setUp(self): self.g = synthetic_grid()

    def test_load_real_grid(self):
        rg = load_real_grid()
        self.assertEqual(rg.w, 120)
        self.assertEqual(rg.h, 76)
        self.assertEqual(rg.terrain_source, "HiRISE_DTM")
        self.assertAlmostEqual(rg.cell_m, 35.99)
        r = search(rg, (10, 38), (100, 40), PROFILES["balanced"])
        self.assertIsNotNone(r)
        lms = pick_landmarks(rg, r)
        self.assertIn(len(lms), (5, 6))
        rk = risk_score(rg, r)
        self.assertTrue(0 <= rk["score"] <= 100)

    def test_astar_matches_dijkstra_cost(self):
        for name, wt in PROFILES.items():
            a = search(self.g, (2, 2), (75, 55), wt, algorithm="astar")
            d = search(self.g, (2, 2), (75, 55), wt, algorithm="dijkstra")
            self.assertIsNotNone(a); self.assertAlmostEqual(a.total_cost, d.total_cost, places=6, msg=name)
            self.assertLessEqual(a.nodes_expanded, d.nodes_expanded)

    def test_validation_passes(self):
        wt = PROFILES["balanced"]; r = search(self.g, (2, 2), (60, 40), wt)
        self.assertTrue(all(validate(self.g, r, wt, 20.0).values()))

    def test_flat_grid_is_straight_and_positive(self):
        n = 20
        g = Grid(n, n, 100.0, [0.0] * n * n, [0.0] * n * n, [0.0] * n * n, [0.0] * n * n)
        r = search(g, (0, 0), (10, 0), PROFILES["safety"])
        self.assertAlmostEqual(metrics(g, r)["distance_m"], 1000.0)
        self.assertGreater(r.total_cost, 0)

    def test_blocked_endpoint_and_no_route(self):
        n = 10
        slope = [0.0] * n * n
        for y in range(n): slope[y * n + 5] = 45.0  # impassable wall
        g = Grid(n, n, 100.0, [0.0] * n * n, slope, [0.0] * n * n, [0.0] * n * n)
        self.assertIsNone(search(g, (0, 0), (9, 9), PROFILES["balanced"]))
        self.assertIsNone(search(g, (5, 0), (9, 9), PROFILES["balanced"]))

    def test_safety_not_steeper_than_fastest(self):
        s = metrics(self.g, search(self.g, (2, 2), (75, 55), PROFILES["safety"]))
        f = metrics(self.g, search(self.g, (2, 2), (75, 55), PROFILES["fastest"]))
        self.assertLessEqual(s["mean_slope_deg"], f["mean_slope_deg"] + 1e-9)
        self.assertGreaterEqual(s["distance_m"], f["distance_m"] - 1e-9)

if __name__ == "__main__": unittest.main()
