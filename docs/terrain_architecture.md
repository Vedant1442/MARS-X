# Jezero 3D terrain architecture

## Goal

Add an offline, orbitable 3D map of Jezero to the existing Flutter Map tab. Keep the current Flutter application and its mission features. Use real CTX imagery as the visible surface texture and clearly identified stereo-derived or altimeter-derived elevation for terrain height.

## Data layers

1. **Whole-crater terrain:** use the downloaded USGS Mars 2020 Science Investigation CTX DEM mosaic at 20 m/pixel as the Jezero crater elevation foundation. Its documentation says added stereo DEM areas were tied vertically to MOLA and some horizontal georeferencing was performed in ArcGIS Pro; validate overlaps and display source/uncertainty before app integration.
2. **Whole-crater imagery:** use the matching CTX orthomosaic at 5 m/pixel as a grayscale surface texture, separate from the DEM. Build a multiresolution offline image pyramid.
3. **Global shape:** use MOLA MEGDR topography for the planet-wide overview and where no higher-resolution terrain is available. Its roughly 463 m/pixel 128-pixels-per-degree product is useful for broad topography, not rover-scale hazards.
4. **HiRISE detail:** use each verified HiRISE DTM only inside its published footprint. The original `DTEEC_045994_1985_046060_1985_U01.IMG` has been restored and used to generate a georeferenced local patch; it covers only a small area around the landing site. Keep source resolution distinct from the resampled app mesh and planning grid.
5. **Overlays:** keep rover observations, traverse, landing ellipse, channels, and landmarks as separate georeferenced vector layers. Do not bake them into CTX imagery. The Flutter APK now includes the landing and Gazetteer reference points, eight USGS map-label anchors, and PDS per-sol rover localizations; full polygon and line layers remain outside the app.

## Processing and storage

- Keep downloaded source datasets in `data/raw/` and immutable.
- Crop and align in the Mars source CRS with a documented, explicit transform. Do not use Web Mercator or Earth-oriented XYZ/MBTiles assumptions.
- Build an offline pyramid with transparent NoData and chunked texture tiles. Store installable map data under app-managed storage, not in the APK asset bundle.
- Record dataset identifiers, source URLs, checksums, CRS definitions, crop bounds, output resolutions, resampling methods, and processing versions in metadata.

## Flutter rendering

Keep rendering native to Flutter so the map can use the app's existing gesture, storage, and accessibility flows without introducing a WebView or remote JavaScript dependency. Replace the current cell painter with a mesh painter: use MOLA for planet-wide shape, the 20 m CTX DEM for Jezero's crater-wide surface, and verified HiRISE tiles for local detail. Drape the selected CTX image LOD over mesh patches and draw georeferenced overlays in the same Mars coordinate frame. Use Flutter's GPU-backed `Canvas.drawVertices` and image shaders for textured mesh patches. Keep the rendering code independent from the web-only React Three.js demo.

The 3D camera should support drag-to-orbit, two-finger pan and pinch zoom, plus reset-to-Jezero. A 2D north-up mode should remain available for precise landmark selection. Any exaggeration control must be labeled and default to 1x; it changes display relief, not source elevations. Use Jezero's Gazetteer center (18.41 N, 77.69 E) for the initial camera target and calculate each screen-to-map conversion from the stored projection and raster transform.

## Android constraints

- Never load the 2.2 GB CTX TIFF into memory.
- Decode and retain only visible image tiles; dispose textures when the camera moves to a new LOD.
- Keep height values in compact typed arrays and geometry at a measured level of detail. Match the terrain sampling to the active source: MOLA for global views, CTX DEM (20 m/pixel) for crater-scale terrain, and HiRISE only where its detailed DTM footprint is verified. Do not use CTX DEM to claim rock-scale hazards or extend HiRISE detail beyond its coverage.
- Install map data outside the APK. Show installed size and progress during import, and permit the user to remove processed data without touching original files.
- Profile `drawVertices` and image-shader rendering on the target Android device before choosing mesh patch and texture tile sizes.

## Validation gates

1. Verify dataset CRS and the documented latitude convention with GDAL.
2. Confirm MOLA and CTX crop bounds overlap and test known coordinate-to-pixel conversions in both directions.
3. Compare seam-map locations and tie-point distribution with the CTX crop; retain NoData as transparency.
4. Check north/south orientation, longitude direction, image-to-height alignment, and tile boundaries.
5. Capture screenshots at crater and local-detail zoom; report pixel scale and data source for each layer.
6. Profile Android memory, frame rate, and storage on the target device before packaging the full map.
