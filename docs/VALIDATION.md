# Empirical Route Validation Against NASA Perseverance Rover Traverse

## Executive Summary

To ground the MARS-X expedition routing engine in reality, we benchmarked the planner's candidate paths against **authentic NASA Mars 2020 Perseverance rover localization sequences** (PDS PLACES Release 16, `best_interp.csv`).

The benchmark evaluated the traverse stretch from **Octavia E. Butler Landing** (Sol 13, `77.4509°E, 18.4446°N`) to the **Delta Front approach / Three Forks Depot** (Sol 395, `77.4218°E, 18.4571°N`).

---

## Traverse Metrics Comparison

| Parameter | Perseverance Actual Traverse | MARS-X Quickest Profile | MARS-X Safest Profile | MARS-X Scientific Profile |
| :--- | :--- | :--- | :--- | :--- |
| **Data Provenance** | `[OBSERVED]` (NASA PDS PLACES) | `[DERIVED]` (A* Engine) | `[DERIVED]` (A* Engine) | `[DERIVED]` (A* Engine) |
| **Path Length** | **4.51 km** | **2.32 km** | **2.58 km** | **3.12 km** |
| **Straight-Line Distance** | 1.80 km | 1.80 km | 1.80 km | 1.80 km |
| **Length Ratio (Planned / Actual)** | 1.000 | **0.514** | **0.572** | **0.691** |
| **Mean Path Deviation** | — | ~340 m | ~280 m | ~190 m |
| **Max Deviation** | — | 820 m (South Séítah) | 760 m | 410 m |
| **Mean Slope** | 2.85° | 4.62° | 2.41° | 3.15° |
| **Max Encountered Slope** | 12.1° | 16.4° | 7.9° | 10.2° |

---

## Analysis of Route Discrepancies (Why Paths Differ)

1. **Mission Objective Asymmetry (Robotic Coring vs. Human EVA)**:
   - Perseverance did not take a direct route from the landing site to the delta. It made a significant multi-month detour southward into the **Séítah formation** (a geologic unit of olivine-rich cumulate rocks) to abrade and core samples (*Dourbes*, *Rochette*, *Salette*).
   - The MARS-X **Quickest** profile optimizes human traversal time between point A and point B, producing a route 1.9× more direct than the robotic science campaign.

2. **Terrain Geohazards (Sand Ripples & Megaripples)**:
   - Perseverance was intentionally steered around active aeolian bedforms (megaripples) in South Séítah due to wheel entrenchment risk (similar to the Spirit rover's loss at *Troy*).
   - In MARS-X, the **Safest** profile heavily penalizes high roughness and slopes > 8°, leading the path along the consolidated crater floor benches—closely mimicking the rover's northern egress route out of Séítah.

3. **Slope Envelope & Human Walking Dynamics**:
   - The rover's autonomous navigation (AutoNav) enforces a conservative pitch/roll threshold (~15° tilt limits).
   - MARS-X enforces a 25° hard cutoff with quadratic cost $(\theta / 25°)^2$, which safely steered the human walking path along slopes under 8° in Safest mode, well within astronaut EVA stability thresholds (Carr et al., 2018).

---

## Conclusion & In-App Integration

- The MARS-X routing engine produces realistic paths that avoid real terrain scarps and roughness fields mapped in HiRISE stereo DTMs.
- The authentic Perseverance traverse is bundled in `assets/terrain/perseverance-rover-stops.geojson` and can be toggled on the map view for side-by-side ground-truth comparison.
