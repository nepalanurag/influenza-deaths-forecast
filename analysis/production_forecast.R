#!/usr/bin/env Rscript
# analysis/production_forecast.R — the production forecast pipeline.
#
# This reconciles the final forecast to ONE pipeline, documented in the README
# as "the production forecast pipeline":
#
#   mean:      log-ARIMA on the tsclean-cleaned series
#              (auto.arima(..., lambda = 0), the Rmd's chosen mean model)
#   intervals: GARCH(1,1) with Student-t errors fit on the log-ARIMA residuals,
#              t-quantiles (not 1.96) times the forecasted conditional
#              volatility, back-transformed; lower bound clipped at 0.
#
# The log-scale forecast is obtained exactly by re-fitting the selected order
# on log(y) with Arima() — identical to the lambda = 0 fit — so the interval
# construction stays on the scale where the GARCH model lives.
#
# Reads:  data/fluview_snapshot.csv   (via data/fetch_fluview.R)
# Writes: dashboard-data/forecast_24mo.csv  (date, forecast, lower_95, upper_95)
#
# Usage: Rscript analysis/production_forecast.R

suppressPackageStartupMessages({
  library(forecast)
  library(rugarch)
  library(lubridate)
  library(dplyr)
})

repo_root <- (function() {
  args <- commandArgs(trailingOnly = FALSE)
  script_path <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(script_path) == 1 && file.exists(script_path)) {
    return(normalizePath(file.path(dirname(script_path), "..")))
  }
  normalizePath(".")
})()
snap <- file.path(repo_root, "data", "fluview_snapshot.csv")
if (!file.exists(snap)) {
  stop("data/fluview_snapshot.csv not found. Run: Rscript data/fetch_fluview.R")
}

# ---- cleaning pipeline (same as the Rmd) -----------------------------------
clean_col <- function(x) as.numeric(gsub(",", "", x))
raw <- read.csv(snap, stringsAsFactors = FALSE, check.names = FALSE)
raw$NUM.INFLUENZA.DEATHS <- clean_col(raw$NUM.INFLUENZA.DEATHS)
raw$NUM.PNEUMONIA.DEATHS <- clean_col(raw$NUM.PNEUMONIA.DEATHS)
raw$TOTAL.DEATHS <- clean_col(raw$TOTAL.DEATHS)
get_cal_year <- function(season, week) {
  start_year <- as.numeric(substr(season, 1, 4))
  if (week >= 40) start_year else start_year + 1
}
raw$Year <- mapply(get_cal_year, raw$SEASON, raw$WEEK)
raw$Date <- as.Date(paste(raw$Year, raw$WEEK, 1, sep = "-"), format = "%Y-%U-%u")
monthly <- raw %>%
  group_by(MonthDate = floor_date(Date, "month")) %>%
  summarise(Total_P_I = sum(NUM.INFLUENZA.DEATHS + NUM.PNEUMONIA.DEATHS, na.rm = TRUE),
            Total_All_Deaths = sum(TOTAL.DEATHS, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(Percent_PI = (Total_P_I / Total_All_Deaths) * 100) %>%
  arrange(MonthDate) %>%
  filter(!is.na(MonthDate))
start_yr <- year(min(monthly$MonthDate)); start_mo <- month(min(monthly$MonthDate))
ts_raw <- ts(monthly$Percent_PI, start = c(start_yr, start_mo), frequency = 12)
ts_cleaned <- tsclean(ts_raw)

# ---- mean model: log-ARIMA (the Rmd's chosen specification) -----------------
fit_log <- auto.arima(ts_cleaned, seasonal = TRUE, lambda = 0,
                      stepwise = FALSE, approximation = FALSE)
ord <- arimaorder(fit_log)
cat("selected order:", paste0("ARIMA(", paste(ord[1:3], collapse = ","),
      ")(", paste(ord[4:6], collapse = ","), ")[12]"), "\n")
# Exact log-scale working model (lambda = 0 is the log transform)
fit_ll <- Arima(log(ts_cleaned), order = ord[1:3], seasonal = ord[4:6])
fc_ll <- forecast(fit_ll, h = 24)
m_h <- as.numeric(fc_ll$mean)  # log scale

# ---- volatility model: GARCH(1,1)-t on the log-ARIMA residuals --------------
spec <- ugarchspec(
  variance.model = list(model = "sGARCH", garchOrder = c(1, 1)),
  mean.model = list(armaOrder = c(0, 0), include.mean = FALSE),
  distribution.model = "std"
)
garch_fit <- ugarchfit(spec = spec, data = as.numeric(residuals(fit_ll)),
                       solver = "hybrid")
shape <- as.numeric(coef(garch_fit)["shape"])
tq <- qt(0.975, df = shape)
cat(sprintf("GARCH-t shape = %.2f, t-quantile = %.3f\n", shape, tq))
garch_fc <- ugarchforecast(garch_fit, n.ahead = 24)
sigma_h <- as.numeric(sigma(garch_fc))

# ---- back-transform: bias-adjusted mean, t-intervals, clip at 0 -------------
mean_o <- exp(m_h + 0.5 * sigma_h^2)
lower_o <- pmax(exp(m_h - tq * sigma_h), 0)
upper_o <- exp(m_h + tq * sigma_h)

last_date <- max(monthly$MonthDate)
dates <- seq(last_date %m+% months(1), by = "month", length.out = 24)
out <- data.frame(
  date = format(dates, "%Y-%m-%d"),
  forecast = round(mean_o, 2),
  lower_95 = round(lower_o, 2),
  upper_95 = round(upper_o, 2)
)
dd <- file.path(repo_root, "dashboard-data")
dir.create(dd, showWarnings = FALSE)
write.csv(out, file.path(dd, "forecast_24mo.csv"), row.names = FALSE)
cat("wrote dashboard-data/forecast_24mo.csv\n")
print(head(out, 6))
