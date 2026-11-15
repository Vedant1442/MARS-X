FROM python:3.12-slim
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/app ./app
COPY backend/tests ./tests
# DEM for routing (real HiRISE DTM, Int16 LE)
COPY backend/data/jezero-dem.dat ./data/jezero-dem.dat
# Processed GeoJSON layers (science targets, rover traverse, landmarks)
COPY data/processed/jezero ./data/processed/jezero
# Real MEDA weather PDS4 derived tables (Sols 10, 14, 20, 28)
COPY data/raw/D9 ./data/raw/D9
EXPOSE 8000
# Railway injects $PORT; fall back to 8000 for local runs
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
