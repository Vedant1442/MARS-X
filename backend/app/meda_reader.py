"""Reader and aggregator for archived NASA Mars 2020 Perseverance MEDA weather data.

Reads PDS4 derived tables (TIRS and RHS) stored in data/raw/D9/ for Sols 10, 14, 20, 28.
Data represents real calibrated sensor observations from Jezero Crater.
"""
from __future__ import annotations
import csv, glob, math, os
from typing import Any, Optional

SIGMA_SB = 5.670374419e-8  # Stefan-Boltzmann constant (W/(m^2 K^4))


def _find_d9_dir() -> str | None:
    candidates = [
        os.environ.get("MARSX_D9_PATH"),
        os.path.join(os.path.dirname(__file__), "..", "..", "data", "raw", "D9"),
        os.path.join(os.path.dirname(__file__), "..", "data", "raw", "D9"),
    ]
    for c in candidates:
        if c and os.path.isdir(os.path.abspath(c)):
            return os.path.abspath(c)
    return None


class MedaCatalog:
    def __init__(self, d9_dir: Optional[str] = None):
        self.d9_dir = d9_dir or _find_d9_dir()
        self._sols_cache: dict[int, dict[str, Any]] = {}
        self._loaded = False

    def load(self) -> None:
        if not self.d9_dir or not os.path.isdir(self.d9_dir):
            return

        sol_dirs = sorted(glob.glob(os.path.join(self.d9_dir, "sol_*")))
        for sd in sol_dirs:
            base = os.path.basename(sd)
            try:
                sol_num = int(base.split("_")[-1])
            except ValueError:
                continue

            rhs_files = glob.glob(os.path.join(sd, "*_DER_RHS_*.CSV"))
            tirs_files = glob.glob(os.path.join(sd, "*_DER_TIRS_*.CSV"))

            temps_k = []
            hums = []
            lmst_list = []
            ltst_list = []

            if rhs_files:
                with open(rhs_files[0], "r", encoding="utf-8", errors="ignore", newline="") as f:
                    r = csv.DictReader(f)
                    for row in r:
                        tk = row.get("HUMIDITY_LOCAL_TEMP")
                        rh = row.get("LOCAL_RELATIVE_HUMIDITY")
                        lmst = row.get("LMST")
                        ltst = row.get("LTST")
                        if tk:
                            try:
                                val = float(tk)
                                temps_k.append(val)
                                if lmst:
                                    lmst_list.append(lmst.strip())
                                if ltst:
                                    ltst_list.append(ltst.strip())
                            except ValueError:
                                pass
                        if rh:
                            try:
                                hums.append(float(rh))
                            except ValueError:
                                pass

            ground_temps_k = []
            if tirs_files:
                with open(tirs_files[0], "r", encoding="utf-8", errors="ignore", newline="") as f:
                    r = csv.DictReader(f)
                    for row in r:
                        up = row.get("UPWARD_LW_IRRADIANCE")
                        if up:
                            try:
                                val = float(up)
                                if val > 0:
                                    # Radiative equilibrium brightness temperature
                                    ground_temps_k.append((val / SIGMA_SB) ** 0.25)
                            except ValueError:
                                pass

            temps_c = [k - 273.15 for k in temps_k]
            ground_c = [k - 273.15 for k in ground_temps_k]

            air_summary = None
            if temps_c:
                air_summary = {
                    "min": round(min(temps_c), 1),
                    "max": round(max(temps_c), 1),
                    "mean": round(sum(temps_c) / len(temps_c), 1),
                    "unit": "degC",
                }

            ground_summary = None
            if ground_c:
                ground_summary = {
                    "min": round(min(ground_c), 1),
                    "max": round(max(ground_c), 1),
                    "mean": round(sum(ground_c) / len(ground_c), 1),
                    "unit": "degC",
                }

            rh_summary = None
            if hums:
                rh_summary = {
                    "min": round(min(hums), 2),
                    "max": round(max(hums), 2),
                    "mean": round(sum(hums) / len(hums), 2),
                    "unit": "%",
                }

            # Downsample hourly or ~24 points for diurnal curve
            time_series = []
            if temps_c and len(temps_c) == len(lmst_list):
                step = max(1, len(temps_c) // 24)
                for idx in range(0, len(temps_c), step):
                    time_series.append({
                        "lmst": lmst_list[idx],
                        "air_temp_c": round(temps_c[idx], 1),
                    })

            self._sols_cache[sol_num] = {
                "sol": sol_num,
                "data_type": "MEASURED",
                "instrument": "Mars 2020 MEDA (TIRS & RHS)",
                "source": "NASA/PDS Atmospheres Node (PDS4 archived)",
                "citation": "Rodriguez-Manfredi et al. (2021), The Mars Environmental Dynamics Analyzer (MEDA) on the Mars 2020 Mission, Space Sci Rev.",
                "sample_count": len(temps_c) + len(ground_c),
                "lmst_span": f"{lmst_list[0]} to {lmst_list[-1]}" if lmst_list else "unknown",
                "air_temperature": air_summary,
                "ground_brightness_temperature": ground_summary,
                "relative_humidity": rh_summary,
                "diurnal_samples": time_series[:24],
            }

        self._loaded = True

    def get_sol(self, sol: int) -> Optional[dict[str, Any]]:
        if not self._loaded:
            self.load()
        return self._sols_cache.get(sol)

    def get_all_sols(self) -> dict[str, Any]:
        if not self._loaded:
            self.load()
        if not self._sols_cache:
            return {"available_sols": [], "sols": {}, "data_type": "DATASET_UNAVAILABLE"}
        return {
            "data_type": "MEASURED",
            "available_sols": sorted(list(self._sols_cache.keys())),
            "sols": self._sols_cache,
            "provenance": {
                "mission": "NASA Mars 2020 Perseverance",
                "instrument": "Mars Environmental Dynamics Analyzer (MEDA)",
                "pds_bundle": "urn:nasa:pds:mars2020_meda",
                "landing_site": "Octavia E. Butler Landing, Jezero Crater",
                "note": "Archived PDS4 tables (not real-time telemetry).",
            },
        }


# Global singleton instance
meda_catalog = MedaCatalog()
