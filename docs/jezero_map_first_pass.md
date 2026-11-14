# Jezero map data first pass

## What is in the Flutter app now

- The offline terrain binary is derived from a USGS HiRISE DTM, but the checked-in binary has no map transform. The currently bundled map therefore cannot place geographic points responsibly.
- The planner routes over the local elevation grid only. Its cost functions are prototype heuristics, not astronaut safety criteria.
- The old target pins were pixel placeholders. They have been removed from routing and map rendering.
- The current repository has no rover panorama assets or panorama viewer implementation.

## Offline landmark layer

`mobile/assets/terrain/jezero-landmarks.geojson` contains the first two verified point references:

1. Perseverance / Octavia E. Butler Landing, from the published Jezero rover investigation coordinate (18.4446 N, 77.4509 E).
2. Jezero crater center from the USGS Gazetteer (18.41 N, 77.69 E). It is a reference point, not a crater-boundary geometry.

The map lists these points offline, but only draws or routes to a point when the installed terrain has a Mars grid transform and the point falls inside its footprint. The downloaded raster source is not present in this checkout, and network DNS is unavailable in the current environment, so the terrain package could not be rebuilt here.

## Georeferenced terrain build

`data/build_dem.py` now uses the STAC item's Mars equirectangular transform to center a deterministic crop on Perseverance's published landing location. It writes the projected coordinate of the planning-grid cell centers and preserves NoData with the Int16 sentinel `-32768`. Once the source COG is restored at `data/raw/D3/DTEEC_045994_1985_046060_1985_U01.tif`, run the documented build pipeline to regenerate both web and Flutter terrain assets. This rebuild is necessary before the landing pin appears on the map.

## Next data work

The delta, inlet channels, Máaz and Séítah formation boundaries, Artuby Ridge, Kodiak remnant, Three Forks depot, and rover traverse need source geometries or verified coordinates before adding them to the map. Geological-unit polygons should come from a georeferenced mission map or GIS dataset; traverse points should come from the mission localization archive. Panorama work should begin from PDS original images and calibrated camera poses, generating 360 views only for compatible image sets with adequate angular coverage.
