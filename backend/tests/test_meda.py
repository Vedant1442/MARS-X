import unittest
from app.meda_reader import meda_catalog


class TestMedaReader(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        meda_catalog.load()

    def test_sols_available(self):
        sols = meda_catalog.get_all_sols()["available_sols"]
        self.assertIn(10, sols)
        self.assertIn(14, sols)
        self.assertIn(20, sols)
        self.assertIn(28, sols)

    def test_sol_20_temperature(self):
        sol20 = meda_catalog.get_sol(20)
        self.assertIsNotNone(sol20)
        self.assertEqual(sol20["sol"], 20)
        self.assertEqual(sol20["data_type"], "MEASURED")

        # Mars temperatures should be well below 0 C
        air_t = sol20["air_temperature"]
        self.assertLess(air_t["mean"], 0)
        self.assertLess(air_t["min"], -50)

        ground_t = sol20["ground_brightness_temperature"]
        self.assertIsNotNone(ground_t)
        self.assertLess(ground_t["mean"], 0)

    def test_diurnal_samples(self):
        sol28 = meda_catalog.get_sol(28)
        self.assertIsNotNone(sol28)
        samples = sol28["diurnal_samples"]
        self.assertGreater(len(samples), 0)
        self.assertIn("lmst", samples[0])
        self.assertIn("air_temp_c", samples[0])


if __name__ == "__main__":
    unittest.main()
