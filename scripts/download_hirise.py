
from pystac_client import Client
import json
import os

# Connect to USGS STAC catalog
catalog = Client.open(
    "https://stac.astrogeology.usgs.gov/api"
)

# Correct HiRISE collection
collection = "mro_hirise_uncontrolled_observations"

# Jezero crater study area
bbox = [77.2, 18.2, 77.8, 18.6]

# Search products
search = catalog.search(
    collections=[collection],
    bbox=bbox,
    max_items=20
)

items = list(search.items())

print("Products found:", len(items))

# Create output directory
os.makedirs("data/metadata", exist_ok=True)

# Save metadata
with open(
    "data/metadata/hirise_results.json",
    "w"
) as f:
    json.dump(
        [item.to_dict() for item in items],
        f,
        indent=2
    )

# Display products and assets
for item in items:
    print("\nProduct:", item.id)

    for name, asset in item.assets.items():
        print("Asset:", name)
        print("URL:", asset.href)

