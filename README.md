# Influenza Deaths Forecast

I forecast monthly influenza and pneumonia deaths from CDC surveillance data.

Walkthrough with all plots: https://nepalanurag.github.io/influenza-deaths-forecast/

## What this is

Weekly flu and pneumonia death counts are a classic seasonal time series: a winter peak, a summer trough, and some noisy reporting artifacts that will break any model that trusts the raw numbers. I took weekly data from CDC FluView's NCHS mortality surveillance, cleaned it up, and compared forecasting models for a 24-month production forecast with prediction intervals.

## The pipeline

1. `data/fetch_fluview.R` tries CDC's documented FluView endpoints first, then falls back to a manually placed `National_Custom_Data.csv` (their Downloads tool, National region). Either way the data lands as a checksummed `data/fluview_snapshot.csv`, so the scripts never read an unvalidated file.
2. Cleaning: strip comma formatting, convert flu seasons and MMWR weeks to calendar dates, aggregate weekly to monthly, and model the percent of all deaths (`Percent_PI`) rather than raw counts.
3. `influenza-deaths-forecast.Rmd` is the analysis itself: ARIMA on raw vs cleaned series, with and without a log transform, plus ETS on the cleaned series.
4. `analysis/rolling_origin_cv.R` is the out-of-sample answer: expanding-window rolling-origin cross-validation with 1 to 12 month ahead errors, ETS and ARIMA variants against a seasonal naive benchmark. Cleaning is re-applied inside each training window so there is no look-ahead.
5. `analysis/production_forecast.R` produces the actual forecast: log-ARIMA for the mean, and a GARCH(1,1) with Student-t errors fit on the residuals for the 95% intervals (t-quantiles, not 1.96). It writes `dashboard-data/forecast_24mo.csv`.

## Key results

From `dashboard-data/model_comparison.csv` (in-sample fit on the monthly series):

| Model | AICc | RMSE | MAPE |
|---|---|---|---|
| ARIMA (raw) | 363.24 | 1.42 | 9.93% |
| ARIMA (cleaned) | 291.47 | 1.09 | 9.72% |
| ARIMA (raw + log) | -72.83 | 1.33 | 9.04% |
| ARIMA (cleaned + log) | -96.64 | 1.01 | 8.33% |

Two things mattered: cleaning (comma-formatted counts and reporting artifacts were breaking the fit), and the log transform (it fits the series' growing variance much better). The cleaned + log ARIMA won on all three measures.

The production forecast (`dashboard-data/forecast_24mo.csv`) runs 24 months and keeps the seasonal shape: the next winter peak lands around January 2027 at 7.2% of all deaths, with a 95% interval of 3.7 to 12.6.

## How to run

You need R with the `forecast`, `rugarch`, `lubridate`, and `dplyr` packages.

```
Rscript data/fetch_fluview.R          # data/fluview_snapshot.csv (or place National_Custom_Data.csv next to the Rmd)
Rscript analysis/production_forecast.R # dashboard-data/forecast_24mo.csv
Rscript analysis/rolling_origin_cv.R   # analysis/rolling_origin_results.csv
```

Reproducibility note: the source CSV (`National_Custom_Data.csv`, weekly influenza/pneumonia deaths) is a custom CDC FluView download and is not in this repo. Without it, the Rmd cannot be re-run as-is; the rendered `influenza-deaths-forecast.pdf` is the archived output of the completed analysis.

## Methods in plain words

I treated this as a univariate forecasting problem: find a model that captures the yearly flu cycle and predicts next year's deaths. ARIMA handles the seasonal autocorrelation, ETS is a simpler exponential-smoothing alternative, and the GARCH part exists because flu seasons are not equally volatile year to year, so fixed-width intervals would be wrong. The log transform fixes the variance growing with the level, which is why every metric preferred it.
