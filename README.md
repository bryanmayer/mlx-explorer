## Setup

  Copy three files into your project:

  R/generate-explorer-data.R
  R/generate-explorer-figures.R
  analysis/model-explorer.html

  Then edit the config block at the top of each R script:

Bash script 

```
  # one-liner — adjust the branch name if needed (main vs master)
  REPO="bryanmayer/mlx-explorer"
  BRANCH="main"
  RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"

  curl -fsSL "$RAW/R/generate-explorer-data.R"    -o R/generate-explorer-data.R
  curl -fsSL "$RAW/R/generate-explorer-figures.R" -o R/generate-explorer-figures.R
  curl -fsSL "$RAW/analysis/model-explorer.html"  -o analysis/model-explorer.html
  curl -fsSL "$RAW/MODEL-EXPLORER.md"  -o MODEL-EXPLORER.md

```


  **`generate-explorer-data.R`**
  ```r
  MODELS_SUBDIR      <- "models"       # where your .mlxtran projects live
  PHASE_PATTERNS     <- list(          # path prefix → phase label; set to list() to disable
    phase1 = "^phase1/",
    phase2 = "^phase2/"
  )
  NOTES_EXCLUDE_PARAMS <- character(0) # params always fixed by design, omit from notes

  generate-explorer-figures.R
  MODELS_SUBDIR <- "models"
  FITS_Y_LABEL  <- "Concentration (ng/mL)"  # y-axis label on individual fits plot

  No changes needed to model-explorer.html.

  ---
  After each model run

  source(root("R", "generate-explorer-data.R"))

  This scans models/ for completed runs, extracts parameters and fit metrics,
  generates figures, and writes analysis/model-data.js. Then refresh the browser.

  ---
  Viewing the dashboard

  Open analysis/model-explorer.html directly in a browser (no server needed).
  Requires an internet connection on first open to load React and Tailwind from CDN.

  ---
  Requirements

  R packages: tidyverse, jsonlite, glue, base64enc, rprojroot

  install.packages(c("tidyverse", "jsonlite", "glue", "base64enc", "rprojroot"))

  Your project must have an .Rproj file at the root (used by rprojroot to
  locate the project directory).
  ```
