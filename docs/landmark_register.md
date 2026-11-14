# Jezero landmark register

`data/processed/jezero/landmarks.json`, `landmarks.geojson`, and
`landmarks.csv` contain the same 29 names requested for the first MARS-X
Jezero landmark pass. Regenerate them with:

```powershell
python data/build_landmark_register.py
```

## Coordinate and evidence policy

Coordinates use east-positive Mars longitude and planetocentric latitude on
the Mars 2000 sphere (3,396,190 m). The bounding box is recorded in the files
as west, south, east, north. Unknown coordinates are deliberately null, and
`insideDemExtent` remains `unknown` until a source geometry or defensible point
is available. Null GeoJSON geometries are valid Feature geometry values and
mean that a name is in the research register, not ready to draw.

The existing SIM 3464 line and polygon files hold regional geology. Their
geometries are kept separate from this named register so that a label anchor
is not confused with a feature boundary. Four records have sourced catalog
coordinates: the published Octavia E. Butler touchdown point and the official
Gazetteer centers of Neretva Vallis, Sava Vallis, and Pliva Vallis. The valley
points are explicitly representative centers, with official source extents
recorded separately; Sava and Pliva only partially overlap the DEM. The
existing Belva and Neretva map-label anchors remain in
`jezero_landmarks.geojson`; neither is promoted to a feature center. Rover
localizations remain separate in `perseverance_rover_stops.geojson`.

Scientific importance is descriptive text, not a numerical route score.
Terrain hazards are not asserted by this named-landmark register: derive them
from verified terrain slope/roughness data and keep those outputs in their own
layer. No route-safety claims are encoded here.

## Research findings and remaining location joins

The NASA/JPL panorama identifies Three Forks, Hawksbill Gap, and Tuff Cliff;
papers and NASA mission updates provide stronger context for Kodiak, the
crater-floor formations, the Margin campaign names, and later crater-rim
targets. Several informal names were absent from the sources currently
bundled in the repository. The register records those as unresolved rather
than silently treating them as verified or assigning guessed positions.

In particular, the USGS map-label point for Belva is a text anchor only. The
PDS Three Forks sample-drop table has event names/times but no tube
coordinates. Bunsen Peak, Beehive Geyser, Pelican Point, Gnaraloo Bay,
Jurabi Point, Mandu Wall, and Faraway Rock are confirmed by NASA/mission
science references, but the exact named target geometries still need to be
joined to mission waypoint/PLACES/sample localization records. Bunsen Peak
and Beehive Geyser are informal mission names; “geyser” does not imply a
physical geyser process.

Some requested geological labels are generalized rather than unique mapped
objects. “Eastern Outlet Valley” is normalized to the official name Pliva
Vallis. Lake extents change with reconstructed paleolake level and should be
stored as individually sourced contour geometries, not one exact basin point.
The northern fan/delta interpretation is less settled than the western delta.

The five requested layer IDs are declared in the JSON/GeoJSON metadata.
Only named register rows are included in these three exports; existing geology
and rover geometries remain companion files, and the terrain-hazards layer is
empty pending validated derivation from terrain data.

## Primary references

- [USGS SIM 3464](https://pubs.usgs.gov/publication/sim3464) and [USGS Planetary Nomenclature](https://planetarynames.wr.usgs.gov/Feature/14300)
- [NASA annotated Perseverance panorama](https://science.nasa.gov/resource/perseverances-mid-climb-view-of-jezero-crater/)
- [NASA/JPL Beehive Geyser update](https://science.nasa.gov/blog/beehive-geyser-beckons/)
- [NASA/JPL Pelican Point sample record](https://www.jpl.nasa.gov/videos/meet-the-mars-samples-pelican-point-sample-22/)
- [NASA Perseverance sample inventory](https://science.nasa.gov/mission/mars-2020-perseverance/mars-rock-samples/)
- [Stack et al. 2022, Jezero geological results](https://doi.org/10.1126/sciadv.abo4856)
- [Farley et al. 2022, first science campaign](https://doi.org/10.1029/2022JE007613)
- [NASA NTRS, Shenandoah lower delta sequence](https://ntrs.nasa.gov/citations/20230000582)
- [NASA/JPL, rover and helicopter Jezero location map](https://science.nasa.gov/resource/rover-helicopter-locations-in-jezero-crater/)
- [PDS Mars 2020 PLACES](https://pds-geosciences.wustl.edu/missions/mars2020/places.htm)
- [ESA/FU Berlin Jezero interactive map](https://maps.planet.fu-berlin.de/jezero/)

## Status

These files provide a complete **requested-name register**, but not a fully
georeferenced final landmark database. Most coordinates remain null pending
authoritative geometry/waypoint joins, imagery references are selective, and
the terrain-hazard layer is not derived. This preserves the no-invented-
coordinates requirement while making the remaining work explicit and
machine-readable.
