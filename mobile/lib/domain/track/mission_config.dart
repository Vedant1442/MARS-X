/// Centralized configuration for MARS-X expedition routing, safety model,
/// EVA consumables burn rates, and terrain constraints.
///
/// Every parameter is labeled with either an authentic cited source or
/// "assumption - not validated" pursuant to NASA Space Apps Challenge rules.
library mission_config;

class MissionConfig {
  // ---------------------------------------------------------------------------
  // 1. TERRAIN & SLOPE MOBILITY CONSTRAINTS
  // ---------------------------------------------------------------------------

  /// Maximum passable slope angle in degrees. Slopes exceeding this cutoff
  /// are treated as impassable (infinite routing cost).
  ///
  /// Basis: Assumption grounded in Apollo 15/16 lunar surface rover slope limits
  /// and Carr et al. (2018) pressurized rover rollover stability limits (25° dynamic cutoff).
  static const double maxPassableSlopeDeg = 25.0;

  /// Maximum slope threshold (degrees) for string-pulling line-of-sight smoothing.
  /// Safest mode restricts shortcuts across slopes steeper than this threshold.
  ///
  /// Basis: Assumption - not validated (conservatively chosen to keep Safest routes on gentle terrain).
  static const double safestSmoothingMaxSlopeDeg = 6.0;

  /// Grid cell spatial resolution (nominal meters per cell edge).
  ///
  /// Source: HiRISE DTM DTEEC_045994_1985_046060_1985_U01 4x downsample (35.99 m/cell).
  static const double nominalCellSizeM = 35.99;

  // ---------------------------------------------------------------------------
  // 2. ROUTING COST WEIGHTS (C = d * [1 + ws*(theta/25)^2 + wr*R + wu*U] + wh*dh+)
  // ---------------------------------------------------------------------------

  // Safest Profile: Heavily penalizes slopes, roughness, and ascents
  /// Slope penalty weight ws for Safest profile.
  /// Basis: Assumption - heuristic tuning to strictly avoid scarps.
  static const double safestWeightSlope = 15.0;
  /// Roughness penalty weight wr for Safest profile.
  /// Basis: Assumption - based on Golombek et al. (2020) rock hazard distribution models.
  static const double safestWeightRoughness = 3.0;
  /// Uncertainty penalty weight wu for Safest profile.
  /// Basis: Assumption - penalizes unmapped edges and data gaps.
  static const double safestWeightUncertainty = 1.5;
  /// Directional uphill ascent penalty wh for Safest profile.
  /// Basis: Santee et al. (2003) metabolic work expenditure during human uphill ascents.
  static const double safestWeightAscent = 3.0;

  // Quickest Profile: Minimizes distance and travel time with low slope resistance
  /// Slope penalty weight ws for Quickest profile.
  /// Basis: Assumption - minimal resistance up to the 25° hard cutoff.
  static const double quickestWeightSlope = 0.15;
  /// Roughness penalty weight wr for Quickest profile.
  /// Basis: Assumption - accepts moderate roughness for speed.
  static const double quickestWeightRoughness = 0.10;
  /// Uncertainty penalty weight wu for Quickest profile.
  /// Basis: Assumption - zero penalty for fastest trajectory.
  static const double quickestWeightUncertainty = 0.0;
  /// Directional uphill ascent penalty wh for Quickest profile.
  /// Basis: Assumption - minimal uphill resistance (0.25).
  static const double quickestWeightAscent = 0.25;

  // Scientific Profile: Balances safety with attraction toward exploration landmarks
  /// Slope penalty weight ws for Scientific profile.
  /// Basis: Assumption - intermediate stability between Safest and Quickest.
  static const double scienceWeightSlope = 3.0;
  /// Roughness penalty weight wr for Scientific profile.
  /// Basis: Assumption - allows traversing rocky outcrops for scientific sampling.
  static const double scienceWeightRoughness = 1.5;
  /// Uncertainty penalty weight wu for Scientific profile.
  /// Basis: Assumption - intermediate caution (1.0).
  static const double scienceWeightUncertainty = 1.0;
  /// Directional uphill ascent penalty wh for Scientific profile.
  /// Basis: Assumption - moderate uphill penalty (1.5).
  static const double scienceWeightAscent = 1.5;

  /// Maximum allowable detour ratio for Scientific routes compared to the Quickest route.
  ///
  /// Basis: Mission flight rule constraint: scientific diversions cannot exceed
  /// 150% (1.5x) of the direct fastest egress distance to preserve life-support margin.
  static const double scienceDetourCapRatio = 1.5;

  // ---------------------------------------------------------------------------
  // 3. HUMAN WALKING & EVA BIOMECHANICS
  // ---------------------------------------------------------------------------

  /// Baseline horizontal astronaut walking speed in m/s (approx 3.0 km/h).
  ///
  /// Source: Carr et al. (2018) pressurized suit mobility in 0.38g Mars gravity.
  static const double baseWalkingSpeedMs = 0.833;

  /// Tobler exponential slope decay factor adapted for Mars suit locomotion.
  /// v(theta) = v0 * exp(-slopeDecayFactor * |tan(theta) + slopeNeutralOffset|)
  ///
  /// Source: Adapted from Tobler (1993) hiking function with suit stiffness damping.
  static const double toblerSlopeDecayFactor = 3.5;
  static const double toblerSlopeNeutralOffset = 0.05;

  /// Rest stop cadence: mandatory 10-minute rest stop for every 60 minutes of walking.
  ///
  /// Basis: NASA EVA operational guidelines for metabolic recovery (NASA-STD-3001).
  static const double restMinutesPerWalkingHour = 10.0;

  // ---------------------------------------------------------------------------
  // 4. ASTRONAUT CREW & EVA CONSUMABLES CONSUMPTION
  // ---------------------------------------------------------------------------

  /// Astronaut crew size per EVA excursion.
  ///
  /// Source: NASA EVA buddy-system standard (NASA-STD-3001, Vol 2).
  static const int crewSize = 2;

  /// Oxygen consumption rate in kg per minute per astronaut (approx 80 g/hour).
  ///
  /// Source: NASA xEMU baseline specifications for moderate metabolic workload (NASA-STD-3001).
  static const double oxygenConsumptionKgPerMinPerCrew = 0.00133;

  /// Portable life support system (PLSS) battery power draw in kWh per minute per crew (approx 300 W).
  ///
  /// Source: NASA xEMU suit electronics and ventilation power budget.
  static const double batteryConsumptionKwhPerMinPerCrew = 0.00500;

  /// Sublimator cooling water loss rate in kg per minute per crew (approx 400 g/hour).
  ///
  /// Source: Spacesuit Water Membrane Evaporator (SWME) thermal rejection for 250 W metabolic heat.
  static const double coolingWaterConsumptionKgPerMinPerCrew = 0.00667;

  /// Point-of-No-Return (PNR) consumable safety margin.
  ///
  /// Source: NASA Flight Rules: 20% remaining reserve contingency for emergency ingress.
  static const double pnrSafetyReserveFraction = 0.20;

  // ---------------------------------------------------------------------------
  // 5. ENVIRONMENTAL & RADIATION EXPOSURE
  // ---------------------------------------------------------------------------

  /// Galactic Cosmic Ray (GCR) + solar ambient surface radiation dose rate in microSieverts per minute.
  /// Equivalent to 26.7 uSv/hr or ~0.64 mSv/day.
  ///
  /// Source: Mars Science Laboratory (MSL) Radiation Assessment Detector (RAD)
  /// published surface measurements at Gale Crater (Hassler et al., 2014, Science 343:1244797; Zeitlin et al., 2019).
  /// Assumes quiet Sun GCR background without active Solar Particle Event (SPE).
  static const double surfaceRadiationDoseRateMicroSvPerMin = 0.445;

  /// Jezero crater floor reference elevation in meters (Octavia E. Butler Landing datum).
  ///
  /// Source: HiRISE DTM DTEEC_045994_1985_046060_1985_U01.
  static const double jezeroReferenceElevationM = -2560.0;

  /// Mars atmospheric scale height in meters.
  ///
  /// Source: Mars Atmosphere Model (NASA SP-8010); H = R_spec * T / g_mars ~ 11.1 km.
  static const double atmosphericScaleHeightM = 11100.0;
}
