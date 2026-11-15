FROM python:3.12-slim
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/app ./app
COPY backend/tests ./tests
# DEM for routing
COPY public/jezero-dem.bin ./data/jezero-dem.bin
# Processed GeoJSON layers (science targets, rover traverse, landmarks)
COPY data/processed/jezero ./data/processed/jezero
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
