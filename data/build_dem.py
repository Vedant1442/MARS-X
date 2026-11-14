#!/usr/bin/env python3
"""Build a deterministic, georeferenced offline Jezero HiRISE terrain patch.

The crop is centered on Perseverance's published landing location instead of
choosing a visually interesting window. Int16 decimetres are little-endian;
-32768 means NoData. The JSON records Mars projected coordinates for the
planning-grid cell centers. Requires the source USGS COG in data/raw/D3/.
"""
import os
import sys
import json
import base64
import struct
import shutil
import math

sys.path.insert(0, os.path.dirname(__file__))
from tiff_read import read_ifds, read_level

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEM = 'DTEEC_045994_1985_046060_1985_U01'
DTM = os.path.join(ROOT, 'data/raw/D3', ITEM + '.tif')
STAC = os.path.join(ROOT, 'data/catalogue', 'stac_' + ITEM + '.json')
RADIUS_M = 3396190.0
LANDING_LON_DEG = 77.4509
LANDING_LAT_DEG = 18.4446
OW, OH = 480, 304
GW, GH = 120, 76
NODATA = -32768

if not os.path.exists(DTM):
    raise SystemExit(f'Missing source DTM: {DTM}. Fetch the catalogued USGS asset before building.')

with open(DTM, 'rb') as f:
    raw = f.read()
ifds = read_ifds(raw)
base = ifds[0]
overview = ifds[2]
step_m = base['scale'][0] * base['w'][0] / overview['w'][0]
rows = read_level(raw, overview)
height, width = len(rows), len(rows[0])
print('overview', width, height, 'spacing_m', round(step_m, 3))

with open(STAC, encoding='utf-8') as f:
    item = json.load(f)
gt = item['properties']['proj:transform']
source_gsd = item['properties']['gsd']
overview_step_x = gt[1] * base['w'][0] / overview['w'][0]
overview_step_y = gt[5] * base['h'][0] / overview['h'][0]
world_x = RADIUS_M * math.radians(LANDING_LON_DEG)
world_y = RADIUS_M * math.radians(LANDING_LAT_DEG)
center_x = (world_x - gt[0]) / overview_step_x - 0.5
center_y = (world_y - gt[3]) / overview_step_y - 0.5

window_w = int(width * 0.62)
window_h = round(window_w * GH / GW)
x0 = round(center_x - (window_w - 1) / 2)
y0 = round(center_y - (window_h - 1) / 2)
if x0 < 0 or y0 < 0 or x0 + window_w > width or y0 + window_h > height:
    raise ValueError('Landing-centered crop falls outside the DTM overview.')
print('crop', x0, y0, window_w, window_h)

def sample(fx, fy):
    x = x0 + fx * (window_w - 1)
    y = y0 + fy * (window_h - 1)
    ix, iy = int(x), int(y)
    tx, ty = x - ix, y - iy
    ix1, iy1 = min(ix + 1, width - 1), min(iy + 1, height - 1)
    q = [rows[iy][ix], rows[iy][ix1], rows[iy1][ix], rows[iy1][ix1]]
    if any(v is None for v in q):
        return None
    return (q[0] * (1 - tx) + q[1] * tx) * (1 - ty) + (q[2] * (1 - tx) + q[3] * tx) * ty

hi = [[sample(x / (OW - 1), y / (OH - 1)) for x in range(OW)] for y in range(OH)]
valid = [v for row in hi for v in row if v is not None]
if not valid:
    raise ValueError('The selected crop contains no valid elevations.')
print('elevation_m', round(min(valid), 1), round(max(valid), 1), 'valid_samples', len(valid))

hi_values = [round(v * 10) if v is not None else NODATA for row in hi for v in row]
hi_path = os.path.join(ROOT, 'public/jezero-dem.bin')
with open(hi_path, 'wb') as f:
    f.write(struct.pack('<' + str(OW * OH) + 'h', *hi_values))

grid = []
grid_mask = []
for gy in range(GH):
    grid_row, mask_row = [], []
    for gx in range(GW):
        block = [hi[gy * 4 + by][gx * 4 + bx] for by in range(4) for bx in range(4)]
        samples = [v for v in block if v is not None]
        grid_row.append(sum(samples) / len(samples) if samples else 0.0)
        # Any missing source samples make this planning cell unknown.
        mask_row.append(0 if len(samples) == 16 else 1)
    grid.append(grid_row)
    grid_mask.append(mask_row)

projected_cell_x_m = step_m * ((window_w - 1) / (OW - 1)) * 4
cell_width_m = projected_cell_x_m * math.cos(math.radians(LANDING_LAT_DEG))
cell_height_m = projected_cell_x_m
cell_m = math.sqrt(cell_width_m * cell_height_m)
grid_center_x = gt[0] + (x0 + 0.5 + 1.5 * (window_w - 1) / (OW - 1)) * overview_step_x
grid_center_y = gt[3] + (y0 + 0.5 + 1.5 * (window_h - 1) / (OH - 1)) * overview_step_y
meta = {
    'w': GW, 'h': GH, 'cellM': cell_m, 'cellWidthM': cell_width_m, 'cellHeightM': cell_height_m,
    'widthM': cell_width_m * GW, 'heightM': cell_height_m * GH,
    'hiW': OW, 'hiH': OH, 'min': min(valid), 'max': max(valid),
    'encoding': 'int16-decimetres-le', 'nodata': NODATA,
    'source': 'USGS HiRISE DTM ' + ITEM, 'sourceGsdM': source_gsd,
    'sourceItem': 'data/catalogue/stac_' + ITEM + '.json',
    'crs': 'Mars 2015 sphere / planetocentric / equirectangular, east-positive longitude',
    'radiusM': RADIUS_M, 'gridCenterX': grid_center_x, 'gridCenterY': grid_center_y,
    'gridStepXM': projected_cell_x_m, 'gridStepYM': projected_cell_x_m,
    'planningWindowCenter': {'longitudeEastDeg': LANDING_LON_DEG, 'latitudePlanetocentricDeg': LANDING_LAT_DEG},
    'gridNoDataCells': sum(sum(r) for r in grid_mask),
}
meta_path = os.path.join(ROOT, 'public/jezero-dem.json')
with open(meta_path, 'w', encoding='utf-8') as f:
    json.dump(meta, f, indent=2)

grid_bin = [round(grid[y][x] * 10) if not grid_mask[y][x] else NODATA for y in range(GH) for x in range(GW)]
b64 = base64.b64encode(struct.pack('<' + str(GW * GH) + 'h', *grid_bin)).decode()
with open(os.path.join(ROOT, 'src/jezeroGrid.ts'), 'w', encoding='utf-8') as f:
    f.write('// Generated from the USGS HiRISE DTM; Int16 decimetres, -32768 is NoData.\n')
    f.write(f'export const JEZERO_META = {json.dumps(meta)} as const;\n')
    f.write(f'export const JEZERO_B64 = "{b64}";\n')

mobile_assets = os.path.join(ROOT, 'mobile/assets/terrain')
os.makedirs(mobile_assets, exist_ok=True)
shutil.copyfile(hi_path, os.path.join(mobile_assets, 'jezero-dem.bin'))
shutil.copyfile(meta_path, os.path.join(mobile_assets, 'jezero-dem.json'))
with open(os.path.join(mobile_assets, 'jezero-grid.bin'), 'wb') as f:
    f.write(struct.pack('<' + str(GW * GH) + 'h', *grid_bin))
print(json.dumps(meta, indent=2))
