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
The register now includes named point locations, a two-viewpoint MultiPoint
for Three Forks, three channel line geometries, a possible paleo-lake polygon,
and the two existing SIM 3464 GeometryCollections (rim and western fan). Named
points include the touchdown site, FU Berlin panorama viewpoints for Belva
Crater, Enchanted Lake, and Bunsen Peak, PDS sample localizations associated
with Hawksbill Gap and Cape Nukshak, and PDS PLACES rover visit localizations
for Jurabi Point (Sol 958) and Gnaraloo Bay (Sol 959). These are rover/sample
viewpoints or visit localizations, not necessarily feature centers or
boundaries. The Three Forks MultiPoint represents two named panorama
viewpoints, not tube-drop coordinates. The Neretva, Sava, and Pliva lines come
from an unnamed FU Berlin WFS channel layer; their matching to official
Gazetteer centers is spatial and documented as such, rather than an explicit
name attribute in the WFS. The existing Belva and Neretva map-label anchors remain in
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

The FU Berlin interactive map WFS was queried and cached in
`data/raw/JezeroLandmarks/FUBerlin/`. Its EPSG:49911 Mars equirectangular
coordinates were converted using the Mars 2000 sphere radius (3,396,190 m) to
east-positive longitude and planetocentric latitude. The register uses the
WFS lake-level polygon, channel line components, and named panorama viewpoints.
Channel lines have no names in their attributes; the three assignments are
spatial matches to USGS Gazetteer representative points and should be treated
as medium-confidence attribution. The lake polygon represents one possible
reconstructed level, not the entire ancient basin. Panorama locations are
observation points, not feature centers.

An additional authoritative geomorphology dataset is available online:
[Ovchinnikova & Jaumann (2024), Valleys and deltas in Jezero crater](https://refubium.fu-berlin.de/handle/fub188/45321), DOI
[10.17169/refubium-45033](https://doi.org/10.17169/refubium-45033). Its published
description says the downloadable geodatabase contains mapped western and
northern delta extents and initial/last-incision geometries for the western
inlet, northern inlet, and outlet. It could support several currently null
regional features. It is not yet included in this repository: an attempted
download from the repository endpoint returned an anti-bot HTML page rather
than the advertised 257.4 KB ZIP, so no geometry was extracted or represented
as validated. On successful retrieval, verify the published MD5
`dbd7656954975ca8128c22179231f60e`, inspect the Mars CRS and source coverage,
then integrate the geometries without substituting centroids.

In particular, the USGS map-label point for Belva is a text anchor only. The
PDS Three Forks sample-drop table in this checkout has event names/times but no tube
coordinates. The [PDS Analyst's Notebook depot documentation](https://an.rsl.wustl.edu/help/Content/About%20the%20mission/M20/Return%20sample%20science/Three%20Forks%20Depot.htm)
describes tube-location and sample-in-image tables, including rover positions
and per-image sample pixel coordinates. Those need to be joined with the
archived Navcam mosaics/DEMs or returned as mission-localization visit points;
the local timestamp CSV alone is insufficient for individual tube points.
Bunsen Peak, Beehive Geyser, Pelican Point,
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
georeferenced final landmark database. Fourteen names still have null
geometry pending authoritative feature boundaries or waypoint/sample-location
joins. Two mapped geologic entries have geometry but no representative point.
Imagery references are selective, and the terrain-hazard layer is not derived.
This preserves the no-invented-coordinates requirement while making the
remaining work explicit and machine-readable.
