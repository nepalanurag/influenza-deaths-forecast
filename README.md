# Influenza Deaths Forecast

Walkthrough with all plots: https://nepalanurag.github.io/influenza-deaths-forecast/

I modeled weekly influenza and pneumonia death counts from national surveillance data as a time series problem.

Note on reproducibility: the analysis reads `National_Custom_Data.csv` (weekly influenza/pneumonia death counts), which is not in this repo, so the Rmd cannot be re-run as-is. The file is a custom data download from CDC FluView's pneumonia, influenza, and COVID-19 mortality surveillance (NCHS), National region: open the FluView mortality surveillance page and use its Downloads tool to export the National-level custom dataset. The rendered PDF below is the archived output of the completed analysis.

I compared ARIMA models on the raw and cleaned series and ETS on the cleaned series, then built a hybrid ARIMA + GARCH(1,1) model for a 24-month forecast with 95% prediction intervals. The cleaning step mattered: comma-formatted counts and reporting artifacts had to be handled before any model would behave.

## Files

- `influenza-deaths-forecast.Rmd` - the analysis
- `influenza-deaths-forecast.pdf` - rendered version
- `data/fetch_fluview.R` - scripted data fetch: tries documented CDC endpoints, falls back to a schema-validated `National_Custom_Data.csv`, and writes the checksummed `data/fluview_snapshot.csv` that the analysis scripts read
- `analysis/rolling_origin_cv.R` - out-of-sample model comparison: expanding-window rolling-origin CV, 1- to 12-step-ahead errors, ETS / ARIMA / log-ARIMA / seasonal-naive
- `analysis/production_forecast.R` - the production forecast pipeline (below); regenerates `dashboard-data/forecast_24mo.csv`

## The production forecast pipeline

One pipeline generates `dashboard-data/forecast_24mo.csv`:

- **Mean:** log-ARIMA on the `tsclean`-cleaned series (`auto.arima(..., lambda = 0)`), the Rmd's chosen mean specification, bias-adjusted on back-transform.
- **Intervals:** GARCH(1,1) with Student-t errors fit on the log-ARIMA residuals; 95% bands from t-quantiles times the forecasted conditional volatility, back-transformed; lower bound clipped at 0 (percent of deaths cannot be negative).

Run it with:

```bash
Rscript data/fetch_fluview.R
Rscript analysis/production_forecast.R
Rscript analysis/rolling_origin_cv.R   # extended out-of-sample comparison
```

## Changelog

- 2026-10-05: added scripted data fetch, rolling-origin out-of-sample comparison, and the production forecast pipeline as the single generator of `dashboard-data/forecast_24mo.csv`. The Rmd walkthrough and its rendered PDF are unchanged.
