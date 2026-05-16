# Maize Price Forecast API - Quick Usage

## Setup

```bash
# Install dependencies
pip install -r requirements.txt

# Run the API
uvicorn api:app --reload
```

The API will be available at: `http://localhost:8000`

## Testing

### Interactive API Docs
Visit: `http://localhost:8000/docs`

Click "Try it out" on any endpoint to test.

### Using cURL

```bash
# Get available counties
curl http://localhost:8000/counties

# Predict for 7 days ahead (national median)
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"horizon_days": 7}'

# Predict for 7 days ahead in Kiambu
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"horizon_days": 7, "county": "Kiambu"}'

# Predict from a specific reference date
curl -X POST http://localhost:8000/predict \
  -H "Content-Type: application/json" \
  -d '{"horizon_days": 7, "county": "Kiambu", "reference_date": "2026-05-13"}'
```

### Using Python

```python
import requests

BASE_URL = "http://localhost:8000"

# Get counties
response = requests.get(f"{BASE_URL}/counties")
print(response.json())

# Make prediction
response = requests.post(
    f"{BASE_URL}/predict",
    json={"horizon_days": 7, "county": "Kiambu"}
)
print(response.json())
```

## API Endpoints

- `GET /` - Root info
- `GET /counties` - List available counties
- `POST /predict` - Get price prediction
- `GET /docs` - Interactive API docs (Swagger)

## Parameters

### POST /predict

- `horizon_days` (required): 1-14 days ahead
- `county` (optional): County name (if None, uses national median)
- `reference_date` (optional): YYYY-MM-DD format (if None, uses latest date)

## Response

```json
{
  "date": "2026-05-20",
  "horizon_days": 7,
  "location": "Kiambu",
  "current_price": 42.50,
  "predicted_price": 43.15,
  "change_kes": 0.65,
  "change_percent": 1.53
}
```

## Notes

- First run trains 14 models (takes 2-5 minutes)
- Subsequent runs are fast (~20-50ms per prediction)
- Models are cached in memory after first load
- Data is aggregated to daily median per location
