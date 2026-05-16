import pandas as pd

kamis_url = "https://kilimo.go.ke"

try:
    print("Fetching KAMIS data stream...")

    # Read tables from webpage (not Excel)
    tables = pd.read_html(kamis_url)
    if not tables:
        raise ValueError("No tables found on KAMIS page.")

    df_raw = tables[0]

    # Filter maize rows safely
    if "Commodity" not in df_raw.columns:
        raise KeyError("Column 'Commodity' not found in source data.")

    df_maize = df_raw[
        df_raw["Commodity"].astype(str).str.contains("Maize", case=False, na=False)
    ]

    print(f"Successfully retrieved {len(df_maize)} maize price records!")
    print(df_maize.head())

except Exception as e:
    print(f"Connection failed: {e}. Check server status or page/table format.")