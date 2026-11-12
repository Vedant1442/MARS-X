#!/bin/bash
cd "$(dirname "$0")/.."
export MARSX_DEM_PATH="public/jezero-dem.bin"
uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 --reload
