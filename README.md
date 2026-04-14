## Setup

Download the `dashboard/` folder into your project's final-models directory,
then knit `setup-dashboard.Rmd` to scaffold a configured dashboard.

### Quick start (bash)

```bash
# one-liner — adjust the branch name if needed (main vs master)
REPO="bryanmayer/mlx-explorer"
BRANCH="main"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"

mkdir -p dashboard

curl -fsSL "$RAW/dashboard/generate-explorer-data.R"       -o dashboard/generate-explorer-data.R
curl -fsSL "$RAW/dashboard/model-explorer-template.html"    -o dashboard/model-explorer-template.html
curl -fsSL "$RAW/dashboard/setup-dashboard.Rmd"             -o dashboard/setup-dashboard.Rmd
curl -fsSL "$RAW/dashboard/validate-models.R"               -o dashboard/validate-models.R
curl -fsSL "$RAW/dashboard/wipe-data.R"                     -o dashboard/wipe-data.R
curl -fsSL "$RAW/dashboard/update-dashboard.sh"             -o dashboard/update-dashboard.sh
curl -fsSL "$RAW/dashboard/setup_dashboard.py"              -o dashboard/setup_dashboard.py
chmod +x dashboard/update-dashboard.sh
curl -fsSL "$RAW/MODEL-EXPLORER.md"                         -o MODEL-EXPLORER.md
```

### After downloading

**Option A — R (Rmd):**
1. Edit `dashboard/setup-dashboard.Rmd` — fill in `PHASE_MAP` and `NOTES_EXCLUDE`
2. Knit `setup-dashboard.Rmd` — patches the config and copies `model-explorer.html` one level up

**Option B — Python (no R/Rmd required for setup):**
1. Edit `PHASE_MAP` and `NOTES_EXCLUDE` at the top of `dashboard/setup_dashboard.py`
2. Run: `cd dashboard && python setup_dashboard.py`

**Then (either option):**
3. **Run** `source("dashboard/generate-explorer-data.R")` or `bash dashboard/update-dashboard.sh` after each model run
4. **Open** `model-explorer.html` in a browser (no server needed)

### Project layout after setup

```
final-models/
├── model-explorer.html              ← the dashboard (created by setup-dashboard.Rmd)
├── dashboard/
│   ├── generate-explorer-data.R     ← data generator (configured by setup)
│   ├── model-explorer-template.html ← clean HTML template
│   ├── setup-dashboard.Rmd          ← one-time scaffolding notebook
│   ├── validate-models.R            ← pre-hoc validation checks
│   └── wipe-data.R                  ← strips injected data from HTML
├── 01-Primary/
│   └── ...
├── 02-Decay/
│   └── ...
```

### Configuration

**`dashboard/generate-explorer-data.R`** (after knitting setup-dashboard.Rmd):
```r
BASE_DIR   <- "/path/to/final-models"   # set by setup-dashboard.Rmd
PHASE_MAP  <- list(
  "01-Primary" = "Primary",
  "02-Decay"   = "Decay"
)
NOTES_EXCLUDE <- c()                     # params always fixed by design
PLOT_DEFAULTS <- list(
  lloq           = NA,         # lower limit of quantification
  yLimitLower    = NA,         # lower y-axis bound
  dataIsLog      = FALSE,      # TRUE if DV is already log10-transformed
  logY           = FALSE,      # default log-axis toggle state
  allowLogToggle = TRUE        # show/hide Log Y checkbox
)
```

No changes needed to `model-explorer.html`.

---

### Requirements

R packages: `jsonlite`, `rprojroot`

```r
install.packages(c("jsonlite", "rprojroot"))
```

Your project must have an `.Rproj` file at the root (used by `rprojroot`
to locate the project directory) or set `BASE_DIR` to an absolute path.
