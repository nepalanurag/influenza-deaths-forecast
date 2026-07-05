# Dashboard data: Influenza Deaths Forecast

Results from `influenza-deaths-forecast.Rmd`. Values are transcribed from the
rendered PDF, the archived output of the completed analysis. Target: monthly US
pneumonia and influenza deaths as a percent of all deaths.

## Files

- `model_comparison.csv` — ARIMA bake-off on AICc, in-sample RMSE, and MAPE.
  Columns: `model`, `aicc`, `rmse`, `mape`. Note: the archived PDF fits four
  ARIMA variants (including ARIMA on raw data with log transform); the current
  Rmd source fits three (the raw+log variant was dropped in a later edit).
- `forecast_24mo.csv` — 24-month forecast from the chosen model (log-transformed
  ARIMA on the cleaned series), 2026-01 to 2027-12. Columns: `date` (month),
  `forecast` (percent of all deaths), `lower_95`, `upper_95` (95% interval).

Headline: the log-transformed ARIMA on the cleaned series won on all three
metrics (AICc -96.64, RMSE 1.0127, MAPE 8.3257). A hybrid ARIMA + GARCH(1,1)
extends it with volatility-aware intervals.
