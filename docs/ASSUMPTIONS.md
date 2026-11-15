# MARS-X Mission Model Assumptions & Sensitivity Analysis

This document provides a full inventory of all physical parameters, heuristics, life-support burn rates, and terrain constraints utilized in the MARS-X expedition planner. In compliance with the NASA Space Apps Challenge Hard Rules, each parameter is explicitly classified as either **CITED / GROUNDED** or **ASSUMPTION - NOT VALIDATED**, followed by empirical sensitivity analysis under $\pm 20\%$ variations.

All operational values are centralized in [`mobile/lib/domain/track/mission_config.dart`](../mobile/lib/domain/track/mission_config.dart).

---

## 1. Parameter Inventory & Evidentiary Basis

| Parameter | Default Value | Evidentiary Basis & Citation | Classification |
| :--- | :--- | :--- | :--- |
| `maxPassableSlopeDeg` | `25.0°` | Grounded in Apollo lunar roving vehicle pitch/roll limits and Carr et al. (2018) pressurized rover rollover stability limits. | **CITED / GROUNDED** |
| `safestSmoothingMaxSlopeDeg` | `6.0°` | Line-of-sight shortcut constraint to prevent smoothing through steep gullies. | **ASSUMPTION - NOT VALIDATED** |
| `safestWeightSlope` ($w_s$) | `15.0` | Heuristic tuning to strictly penalize steep scarps ($(\theta/25°)^2$). | **ASSUMPTION - NOT VALIDATED** |
| `safestWeightRoughness` ($w_r$) | `3.0` | Golombek et al. (2020) rock hazard distribution models. | **ASSUMPTION - GROUNDED** |
| `safestWeightAscent` ($w_h$) | `3.0` | Santee et al. (2003) metabolic work expenditure on uphill gradients. | **CITED / GROUNDED** |
| `quickestWeightSlope` | `0.15` | Minimal slope resistance to optimize geometric distance. | **ASSUMPTION - NOT VALIDATED** |
| `baseWalkingSpeedMs` ($v_0$) | `0.833 m/s` (3.0 km/h) | Carr et al. (2018) pressurized suit mobility in 0.38g Mars gravity. | **CITED / GROUNDED** |
| `toblerSlopeDecayFactor` | `3.5` | Adapted from Tobler (1993) hiking function with suit stiffness damping. | **CITED / GROUNDED** |
| `crewSize` | `2` astronauts | NASA EVA buddy-system standard (NASA-STD-3001, Vol 2). | **CITED / GROUNDED** |
| `oxygenConsumptionKgPerMinPerCrew` | `0.00133 kg/min` (80 g/h) | NASA xEMU baseline specifications for moderate metabolic workload. | **CITED / GROUNDED** |
| `batteryConsumptionKwhPerMinPerCrew` | `0.005 kWh/min` (300 W) | NASA xEMU PLSS electronics and ventilation power budget. | **CITED / GROUNDED** |
| `coolingWaterConsumptionKgPerMinPerCrew` | `0.00667 kg/min` (400 g/h) | SWME thermal rejection for 250 W metabolic heat dissipation. | **CITED / GROUNDED** |
| `surfaceRadiationDoseRateMicroSvPerMin` | `0.445 µSv/min` (26.7 µSv/h) | MSL RAD surface measurements at Gale Crater (Hassler et al., 2014, Science). | **CITED / GROUNDED** |
| `scienceDetourCapRatio` | `1.50x` (150%) | Flight rule constraint: scientific detour capped at 150% of fastest route. | **ASSUMPTION - NOT VALIDATED** |

---

## 2. Sensitivity Analysis (±20% Perturbations)

Benchmark executed on Demo Pair 1: **Western Delta Fan `(22, 28)` to Belva Crater Rim `(84, 16)`** (Straight-line distance: 2.18 km).

### maxPassableSlopeDeg
- **Category**: Mobility & Terrain
- **Baseline**: `25.0°` (CITED / GROUNDED)
- **Basis**: Apollo 15/16 lunar rover limits & Carr et al. (2018) rollover stability threshold.
- **-20% Perturbation (`20.0°`)**: Quickest route is forced to detour around the 22.4° delta scarp, increasing distance by +7.1% (to 2.58 km) and matching Safest path. Safest route unaffected.
- **+20% Perturbation (`30.0°`)**: Quickest route takes an even steeper ascent (up to 27.5°), saving 40 m of distance but spiking simulated risk by +28%. Safest route unaffected.
- **Sensitivity Assessment**: **HIGH for Quickest profile; ZERO for Safest profile.**

### safestWeightSlope (ws = 15.0)
- **Category**: Routing Heuristic
- **Baseline**: `15.0` (ASSUMPTION - NOT VALIDATED)
- **Basis**: Assumption - heuristic tuning to strictly penalize steep scarps.
- **-20% Perturbation (`12.0 (-20%)`)**: Safest route length decreases by 1.2% (to 2.56 km); mean slope marginally increases from 3.22° to 3.48°. Risk score changes by +1.1 pts.
- **+20% Perturbation (`18.0 (+20%)`)**: Safest route lengthens by +1.9% (to 2.64 km) to bypass a gentle 6.5° rise. Risk score drops by -0.8 pts.
- **Sensitivity Assessment**: **LOW (path geometry is robust to +/-20% variation; primary avoidance is preserved).**

### safestWeightRoughness (wr = 3.0)
- **Category**: Routing Heuristic
- **Baseline**: `3.0` (ASSUMPTION - GROUNDED IN ANALOG)
- **Basis**: Assumption based on Golombek et al. (2020) rock hazard distribution models.
- **-20% Perturbation (`2.4 (-20%)`)**: Path shifts up to 1 cell closer to rocky boulder margins near Cape Nukshak; total distance changes by < 0.5%.
- **+20% Perturbation (`3.6 (+20%)`)**: Path widens corridor around Cape Nukshak by 36 m (1 cell); distance increases by +0.8%.
- **Sensitivity Assessment**: **VERY LOW (secondary contributor behind slope penalty).**

### baseWalkingSpeedMs (v0 = 0.833 m/s)
- **Category**: EVA Biomechanics
- **Baseline**: `0.833 m/s (3.0 km/h)` (CITED / GROUNDED)
- **Basis**: Carr et al. (2018) pressurized suit mobility in 0.38g Mars gravity.
- **-20% Perturbation (`0.667 m/s (2.4 km/h)`)**: Direct inverse proportional scaling: estimated travel time increases by exactly +25.0% (Safest: 61.8 min -> 77.3 min). Consumables (O2, battery, water) increase by +25.0%.
- **+20% Perturbation (`1.000 m/s (3.6 km/h)`)**: Estimated travel time decreases by -16.7% (Safest: 61.8 min -> 51.5 min). Consumables decrease by -16.7%.
- **Sensitivity Assessment**: **HIGH on time and consumables; ZERO on spatial route geometry.**

### oxygenConsumptionKgPerMinPerCrew
- **Category**: Life Support Burn Rate
- **Baseline**: `0.00133 kg/min (80 g/hr/crew)` (CITED / GROUNDED)
- **Basis**: NASA Exploration EVA System (xEMU) moderate metabolic rate (NASA-STD-3001).
- **-20% Perturbation (`0.00106 kg/min (-20%)`)**: Total O2 mass consumed drops from 0.164 kg to 0.131 kg for 2-crew Safest EVA. PNR margin extends outward by +20%.
- **+20% Perturbation (`0.00160 kg/min (+20%)`)**: Total O2 consumed increases to 0.197 kg. PNR radius contracts by -16.7%.
- **Sensitivity Assessment**: **HIGH on consumable mass budget and Point-of-No-Return boundary; ZERO on path geometry.**

### surfaceRadiationDoseRateMicroSvPerMin
- **Category**: Environmental Hazard
- **Baseline**: `0.445 µSv/min (26.7 µSv/hr)` (CITED / GROUNDED)
- **Basis**: MSL RAD surface measurements at Gale Crater (Hassler et al., 2014, Science 343:1244797).
- **-20% Perturbation (`0.356 µSv/min (-20%)`)**: Cumulative EVA dose for Safest route drops from 27.5 µSv to 22.0 µSv.
- **+20% Perturbation (`0.534 µSv/min (+20%)`)**: Cumulative EVA dose for Safest route increases to 33.0 µSv (well within 500 mSv annual occupational limit).
- **Sensitivity Assessment**: **MODERATE on cumulative EVA dose; ZERO on path geometry.**

### scienceDetourCapRatio (1.5x)
- **Category**: Mission Flight Rules
- **Baseline**: `1.50x` (ASSUMPTION - NOT VALIDATED)
- **Basis**: Assumption - mission rule constraint to preserve 50% emergency life-support reserve.
- **-20% Perturbation (`1.20x (-20%)`)**: Max allowable distance drops from 3.62 km to 2.89 km. Scientific planner can no longer reach Enchanted Lake outcrop, dropping science score from 84 to 46.
- **+20% Perturbation (`1.80x (+20%)`)**: Max allowable distance expands to 4.34 km. Scientific planner visits both Enchanted Lake and Hawksbill Gap, increasing score to 96 at the expense of +38% EVA duration.
- **Sensitivity Assessment**: **HIGH on science target yield and detour reach; ZERO on Safest/Quickest routes.**

---

## 3. Conclusions for Mission Planners

1. **Topological Invariance of Safest Route**:
   The Safest route profile is exceptionally robust against heuristic tuning ($w_s, w_r$). Varying weights by $\pm 20\%$ shifts the ground path by less than 1 grid cell (36 m) because steep scarps ($> 15°$) dominate the quadratic cost landscape.
2. **Criticality of the 25° Slope Cutoff**:
   The 25° hard slope cutoff is the primary bifurcation point between Quickest and Safest modes. Lowering it to 20° merges Quickest into Safest, while raising it to 30° creates dangerously steep scrambles.
3. **Consumable Linearity**:
   Metabolic consumption ($O_2$, battery, water) and radiation dose scale linearly ($1:1$) with traverse time. The walking speed $v_0$ is the single highest-leverage human variable for EVA range.
