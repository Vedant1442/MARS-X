# MARS-X

An offline-capable Mars exploration prototype for Jezero crater. The project is being expanded to combine orbital terrain and imagery, sourced landmarks, rover observations, and route planning. Data availability and scientific limits vary by layer; the app should identify the source and resolution of the map currently shown.

## Start here

- [Data sources and plain-language explanations](docs/DATA_SOURCES.md) — source, coverage, resolution, current status, limitations, and credit for each layer.
- [Data processing notes](data/README.md) — how the original HiRISE PDS elevation product becomes offline terrain assets.
- [Jezero map architecture](docs/terrain_architecture.md) — current rendering and offline-data design.

## Coverage status

The original HiRISE DTM is being used for a small, high-detail patch around Perseverance's landing site. The whole-crater CTX elevation and image mosaics are downloaded and verified, but still need to be aligned and integrated. Read the source register before describing the current app map as whole-crater coverage.
