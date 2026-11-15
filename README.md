# MARS-X: Autonomous Human Mars Surface Excursion Planning & Navigation

Offline-first Martian expedition planner and navigation suite built for Jezero Crater exploration (NASA Space Apps 2026).

---

## Reproducible Demo Route Pairs (For Video & Testing)

Use these two verified landmark pairs on the HiRISE planning grid (120 × 76 cells) to demonstrate clear differentiation between **Safest**, **Quickest**, and **Scientific** route profiles:

### Demo Pair 1: Western Delta to Belva Crater (Delta Scarp Traversal)
- **Start Waypoint**: `(22, 28)` — *Western Delta Fan*
- **Destination Waypoint**: `(84, 16)` — *Belva Crater Rim*
- **What to Observe**:
  - **Quickest** (Atmos Teal): Traverses the direct route climbing straight over the steep delta scarp (Distance: ~2.41 km, Mean Slope: ~7.5°, Max Slope: 22.4°, higher simulated risk).
  - **Safest** (Sage Green): Skirts southward around the scarp base through gentle lacustrine benches (Distance: ~2.59 km, Mean Slope: ~3.2°, Max Slope drops to 8.25°, low simulated risk).
  - **Scientific** (Mars Red): Detours to sample the *Enchanted Lake* mudstone outcrop while strictly respecting the $\le 1.5\times$ distance cap.

### Demo Pair 2: Neretva Vallis to Three Forks Depot (Channel Inflow Traversal)
- **Start Waypoint**: `(12, 38)` — *Neretva Vallis Inflow Canyon*
- **Destination Waypoint**: `(52, 34)` — *Three Forks Sample Depot*
- **What to Observe**:
  - **Quickest**: Direct line across uneven boulder-strewn channel deposit margins (Distance: ~1.50 km, Max Slope: 8.4°).
  - **Safest**: Navigates along the smoothed paleochannel bed (Distance: ~1.53 km, Mean Slope: 2.63°, Max Slope drops to 4.67°).
  - **Scientific**: Routes directly through the first extraterrestrial sample depot cache.
