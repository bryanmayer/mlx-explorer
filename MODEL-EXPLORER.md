# Model Explorer Dashboard

A lightweight, zero-dependency browser dashboard for inspecting and comparing
Monolix (NLME) model runs. No server required — open `analysis/model-explorer.html`
directly in a browser.

---

## Overview

The dashboard consists of three files that work together:

| File | Role |
|------|------|
| `R/generate-explorer-data.R` | Auto-discovers saved Monolix projects, extracts results, writes `analysis/model-data.js` |
| `R/generate-explorer-figures.R` | Generates EBE box plots and individual fit plots (base64-encoded PNGs), appended to `model-data.js` |
| `analysis/model-explorer.html` | Static React app that reads `model-data.js` and renders the dashboard |

The R scripts write plain JavaScript (`window.MODEL_DATA = {...}`) which the HTML
page loads as a `<script>` tag — no build step, no npm, no server.

---

## Usage

After any Monolix run, regenerate the data file and refresh the browser:

```r
source(root("R", "generate-explorer-data.R"))
# ↳ also calls generate-explorer-figures.R automatically
```

Then open (or refresh) `analysis/model-explorer.html` in a browser.

The script cache-busts the `<script>` tag in the HTML automatically
(`?v=<timestamp>`), so a hard refresh is not usually needed.

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

The scripts are intentionally generic. Minimal changes needed:

1. **Path convention** — update `models_root` if your model output directory
   is not `models/`. The phase inference regex (`^acute/`, `^rebound/`) can be
   changed or removed.

2. **Shrinkage tab RE list** — the shrinkage tab currently shows a hardcoded list
   of random effect names. Edit the `reParams` array in the HTML to match your
   model's omegas, or replace it with a dynamic union of all omegas found across
   selected models.

3. **Y-axis label** — the individual fits plot is labelled "Viral load (log₁₀ copies/mL)".
   Update the `y` label in `make_fits_plot()` in `generate-explorer-figures.R`.

4. **Sidebar footer** — the footer reads "acute phase · RV217 data". Update the
   static string in `model-explorer.html`.

5. **Sort default** — defaults to BICc. Change `sortMetric` initial state in
   `ModelExplorer` if BIC or AIC is preferred.

Everything else (parameter tables, comparison, figures) is fully data-driven and
requires no changes.

---

## File Dependencies (runtime)

```
analysis/model-explorer.html
└── analysis/model-data.js        ← generated by R scripts
    ├── window.MODEL_DATA          ← registry + parameter tables
    └── window.MODEL_FIGURES       ← base64 PNG figures (EBE + fits)
```

CDN dependencies loaded by the HTML (internet required on first open, then cached):
- React 18 (UMD)
- Babel standalone (JSX transpilation in-browser)
- Tailwind CSS (CDN)

For fully offline use, download these three scripts and update the `<script>` /
`<link>` tags to local paths.

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
