import pandas as pd
from selenium import webdriver
from io import StringIO
from pathlib import Path
import datetime

end_date = datetime.datetime.now()
start_date = end_date - datetime.timedelta(days=5)

url = (
    "https://kamis.kilimo.go.ke/site/market_search?"
    f"product%5B%5D=1&start={start_date:%Y-%m-%d}&end={end_date:%Y-%m-%d}&per_page=3000"
)

driver = webdriver.Chrome()
driver.get(url)
driver.implicitly_wait(10)

html = driver.page_source
driver.quit()

# Key fix: wrap HTML string
tables = pd.read_html(StringIO(html))
df = tables[0]

# Safer output folder (relative to current script)
out_dir = Path(__file__).resolve().parent / "data"
out_dir.mkdir(parents=True, exist_ok=True)

csv_path = out_dir / "table_data.csv"
json_path = out_dir / "table_data.json"

df.to_csv(csv_path, index=False)
df.to_json(json_path, orient="records", indent=2)

print(f"Saved CSV:  {csv_path}")
print(f"Saved JSON: {json_path}")