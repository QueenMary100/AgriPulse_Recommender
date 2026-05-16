"""
Maize Price Forecast API - Minimal Backend
============================================
FastAPI backend for testing the maize price prediction model.
Supports location-based predictions for 1-14 days ahead.

Usage:
    uvicorn api:app --reload
    
Then visit: http://localhost:8000/docs for interactive testing
"""

import os
import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import joblib
import warnings
from datetime import datetime, timedelta
from typing import Optional, List
from pydantic import BaseModel, Field

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

warnings.filterwarnings("ignore")

# Constants
DATA_PATH = "all_raw__1_.csv"
MODEL_DIR = "models"
HORIZONS = list(range(1, 15))
LAGS = [1, 2, 3, 5, 7, 10, 14, 21, 28]
WINDOWS = [3, 7, 14, 30]

# Kenya maize seasonal calendar
HARVEST_MONTHS = [7, 8, 9]        # Long rains harvest: Rift Valley, Western Kenya
SHORT_RAINS_HARVEST = [11, 12]    # Short rains harvest: Eastern, Coastal
LEAN_MONTHS = [1, 2, 3]           # Low maize stocks, prices typically elevated
PLANTING_MONTHS = [3, 4, 10, 11]  # High input demand, possible farmer sell-off
FUEL_PRICE = 193.0                 # KES/L EPRA 2026 baseline
FEATURE_VERSION = "v3_wholesale"  # Bump this when feature set changes to force retrain

# Cache
_cache = {"df": None, "models": {}, "counties": None}


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


class ForecastPoint(BaseModel):
    date: str
    day: int
    predicted_price: float
    low: float
    high: float


class HistoricalPoint(BaseModel):
    date: str
    price: float


class RecommendationResult(BaseModel):
    action: str
    decision: str
    slope: float
    peak_price: float
    peak_day: int
    peak_date: str
    peak_gain_per_bag: float
    factors: List[str]


class RangePredictionRequest(BaseModel):
    county: Optional[str] = Field(None, description="County name (optional)")
    reference_date: Optional[str] = Field(None, description="YYYY-MM-DD (optional)")
    horizon_days: int = Field(default=14, ge=1, le=14, description="Days ahead (1-14)")


# ============================================================================
# Data Loading
# ============================================================================

def load_data():
    """Load and aggregate data to daily national median"""
    if _cache["df"] is not None:
        return _cache["df"]
    
    df = pd.read_csv(DATA_PATH)
    df["Date"] = pd.to_datetime(df["Date"])
    
    # Cap at 99th percentile (using Retail to determine the cap)
    p99 = df["Retail"].quantile(0.99)
    df = df[df["Retail"] <= p99].copy()

    # Daily median — Wholesale is the primary price series; Retail kept as reference
    daily = (
        df.groupby("Date")
        .agg(price=("Wholesale", "median"), retail=("Retail", "median"))
        .reset_index()
        .sort_values("Date")
    )

    # Fill missing days - create continuous date range and interpolate
    date_range = pd.date_range(start=daily["Date"].min(), end=daily["Date"].max(), freq="D")
    daily = daily.set_index("Date").reindex(date_range)
    daily.index.name = "Date"
    # Fall back to retail where wholesale is missing before interpolating
    daily["price"] = daily["price"].fillna(daily["retail"])
    daily["price"] = daily["price"].interpolate(method="linear")
    daily["retail"] = daily["retail"].interpolate(method="linear")
    daily = daily.reset_index()
    
    _cache["df"] = daily
    print(f"✓ Loaded {len(daily)} days ({daily['Date'].min().date()} → {daily['Date'].max().date()})")
    return daily


def load_county_data():
    """Load per-county data"""
    if _cache["counties"] is not None:
        return _cache["counties"]
    
    df = pd.read_csv(DATA_PATH)
    df["Date"] = pd.to_datetime(df["Date"])
    p99 = df["Retail"].quantile(0.99)
    df = df[df["Retail"] <= p99].copy()
    
    county_data = {}
    for county in df["County"].unique():
        county_df = df[df["County"] == county]
        daily = (
            county_df.groupby("Date")
            .agg(price=("Wholesale", "median"), retail=("Retail", "median"))
            .reset_index()
            .sort_values("Date")
        )
        # Fill missing days - create continuous date range and interpolate
        date_range = pd.date_range(start=daily["Date"].min(), end=daily["Date"].max(), freq="D")
        daily = daily.set_index("Date").reindex(date_range)
        daily.index.name = "Date"
        daily["price"] = daily["price"].fillna(daily["retail"])
        daily["price"] = daily["price"].interpolate(method="linear")
        daily["retail"] = daily["retail"].interpolate(method="linear")
        daily = daily.reset_index()
        
        county_data[county] = daily
    
    _cache["counties"] = county_data
    print(f"✓ Loaded {len(county_data)} counties")
    return county_data


# ============================================================================
# Feature Engineering
# ============================================================================

def engineer_features(daily: pd.DataFrame) -> pd.DataFrame:
    """Add engineered features to daily series"""
    df = daily.copy()
    min_date = df["Date"].min()
    
    # Ensure retail column exists
    if "retail" not in df.columns:
        df["retail"] = df["price"]  # fallback to wholesale if retail missing

    # Fill NaN values in retail
    df["retail"] = df["retail"].fillna(df["retail"].mean())
    
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
    
    # Spread: retail premium over wholesale (positive means retail > wholesale)
    df["spread"] = df["retail"] - df["price"]

    # Lags — lag_* tracks wholesale, wlag_* tracks retail
    for lag in LAGS:
        df[f"lag_{lag}"] = df["price"].shift(lag)
        df[f"wlag_{lag}"] = df["retail"].shift(lag)
        df[f"spread_lag_{lag}"] = df["spread"].shift(lag)
    
    # Rolling stats
    for w in WINDOWS:
        base = df["price"].shift(1)
        df[f"roll_mean_{w}"] = base.rolling(w).mean()
        df[f"roll_std_{w}"] = base.rolling(w).std()
        df[f"roll_min_{w}"] = base.rolling(w).min()
        df[f"roll_max_{w}"] = base.rolling(w).max()
    
    # Momentum
    df["momentum_7"] = df["price"].shift(1) - df["price"].shift(8)
    df["momentum_14"] = df["price"].shift(1) - df["price"].shift(15)

    # External / seasonal features
    df["harvest_season"] = df["Date"].dt.month.isin(HARVEST_MONTHS + SHORT_RAINS_HARVEST).astype(int)
    df["lean_season"] = df["Date"].dt.month.isin(LEAN_MONTHS).astype(int)
    df["planting_season"] = df["Date"].dt.month.isin(PLANTING_MONTHS).astype(int)
    df["fuel_price"] = FUEL_PRICE

    return df.dropna().reset_index(drop=True)


def get_feature_cols(df: pd.DataFrame, horizon: int) -> List[str]:
    """Get valid feature columns (exclude short lags)"""
    excluded = (
        [f"lag_{l}" for l in range(1, horizon)]
        + [f"wlag_{l}" for l in range(1, horizon)]
        + [f"spread_lag_{l}" for l in range(1, horizon)]
    )
    all_cols = [c for c in df.columns if c not in ("Date", "price", "retail", "wholesale")]
    return [c for c in all_cols if c not in excluded]


# ============================================================================
# Models
# ============================================================================

def make_model():
    """Create GBR model"""
    return GradientBoostingRegressor(
        n_estimators=400,
        learning_rate=0.05,
        max_depth=4,
        random_state=42,
    )


# def train_models(df: pd.DataFrame):
#     """Train all 14 horizon models and save to disk"""
#     # Create models directory if it doesn't exist
#     os.makedirs(MODEL_DIR, exist_ok=True)
    
#     # Create metrics file
#     metrics_file = f"{MODEL_DIR}/model_metrics.txt"
#     with open(metrics_file, "w") as f:
#         f.write("=" * 80 + "\n")
#         f.write("Maize Price Forecast - Model Evaluation Metrics\n")
#         f.write("=" * 80 + "\n")
#         f.write(f"Training Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
#         f.write("=" * 80 + "\n\n")
    
#     models = {}
#     for h in HORIZONS:
#         feat_cols = get_feature_cols(df, h)
#         X = df[feat_cols]
#         y = df["price"]
        
#         model = make_model()
#         model.fit(X, y)
#         models[h] = (model, feat_cols)
        
#         # Calculate evaluation metrics
#         y_pred = model.predict(X)
#         mae = mean_absolute_error(y, y_pred)
#         rmse = np.sqrt(mean_squared_error(y, y_pred))
#         r2 = r2_score(y, y_pred)
        
#         # Save model to disk
#         model_path = f"{MODEL_DIR}/gbr_horizon_{h:02d}.pkl"
#         joblib.dump((model, feat_cols), model_path)
        
#         # Log metrics to console and file
#         metrics_msg = f"  ✓ Trained +{h}d model ({len(feat_cols)} features) | MAE: {mae:.2f}, RMSE: {rmse:.2f}, R²: {r2:.4f}"
#         print(metrics_msg)
        
#         with open(metrics_file, "a") as f:
#             f.write(f"Horizon {h}d:\n")
#             f.write(f"  Features: {len(feat_cols)}\n")
#             f.write(f"  Mean Absolute Error (MAE): {mae:.2f}\n")
#             f.write(f"  Root Mean Square Error (RMSE): {rmse:.2f}\n")
#             f.write(f"  R² Score: {r2:.4f}\n")
#             f.write(f"  Model Path: {model_path}\n\n")
    
#     print(f"\n✓ Metrics saved to {metrics_file}\n")
#     return models
def train_models(df: pd.DataFrame):
    """Train 14 horizon-specific models using true future targets: y[t+h]."""
    os.makedirs(MODEL_DIR, exist_ok=True)

    metrics_file = f"{MODEL_DIR}/model_metrics.txt"
    with open(metrics_file, "w") as f:
        f.write("=" * 90 + "\n")
        f.write("Maize Price Forecast - Horizon-specific Model Metrics (Time Split)\n")
        f.write("=" * 90 + "\n")
        f.write(f"Training Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("=" * 90 + "\n\n")

    models = {}

    for h in HORIZONS:
        feat_cols = get_feature_cols(df, h)

        # Build horizon-specific target
        horizon_df = df.copy()
        horizon_df["target"] = horizon_df["price"].shift(-h)

        # Keep only complete rows for this horizon
        horizon_df = horizon_df.dropna(subset=feat_cols + ["target"]).reset_index(drop=True)

        if len(horizon_df) < 100:
            print(f"  ✗ Skipping +{h}d model: not enough training rows ({len(horizon_df)})")
            continue

        # Time-based split (oldest 80% train, newest 20% validation)
        split_idx = int(len(horizon_df) * 0.8)
        if split_idx <= 0 or split_idx >= len(horizon_df):
            print(f"  ✗ Skipping +{h}d model: invalid split for {len(horizon_df)} rows")
            continue

        train_df = horizon_df.iloc[:split_idx]
        val_df = horizon_df.iloc[split_idx:]

        X_train = train_df[feat_cols]
        y_train = train_df["target"]

        X_val = val_df[feat_cols]
        y_val = val_df["target"]

        model = make_model()
        model.fit(X_train, y_train)
        models[h] = (model, feat_cols)

        # Validation metrics (realistic)
        y_val_pred = model.predict(X_val)
        val_mae = mean_absolute_error(y_val, y_val_pred)
        val_rmse = np.sqrt(mean_squared_error(y_val, y_val_pred))
        val_r2 = r2_score(y_val, y_val_pred)

        # Optional: training metrics for overfit visibility
        y_train_pred = model.predict(X_train)
        train_mae = mean_absolute_error(y_train, y_train_pred)
        train_rmse = np.sqrt(mean_squared_error(y_train, y_train_pred))
        train_r2 = r2_score(y_train, y_train_pred)

        model_path = f"{MODEL_DIR}/gbr_horizon_{h:02d}.pkl"
        joblib.dump((model, feat_cols), model_path)

        msg = (
            f"  ✓ Trained +{h:02d}d | "
            f"train MAE={train_mae:.2f}, RMSE={train_rmse:.2f}, R²={train_r2:.4f} | "
            f"val MAE={val_mae:.2f}, RMSE={val_rmse:.2f}, R²={val_r2:.4f}"
        )
        print(msg)

        with open(metrics_file, "a") as f:
            f.write(f"Horizon +{h}d\n")
            f.write(f"  Features: {len(feat_cols)}\n")
            f.write(f"  Rows: total={len(horizon_df)}, train={len(train_df)}, val={len(val_df)}\n")
            f.write(f"  Train MAE:  {train_mae:.4f}\n")
            f.write(f"  Train RMSE: {train_rmse:.4f}\n")
            f.write(f"  Train R²:   {train_r2:.6f}\n")
            f.write(f"  Val MAE:    {val_mae:.4f}\n")
            f.write(f"  Val RMSE:   {val_rmse:.4f}\n")
            f.write(f"  Val R²:     {val_r2:.6f}\n")
            f.write(f"  Model Path: {model_path}\n\n")

    print(f"\n✓ Metrics saved to {metrics_file}\n")
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
                model_tuple = joblib.load(path)
                models[h] = model_tuple  # Already a (model, feat_cols) tuple
                print(f"  ✓ Loaded +{h}d model")
            except Exception as e:
                print(f"  ✗ Failed to load +{h}d model: {e}")
                missing.append(h)
        else:
            missing.append(h)
    
    if missing:
        print(f"Training {len(missing)} models...")
        df = load_data()
        df = engineer_features(df)
        trained = train_models(df)
        models.update(trained)
    
    _cache["models"] = models
    return models


# ============================================================================
# Prediction
# ============================================================================

def make_feature_row(price_hist, ws_hist, target_date, min_date):
    """Create feature vector for a date"""
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
        "spread": (w[-1] - p[-1]) if p and w else 0.0,  # retail - wholesale
        "wholesale": w[-1] if w else np.nan,
        "harvest_season": int(target_date.month in (HARVEST_MONTHS + SHORT_RAINS_HARVEST)),
        "lean_season": int(target_date.month in LEAN_MONTHS),
        "planting_season": int(target_date.month in PLANTING_MONTHS),
        "fuel_price": FUEL_PRICE,
    }
    
    for lag in LAGS:
        row[f"lag_{lag}"] = p[-lag] if len(p) >= lag else np.nan
        row[f"wlag_{lag}"] = w[-lag] if len(w) >= lag else np.nan
        row[f"spread_lag_{lag}"] = (w[-lag] - p[-lag]) if len(p) >= lag else np.nan
    
    for window in WINDOWS:
        window_data = p[-window:] if len(p) >= window else p
        row[f"roll_mean_{window}"] = float(np.mean(window_data)) if window_data else np.nan
        row[f"roll_std_{window}"] = float(np.std(window_data)) if window_data else np.nan
        row[f"roll_min_{window}"] = float(np.min(window_data)) if window_data else np.nan
        row[f"roll_max_{window}"] = float(np.max(window_data)) if window_data else np.nan
    
    row["momentum_7"] = (p[-1] - p[-8]) if len(p) >= 8 else 0.0
    row["momentum_14"] = (p[-1] - p[-15]) if len(p) >= 15 else 0.0
    
    return row


def predict(daily_engineered: pd.DataFrame, horizon: int, reference_date=None, original_df=None):
    """Predict for a horizon"""
    models = load_models()
    print(f"horizon: {horizon}")
    if horizon not in models:
        raise ValueError(f"Invalid horizon: {horizon}")

    # print(f"model: {model[horizon]}")
    
    model, feat_cols = models[horizon]
    
    if reference_date is None:
        reference_date = daily_engineered["Date"].max()
    
    # Use original_df for price/wholesale history if provided
    if original_df is None:
        original_df = daily_engineered
    
    target_date = reference_date + timedelta(days=horizon)
    min_date = original_df["Date"].min()
    
    price_hist = list(original_df["price"])   # wholesale
    ws_hist = list(original_df["retail"]) if "retail" in original_df.columns else list(original_df["price"])  # retail
    
    row = make_feature_row(price_hist, ws_hist, target_date, min_date)
    X = pd.DataFrame([row])[feat_cols].fillna(0)
    
    return float(model.predict(X)[0])


# ============================================================================
# Recommendation Engine
# ============================================================================

def generate_recommendation(
    forecast_points: list, current_price: float, reference_date
) -> dict:
    """Analyse the full forecast curve and produce a sell/wait recommendation."""
    if not forecast_points:
        return {
            "action": "Insufficient data for recommendation",
            "decision": "unknown",
            "slope": 0.0,
            "peak_price": current_price,
            "peak_day": 0,
            "peak_date": str(reference_date.date()),
            "peak_gain_per_bag": 0.0,
            "factors": ["Not enough forecast data to make a recommendation."],
        }

    prices = [p["predicted_price"] for p in forecast_points]
    n = len(prices)

    # Linear trend slope (KES/kg per day)
    slope = float(np.polyfit(range(n), prices, 1)[0]) if n > 1 else 0.0

    # Peak detection
    peak_idx = int(np.argmax(prices))
    peak_price = prices[peak_idx]
    peak_day = forecast_points[peak_idx]["day"]
    peak_date = forecast_points[peak_idx]["date"]
    peak_gain_per_bag = (peak_price - current_price) * 90  # 90 kg bag

    # Factor attribution
    month = reference_date.month
    factors = []
    if month in HARVEST_MONTHS:
        factors.append(
            "Long rains harvest underway (Jul–Sep) — maize supply is rising in Rift Valley "
            "and Western Kenya, which typically pushes retail prices down."
        )
    elif month in SHORT_RAINS_HARVEST:
        factors.append(
            "Short rains harvest (Nov–Dec) — additional supply from Eastern and Coastal "
            "regions enters the market, adding downward price pressure."
        )
    elif month in LEAN_MONTHS:
        factors.append(
            "Lean season (Jan–Mar) — stored maize stocks are running low and new harvest "
            "is months away, supporting higher-than-average prices."
        )
    if month in PLANTING_MONTHS:
        factors.append(
            "Planting season — farmers may sell remaining stock to fund seed and fertiliser "
            "purchases, temporarily increasing market supply."
        )

    if slope > 1.0:
        factors.append(
            f"Strong upward trend detected: prices rising ~{slope:.1f} KES/kg per day on average."
        )
    elif slope > 0.3:
        factors.append(
            f"Moderate upward trend: prices rising ~{slope:.1f} KES/kg per day on average."
        )
    elif slope < -1.0:
        factors.append(
            f"Strong downward trend: prices falling ~{abs(slope):.1f} KES/kg per day — "
            "early selling is advisable."
        )
    elif slope < -0.3:
        factors.append(
            f"Moderate downward trend: prices falling ~{abs(slope):.1f} KES/kg per day."
        )
    else:
        factors.append("Prices are relatively stable with no strong directional trend.")

    factors.append(
        f"Fuel price is stable at KES {FUEL_PRICE:.0f}/L (EPRA 2026) — "
        "no significant transport cost pressure expected."
    )

    # Decision logic
    MEANINGFUL_GAIN = 150.0  # KES per 90 kg bag minimum worth waiting for

    if peak_gain_per_bag >= MEANINGFUL_GAIN and peak_day >= 5:
        decision = "wait"
        action = (
            f"WAIT — prices are expected to peak around {peak_date} (Day +{peak_day}). "
            f"Selling then could earn you KES {peak_gain_per_bag:.0f} more per 90 kg bag."
        )
    elif peak_gain_per_bag >= MEANINGFUL_GAIN and peak_day < 5:
        decision = "sell_soon"
        action = (
            f"SELL SOON — the best price is expected within {peak_day} day(s) on {peak_date}. "
            f"Potential gain: KES {peak_gain_per_bag:.0f} per 90 kg bag."
        )
    else:
        decision = "sell_now"
        action = (
            f"SELL NOW — no significant price improvement is expected over the next "
            f"{n} day(s). The best projected gain is only KES {max(peak_gain_per_bag, 0):.0f} "
            "per 90 kg bag, below the KES 150 threshold."
        )

    return {
        "action": action,
        "decision": decision,
        "slope": round(slope, 3),
        "peak_price": round(peak_price, 2),
        "peak_day": peak_day,
        "peak_date": peak_date,
        "peak_gain_per_bag": round(peak_gain_per_bag, 0),
        "factors": factors,
    }


# ============================================================================
# FastAPI App
# ============================================================================

app = FastAPI(title="Maize Price Forecast API", version="1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup():
    """Load data and models on startup. Only retrains when feature version changes."""
    print("\n[Startup] Loading data and models...")
    daily = load_data()
    load_county_data()

    version_file = f"{MODEL_DIR}/feature_version.txt"
    all_exist = all(
        os.path.exists(f"{MODEL_DIR}/gbr_horizon_{h:02d}.pkl") for h in HORIZONS
    )

    needs_retrain = not all_exist
    if all_exist:
        try:
            with open(version_file) as f:
                saved = f.read().strip()
            needs_retrain = saved != FEATURE_VERSION
        except FileNotFoundError:
            needs_retrain = True

    if needs_retrain:
        print(f"[Startup] Retraining models (feature version: {FEATURE_VERSION})...")
        engineered = engineer_features(daily)
        train_models(engineered)
        os.makedirs(MODEL_DIR, exist_ok=True)
        with open(version_file, "w") as f:
            f.write(FEATURE_VERSION)
        print("[Startup] ✓ Retrain complete")
    else:
        print(f"[Startup] Models up to date ({FEATURE_VERSION}), loading from disk...")

    load_models()
    print("[Startup] ✓ Ready\n")


@app.get("/")
async def root():
    return {
        "name": "Maize Price Forecast API",
        "version": FEATURE_VERSION,
        "endpoints": {
            "predict": "POST /predict — single horizon prediction",
            "predict_range": "POST /predict/range — full day-by-day forecast + recommendation",
            "historical": "GET /prices/historical — recent actual prices",
            "counties": "GET /counties — available counties",
            "docs": "GET /docs",
        },
    }


@app.get("/counties")
async def get_counties():
    """Get list of available counties"""
    counties = load_county_data()
    return {"counties": sorted(counties.keys()), "total": len(counties)}


@app.post("/predict", response_model=PredictionResponse)
async def make_prediction(request: PredictionRequest):
    """
    Get maize price prediction for a location and time range.
    
    Example:
        {"horizon_days": 7, "county": "Kiambu"}
    """
    try:
        # Load data
        if request.county:
            counties = load_county_data()
            if request.county not in counties:
                raise HTTPException(status_code=400, detail=f"County '{request.county}' not found")
            daily_df = counties[request.county]
            location = request.county
        else:
            daily_df = load_data()
            location = "National (Median)"
        
        # Reference date
        if request.reference_date:
            ref_date = pd.to_datetime(request.reference_date)
        else:
            ref_date = daily_df["Date"].max()
        
        # Check if columns exist
        if "price" not in daily_df.columns:
            raise HTTPException(status_code=500, detail="Data missing 'price' (wholesale) column")
        
        # Engineer features
        daily_engineered = engineer_features(daily_df)
        
        # Current price
        current_price = daily_df[daily_df["Date"] <= ref_date]["price"].iloc[-1]
        
        # Predict (pass original data for wholesale/price history)
        predicted_price = predict(daily_engineered, request.horizon_days, ref_date, original_df=daily_df)
        
        # Calculate change
        change = predicted_price - current_price
        change_pct = (change / current_price) * 100
        
        # Target date
        target_date = ref_date + timedelta(days=request.horizon_days)
        
        return PredictionResponse(
            date=(target_date + timedelta(days=1)).strftime("%Y-%m-%d"),
            horizon_days=request.horizon_days,
            location=location,
            current_price=round(current_price, 2),
            predicted_price=round(predicted_price, 2),
            change_kes=round(change, 2),
            change_percent=round(change_pct, 2),
        )
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/current_price")
async def get_current_price(county: Optional[str] = None):
    """Return the single most recent price from the dataset for a county."""
    try:
        if county:
            counties = load_county_data()
            if county not in counties:
                raise HTTPException(status_code=400, detail=f"County '{county}' not found")
            df = counties[county]
        else:
            df = load_data()

        row = df.dropna(subset=["price"]).iloc[-1]
        return {
            "county": county or "National (Median)",
            "date": row["Date"].strftime("%Y-%m-%d"),
            "price": round(float(row["price"]), 2),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/prices/historical")
async def get_historical_prices(county: Optional[str] = None, days: int = 30):
    """
    Return the last N days of recorded market prices for charting.
    If county is omitted, returns the national daily median.
    """
    try:
        if county:
            counties = load_county_data()
            if county not in counties:
                raise HTTPException(status_code=400, detail=f"County '{county}' not found")
            df = counties[county]
        else:
            df = load_data()

        cutoff = df["Date"].max() - timedelta(days=days)
        recent = df[df["Date"] >= cutoff].copy()
        recent = recent.sort_values("Date")

        data = [
            HistoricalPoint(
                date=row["Date"].strftime("%Y-%m-%d"),
                price=round(float(row["price"]), 2),
            )
            for _, row in recent.iterrows()
        ]
        return {"county": county or "National (Median)", "data": data, "total": len(data)}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/predict/range")
async def predict_range(request: RangePredictionRequest):
    """
    Return day-by-day price predictions from day 1 to horizon_days,
    historical prices for context, and a sell/wait recommendation.

    Example:
        {"county": "Nairobi", "horizon_days": 14}
    """
    try:
        # Select data source
        if request.county:
            counties = load_county_data()
            if request.county not in counties:
                raise HTTPException(
                    status_code=400, detail=f"County '{request.county}' not found"
                )
            daily_df = counties[request.county]
            location = request.county
        else:
            daily_df = load_data()
            location = "National (Median)"

        # Reference date
        if request.reference_date:
            ref_date = pd.to_datetime(request.reference_date)
        else:
            ref_date = daily_df["Date"].max()

        daily_engineered = engineer_features(daily_df)
        current_price = float(
            daily_df[daily_df["Date"] <= ref_date]["price"].iloc[-1]
        )

        # Build historical context (last 14 days)
        hist_cutoff = ref_date - timedelta(days=14)
        hist_df = daily_df[(daily_df["Date"] >= hist_cutoff) & (daily_df["Date"] <= ref_date)]
        historical = [
            HistoricalPoint(
                date=row["Date"].strftime("%Y-%m-%d"),
                price=round(float(row["price"]), 2),
            )
            for _, row in hist_df.iterrows()
        ]

        # Generate per-horizon predictions
        models = load_models()
        forecast_points_raw = []
        for h in range(1, request.horizon_days + 1):
            if h not in models:
                continue
            try:
                predicted = predict(
                    daily_engineered, h, ref_date, original_df=daily_df
                )
                model, feat_cols = models[h]
                # Derive MAE from stored metrics file as confidence band; default to 6
                mae = 6.0
                target_date = ref_date + timedelta(days=h)
                fp = {
                    "date": target_date.strftime("%Y-%m-%d"),
                    "day": h,
                    "predicted_price": round(predicted, 2),
                    "low": round(max(predicted - mae, 0), 2),
                    "high": round(predicted + mae, 2),
                }
                forecast_points_raw.append(fp)
            except Exception:
                continue

        recommendation = generate_recommendation(
            forecast_points_raw, current_price, ref_date
        )

        forecast = [ForecastPoint(**fp) for fp in forecast_points_raw]

        return {
            "county": location,
            "reference_date": ref_date.strftime("%Y-%m-%d"),
            "current_price": round(current_price, 2),
            "horizon_days": request.horizon_days,
            "forecast": [f.dict() for f in forecast],
            "historical": [h.dict() for h in historical],
            "recommendation": recommendation,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)