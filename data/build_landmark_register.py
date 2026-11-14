#!/usr/bin/env python3
"""Build a source-traceable offline register of requested Jezero landmarks.

The requested list mixes mapped regional features with informal rover-era
names. This register deliberately leaves coordinates null unless an existing
authoritative point or geometry can be joined without guessing. Regional GIS
geometry remains in the companion SIM 3464 files.
"""
from __future__ import annotations

import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "processed" / "jezero"
BOUNDS = [76.99743706146005, 17.58051991054471, 78.58256332408821, 19.290187006866102]
CRS = {
    "body": "Mars", "datum": "Mars 2000 sphere", "sphereRadiusMetres": 3396190,
    "longitude": "east-positive degrees, 0 to 360", "latitude": "planetocentric degrees",
    "ordinateOrder": ["longitudeEastDeg", "latitudePlanetocentricDeg"],
    "notEarthWGS84": True,
}
USGS = "https://pubs.usgs.gov/publication/sim3464"
NASA_PANORAMA = "https://science.nasa.gov/resource/perseverances-mid-climb-view-of-jezero-crater/"
PAPER = "https://doi.org/10.1126/sciadv.abo4856"
FUB = "https://maps.planet.fu-berlin.de/jezero/"

# id, name, category, subcategory, geometry, confidence, status, description,
# significance, exploration, source title, source URL, source geometry note
ROWS = [
 ("jezero-rim","Jezero Crater rim","geological_features","crater rim","LineString/Polygon","high","mapped_region","Impact crater rim; use USGS crater-rim crest lines and rim-unit polygons, not a point.","Defines basin boundary and relief; rim breaching records past hydrology.",None,"USGS SIM 3464",USGS,"Existing clipped SIM 3464 line and polygon layers; this register does not duplicate geometry."),
 ("western-delta","Western Delta","geological_features","delta/fan deposit","Polygon/MultiPolygon","high","regional_feature_geometry_available","Western fluvio-deltaic fan deposits at the mouth of Neretva Vallis.","Preserves fluvial and lacustrine deposits and potential biosignature-bearing sediments.","Perseverance explored the western fan and sampled its sedimentary succession.","Mangold et al. 2021 Science",PAPER,"Mapped extent should be joined from a source geologic polygon; no centroid substituted."),
 ("northern-delta","Northern Delta","geological_features","fan/delta deposits","Polygon/MultiPolygon","medium","interpretation_uncertain","Eroded fan deposits in the northern crater; literature notes their origin and relation to the western delta remain debated.","Constrains northern-inlet sediment transport and basin history.",None,"Stratigraphic Relationships in Jezero Crater", "https://doi.org/10.1029/2021JE006840","Use mapped deposits and preserve interpretation caveat; no point coordinate assigned."),
 ("neretva-vallis","Neretva Vallis","geological_features","inlet valley/channel","LineString region; point is official center","high","official_gazetteer_center_and_extent","Inlet valley/channel entering Jezero from the west/northwest.","Records fluvial transport into the paleolake; rover observations include fluvio-lacustrine strata.","Perseverance investigated the inlet channel including Tuff Cliff / Bright Angel region.","USGS Gazetteer of Planetary Nomenclature", "https://planetarynames.wr.usgs.gov/Feature/15879","Representative point is the Gazetteer center (77.20°E, 18.55°N); source extent 77.00–77.30°E, 18.50–18.60°N. Full feature remains linear."),
 ("sava-vallis","Sava Vallis","geological_features","inlet valley/channel","LineString region; point is official center","high","official_gazetteer_center_and_extent","Named western/northern inlet valley system in regional nomenclature.","Evidence for fluvial inflow to Jezero basin.",None,"USGS Gazetteer of Planetary Nomenclature","https://planetarynames.wr.usgs.gov/Feature/15904","Representative point is the Gazetteer center (77.13°E, 19.09°N); source extent 76.69–77.56°E, 18.74–19.43°N, so the valley crosses the DEM boundary."),
 ("eastern-outlet","Eastern Outlet Valley (Pliva Vallis)","geological_features","outlet valley/channel","LineString region; point is official center","high","name_normalized_to_official_gazetteer_center","The eastern outlet channel is officially named Pliva Vallis; “Eastern Outlet Valley” is a descriptive synonym, not a separate feature.","Records overflow/drainage and episodic fluvial activity.",None,"USGS Gazetteer of Planetary Nomenclature","https://planetarynames.wr.usgs.gov/Feature/15903","Representative point is the Gazetteer center (78.35°E, 18.67°N); source extent 78.09–78.60°E, 18.52–18.81°N, extending slightly beyond the DEM east edge."),
 ("ancient-lake-basin","Ancient lake basin","geological_features","paleolake basin","Polygon","high","inferred_extent_not_single_boundary","Jezero hosted an ancient lake; reconstructed lake extents vary with inferred water level and time.","Habitability context and depositional setting for delta/lacustrine sediments.","Mission investigates rocks formed in and around the paleolake.","Mangold et al. 2021 Science",PAPER,"Represent individual published paleolake-level contours as separate dated/inferred lines; no single exact polygon asserted."),
 ("crater-rim-breach","Crater rim breach","geological_features","outlet breach","LineString/Polygon","high","regional_geometry_available","Eroded eastern rim breach/outlet associated with discharge through Pliva Vallis.","Constrains open-basin phase and outflow-flood history.",None,"Fassett et al. outlet-forming flood study","https://ntrs.nasa.gov/citations/20170002566","Requires DEM-derived/local mapped breach outline; not a point."),
 ("kodiak-butte","Kodiak Butte (Kodiak)","geological_features","delta remnant/butte","Point plus mapped polygon if sourced","high","named_confirmed_coordinates_unjoined","Eroded isolated western fan remnant with preserved bottomset, foreset, and topset strata.","Key evidence for Jezero delta deposition and changing lake level.","Imaged by Perseverance from the landing region; not a rover stop named as the feature center.","Stack et al. 2022 Science Advances",PAPER,"Published orbital/rover mapping identifies it; this repo has no verified footprint/center coordinate. No screenshot estimate."),
 ("landing","Octavia E. Butler Landing Site","rover_exploration","landing site","Point","high","coordinate_available","Perseverance touchdown location.","Mission entry point for in-situ exploration.","Touchdown on Sol 0, 18 February 2021.","Stack et al. 2023 Science Advances",PAPER,"Published landing coordinate 77.4509°E, 18.4446°N; planetocentric, east-positive."),
 ("seitah","Séítah","rover_exploration","geologic formation / campaign region","Polygon/MultiPolygon","high","named_confirmed_geometry_unjoined","Informal name for olivine-rich crater-floor unit and rover exploration area; consists of dispersed exposures among aeolian bedforms.","Records ancient igneous/crater-floor geology, with possible aqueous alteration.","Explored during first science campaign; rover traversed exposures and collected samples.","Farley et al. 2022; USGS SIM 3464", "https://doi.org/10.1029/2022JE007613","Use mapped unit/exposure geometry; avoid a single point for broad unit."),
 ("maaz","Máaz Formation","rover_exploration","geologic formation","Polygon/MultiPolygon","high","named_confirmed_geometry_unjoined","Informal name for basaltic crater-floor rocks overlying Séítah.","Constrains igneous history and the stratigraphy of Jezero floor.","Studied and sampled during first science campaign.","Farley et al. 2022", "https://doi.org/10.1029/2022JE007613","Use published unit map/USGS correlations, not point coordinate."),
 ("three-forks","Three Forks","rover_exploration","sample depot / waypoint","Point or depot-area polygon","high","named_confirmed_exact_tube_positions_unavailable","Named location of Perseverance's sample depot. Depot event table identifies ten drops but does not provide individual tube coordinates.","Preserves cached samples for possible future return.","Ten sample tubes deposited during December 2022–January 2023; individual positions must not be inferred from rover position.","NASA annotated panorama; PDS Three Forks depot bundle",NASA_PANORAMA,"Exact depot coordinate / individual tube locations not joined in repository."),
 ("hawksbill-gap","Hawksbill Gap","rover_exploration","delta-front waypoint / outcrop","Point or local outcrop polygon","high","named_confirmed_coordinates_unjoined","Named passage/outcrop area in the western delta front, associated with the Shenandoah formation.","Exposes delta-front sedimentary stratigraphy.","Perseverance traversed and sampled in the delta-front campaign.","NASA annotated panorama; AGU stratigraphy paper",NASA_PANORAMA,"Use rover observation localizations or source map GIS; no point inferred from illustration."),
 ("kodiak","Kodiak","rover_exploration","named butte / observation target","Point plus polygon if sourced","high","named_confirmed_coordinates_unjoined","Same geological landmark as Kodiak Butte; not a second feature.","Delta stratigraphy and paleolake-level evidence.","Perseverance observed remotely; distinguish rover observation positions from butte location.","Stack et al. 2022 Science Advances",PAPER,"Alias of Kodiak Butte; deduplicate geometry."),
 ("belva-crater","Belva Crater","rover_exploration","impact crater / rover stop","Point plus crater polygon","high","label_anchor_only","Named impact crater and nearby rover observation area. Existing “Belva” coordinate is a USGS text-label anchor, not necessarily crater center.","Provides exposure/context for crater-floor stratigraphy.","Visited/imaged by Perseverance during delta approach.","USGS SIM 3464; NASA mission map",USGS,"Existing anchor in jezero_landmarks.geojson must not be promoted to crater center."),
 ("enchanted-lake","Enchanted Lake","rover_exploration","informal waypoint / target","Point or local polygon","medium","name_requires_source_geometry","Informal rover-era name; precise feature footprint and authoritative coordinate are not present in bundled sources.","Not assigned beyond mission waypoint context until primary mission reference is linked.","Not independently verified in currently bundled primary sources.","ESA/FU Berlin Jezero map",FUB,"Do not place until map waypoint feature data is obtained."),
 ("cape-nukshak","Cape Nukshak","rover_exploration","delta-front outcrop / waypoint","Point or local outcrop polygon","high","named_confirmed_coordinates_unjoined","Named section/outcrop along eastern scarp of the western delta, in the Shenandoah formation.","Exposes lower delta sequence and facies architecture.","Perseverance investigated the section during delta-front campaign.","NASA NTRS lower delta sequence study","https://ntrs.nasa.gov/citations/20230000582","Source confirms location context; exact geometry needs mission waypoint join."),
 ("artuby-ridge","Artuby Ridge","rover_exploration","ridge / campaign region","LineString/Polygon","high","named_confirmed_coordinates_unjoined","Informal ridge/region south of landing area, associated with Máaz/Séítah exposures.","Stratigraphic relationships and crater-floor geology.","Perseverance traversed and investigated Artuby Ridge; flight reconnaissance supported planning.","SuperCam Séítah traverse paper","https://doi.org/10.1029/2022JE007638","Use source map / PLACES localized stops to trace rover traverse; no representative point inferred."),
 ("tuff-cliff","Tuff Cliff","scientific_interest","inlet-channel outcrop / stratigraphic member","Point or outcrop polygon","high","named_confirmed_coordinates_unjoined","Outcrop/member in Neretva Vallis inlet channel, stratigraphically associated with fluvio-lacustrine deposits.","Records transition toward sustained lacustrine conditions.","Observed by Perseverance in the Bright Angel exploration region.","AGU 2025 Neretva Vallis study","https://doi.org/10.1029/2025JE009420","Precise feature geometry not bundled; NASA panorama says outcrop is ~480 m east of Cheyava Falls but that is not a coordinate."),
 ("valinor-hills","Valinor Hills","points_of_interest","informal regional feature","Point/Polygon","medium","existence_confirmed_geometry_unjoined","Informal named feature appearing on NASA Mars 2020 traverse map materials.","No independent scientific interpretation assigned from available source.","Mission traverse-map label; exact footprint not joined.","NASA Mars 2020 traverse map", "https://science.nasa.gov/wp-content/uploads/2024/08/4-mars-exploration-program-pac-july-2024.pdf","NASA figure label is not coordinate geometry."),
 ("beehive-geyser","Beehive Geyser","points_of_interest","informal waypoint / terrain region","Point/Polygon","high","name_and_approximate_relative_location_confirmed","Informal area about 500 m west of the rover at Sol 1059; name does not establish a geological geyser process.","NASA describes a margin-unit interval about 60 m above an earlier sampled section; scientific interest is stratigraphic comparison.","Perseverance planned an excursion there in February 2024.","NASA Science, Beehive Geyser Beckons","https://science.nasa.gov/blog/beehive-geyser-beckons/","Relative distance/direction only; do not turn into a coordinate."),
 ("bunsen-peak","Bunsen Peak","points_of_interest","informal waypoint / sampled rock","Point","high","name_and_rover_observation_confirmed_coordinate_unjoined","Large rock on a ridge in the Margin unit; sample source for Comet Geyser.","Sampled sedimentary rock helps characterize the carbonate-bearing Margin unit.","Perseverance performed proximity science and collected its 27th named sample at the Bunsen Peak target on Sol 1088.","NASA Science and NASA sample inventory","https://science.nasa.gov/blog/beehive-geyser-beckons/","Named target confirmed; exact location can be joined from rover localization and sample event metadata."),
 ("jurabi-point","Jurabi Point","points_of_interest","informal waypoint / traverse area","Point/Polygon","high","name_and_traverse_context_confirmed_coordinate_unjoined","Named waypoint in the Margin Unit campaign.","Provides context for the rover's exploration of carbonate-bearing margin terrain.","Perseverance passed through Jurabi Point during the 2024 Margin Unit traverse.","NASA Science, New Year, New Images from Mars","https://science.nasa.gov/blog/new-year-new-images-from-mars/","Waypoint location needs rover localization join."),
 ("gnaraloo-bay","Gnaraloo Bay","points_of_interest","informal waypoint / erosional window","Polygon","high","named_region_confirmed_geometry_unjoined","Erosional window through the western fan apex exposing underlying Margin Unit.","Exposes the fan-Margin unconformity and stratigraphic relations.","Perseverance explored the region approximately Sols 952–999.","AGU 2025 Margin Unit stratigraphy paper","https://doi.org/10.1029/2025JE009111","Published regional description; exact boundary should be digitized from source map, not approximated."),
 ("mandu-wall","Mandu Wall","points_of_interest","informal escarpment / margin region","LineString/Polygon","high","name_confirmed_geometry_unjoined","Named Margin Unit terrain region associated with the first sample, Pelican Point.","Context for carbonate-bearing rocks and possible shoreline/volcanic/alteration interpretations.","Explored during the Margin campaign; Pelican Point collected from workspace within Mandu Wall.","PDS/PNAS sample context","https://pmc.ncbi.nlm.nih.gov/articles/PMC11745317/","Use traverse/sample observations and regional mapping; no representative point asserted."),
 ("pelican-point","Pelican Point","scientific_interest","named sample / workspace","Point","high","sample_name_confirmed_location_join_required","Perseverance sample name collected at Hans Amundsen Memorial Workspace within Mandu Wall.","First sample from the carbonate-rich Margin Unit; helps assess its origin and habitability context.","Core/sample 22 collected on Sol 923.","NASA/JPL Meet the Mars Samples","https://www.jpl.nasa.gov/videos/meet-the-mars-samples-pelican-point-sample-22/","Sample/workspace coordinates should be joined from PDS PLACES or sample localization metadata."),
 ("pinestand","Pinestand","points_of_interest","informal waypoint / rock feature","Point/Polygon","medium","name_requires_source_geometry","Requested name not verified in available bundled authoritative sources; do not assume it is a distinct Jezero landmark.","Unassigned pending verification.","No verified exploration record in sources reviewed.","ESA/FU Berlin Jezero map",FUB,"Name and coordinate need primary source confirmation."),
 ("faraway-rock","Faraway Rock","points_of_interest","informal waypoint / outcrop","Point","high","name_confirmed_location_join_required","Named group of rocks near the inner crater rim, encountered at the start of the crater-rim campaign.","Rim campaign explores older crustal materials and stratigraphy.","Perseverance reached the area around Sol 1282 and began the rim ascent campaign.","LPSC 2025 abstract","https://www.hou.usra.edu/meetings/lpsc2025/pdf/2189.pdf","Named regional location confirmed; rover stop/localization join required for coordinate."),
]

FIELDS = ["id","name","category","subcategory","geometryType","longitudeEastDeg","latitudePlanetocentricDeg","coordinateSystem","locationConfidence","verificationStatus","insideDemExtent","sourceExtentEastLat","geometryNote","geologicalDescription","scientificSignificance","perseveranceHistory","sourceName","sourceUrl","coordinateSource","imageryUrl","layerId"]

def main():
    points = json.loads((OUT / "jezero_landmarks.geojson").read_text(encoding="utf-8"))["features"]
    published = {"landing": points[0]}
    records=[]
    for row in ROWS:
        (fid,name,category,subcategory,geometry,confidence,status,description,significance,history,source_name,source_url,coordinate_note,*tail)=row
        lon=lat=None; geom=None; inside="unknown"
        representative = {
            "neretva-vallis": (77.20, 18.55),
            "sava-vallis": (77.13, 19.09),
            "eastern-outlet": (78.35, 18.67),
        }
        if fid == "landing":
            g=published["landing"]["geometry"]; lon,lat=g["coordinates"]; geom=g; inside=True
        elif fid in representative:
            lon,lat=representative[fid]; geom={"type":"Point","coordinates":[lon,lat]}; inside="partially_intersects" if fid in {"sava-vallis","eastern-outlet"} else True
        props={"id":fid,"name":name,"category":category,"subcategory":subcategory,"geometryType":geometry,
          "longitudeEastDeg":lon,"latitudePlanetocentricDeg":lat,"coordinateSystem":CRS,
          "locationConfidence":confidence,"verificationStatus":status,"insideDemExtent":inside,
          "geologicalDescription":description,"scientificSignificance":significance,"perseveranceHistory":history,
          "sourceName":source_name,"sourceUrl":source_url,"coordinateSource":coordinate_note,
          "imageryUrl":NASA_PANORAMA if fid in {"hawksbill-gap","three-forks","tuff-cliff"} else None,
          "layerId":category}
        if fid in {"neretva-vallis","sava-vallis","eastern-outlet"}:
            extents={"neretva-vallis":[77.00,18.50,77.30,18.60],"sava-vallis":[76.69,18.74,77.56,19.43],"eastern-outlet":[78.09,18.52,78.60,18.81]}
            props["sourceExtentEastLat"] = extents[fid]
            props["geometryNote"] = "Geometry is the official gazetteer center point for catalog display; the named landform is linear and its source extent is recorded separately."
        records.append({"type":"Feature","id":fid,"geometry":geom,"properties":props})
    doc={"title":"Jezero requested landmark register","version":1,"status":"evidence-triage; unresolved coordinates are intentionally null","coordinateSystem":CRS,
      "demBoundsEastLat":BOUNDS,"layers":["geological_features","rover_exploration","scientific_interest","terrain_hazards","points_of_interest"],
      "layerNotes":{"geological_features":"Use companion SIM 3464 polygon/line layers; source map coverage does not span the full DEM.","rover_exploration":"Use PLACES observations/traverse separately; rover stops do not equal named-feature coordinates.","scientific_interest":"No invented score; scientific significance is descriptive and separate from route safety.","terrain_hazards":"No named hazards asserted. Derive slope/roughness hazards from validated DEM at runtime or offline preprocessing; not included in this named register.","points_of_interest":"Informal names need authoritative waypoint geometries before coordinate placement."},
      "features":records}
    (OUT/"landmarks.json").write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    (OUT/"landmarks.geojson").write_text(json.dumps({"type":"FeatureCollection",**doc},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    with (OUT/"landmarks.csv").open("w",encoding="utf-8-sig",newline="") as f:
        w=csv.DictWriter(f,fieldnames=FIELDS,extrasaction="ignore"); w.writeheader()
        for feature in records:
            props = dict(feature["properties"])
            props["coordinateSystem"] = json.dumps(props["coordinateSystem"], separators=(",", ":"))
            w.writerow(props)
    print(f"Wrote {len(records)} requested landmarks to JSON, GeoJSON, CSV")

if __name__ == "__main__": main()
