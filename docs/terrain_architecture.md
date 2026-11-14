# Jezero 3D terrain architecture

## Goal

Add an offline, orbitable 3D map of Jezero to the existing Flutter Map tab. Keep the current Flutter application and its mission features. Use real CTX imagery as the visible surface texture and measured elevation as terrain height.

## Data layers

1. **CTX albedo:** crop the supplied E076_N16 GeoTIFF to the verified Jezero map extent. Preserve the source file, projection, pixel scale, and NoData mask. Build a local multiresolution image pyramid from this crop.
2. **MOLA shape:** use the official MOLA MEGDR topography product for continuous crater-scale elevation. Its approximately 463 m grid is suitable for the broad basin shape, not rover-scale hazards.
3. **HiRISE detail:** optionally restore the original DTM and use it only inside its published footprint. The existing bundled sample has lost georeferencing and must not be placed by guessed coordinates.
4. **Overlays:** keep rover observations, traverse, landing ellipse, channels, and landmarks as separate georeferenced vector layers. Do not bake them into CTX imagery.

## Processing and storage

- Keep downloaded source datasets in `data/raw/` and immutable.
- Crop and align in the Mars source CRS with a documented, explicit transform. Do not use Web Mercator or Earth-oriented XYZ/MBTiles assumptions.
- Build an offline pyramid with transparent NoData and chunked texture tiles. Store installable map data under app-managed storage, not in the APK asset bundle.
- Record dataset identifiers, source URLs, checksums, CRS definitions, crop bounds, output resolutions, resampling methods, and processing versions in metadata.

## Flutter rendering

Keep rendering native to Flutter so the map can use the app's existing gesture, storage, and accessibility flows without introducing a WebView or remote JavaScript dependency. Replace the current cell painter with a mesh painter: project a sampled MOLA heightfield into the camera view, drape the selected CTX LOD tile textures over its triangle patches, and draw georeferenced overlays in the same local Mars coordinate frame. Use Flutter's GPU-backed `Canvas.drawVertices` and image shaders for textured mesh patches. Keep the rendering code independent from the web-only React Three.js demo.

The 3D camera should support drag-to-orbit, two-finger pan and pinch zoom, plus reset-to-Jezero. A 2D north-up mode should remain available for precise landmark selection. Any exaggeration control must be labeled and default to 1x; it changes display relief, not source elevations. Use Jezero's Gazetteer center (18.41 N, 77.69 E) for the initial camera target and calculate each screen-to-map conversion from the stored projection and raster transform.

## Android constraints

- Never load the 2.2 GB CTX TIFF into memory.
- Decode and retain only visible image tiles; dispose textures when the camera moves to a new LOD.
- Keep MOLA height values in compact typed arrays and geometry at a measured level of detail. Limit mesh density to the source MOLA spacing for the crater overview; do not imply sub-kilometre elevation detail from CTX pixels.
- Install map data outside the APK. Show installed size and progress during import, and permit the user to remove processed data without touching original files.
- Profile `drawVertices` and image-shader rendering on the target Android device before choosing mesh patch and texture tile sizes.

## Validation gates

1. Verify dataset CRS and the documented latitude convention with GDAL.
2. Confirm MOLA and CTX crop bounds overlap and test known coordinate-to-pixel conversions in both directions.
3. Compare seam-map locations and tie-point distribution with the CTX crop; retain NoData as transparency.
4. Check north/south orientation, longitude direction, image-to-height alignment, and tile boundaries.
5. Capture screenshots at crater and local-detail zoom; report pixel scale and data source for each layer.
6. Profile Android memory, frame rate, and storage on the target device before packaging the full map.
