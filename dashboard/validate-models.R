#!/usr/bin/env Rscript
# validate-models.R
# Pre-hoc validation checks for Monolix model outputs before dashboard injection.
# Called by generate-explorer-data.R. Returns a list of warnings per model.
#
# Each check returns: list(level, category, msg)
#   level:    "ERROR" | "WARN"
#   category: "integrity" — actionable data/pipeline issue (stale charts, missing files, precision)
#             "diagnostic" — model interpretation flag (high shrinkage, high RSE, convergence)
#
# The HTML banner only surfaces "integrity" issues prominently.
# "diagnostic" issues are logged to the R console and available in the expandable details.

validate_model <- function(model_dir, model_name, pop_df, shrink_df, ebe_df) {
  warnings <- list()
  w <- function(level, category, msg) {
    warnings[[length(warnings) + 1]] <<- list(level = level, category = category, msg = msg)
  }

  # ═══════════════════════════════════════════════════════════════════════════
  # INTEGRITY checks — actionable issues with data pipeline / dashboard accuracy
  # ═══════════════════════════════════════════════════════════════════════════

  # 1. Stale ChartsData: popParams newer than fits
  pop_path <- file.path(model_dir, "populationParameters.txt")
  charts_dir <- file.path(model_dir, "ChartsData", "IndividualFits")
  if (file.exists(pop_path) && dir.exists(charts_dir)) {
    fits_files <- list.files(charts_dir, pattern = "_fits\\.txt$", full.names = TRUE)
    if (length(fits_files) > 0) {
      pop_mtime <- file.mtime(pop_path)
      fits_mtime <- file.mtime(fits_files[1])
      if (!is.na(pop_mtime) && !is.na(fits_mtime) && pop_mtime > fits_mtime + 60) {
        w("ERROR", "integrity", sprintf(
          "populationParameters.txt (%s) is newer than ChartsData (%s) \u2014 model refit without re-exporting charts",
          format(pop_mtime, "%Y-%m-%d %H:%M"),
          format(fits_mtime, "%Y-%m-%d %H:%M")
        ))
      }
    }
  }

  # 2. Missing ChartsData entirely
  if (!dir.exists(charts_dir)) {
    w("WARN", "integrity", "No ChartsData/IndividualFits \u2014 Ind. Fits tab will be empty")
  }

  # 3. NaN / Inf in population parameters
  if (!is.null(pop_df)) {
    bad_vals <- pop_df$parameter[is.na(pop_df$value) | is.infinite(pop_df$value)]
    if (length(bad_vals) > 0) {
      w("ERROR", "integrity", sprintf("NaN/Inf in parameter values: %s", paste(bad_vals, collapse = ", ")))
    }
  }

  # 4. Very small values that may lose precision in JSON
  if (!is.null(pop_df)) {
    tiny <- pop_df$parameter[!is.na(pop_df$value) & pop_df$value != 0 & abs(pop_df$value) < 1e-15]
    if (length(tiny) > 0) {
      w("WARN", "integrity", sprintf("Values < 1e-15 may lose precision: %s", paste(tiny, collapse = ", ")))
    }
  }

  # 5. EBE file missing when shrinkage suggests random effects exist
  if (!is.null(shrink_df) && nrow(shrink_df) > 0 && is.null(ebe_df)) {
    w("WARN", "integrity", "estimatedIndividualParameters.txt missing \u2014 Parm Plot will be empty")
  }

  # 6. Observation column ambiguity
  obs_files <- list.files(charts_dir, pattern = "_observations\\.txt$", full.names = TRUE)
  if (length(obs_files) > 0) {
    obs_header <- names(read.csv(obs_files[1], nrows = 0, check.names = FALSE))
    known_cols <- c("ID", "time", "median", "piLower", "piUpper", "censored", "color", "filter")
    obs_col_candidates <- setdiff(obs_header, known_cols)
    if (length(obs_col_candidates) > 1) {
      w("WARN", "integrity", sprintf(
        "Ambiguous observation column: found %s \u2014 using '%s'",
        paste(obs_col_candidates, collapse = ", "), obs_col_candidates[1]
      ))
    } else if (length(obs_col_candidates) == 0) {
      w("ERROR", "integrity", "Could not identify observation column in IndividualFits")
    }
  }

  # 7. Subject mismatch: EBE vs IndividualFits
  if (!is.null(ebe_df) && length(obs_files) > 0) {
    ebe_ids <- unique(as.character(ebe_df$id))
    if (length(ebe_ids) == 0 && "ID" %in% names(ebe_df)) {
      ebe_ids <- unique(as.character(ebe_df$ID))
    }
    obs_df_check <- tryCatch(read.csv(obs_files[1], stringsAsFactors = FALSE), error = function(e) NULL)
    if (!is.null(obs_df_check)) {
      obs_ids <- unique(as.character(obs_df_check$ID))
      if (length(ebe_ids) > 0 && length(obs_ids) > 0) {
        missing_in_obs <- setdiff(ebe_ids, obs_ids)
        if (length(missing_in_obs) > 0 && length(missing_in_obs) <= 5) {
          w("WARN", "integrity", sprintf("Subjects in EBE but not in fits: %s", paste(missing_in_obs, collapse = ", ")))
        }
      }
    }
  }

  # 8. Log-likelihood file missing
  ll_path <- file.path(model_dir, "LogLikelihood", "logLikelihood.txt")
  if (!file.exists(ll_path)) {
    w("WARN", "integrity", "logLikelihood.txt missing \u2014 BIC/AIC unavailable")
  }

  # ═══════════════════════════════════════════════════════════════════════════
  # DIAGNOSTIC checks — model interpretation flags (not dashboard bugs)
  # ═══════════════════════════════════════════════════════════════════════════

  # 9. Parameters with RSE > 100%
  if (!is.null(pop_df) && "rse_sa" %in% names(pop_df)) {
    rse_vals <- suppressWarnings(as.numeric(pop_df$rse_sa))
    high_rse <- pop_df$parameter[!is.na(rse_vals) & rse_vals > 100]
    if (length(high_rse) > 0) {
      w("WARN", "diagnostic", sprintf("RSE > 100%%: %s", paste(high_rse, collapse = ", ")))
    }
  }

  # 10. Shrinkage > 80%
  if (!is.null(shrink_df) && "shrinkage_mode" %in% names(shrink_df)) {
    shrink_vals <- suppressWarnings(as.numeric(shrink_df$shrinkage_mode))
    high_shrink <- shrink_df$parameters[!is.na(shrink_vals) & shrink_vals > 80]
    if (length(high_shrink) > 0) {
      w("WARN", "diagnostic", sprintf("Shrinkage > 80%%: %s", paste(high_shrink, collapse = ", ")))
    }
  }

  return(warnings)
}

# ── Cross-model checks (run after all models parsed) ──────────────────────
validate_phase <- function(phase_models, phase_name) {
  warnings <- list()
  w <- function(level, category, msg) {
    warnings[[length(warnings) + 1]] <<- list(level = level, category = category, msg = msg)
  }

  if (length(phase_models) < 2) return(warnings)

  # 11. Subject count mismatch within phase
  n_subj <- sapply(phase_models, function(m) m$n_individuals)
  n_subj <- n_subj[!is.na(n_subj)]
  if (length(unique(n_subj)) > 1) {
    w("WARN", "integrity", sprintf(
      "Different subject counts across models: %s \u2014 observed data may not be comparable",
      paste(unique(n_subj), collapse = ", ")
    ))
  }

  # 12. Observation count mismatch within phase
  n_obs <- sapply(phase_models, function(m) m$n_observations)
  n_obs <- n_obs[!is.na(n_obs)]
  if (length(unique(n_obs)) > 1) {
    w("WARN", "integrity", sprintf(
      "Different observation counts across models: %s \u2014 data subsets may differ",
      paste(unique(n_obs), collapse = ", ")
    ))
  }

  return(warnings)
}

# ── Logging utility ───────────────────────────────────────────────────────
log_warnings <- function(all_warnings) {
  n_integrity <- 0
  n_diagnostic <- 0
  n_errors <- 0

  # Group by category for cleaner output
  integrity_msgs <- list()
  diagnostic_msgs <- list()

  for (entry in all_warnings) {
    for (w in entry$warnings) {
      item <- list(model = entry$model, level = w$level, msg = w$msg)
      if (w$category == "integrity") {
        integrity_msgs[[length(integrity_msgs) + 1]] <- item
        n_integrity <- n_integrity + 1
      } else {
        diagnostic_msgs[[length(diagnostic_msgs) + 1]] <- item
        n_diagnostic <- n_diagnostic + 1
      }
      if (w$level == "ERROR") n_errors <- n_errors + 1
    }
  }

  if (length(integrity_msgs) > 0) {
    cat("\n  \033[1mData integrity issues:\033[0m\n")
    for (item in integrity_msgs) {
      prefix <- if (item$level == "ERROR") "\033[31mERROR\033[0m" else "\033[33mWARN\033[0m"
      cat(sprintf("    [%s] %s: %s\n", prefix, item$model, item$msg))
    }
  }

  if (length(diagnostic_msgs) > 0) {
    cat("\n  \033[1mModel diagnostics:\033[0m\n")
    for (item in diagnostic_msgs) {
      cat(sprintf("    [%s] %s: %s\n", "\033[36mDIAG\033[0m", item$model, item$msg))
    }
  }

  cat(sprintf("\n  Summary: %d integrity issue(s) (%d errors), %d diagnostic flag(s)\n",
              n_integrity, n_errors, n_diagnostic))

  return(list(n_errors = n_errors, n_integrity = n_integrity, n_diagnostic = n_diagnostic))
}
