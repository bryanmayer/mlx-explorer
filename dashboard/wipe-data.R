#!/usr/bin/env Rscript
# wipe-data.R — Remove injected model data from model-explorer.html
# This restores the HTML to a clean template that can be re-populated
# by running generate-explorer-data.R
#
# Usage:  Rscript dashboard/wipe-data.R

# Look for model-explorer.html one level up from this script's directory
script_dir <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile, mustWork = FALSE)),
  error = function(e) "."
)
HTML_FILE <- file.path(dirname(script_dir), "model-explorer.html")

if (!file.exists(HTML_FILE)) {
  # Fallback: current working directory
  HTML_FILE <- "model-explorer.html"
}
if (!file.exists(HTML_FILE)) stop("Cannot find model-explorer.html")

HTML_FILE_OUT <- sub("\\.html$", "-clean.html", HTML_FILE)

html <- readLines(HTML_FILE, warn = FALSE)

start_marker <- "// <!-- MODEL_DATA_START -->"
end_marker   <- "// <!-- MODEL_DATA_END -->"

start_idx <- grep(start_marker, html, fixed = TRUE)
end_idx   <- grep(end_marker, html, fixed = TRUE)

if (length(start_idx) == 0 || length(end_idx) == 0) {
  cat("No data markers found — file is already clean.\n")
  quit(status = 0)
}

# Replace everything between markers with empty data
empty_data <- paste0(
  "window.MODEL_DATA = [];\n",
  "window.DASHBOARD_META = {};"
)

new_html <- c(
  html[1:start_idx],
  empty_data,
  html[end_idx:length(html)]
)

writeLines(new_html, HTML_FILE_OUT)
cat(sprintf("Wiped model data from %s\n", HTML_FILE_OUT))
