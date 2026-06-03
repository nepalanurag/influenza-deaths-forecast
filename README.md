# Influenza Deaths Forecast

Walkthrough with all plots: https://nepalanurag.github.io/influenza-deaths-forecast/

I modeled weekly influenza and pneumonia death counts from national surveillance data as a time series problem.

Note on reproducibility: the analysis reads `National_Custom_Data.csv` (weekly influenza/pneumonia death counts), which is not in this repo, so the Rmd cannot be re-run as-is. The file is a custom data download from CDC FluView's pneumonia, influenza, and COVID-19 mortality surveillance (NCHS), National region: open the FluView mortality surveillance page and use its Downloads tool to export the National-level custom dataset. The rendered PDF below is the archived output of the completed analysis.

I compared ARIMA and ETS models on both the raw and cleaned series, then built a hybrid ARIMA + GARCH(1,1) model for a 24-month forecast with 95% prediction intervals. The cleaning step mattered: comma-formatted counts and reporting artifacts had to be handled before any model would behave.

## Files

- `influenza-deaths-forecast.Rmd` - the analysis
- `influenza-deaths-forecast.pdf` - rendered version
