#!/usr/bin/env python3
"""Fetch and verify MARS-X datasets (stdlib only). Run from repo root: python3 data/fetch_datasets.py [--full]
Writes data/catalogue/datasets.json (only fields actually verified over HTTP, with verified_on),
small files into data/raw/, and with --full the large DTM GeoTIFF (gitignored)."""
import json, os, re, sys, urllib.request, urllib.error
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__)); RAW = os.path.join(HERE, "raw"); CAT = os.path.join(HERE, "catalogue")
STAC = "https://stac.astrogeology.usgs.gov/api/collections"
AOI = [77.30, 18.30, 77.55, 18.50]
MEDA = "https://atmos.nmsu.edu/PDS/data/PDS4/Mars2020/mars2020_meda"
SOLS = {"sol_0000_0089": [10, 14, 20, 28]}  # small archived subset; extend as needed
TODAY = date.today().isoformat()

UA = {"User-Agent": "MARS-X-fetch/0.1"}

def get(url, binary=False):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "MARS-X-fetch/0.1"}), timeout=60) as r:
        b = r.read(); return b if binary else b.decode("utf-8", "replace")
def head(url):
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, method="HEAD", headers=UA), timeout=30)
        return {"status": r.status, "bytes": int(r.headers.get("Content-Length", 0))}
    except urllib.error.HTTPError:  # some S3 redirects reject HEAD; ask for one byte instead
        try:
            r = urllib.request.urlopen(urllib.request.Request(url, headers={**UA, "Range": "bytes=0-0"}), timeout=30)
        except urllib.error.URLError as ex:
            return {"status": "UNVERIFIED", "error": str(ex)}
        cr = r.headers.get("Content-Range", "")
        return {"status": r.status, "bytes": int(cr.split("/")[-1]) if "/" in cr else 0}
def save(url, rel):
    p = os.path.join(RAW, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
    if not os.path.exists(p) or os.path.getsize(p) == 0:
        open(p, "wb").write(get(url, True))
    return os.path.relpath(p, os.path.dirname(HERE))

def stac_items(col, limit=10):
    d = json.loads(get(f"{STAC}/{col}/items?bbox={','.join(map(str, AOI))}&limit={limit}"))
    return d.get("features", []), d.get("numberMatched")

def main(full):
    os.makedirs(CAT, exist_ok=True); out = []
    # D3 HiRISE DTM (controlled, USGS ARD)
    items, n = stac_items("mro_hirise_socet_dtms")
    for it in items:
        json.dump(it, open(os.path.join(CAT, f"stac_{it['id']}.json"), "w"), indent=1)
    d3 = []
    for it in items:
        a = it["assets"]; sub = it["id"]
        e = {"stac_item": it["id"], "bbox": it["bbox"], "gsd_m": it["properties"].get("gsd"), "license": it["properties"].get("license"),
             "dtm_url": a["dtm"]["href"], "dtm_head": head(a["dtm"]["href"]), "hillshade_url": a["hillshade"]["href"]}
        if it["id"] == "DTEEC_045994_1985_046060_1985_U01":  # Perseverance landing-site DTM
            e["saved"] = [save(a["thumbnail"]["href"], f"D3/{sub}.jpg"), save(a["provenance"]["href"], f"D3/{sub}_provenance.txt")]
            if full: e["saved"].append(save(a["dtm"]["href"], f"D3/{sub}.tif"))
        d3.append(e)
    out.append({"id": "D3", "name": "HiRISE controlled DTMs overlapping AOI", "mission_instrument": "MRO/HiRISE (USGS SOCET SET)", "data_type": "DERIVED",
                "source_url": f"{STAC}/mro_hirise_socet_dtms", "format": "COG GeoTIFF (IAU_2015:49910)", "n_items_in_aoi": n, "items": d3, "verified_on": TODAY})
    # D4 CTX DTM
    items, n = stac_items("mro_ctx_controlled_usgs_dtms")
    d4 = [{"stac_item": i["id"], "bbox": i["bbox"], "dtm_url": i["assets"]["dtm"]["href"], "dtm_head": head(i["assets"]["dtm"]["href"])} for i in items[:5]]
    out.append({"id": "D4", "name": "CTX controlled DTMs", "mission_instrument": "MRO/CTX (USGS)", "data_type": "DERIVED",
                "source_url": f"{STAC}/mro_ctx_controlled_usgs_dtms", "n_items_in_aoi": n, "items": d4, "verified_on": TODAY,
                "note": "Footprints are large; confirm AOI containment and vertical quality before use."})
    # D5 MOLA/HRSC blended DEM (context only)
    u = "https://planetarymaps.usgs.gov/mosaic/Mars_MGS_MOLA_ClrShade_merge_global_463m.tif"
    out.append({"id": "D5", "name": "MOLA colorized shaded relief (463 m)", "mission_instrument": "MGS/MOLA", "data_type": "DERIVED", "source_url": u, "head": head(u),
                "verified_on": TODAY, "note": "Shaded-relief colour product, not a raw elevation DEM. Context only; find the elevation DEM before routing use."})
    # D9 MEDA derived (archived)
    meda = []
    for folder, sols in SOLS.items():
        for s in sols:
            base = f"{MEDA}/data_derived_env/{folder}/sol_{s:04d}/"
            try: files = sorted(set(re.findall(r'href="([^"?/][^"]*)"', get(base))))
            except urllib.error.URLError as ex: meda.append({"sol": s, "error": str(ex)}); continue
            keep = [f for f in files if "DER_TIRS" in f or "DER_RHS" in f]
            meda.append({"sol": s, "dir": base, "files": [save(base + f, f"D9/sol_{s:04d}/{f}") for f in keep]})
    out.append({"id": "D9", "name": "MEDA derived environmental data (archived subset)", "mission_instrument": "Mars 2020 Perseverance / MEDA", "data_type": "MEASURED",
                "source_url": MEDA + "/", "is_live": False, "subset": meda, "verified_on": TODAY,
                "note": "Archived PDS4 tables; see data_derived_env/ labels (.xml) for fields, units and quality flags."})
    # Not yet resolved: stay explicit
    for i, n_ in [("D1", "CTX mosaic"), ("D2", "HiRISE ortho (available via D3 STAC item assets)"), ("D6", "THEMIS"), ("D7", "CRISM"), ("D8", "Jezero geologic map"),
                  ("D10", "Rover traverse"), ("D11", "Mastcam-Z/Navcam"), ("D12", "SuperCam/PIXL/SHERLOC/RIMFAX"), ("D13", "MSL RAD (Gale)")]:
        out.append({"id": i, "name": n_, "status": "UNVERIFIED", "note": "Exact product not yet resolved; do not cite."})
    json.dump(out, open(os.path.join(CAT, "datasets.json"), "w"), indent=1)
    print("wrote", os.path.join(CAT, "datasets.json"))
if __name__ == "__main__": main("--full" in sys.argv)
