#!/usr/bin/env Rscript
# analysis/rolling_origin_cv.R — out-of-sample model comparison.
#
# The Rmd compares ETS / ARIMA variants in-sample (AICc, training RMSE).
# This script is the natural extension: expanding-window rolling-origin
# cross-validation with 1- to 12-step-ahead errors, so "which model is best"
# is answered out of sample. Includes seasonal naive as the benchmark every
# serious forecaster reports against.
#
# Cleaning (tsclean) is re-applied inside each training window — no look-ahead.
#
# Reads:  data/fluview_snapshot.csv   (via data/fetch_fluview.R)
# Writes: analysis/rolling_origin_results.csv  (rmse/mae by model x horizon)
#
# Usage: Rscript analysis/rolling_origin_cv.R
#   Set ROLLING_ORIGIN_STEP=1 for monthly origins (slower) or a larger
#   number for sparser origins. Default steps 3 months between origins.

suppressPackageStartupMessages({
  library(forecast)
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

# ---- replicate the Rmd cleaning pipeline ---------------------------------
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
y <- ts(monthly$Percent_PI,
        start = c(year(min(monthly$MonthDate)), month(min(monthly$MonthDate))),
        frequency = 12)
n <- length(y)
cat("series:", n, "months from", paste(start(y), collapse = "-"), "\n")

# ---- rolling-origin setup --------------------------------------------------
H <- 12
min_train <- 60  # five years before the first origin
step <- as.integer(Sys.getenv("ROLLING_ORIGIN_STEP", "3"))
origins <- seq(min_train, n - H, by = step)
cat("origins:", length(origins), "\n")

models <- c("ets_cleaned", "arima_raw", "arima_log_cleaned", "snaive")
err <- list()
for (m in models) err[[m]] <- matrix(NA_real_, nrow = length(origins), ncol = H)

for (i in seq_along(origins)) {
  t <- origins[i]
  ytr <- window(y, end = time(y)[t])
  yte <- window(y, start = time(y)[t + 1], end = time(y)[t + H])
  yte <- as.numeric(yte)[seq_len(min(H, length(yte)))]
  hh <- length(yte)

  fit_ok <- TRUE
  fc <- list()
  # ETS on the window-cleaned series (cleaned inside the window: no look-ahead)
  yc <- tryCatch(tsclean(ytr), error = function(e) ytr)
  fc$ets_cleaned <- tryCatch(as.numeric(forecast(ets(yc), h = hh)$mean),
                              error = function(e) { fit_ok <<- FALSE; rep(NA_real_, hh) })
  # ARIMA on the raw window
  fc$arima_raw <- tryCatch(as.numeric(forecast(auto.arima(ytr), h = hh)$mean),
                           error = function(e) { fit_ok <<- FALSE; rep(NA_real_, hh) })
  # ARIMA on the log of the window-cleaned series, bias-adjusted back-transform
  fc$arima_log_cleaned <- tryCatch(
    as.numeric(forecast(auto.arima(log(yc)), h = hh, biasadj = TRUE)$mean),
    error = function(e) { fit_ok <<- FALSE; rep(NA_real_, hh) })
  # Seasonal naive benchmark
  fc$snaive <- as.numeric(snaive(ytr, h = hh)$mean)

  for (m in models) err[[m]][i, seq_len(hh)] <- fc[[m]] - yte
  if (i %% 5 == 0) cat("  origin", i, "of", length(origins), "\n")
}

# ---- aggregate --------------------------------------------------------------
res <- do.call(rbind, lapply(models, function(m) {
  e <- err[[m]]
  data.frame(
    model = m,
    horizon = seq_len(H),
    rmse = sqrt(colMeans(e^2, na.rm = TRUE)),
    mae = colMeans(abs(e), na.rm = TRUE),
    n_origins = colSums(!is.na(e))
  )
}))
out_dir <- file.path(repo_root, "analysis")
dir.create(out_dir, showWarnings = FALSE)
write.csv(res, file.path(out_dir, "rolling_origin_results.csv"), row.names = FALSE)

cat("\nOut-of-sample RMSE by horizon (best per horizon marked *):\n")
wide <- tapply(res$rmse, list(res$horizon, res$model), identity)
print(round(wide, 3))
cat("\nMean RMSE over horizons 1-12:\n")
print(round(tapply(res$rmse, res$model, mean, na.rm = TRUE), 3))
cat("\nwrote analysis/rolling_origin_results.csv\n")
