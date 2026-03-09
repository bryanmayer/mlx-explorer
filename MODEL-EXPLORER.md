# Model Explorer Dashboard

A lightweight, zero-dependency browser dashboard for inspecting and comparing
Monolix (NLME) model runs. No server required, no internet required — open
`analysis/model-explorer.html` directly in a browser.

---

## Overview

The dashboard consists of three files that work together:

| File | Role |
|------|------|
| `R/generate-explorer-data.R` | Auto-discovers saved Monolix projects, extracts results, injects data inline into `model-explorer.html` |
| `R/generate-explorer-figures.R` | Generates EBE box plots and individual fit plots (base64-encoded PNGs), injected inline into `model-explorer.html` |
| `analysis/model-explorer.html` | Self-contained vanilla JS dashboard — no React, no CDN, no external files |

The R scripts inject plain JavaScript (`window.MODEL_DATA = {...}`) directly into
`model-explorer.html` between marker comments, making it fully self-contained.
No build step, no npm, no server, no internet connection required.

---

## Usage

After any Monolix run, regenerate the data file and refresh the browser:

```r
source(root("R", "generate-explorer-data.R"))
# ↳ also calls generate-explorer-figures.R automatically
```

Then open (or refresh) `analysis/model-explorer.html` in a browser.

Because the data is injected inline, a normal refresh is sufficient — no
cache-busting required.

---

## How It Discovers Models

`generate-explorer-data.R` searches `models/` recursively for
`populationParameters.txt` files, skipping `History/` subdirectories.
Each directory containing such a file is treated as one model run.

The phase is inferred from the path:
- `models/acute/...` → phase = `"acute"`
- `models/rebound/...` → phase = `"rebound"`
- anything else → phase = `"unknown"`

Run IDs are assigned sequentially (`run001`, `run002`, ...) ordered by file path.

For each discovered run it reads:

| File (relative to model dir) | Contents extracted |
|-----------------------------|--------------------|
| `populationParameters.txt` | Fixed effects, omegas, error params, RSE |
| `LogLikelihood/logLikelihood.txt` | OFV (−2LL), AIC, BIC, AICc, BICc |
| `IndividualParameters/shrinkage.txt` | Per-parameter EBE shrinkage |
| `IndividualParameters/estimatedIndividualParameters.txt` | EBE mode values (for box plots) |
| `ChartsData/IndividualFits/y_fits.txt` | Individual prediction curves |
| `ChartsData/IndividualFits/y_observations.txt` | Observed data points (with censoring flag) |

---

## Dashboard Layout

### Sidebar

- Scrollable list of all discovered runs, sorted by BICc or −2LL (toggle at top).
- Each entry shows model name, run ID, BIC, and a status badge (Clean / Warn / Failed).
- Click to select/deselect individual models.
- "Select all / Clear all" toggle.
- Only selected models appear in the main panel.

### Tabs

#### Overview
Summary cards showing which selected model has the best BIC, AIC, and −2LL.
Below: a table with all selected models and columns:
- Run ID, model name, status badge
- BIC, BICc, AIC, AICc, −2LL
- Estimated / fixed parameter counts
- Error model
- Flag counts: `⚠ RSE ×N` (fixed effects with RSE > 50%) and `↑ shrink ×N` (random effects with shrinkage > 40%)
- Notes (auto-generated: lists which parameters were FIXED)

Best-BIC row highlighted in green.

#### Parameters
Side-by-side parameter comparison across selected models, split into three sections:
- **Fixed Effects** — population mean estimates
- **Random Effects (ω)** — variance components
- **Error Model** — residual error parameters

Each model gets two columns: estimate and RSE%. Fixed parameters show a `FIXED` badge
instead of an RSE. Estimates with RSE > 50% are flagged in red (`⚠`).

#### Shrinkage
Color-coded heatmap table: rows = random effects, columns = models.

| Shrinkage | Color | Interpretation |
|-----------|-------|----------------|
| < 25% | Green | Well-supported by data |
| 25–40% | Yellow | Acceptable |
| 40–50% | Amber | Consider removing |
| > 50% | Red | Poorly supported — remove random effect |

#### Comparison
Horizontal bar charts for BIC, AIC, −2LL, BICc, and AICc (best model = green bar).

ΔBIC table vs the best model in the selection, with Kass & Raftery (1995) evidence
labels:

| ΔBIC | Evidence against higher-BIC model |
|------|-----------------------------------|
| 0–2  | Negligible |
| 2–6  | Positive |
| 6–10 | Strong |
| > 10 | Very strong |

#### Figures
Per-model panels, each with two plots (if data is available):
- **EBE Parameter Distributions** — box plots of individual parameter modes.
  Parameters with log-Normal distributions in the `.mlxtran` file are
  pre-transformed to log₁₀ scale and labeled accordingly.
  Constant parameters (no variability) are automatically hidden.
- **Individual Fits** — observed data overlaid on individual prediction curves.
  Censored observations are shown as yellow triangles (▼).
  Scales are shared across subjects within a model.

---

## Status Inference

Status is derived automatically from `populationParameters.txt` (no manual registry
required):

| Condition | Status |
|-----------|--------|
| Any NaN in estimates | `failed` |
| Any fixed-effect RSE > 50% | `warnings` |
| Otherwise | `converged` |

---

## Adapting to a New Project

All project-specific settings are in config blocks at the top of each R script.
No changes are needed to `model-explorer.html`.

**`R/generate-explorer-data.R`**

```r
MODELS_SUBDIR      <- "models"       # subdirectory where .mlxtran projects are saved
PHASE_PATTERNS     <- list(          # path prefix → phase label
  phase1 = "^phase1/",               # set to list() to disable phase inference
  phase2 = "^phase2/"
)
NOTES_EXCLUDE_PARAMS <- character(0) # params always fixed by design, omit from notes
```

**`R/generate-explorer-figures.R`**

```r
MODELS_SUBDIR <- "models"                  # must match generate-explorer-data.R
FITS_Y_LABEL  <- "Concentration (ng/mL)"  # y-axis label on individual fits plot
```

Everything else (parameter tables, comparison charts, shrinkage heatmap, figures)
is fully data-driven and requires no changes.

---

## File Dependencies (runtime)

```
analysis/model-explorer.html      ← fully self-contained after R scripts run
    ├── window.MODEL_DATA          ← registry + parameter tables (injected inline)
    └── window.MODEL_FIGURES       ← base64 PNG figures (injected inline)
```

There are no external dependencies. The HTML is a single self-contained file
that works offline and opens directly in any browser via `file://`.

---

## Regeneration Checklist

After each model run:

```r
# 1. Ensure the project is saved (Monolix must write output files)
saveProject()            # or save_project("path/to/project")

# 2. Regenerate dashboard data
source(root("R", "generate-explorer-data.R"))

# 3. Refresh browser tab
```

The figures script (`generate-explorer-figures.R`) is called automatically at
the end of `generate-explorer-data.R` and does not need to be sourced separately.

---

## Known Issues / Implementation Notes

### Empty error-parameter rows crash `parse_params`

Models that have no error parameters (i.e., no row matching `parameter == "a"` in
`populationParameters.txt`) produce a 0-row tibble for `err_rows`. In dplyr,
`rowwise() %>% mutate()` on a 0-row tibble still evaluates the mutate expression
for type inference. An inner `if (!is.na(.data[[rse_col]]))` then receives a
zero-length vector and throws:

```
Error: argument is of length zero
```

**Fix already applied** in `generate-explorer-data.R`: `parse_params()` returns
an empty typed tibble immediately when `nrow(rows) == 0`. If you refactor
`parse_params`, preserve this guard:

```r
parse_params <- function(rows) {
  if (nrow(rows) == 0)
    return(tibble(name = character(), est = numeric(), rse = numeric(), fixed = logical()))
  # ... rest of function
}
```
