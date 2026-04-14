# Model Explorer Dashboard

A lightweight, zero-dependency browser dashboard for inspecting and comparing
Monolix (NLME) model runs. No server required, no internet required — open
`model-explorer.html` directly in a browser.

---

## Architecture

The dashboard is a **single self-contained HTML file** (`model-explorer.html`)
with no external dependencies. Everything is embedded inline:

### Components

| Component | Description |
|-----------|-------------|
| HTML skeleton (~20 lines) | Nested `<div>` containers: top bar with phase tabs, sidebar for model list, content area with tab buttons |
| CSS styles (~130 lines) | CSS Grid layout, table styling, status badges, color-coding |
| JavaScript (~800+ lines) | All tables, plots, and interactivity built dynamically via Canvas 2D API |
| Data injection (R script) | JSON array stored in `window.MODEL_DATA` between marker comments |

### Files

| File | Purpose |
|------|---------|
| `dashboard/generate-explorer-data.R` | Discovers Monolix model outputs, parses results, validates, injects JSON into the HTML |
| `dashboard/model-explorer-template.html` | Clean HTML template (no injected data) |
| `dashboard/setup-dashboard.Rmd` | One-time scaffolding notebook — configures and deploys the dashboard |
| `dashboard/validate-models.R` | Pre-hoc validation framework (integrity + diagnostic checks) |
| `dashboard/wipe-data.R` | Strips injected data from HTML, restoring the clean template |
| `model-explorer.html` | The live dashboard (HTML + CSS + JS + embedded data) |

---

## Usage

After any Monolix run, regenerate the data and refresh the browser:

```r
source("dashboard/generate-explorer-data.R")
```

Then open (or refresh) `model-explorer.html` in a browser. Because the data
is injected inline, a normal refresh is sufficient — no cache-busting required.

---

## How It Discovers Models

`generate-explorer-data.R` searches `BASE_DIR` for `populationParameters.txt`
files recursively, skipping `History/` and `ModelBuilding/` subdirectories.
Each directory containing such a file is treated as one model run.

The phase is determined by matching the top-level directory name against
`PHASE_MAP`:
- `01-Primary/family/model/...` → phase = `"Primary"` (if `"01-Primary"` is in PHASE_MAP)
- Unlisted directories are silently ignored

For each discovered run it reads:

| File (relative to model dir) | Contents extracted |
|-----------------------------|--------------------|
| `populationParameters.txt` | Fixed effects, omegas, error params, RSE, SE, CI |
| `LogLikelihood/logLikelihood.txt` | OFV (−2LL), AIC, BIC, AICc, BICc |
| `IndividualParameters/shrinkage.txt` | Per-parameter EBE shrinkage (mode + mean) |
| `IndividualParameters/estimatedIndividualParameters.txt` | EBE mode values (for violin plots) |
| `summary.txt` | Subject/observation counts, observation name |
| `*.mlxtran` | Initial values, MLE/FIXED method per parameter |
| `ChartsData/IndividualFits/*_fits.txt` | Individual prediction curves (downsampled) |
| `ChartsData/IndividualFits/*_observations.txt` | Observed data points (with censoring flag) |
| `ChartsData/ObservationsVsPredictions/*_obsVsPred.txt` | Obs vs Pred diagnostic data |

---

## Validation

`validate-models.R` runs two categories of checks:

### Integrity checks (actionable data/pipeline issues)

1. Stale ChartsData (populationParameters.txt newer than fits)
2. Missing ChartsData/IndividualFits
3. NaN/Inf in population parameters
4. Values < 1e-15 (precision loss in JSON)
5. EBE missing when shrinkage exists
6. Observation column ambiguity
7. Subject mismatch (EBE vs IndividualFits)
8. Missing logLikelihood.txt

### Diagnostic checks (model interpretation flags)

9. RSE > 100%
10. Shrinkage > 80%

### Cross-model checks (per phase)

11. Subject count mismatch within phase
12. Observation count mismatch within phase

Validation results are logged to the R console and embedded in `DASHBOARD_META`
for display in the HTML.

---

## Dashboard Layout

### Top bar

Phase tabs (Primary / Decay / Rebound) — click to switch between phases.

### Sidebar

- Scrollable list of all discovered models, sorted by BICc or −2LL (toggle).
- Each entry shows model name, family grouping, and a status badge (Converged / Warn / Failed).
- Click to select/deselect individual models.
- "Select all / Clear all" toggle.
- Only selected models appear in the main panel.

### Tabs

#### Overview
Summary cards showing best BIC, AIC, and −2LL among selected models.
Table with all selected models: status, likelihood metrics, parameter counts, flags.
Best-BIC row highlighted in green.

#### Parameters
Side-by-side comparison across selected models:
- **Fixed Effects** — population mean estimates with RSE
- Structure column showing FIXED/FITTED status and initial values from `.mlxtran`
- Estimates with RSE > 50% flagged in red

#### Shrinkage
Color-coded heatmap table: rows = random effects, columns = models.

| Shrinkage | Color | Interpretation |
|-----------|-------|----------------|
| < 25% | Green | Well-supported by data |
| 25–40% | Yellow | Acceptable |
| 40–50% | Amber | Consider removing |
| > 50% | Red | Poorly supported — remove random effect |

#### Comparison
Horizontal bar charts for BIC, AIC, −2LL, BICc, and AICc.
ΔBIC table vs the best model with Kass & Raftery (1995) evidence labels:

| ΔBIC | Evidence against higher-BIC model |
|------|-----------------------------------|
| 0–2 | Negligible |
| 2–6 | Positive |
| 6–10 | Strong |
| > 10 | Very strong |

#### Parm Plot
Violin plots of individual parameter distributions (EBE modes) drawn on
`<canvas>` with from-scratch KDE. Only parameters with random effects are shown.

#### Ind. Fits
Per-subject time-course prediction curves with observed data overlay.
Censored observations shown distinctly. Canvas-based faceted panels.

#### Diagnostics
Observed vs IPRED and Observed vs Pop Pred scatter plots (uncensored data only).

---

## Status Inference

Status is derived automatically from `populationParameters.txt`:

| Condition | Status |
|-----------|--------|
| Any NaN in estimates | `failed` |
| Any fixed-effect RSE > 50% | `warnings` |
| Otherwise | `converged` |

---

## Adapting to a New Project

1. **Knit `dashboard/setup-dashboard.Rmd`** with your `PHASE_MAP` filled in.
   This creates a configured `generate-explorer-data.R` and a clean
   `model-explorer.html` one level up from `dashboard/`.

2. **Or manually edit** `dashboard/generate-explorer-data.R`:

```r
BASE_DIR   <- "/path/to/final-models"
PHASE_MAP  <- list(
  "01-Primary" = "Primary",
  "02-Decay"   = "Decay"
)
PLOT_DEFAULTS <- list(
  lloq           = NA,
  yLimitLower    = NA,
  dataIsLog      = FALSE,
  logY           = FALSE,
  allowLogToggle = TRUE
)
NOTES_EXCLUDE <- c()
```

No changes needed to `model-explorer.html`.

---

## File Dependencies (runtime)

```
model-explorer.html             ← fully self-contained after R script runs
    ├── window.MODEL_DATA       ← model data array (injected inline)
    └── window.DASHBOARD_META   ← metadata + validation log (injected inline)
```

There are no external dependencies. The HTML is a single self-contained file
that works offline and opens directly in any browser via `file://`.

---

## Regeneration Checklist

After each model run:

```r
# 1. Ensure the project is saved (Monolix must write output files)
saveProject()

# 2. Regenerate dashboard data
source("dashboard/generate-explorer-data.R")

# 3. Refresh browser tab
```
