#!/usr/bin/env bash
# update-dashboard.sh — Regenerate model-explorer.html data
# Run from anywhere; the script finds its own directory.
#
# Usage:
#   bash dashboard/update-dashboard.sh
#   # or from inside dashboard/:
#   ./update-dashboard.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

Rscript "$SCRIPT_DIR/generate-explorer-data.R"
