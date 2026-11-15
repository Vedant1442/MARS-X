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

Two entries now include multipart source geometries drawn from the SIM 3464
geologic layers: the mapped crater-rim unit polygons and crater-rim crest
segments, plus Jezero fan units 1 and 2 (western delta). They are clipped to
the DEM footprint and to the published
geologic-map coverage, so they are not complete outlines beyond that coverage.
Seven records have sourced point coordinates: the published Octavia E. Butler
touchdown point, the official Gazetteer centers of Neretva Vallis, Sava Vallis,
and Pliva Vallis, plus PDS PLACES rover visit localizations for Enchanted Lake
(Sol 426), Jurabi Point (Sol 958), and Gnaraloo Bay (Sol 959). Visit points are not outcrop centers or
boundaries. The valley points are explicitly representative
centers, with official source extents recorded separately; Sava and Pliva only
partially overlap the DEM. The existing Belva and Neretva map-label anchors remain in
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
PDS Three Forks sample-drop table in this checkout has event names/times but no tube
coordinates. PDS documentation says a separate depot sample-location table
records rover positions during drops and tube positions; that authoritative
table remains to be joined. Bunsen Peak, Beehive Geyser, Pelican Point,
Mandu Wall, and Faraway Rock are confirmed by NASA/mission science references,
but their exact target geometries still need to be joined to mission waypoint,
PLACES, or sample localization records. Bunsen Peak
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
- [NASA Sol 958 Jurabi Point arrival and Sol 959 Gnaraloo Bay traverse](https://science.nasa.gov/blog/here-comes-the-sun-perseverance-readies-for-solar-conjunction/)
- [NASA/JPL Pelican Point sample record](https://www.jpl.nasa.gov/videos/meet-the-mars-samples-pelican-point-sample-22/)
- [NASA Perseverance sample inventory](https://science.nasa.gov/mission/mars-2020-perseverance/mars-rock-samples/)
- [Stack et al. 2022, Jezero geological results](https://doi.org/10.1126/sciadv.abo4856)
- [Farley et al. 2022, first science campaign](https://doi.org/10.1029/2022JE007613)
- [NASA NTRS, Shenandoah lower delta sequence](https://ntrs.nasa.gov/citations/20230000582)
- [NASA/JPL, rover and helicopter Jezero location map](https://science.nasa.gov/resource/rover-helicopter-locations-in-jezero-crater/)
- [PDS Mars 2020 PLACES](https://pds-geosciences.wustl.edu/missions/mars2020/places.htm)
- [PDS Three Forks Depot bundle](https://pds-geosciences.wustl.edu/m2020/urn-nasa-pds-mars2020_sample_depot_three_forks/)
- [ESA/FU Berlin Jezero interactive map](https://maps.planet.fu-berlin.de/jezero/)

## Status

These files provide a complete **requested-name register**, but not a fully
georeferenced final landmark database. Twenty names still have null
geometry pending authoritative feature boundaries or waypoint/sample-location
joins. Two mapped geologic entries have geometry but no representative point.
Imagery references are selective, and the terrain-hazard layer is not derived.
This preserves the no-invented-coordinates requirement while making the
remaining work explicit and machine-readable.
