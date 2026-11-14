#!/usr/bin/env python3
"""Build a deterministic offline Jezero patch from the original HiRISE PDS3 DTM.

The crop is centered on Perseverance's published landing location. The PDS3
label embedded in the .IMG supplies its dimensions, byte order, map scale and
projection offsets. Outputs are Int16 decimetres; -32768 means NoData.
"""
import os
import sys
import json
import base64
import struct
import shutil
import math
import re
import mmap
import hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEM = 'DTEEC_045994_1985_046060_1985_U01'
DTM = os.path.join(ROOT, 'data/raw/D3', ITEM + '.IMG')
STAC = os.path.join(ROOT, 'data/catalogue', 'stac_' + ITEM + '.json')
RADIUS_M = 3396190.0
LANDING_LON_DEG = 77.4509
LANDING_LAT_DEG = 18.4446
OW, OH = 480, 304
GW, GH = 120, 76
NODATA = -32768

if not os.path.exists(DTM):
    raise SystemExit(f'Missing original HiRISE PDS DTM: {DTM}')

source_hash = hashlib.sha256()
with open(DTM, 'rb') as hash_file:
    for chunk in iter(lambda: hash_file.read(8 * 1024 * 1024), b''):
        source_hash.update(chunk)
source_sha256 = source_hash.hexdigest()

with open(DTM, 'rb') as f:
    header = f.read(65536)
label_end = re.search(rb'(?m)^END\s*$', header)
if not label_end:
    raise SystemExit('Could not find the end of the embedded PDS3 label.')
label = header[:label_end.end()].decode('ascii', errors='strict')

def pds_value(key):
    match = re.search(r'^\s*' + re.escape(key) + r'\s*=\s*([^\r\n]+)', label, re.M)
    if not match:
        raise ValueError(f'Missing {key} in embedded PDS label.')
    return match.group(1).split('<', 1)[0].strip().strip('"')

record_bytes = int(pds_value('RECORD_BYTES'))
image_record = int(pds_value('^IMAGE'))
lines = int(pds_value('LINES'))
samples = int(pds_value('LINE_SAMPLES'))
sample_bits = int(pds_value('SAMPLE_BITS'))
sample_type = pds_value('SAMPLE_TYPE')
if sample_bits != 32 or sample_type != 'PC_REAL':
    raise ValueError(f'Expected 32-bit little-endian PC_REAL, got {sample_bits}-bit {sample_type}.')
data_offset = (image_record - 1) * record_bytes
if os.path.getsize(DTM) < data_offset + lines * samples * 4:
    raise ValueError('PDS image data is truncated.')

map_scale = float(pds_value('MAP_SCALE'))
center_lat = float(pds_value('CENTER_LATITUDE'))
center_lon = float(pds_value('CENTER_LONGITUDE'))
line_offset = float(pds_value('LINE_PROJECTION_OFFSET'))
sample_offset = float(pds_value('SAMPLE_PROJECTION_OFFSET'))
valid_min = float(pds_value('VALID_MINIMUM'))
valid_max = float(pds_value('VALID_MAXIMUM'))
missing_hex = re.search(r'16#([0-9A-Fa-f]+)#', pds_value('MISSING_CONSTANT'))
missing_bits = int(missing_hex.group(1), 16) if missing_hex else None
height, width = lines, samples
print('PDS3 IMG', width, height, 'map_scale_m', round(map_scale, 4), 'data_offset', data_offset)

def pixel_for_lonlat(lon_deg, lat_deg):
    # PDS sample/line coordinates are one-based; convert the result to zero-based.
    sample_1 = sample_offset + math.radians(lon_deg - center_lon) * RADIUS_M * math.cos(math.radians(center_lat)) / map_scale
    line_1 = line_offset - math.radians(lat_deg) * RADIUS_M / map_scale
    return sample_1 - 1.0, line_1 - 1.0

def lonlat_for_pixel(col, row):
    sample_1, line_1 = col + 1.0, row + 1.0
    lon = center_lon + (sample_1 - sample_offset) * map_scale / (RADIUS_M * math.cos(math.radians(center_lat))) * 180.0 / math.pi
    lat = (line_offset - line_1) * map_scale / RADIUS_M * 180.0 / math.pi
    return lon, lat

landing_col, landing_row = pixel_for_lonlat(LANDING_LON_DEG, LANDING_LAT_DEG)
window_w = int(width * 0.62)
window_h = round(window_w * GH / GW)
x0 = round(landing_col - (window_w - 1) / 2)
y0 = round(landing_row - (window_h - 1) / 2)
if x0 < 0 or y0 < 0 or x0 + window_w > width or y0 + window_h > height:
    raise ValueError('Landing-centered crop falls outside the HiRISE DTM.')
print('crop', x0, y0, window_w, window_h, 'landing_pixel', round(landing_col, 1), round(landing_row, 1))

source_file = open(DTM, 'rb')
source_map = mmap.mmap(source_file.fileno(), 0, access=mmap.ACCESS_READ)

def source_value(col, row):
    if col < 0 or row < 0 or col >= width or row >= height:
        return None
    byte_offset = data_offset + (row * width + col) * 4
    raw_bits = struct.unpack_from('<I', source_map, byte_offset)[0]
    if raw_bits == missing_bits:
        return None
    value = struct.unpack_from('<f', source_map, byte_offset)[0]
    if not math.isfinite(value) or value < valid_min or value > valid_max:
        return None
    return value

with open(STAC, encoding='utf-8') as f:
    item = json.load(f)
source_gsd = item['properties']['gsd']

def sample(fx, fy):
    x = x0 + fx * (window_w - 1)
    y = y0 + fy * (window_h - 1)
    ix, iy = int(x), int(y)
    tx, ty = x - ix, y - iy
    ix1, iy1 = min(ix + 1, width - 1), min(iy + 1, height - 1)
    q = [source_value(ix, iy), source_value(ix1, iy), source_value(ix, iy1), source_value(ix1, iy1)]
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

grid_center_col = x0 + (window_w - 1) / 2
grid_center_row = y0 + (window_h - 1) / 2
grid_center_lon, grid_center_lat = lonlat_for_pixel(grid_center_col, grid_center_row)
grid_center_x = RADIUS_M * math.radians(grid_center_lon)
grid_center_y = RADIUS_M * math.radians(grid_center_lat)
projected_cell_x_m = map_scale / math.cos(math.radians(center_lat)) * ((window_w - 1) / (OW - 1)) * 4
cell_width_m = projected_cell_x_m * math.cos(math.radians(LANDING_LAT_DEG))
cell_height_m = map_scale * ((window_h - 1) / (OH - 1)) * 4
cell_m = math.sqrt(cell_width_m * cell_height_m)
meta = {
    'w': GW, 'h': GH, 'cellM': cell_m, 'cellWidthM': cell_width_m, 'cellHeightM': cell_height_m,
    'widthM': cell_width_m * GW, 'heightM': cell_height_m * GH,
    'hiW': OW, 'hiH': OH, 'min': min(valid), 'max': max(valid),
    'encoding': 'int16-decimetres-le', 'nodata': NODATA,
    'source': 'HiRISE PDS3 DTM ' + ITEM, 'sourceSha256': source_sha256, 'sourceGsdM': map_scale,
    'catalogueGsdM': source_gsd, 'verticalDatum': 'Mars 2000 datum; elevations above the martian equipotential surface',
    'projectionMapScaleM': map_scale, 'projectionCenterLatitudeDeg': center_lat,
    'sourceItem': 'data/catalogue/stac_' + ITEM + '.json',
    'crs': 'Mars 2015 sphere / planetocentric / equirectangular, east-positive longitude',
    'radiusM': RADIUS_M, 'gridCenterX': grid_center_x, 'gridCenterY': grid_center_y,
    'gridStepXM': projected_cell_x_m, 'gridStepYM': cell_height_m,
    'planningWindowCenter': {'longitudeEastDeg': LANDING_LON_DEG, 'latitudePlanetocentricDeg': LANDING_LAT_DEG},
    'gridNoDataCells': sum(sum(r) for r in grid_mask),
}
meta_path = os.path.join(ROOT, 'public/jezero-dem.json')
with open(meta_path, 'w', encoding='utf-8') as f:
    json.dump(meta, f, indent=2)

grid_bin = [round(grid[y][x] * 10) if not grid_mask[y][x] else NODATA for y in range(GH) for x in range(GW)]
b64 = base64.b64encode(struct.pack('<' + str(GW * GH) + 'h', *grid_bin)).decode()
with open(os.path.join(ROOT, 'src/jezeroGrid.ts'), 'w', encoding='utf-8') as f:
    f.write('// Generated from the original HiRISE PDS3 DTM; Int16 decimetres, -32768 is NoData.\n')
    f.write(f'export const JEZERO_META = {json.dumps(meta)} as const;\n')
    f.write(f'export const JEZERO_B64 = "{b64}";\n')

mobile_assets = os.path.join(ROOT, 'mobile/assets/terrain')
os.makedirs(mobile_assets, exist_ok=True)
shutil.copyfile(hi_path, os.path.join(mobile_assets, 'jezero-dem.bin'))
shutil.copyfile(meta_path, os.path.join(mobile_assets, 'jezero-dem.json'))
with open(os.path.join(mobile_assets, 'jezero-grid.bin'), 'wb') as f:
    f.write(struct.pack('<' + str(GW * GH) + 'h', *grid_bin))
print(json.dumps(meta, indent=2))
source_map.close()
source_file.close()
