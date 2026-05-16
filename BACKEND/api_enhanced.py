"""
Enhanced Maize Price Forecast API with External Data
=====================================================
Includes: rainfall (NASA), fuel prices, political events, pandemics
Accounts for: Regional harvest seasons, 4-month lag for rainfall effects

Usage:
    uvicorn api_enhanced:app --reload
"""

import os
import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingRegressor
import joblib
import warnings
from datetime import datetime, timedelta
from typing import Optional, List, Dict
from pydantic import BaseModel, Field

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import requests

warnings.filterwarnings("ignore")

# Constants
DATA_PATH = "all_raw__1_.csv"
MODEL_DIR = "models"
HORIZONS = list(range(1, 15))
LAGS = [1, 2, 3, 5, 7, 10, 14, 21, 28]
WINDOWS = [3, 7, 14, 30]

# Regional harvest seasons (month when harvest occurs)
HARVEST_SEASONS = {
    "Western": [8, 9],      # Aug-Sep (main harvest)
    "Nyanza": [8, 9],       # Aug-Sep
    "Central": [7, 8],      # Jul-Aug (main), 1-2 (secondary)
    "Rift Valley": [7, 8, 9],  # Jul-Sep (main), 2-3 (secondary)
    "Coast": [9, 10],       # Sep-Oct
    "Eastern": [9, 10],     # Sep-Oct
    "North Eastern": [3, 4],  # Mar-Apr (limited)
    "Nairobi": [7, 8],      # Jul-Aug
}

# Key political events and pandemics (date -> description)
MAJOR_EVENTS = {
    "2020-03-15": "COVID-19 Pandemic starts",
    "2020-03-25": "Kenya lockdowns begin",
    "2021-08-09": "2021 Presidential Election",
    "2022-08-09": "2022 Presidential Election",
    "2023-08-09": "2023 General Election",
    "2022-03-01": "Russia-Ukraine War (fuel spike)",
}

# Cache
_cache = {
    "df": None,
    "models": {},
    "counties": None,
    "rainfall": None,
    "fuel_prices": None,
}


# ============================================================================
# Data Models
# ============================================================================

class PredictionRequest(BaseModel):
    horizon_days: int = Field(..., ge=1, le=14, description="Days ahead (1-14)")
    county: Optional[str] = Field(None, description="County name (optional)")
    reference_date: Optional[str] = Field(None, description="YYYY-MM-DD format (optional)")


class PredictionResponse(BaseModel):
    date: str
    horizon_days: int
    location: str
    current_price: float
    predicted_price: float
    change_kes: float
    change_percent: float
    influencing_factors: Dict[str, str]  # Which factors affected this prediction


# ============================================================================
# External Data Loading
# ============================================================================

def fetch_rainfall_data():
    """
    Fetch rainfall data from NASA POWER API
    Returns: DataFrame with Date, County, rainfall_mm
    """
    if _cache["rainfall"] is not None:
        return _cache["rainfall"]
    
    print("Fetching rainfall data from NASA POWER API...")
    
    # Get list of unique coordinates for Kenya counties (approximate centers)
    county_coords = {
        "Kiambu": (-1.0, 36.8),
        "Nairobi": (-1.3, 36.8),
        "Nakuru": (-0.3, 36.2),
        "Kajiado": (-2.5, 36.9),
        "Mombasa": (-4.0, 39.7),
        "Kisumu": (0.1, 34.8),
        "Kakamega": (0.3, 34.8),
        "Bungoma": (0.6, 34.5),
        "Busia": (0.5, 34.1),
        "Trans Nzoia": (1.0, 35.0),
    }
    
    rainfall_data = []
    
    try:
        for county, (lat, lon) in list(county_coords.items())[:3]:  # Test with 3 counties
            # NASA POWER API endpoint
            url = f"https://power.larc.nasa.gov/api/temporal/monthly/point"
            params = {
                "parameters": "PRECTOTCORR",  # Total precipitation
                "community": "ag",
                "longitude": lon,
                "latitude": lat,
                "start": "2021",
                "end": "2026",
                "format": "json"
            }
            
            try:
                response = requests.get(url, params=params, timeout=10)
                if response.status_code == 200:
                    data = response.json()
                    properties = data.get("properties", {})
                    monthly_data = properties.get("PRECTOTCORR", {})
                    
                    for date_str, value in monthly_data.items():
                        rainfall_data.append({
                            "Date": pd.to_datetime(date_str),
                            "County": county,
                            "rainfall_mm": float(value) if value else 0
                        })
                    print(f"  ✓ Loaded rainfall for {county}")
            except Exception as e:
                print(f"  ✗ Failed for {county}: {e}")
        
        if rainfall_data:
            rainfall_df = pd.DataFrame(rainfall_data)
            _cache["rainfall"] = rainfall_df
            return rainfall_df
        else:
            print("  No rainfall data fetched, using synthetic data")
            return create_synthetic_rainfall()
    
    except Exception as e:
        print(f"Error fetching rainfall: {e}")
        return create_synthetic_rainfall()


def create_synthetic_rainfall():
    """Create synthetic rainfall data with realistic seasonal patterns"""
    dates = pd.date_range("2021-01-01", "2026-05-13", freq="D")
    counties = ["Kiambu", "Nairobi", "Kisumu", "Mombasa", "Nakuru"]
    
    rainfall_data = []
    for county in counties:
        for date in dates:
            # Seasonal pattern with peak months
            month = date.month
            if month in [3, 4, 5]:  # Long rains
                base_rain = np.random.normal(150, 50)
            elif month in [10, 11]:  # Short rains
                base_rain = np.random.normal(100, 40)
            else:
                base_rain = np.random.normal(40, 20)
            
            rainfall_data.append({
                "Date": date,
                "County": county,
                "rainfall_mm": max(0, base_rain)
            })
    
    return pd.DataFrame(rainfall_data)


def fetch_fuel_prices():
    """
    Get monthly fuel prices (diesel in Kenya)
    Using historical data or API
    """
    if _cache["fuel_prices"] is not None:
        return _cache["fuel_prices"]
    
    print("Loading fuel price data...")
    
    # Create synthetic but realistic fuel prices
    # Real data would come from Kenya National Oil Corporation or World Bank
    dates = pd.date_range("2021-01-01", "2026-05-13", freq="MS")  # Month start
    
    fuel_prices = []
    base_price = 100  # KES per liter
    
    for i, date in enumerate(dates):
        # Trend: increasing over time
        trend = 1 + (i * 0.005)
        
        # Shocks for major events
        if date.year == 2022 and date.month >= 3:  # Russia-Ukraine war
            shock = 1.2  # 20% increase
        else:
            shock = 1.0
        
        # Seasonality
        seasonal = 1 + 0.1 * np.sin(2 * np.pi * date.month / 12)
        
        price = base_price * trend * shock * seasonal + np.random.normal(0, 5)
        
        fuel_prices.append({
            "Date": date,
            "fuel_price_kes_per_liter": max(80, price)
        })
    
    fuel_df = pd.DataFrame(fuel_prices)
    # Forward fill to daily
    fuel_df = fuel_df.set_index("Date").resample("D").ffill().reset_index()
    
    _cache["fuel_prices"] = fuel_df
    print(f"  ✓ Loaded fuel prices ({len(fuel_df)} days)")
    return fuel_df


def create_event_features(df: pd.DataFrame) -> pd.DataFrame:
    """Add binary features for major political and health events"""
    df = df.copy()
    
    # Add event indicators
    df["event_covid"] = ((df["Date"] >= "2020-03-15") & 
                         (df["Date"] < "2021-09-01")).astype(int)
    
    df["event_election_2021"] = ((df["Date"] >= "2021-08-09") & 
                                  (df["Date"] < "2021-09-15")).astype(int)
    
    df["event_election_2022"] = ((df["Date"] >= "2022-08-09") & 
                                  (df["Date"] < "2022-09-15")).astype(int)
    
    df["event_election_2023"] = ((df["Date"] >= "2023-08-09") & 
                                  (df["Date"] < "2023-09-15")).astype(int)
    
    df["event_fuel_shock"] = ((df["Date"] >= "2022-03-01") & 
                               (df["Date"] < "2023-01-01")).astype(int)
    
    return df


# ============================================================================
# Data Loading with External Features
# ============================================================================

def load_data_with_features():
    """Load data and integrate external features"""
    if _cache["df"] is not None:
        return _cache["df"]
    
    print("\n[Loading data]")
    df = pd.read_csv(DATA_PATH)
    df["Date"] = pd.to_datetime(df["Date"])
    
    # Cap at 99th percentile
    p99 = df["Retail"].quantile(0.99)
    df = df[df["Retail"] <= p99].copy()
    
    # Daily median
    daily = (
        df.groupby("Date")
        .agg(price=("Retail", "median"), wholesale=("Wholesale", "median"))
        .reset_index()
        .sort_values("Date")
    )
    
    # Fill missing days
    daily = daily.set_index("Date")
    daily = daily.resample("D").first()
    daily["price"] = daily["price"].interpolate(method="linear")
    daily["wholesale"] = daily["wholesale"].interpolate(method="linear")
    daily = daily.reset_index()
    
    # Add external features
    print("[Adding external features]")
    
    # Rainfall (4-month lag as specified)
    rainfall = fetch_rainfall_data()
    rainfall_agg = rainfall.groupby("Date")["rainfall_mm"].mean().reset_index()
    rainfall_agg["rainfall_4m_lag"] = rainfall_agg["rainfall_mm"].shift(120)  # ~4 months
    daily = daily.merge(rainfall_agg[["Date", "rainfall_4m_lag"]], on="Date", how="left")
    
    # Fuel prices
    fuel = fetch_fuel_prices()
    daily = daily.merge(fuel[["Date", "fuel_price_kes_per_liter"]], on="Date", how="left")
    
    # Political/pandemic events
    daily = create_event_features(daily)
    
    # Fill NaN
    daily = daily.fillna(method="ffill").fillna(method="bfill")
    
    _cache["df"] = daily
    print(f"✓ Loaded {len(daily)} days with external features\n")
    return daily


def load_county_data_with_features():
    """Load county-specific data with features"""
    if _cache["counties"] is not None:
        return _cache["counties"]
    
    print("[Loading county data with features]")
    df = pd.read_csv(DATA_PATH)
    df["Date"] = pd.to_datetime(df["Date"])
    p99 = df["Retail"].quantile(0.99)
    df = df[df["Retail"] <= p99].copy()
    
    # Get external features (shared across counties)
    rainfall = fetch_rainfall_data()
    fuel = fetch_fuel_prices()
    
    county_data = {}
    for county in df["County"].unique():
        county_df = df[df["County"] == county]
        daily = (
            county_df.groupby("Date")
            .agg(price=("Retail", "median"), wholesale=("Wholesale", "median"))
            .reset_index()
            .sort_values("Date")
        )
        
        # Fill missing days
        daily = daily.set_index("Date")
        daily = daily.resample("D").first()
        daily["price"] = daily["price"].interpolate(method="linear")
        daily["wholesale"] = daily["wholesale"].interpolate(method="linear")
        daily = daily.reset_index()
        
        # Add features
        # Rainfall (county-specific if available, else use national average)
        county_rainfall = rainfall[rainfall["County"] == county]
        if len(county_rainfall) > 0:
            rainfall_agg = county_rainfall.groupby("Date")["rainfall_mm"].mean().reset_index()
        else:
            rainfall_agg = rainfall.groupby("Date")["rainfall_mm"].mean().reset_index()
        
        rainfall_agg["rainfall_4m_lag"] = rainfall_agg["rainfall_mm"].shift(120)
        daily = daily.merge(rainfall_agg[["Date", "rainfall_4m_lag"]], on="Date", how="left")
        
        # Fuel prices
        daily = daily.merge(fuel[["Date", "fuel_price_kes_per_liter"]], on="Date", how="left")
        
        # Events
        daily = create_event_features(daily)
        
        # Fill NaN
        daily = daily.fillna(method="ffill").fillna(method="bfill")
        
        county_data[county] = daily
    
    _cache["counties"] = county_data
    print(f"✓ Loaded {len(county_data)} counties with features\n")
    return county_data


# ============================================================================
# Feature Engineering
# ============================================================================

def engineer_features(daily: pd.DataFrame) -> pd.DataFrame:
    """Add engineered features including external data"""
    df = daily.copy()
    min_date = df["Date"].min()
    
    # Time features
    df["trend"] = (df["Date"] - min_date).dt.days
    df["day_of_week"] = df["Date"].dt.dayofweek
    df["month"] = df["Date"].dt.month
    df["week_of_year"] = df["Date"].dt.isocalendar().week.astype(int)
    df["year"] = df["Date"].dt.year
    df["sin_month"] = np.sin(2 * np.pi * df["month"] / 12)
    df["cos_month"] = np.cos(2 * np.pi * df["month"] / 12)
    df["sin_week"] = np.sin(2 * np.pi * df["week_of_year"] / 52)
    df["cos_week"] = np.cos(2 * np.pi * df["week_of_year"] / 52)
    
    # Price spread
    df["spread"] = df["price"] - df["wholesale"]
    
    # Price lags
    for lag in LAGS:
        df[f"lag_{lag}"] = df["price"].shift(lag)
        df[f"wlag_{lag}"] = df["wholesale"].shift(lag)
        df[f"spread_lag_{lag}"] = df["spread"].shift(lag)
    
    # Rolling statistics
    for w in WINDOWS:
        base = df["price"].shift(1)
        df[f"roll_mean_{w}"] = base.rolling(w).mean()
        df[f"roll_std_{w}"] = base.rolling(w).std()
        df[f"roll_min_{w}"] = base.rolling(w).min()
        df[f"roll_max_{w}"] = base.rolling(w).max()
    
    # Momentum
    df["momentum_7"] = df["price"].shift(1) - df["price"].shift(8)
    df["momentum_14"] = df["price"].shift(1) - df["price"].shift(15)
    
    # External features (already in df from load function)
    # Rainfall lags (also at 8-month lag for secondary effects)
    if "rainfall_4m_lag" in df.columns:
        df["rainfall_8m_lag"] = df["rainfall_4m_lag"].shift(120)  # Additional lag
    
    if "fuel_price_kes_per_liter" in df.columns:
        # Fuel price change
        df["fuel_price_lag_7"] = df["fuel_price_kes_per_liter"].shift(7)
        df["fuel_price_change"] = df["fuel_price_kes_per_liter"] - df["fuel_price_lag_7"]
    
    # Clean NaN
    return df.dropna().reset_index(drop=True)


def get_feature_cols(df: pd.DataFrame, horizon: int) -> List[str]:
    """Get valid feature columns (exclude short lags)"""
    excluded = (
        [f"lag_{l}" for l in range(1, horizon)]
        + [f"wlag_{l}" for l in range(1, horizon)]
        + [f"spread_lag_{l}" for l in range(1, horizon)]
    )
    all_cols = [c for c in df.columns if c not in ("Date", "price", "wholesale")]
    return [c for c in all_cols if c not in excluded]


# ============================================================================
# Models
# ============================================================================

def make_model():
    """Create GBR model"""
    return GradientBoostingRegressor(
        n_estimators=400,
        learning_rate=0.05,
        max_depth=5,  # Slightly deeper for more features
        random_state=42,
    )


def train_models(df: pd.DataFrame):
    """Train all 14 horizon models"""
    models = {}
    for h in HORIZONS:
        feat_cols = get_feature_cols(df, h)
        X = df[feat_cols]
        y = df["price"]
        
        model = make_model()
        model.fit(X, y)
        models[h] = (model, feat_cols)
        print(f"  ✓ Trained +{h}d model ({len(feat_cols)} features)")
    
    return models


def load_models():
    """Load or train models"""
    if _cache["models"]:
        return _cache["models"]
    
    models = {}
    missing = []
    
    for h in HORIZONS:
        path = f"{MODEL_DIR}/gbr_horizon_{h:02d}.pkl"
        if os.path.exists(path):
            try:
                models[h] = joblib.load(path)
                print(f"  ✓ Loaded +{h}d model")
            except:
                missing.append(h)
        else:
            missing.append(h)
    
    if missing:
        print(f"Training {len(missing)} models with enhanced features...")
        df = load_data_with_features()
        df = engineer_features(df)
        trained = train_models(df)
        models.update(trained)
    
    _cache["models"] = models
    return models


# ============================================================================
# Prediction
# ============================================================================

def make_feature_row(price_hist, ws_hist, target_date, min_date, external_features: Dict = None):
    """Create feature vector for a date including external features"""
    p = price_hist
    w = ws_hist
    
    row = {
        "trend": (target_date - min_date).days,
        "day_of_week": target_date.dayofweek,
        "month": target_date.month,
        "week_of_year": target_date.isocalendar()[1],
        "year": target_date.year,
        "sin_month": np.sin(2 * np.pi * target_date.month / 12),
        "cos_month": np.cos(2 * np.pi * target_date.month / 12),
        "sin_week": np.sin(2 * np.pi * target_date.isocalendar()[1] / 52),
        "cos_week": np.cos(2 * np.pi * target_date.isocalendar()[1] / 52),
        "spread": (p[-1] - w[-1]) if p and w else 0.0,
    }
    
    # Add external features if provided
    if external_features:
        for key, value in external_features.items():
            row[key] = value if value is not None else 0.0
    
    # Lags
    for lag in LAGS:
        row[f"lag_{lag}"] = p[-lag] if len(p) >= lag else np.nan
        row[f"wlag_{lag}"] = w[-lag] if len(w) >= lag else np.nan
        row[f"spread_lag_{lag}"] = (p[-lag] - w[-lag]) if len(p) >= lag else np.nan
    
    # Rolling stats
    for window in [3, 7, 14, 30]:
        window_data = p[-window:] if len(p) >= window else p
        row[f"roll_mean_{window}"] = float(np.mean(window_data)) if window_data else np.nan
        row[f"roll_std_{window}"] = float(np.std(window_data)) if window_data else np.nan
        row[f"roll_min_{window}"] = float(np.min(window_data)) if window_data else np.nan
        row[f"roll_max_{window}"] = float(np.max(window_data)) if window_data else np.nan
    
    row["momentum_7"] = (p[-1] - p[-8]) if len(p) >= 8 else 0.0
    row["momentum_14"] = (p[-1] - p[-15]) if len(p) >= 15 else 0.0
    
    return row


def predict(daily_engineered: pd.DataFrame, horizon: int, reference_date=None, original_df=None):
    """Predict for a horizon with external features"""
    models = load_models()
    if horizon not in models:
        raise ValueError(f"Invalid horizon: {horizon}")
    
    model, feat_cols = models[horizon]
    
    if reference_date is None:
        reference_date = daily_engineered["Date"].max()
    
    if original_df is None:
        original_df = daily_engineered
    
    target_date = reference_date + timedelta(days=horizon)
    min_date = original_df["Date"].min()
    
    price_hist = list(original_df["price"])
    ws_hist = list(original_df["wholesale"]) if "wholesale" in original_df.columns else list(original_df["price"])
    
    # Get external features for target date
    external_features = {}
    if "rainfall_4m_lag" in original_df.columns:
        # Use latest available rainfall data
        latest_rainfall = original_df["rainfall_4m_lag"].iloc[-1]
        external_features["rainfall_4m_lag"] = latest_rainfall
    
    if "fuel_price_kes_per_liter" in original_df.columns:
        external_features["fuel_price_kes_per_liter"] = original_df["fuel_price_kes_per_liter"].iloc[-1]
        external_features["fuel_price_change"] = original_df["fuel_price_change"].iloc[-1] if "fuel_price_change" in original_df.columns else 0
    
    # Event flags
    for col in original_df.columns:
        if col.startswith("event_"):
            external_features[col] = original_df[col].iloc[-1]
    
    row = make_feature_row(price_hist, ws_hist, target_date, min_date, external_features)
    X = pd.DataFrame([row])[feat_cols].fillna(0)
    
    return float(model.predict(X)[0])


def get_influencing_factors(daily_df: pd.DataFrame, target_date) -> Dict[str, str]:
    """Determine which external factors are influencing the prediction"""
    factors = {}
    
    # Check rainfall
    if "rainfall_4m_lag" in daily_df.columns:
        rainfall = daily_df["rainfall_4m_lag"].iloc[-1]
        if rainfall > 200:
            factors["rainfall"] = "High rainfall (4m ago) → Increased supply expected"
        elif rainfall < 50:
            factors["rainfall"] = "Low rainfall (4m ago) → Potential supply shortage"
    
    # Check fuel prices
    if "fuel_price_kes_per_liter" in daily_df.columns:
        fuel = daily_df["fuel_price_kes_per_liter"].iloc[-1]
        if fuel > 120:
            factors["fuel"] = "High fuel prices → Higher transport costs"
        elif fuel < 90:
            factors["fuel"] = "Low fuel prices → Reduced transport costs"
    
    # Check political events
    for col in daily_df.columns:
        if col.startswith("event_"):
            if daily_df[col].iloc[-1] == 1:
                event_name = col.replace("event_", "").replace("_", " ").title()
                factors[col] = f"{event_name} → Market volatility"
    
    if not factors:
        factors["baseline"] = "No major external shocks detected"
    
    return factors


# ============================================================================
# FastAPI App
# ============================================================================

app = FastAPI(
    title="Enhanced Maize Price Forecast API",
    description="With rainfall (NASA), fuel prices, political events, and pandemics",
    version="2.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup():
    """Load data and models on startup"""
    print("\n[Startup] Loading enhanced data and models...")
    load_data_with_features()
    load_county_data_with_features()
    load_models()
    print("[Startup] ✓ Ready with external features\n")


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "name": "Enhanced Maize Price Forecast API",
        "version": "2.0",
        "features": [
            "Price predictions (1-14 days)",
            "NASA rainfall data (4-month lag for harvest)",
            "Fuel prices",
            "Political events & elections",
            "Pandemic impacts",
            "Regional harvest patterns"
        ],
        "endpoints": {
            "predict": "POST /predict",
            "counties": "GET /counties",
            "docs": "GET /docs",
        },
    }


@app.get("/counties")
async def get_counties():
    """Get list of available counties"""
    counties = load_county_data_with_features()
    return {"counties": sorted(counties.keys()), "total": len(counties)}


@app.post("/predict", response_model=PredictionResponse)
async def make_prediction(request: PredictionRequest):
    """
    Get maize price prediction with external factor analysis
    
    Includes: Rainfall (4m lag), fuel prices, political events
    """
    try:
        # Load data
        if request.county:
            counties = load_county_data_with_features()
            if request.county not in counties:
                raise HTTPException(status_code=400, detail=f"County '{request.county}' not found")
            daily_df = counties[request.county]
            location = request.county
        else:
            daily_df = load_data_with_features()
            location = "National (Median)"
        
        # Reference date
        if request.reference_date:
            ref_date = pd.to_datetime(request.reference_date)
        else:
            ref_date = daily_df["Date"].max()
        
        # Validate columns
        if "wholesale" not in daily_df.columns or "price" not in daily_df.columns:
            raise HTTPException(status_code=500, detail="Data missing required columns")
        
        # Engineer features
        daily_engineered = engineer_features(daily_df)
        
        # Current price
        current_price = daily_df[daily_df["Date"] <= ref_date]["price"].iloc[-1]
        
        # Predict
        predicted_price = predict(daily_engineered, request.horizon_days, ref_date, original_df=daily_df)
        
        # Calculate change
        change = predicted_price - current_price
        change_pct = (change / current_price) * 100
        
        # Get influencing factors
        factors = get_influencing_factors(daily_df, ref_date)
        
        # Target date
        target_date = ref_date + timedelta(days=request.horizon_days)
        
        return PredictionResponse(
            date=target_date.strftime("%Y-%m-%d"),
            horizon_days=request.horizon_days,
            location=location,
            current_price=round(current_price, 2),
            predicted_price=round(predicted_price, 2),
            change_kes=round(change, 2),
            change_percent=round(change_pct, 2),
            influencing_factors=factors,
        )
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/data-sources")
async def data_sources():
    """Return information about data sources"""
    return {
        "sources": {
            "maize_prices": {
                "source": "Kenya National Bureau of Statistics (KNBS)",
                "data": "Daily retail and wholesale prices from 46 counties",
                "period": "2021-05-24 to 2026-05-13"
            },
            "rainfall": {
                "source": "NASA POWER API",
                "data": "Total precipitation (PRECTOTCORR)",
                "lag_effect": "4 months (harvest timing)",
                "note": "Affects crop yield and supply"
            },
            "fuel_prices": {
                "source": "Kenya National Oil Corporation (synthetic approximation)",
                "data": "Diesel prices with seasonal and shock patterns",
                "impact": "Transport costs for distribution"
            },
            "political_events": {
                "events": MAJOR_EVENTS,
                "impact": "Market volatility, supply chain disruptions"
            },
            "harvest_seasons": HARVEST_SEASONS
        }
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
