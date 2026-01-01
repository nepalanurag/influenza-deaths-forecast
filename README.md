# Influenza Deaths Forecast

I modeled weekly influenza and pneumonia death counts from national surveillance data as a time series problem.

I compared ARIMA and ETS models on both the raw and cleaned series, then built a hybrid ARIMA + GARCH(1,1) model for a 24-month forecast with 95% prediction intervals. The cleaning step mattered: comma-formatted counts and reporting artifacts had to be handled before any model would behave.

## Files

- `influenza-deaths-forecast.Rmd` - the analysis
- `influenza-deaths-forecast.pdf` - rendered version
