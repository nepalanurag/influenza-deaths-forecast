#!/usr/bin/env Rscript
# data/fetch_fluview.R — scripted CDC FluView NCHS mortality data fetch.
#
# The analysis scripts read data/fluview_snapshot.csv (a checksummed snapshot).
# This script produces the snapshot, in order of preference:
#   1. A fresh download from documented CDC FluView endpoints (best effort;
#      CDC serves the custom National download through a JS-driven tool, so
#      there is no stable permalink — each attempt is logged).
#   2. A manually placed National_Custom_Data.csv next to the Rmd (the
#      long-standing manual step, now schema-validated instead of trusted
#      blindly). This is the same file the original analysis used.
# Either way the snapshot is validated and checksummed.
#
# Usage: Rscript data/fetch_fluview.R

repo_root <- (function() {
  # Resolve the repo root from this script's location (works via Rscript).
  args <- commandArgs(trailingOnly = FALSE)
  script_path <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(script_path) == 1 && file.exists(script_path)) {
    return(normalizePath(file.path(dirname(script_path), "..")))
  }
  normalizePath(".")
})()
data_dir <- file.path(repo_root, "data")
dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)
snapshot_path <- file.path(data_dir, "fluview_snapshot.csv")
checksum_path <- file.path(data_dir, "fluview_snapshot.sha256")
manual_path <- file.path(repo_root, "National_Custom_Data.csv")

REQUIRED_COLS <- c("SEASON", "WEEK", "NUM.INFLUENZA.DEATHS",
                   "NUM.PNEUMONIA.DEATHS", "TOTAL.DEATHS")

# Best-effort direct endpoints (tried in order; all attempts logged).
CANDIDATE_URLS <- c(
  "https://www.cdc.gov/flu/weekly/weeklyarchives2024-2025/data/NCHSData01.csv",
  "https://www.cdc.gov/flu/weekly/weeklyarchives2023-2024/data/NCHSData01.csv"
)

log_msg <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "-", ..., "\n")

try_download <- function(url) {
  tmp <- tempfile(fileext = ".csv")
  ok <- suppressWarnings(tryCatch({
    utils::download.file(url, tmp, quiet = TRUE, mode = "wb")
    file.info(tmp)$size > 1000
  }, error = function(e) FALSE))
  if (ok) tmp else NULL
}

validate_schema <- function(path) {
  df <- tryCatch(
    utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) NULL
  )
  if (is.null(df)) return("unreadable CSV")
  missing <- setdiff(REQUIRED_COLS, names(df))
  if (length(missing) > 0)
    return(paste("missing columns:", paste(missing, collapse = ", ")))
  wk <- suppressWarnings(as.numeric(df$WEEK))
  if (any(is.na(wk)) || min(wk, na.rm = TRUE) < 1 || max(wk, na.rm = TRUE) > 53)
    return("WEEK column out of range 1-53")
  if (nrow(df) < 52) return("fewer than 52 weekly rows")
  NULL # valid
}

write_snapshot <- function(src_path, provenance) {
  df <- utils::read.csv(src_path, stringsAsFactors = FALSE, check.names = FALSE)
  utils::write.csv(df, snapshot_path, row.names = FALSE)
  sha <- unname(tools::md5sum(snapshot_path))
  writeLines(
    c(paste0(sha, "  fluview_snapshot.csv"),
      paste0("# provenance: ", provenance),
      paste0("# snapshot written: ", format(Sys.time(), "%Y-%m-%d %H:%M %Z")),
      paste0("# rows: ", nrow(df))),
    checksum_path
  )
  log_msg("snapshot written:", snapshot_path, "(md5", substr(sha, 1, 8), ")")
  invisible(df)
}

# 1. Best-effort fresh download -------------------------------------------
for (url in CANDIDATE_URLS) {
  log_msg("trying", url)
  tmp <- try_download(url)
  if (!is.null(tmp)) {
    problem <- validate_schema(tmp)
    if (is.null(problem)) {
      log_msg("download validated")
      write_snapshot(tmp, paste("fresh download", url))
      quit(save = "no", status = 0)
    } else {
      log_msg("download failed schema check:", problem)
    }
  } else {
    log_msg("download failed (no response / blocked)")
  }
}

# 2. Manually placed CSV ----------------------------------------------------
if (file.exists(manual_path)) {
  log_msg("falling back to manually placed National_Custom_Data.csv")
  problem <- validate_schema(manual_path)
  if (!is.null(problem)) {
    log_msg("ERROR: manual CSV failed schema check:", problem)
    quit(save = "no", status = 1)
  }
  write_snapshot(manual_path, "manual download via CDC FluView Downloads tool (National region)")
  quit(save = "no", status = 0)
}

# 3. Nothing available ------------------------------------------------------
log_msg("ERROR: no data source available.")
log_msg("Place National_Custom_Data.csv next to the Rmd, from the CDC FluView")
log_msg("mortality surveillance page (Downloads tool, National region), then re-run.")
quit(save = "no", status = 1)
