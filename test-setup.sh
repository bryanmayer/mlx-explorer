#!/usr/bin/env bash
# test-setup.sh — End-to-end test of the mlx-explorer dashboard setup
#
# Creates a temporary project directory, copies test model data and dashboard
# files, patches the Rmd config, knits it, and runs the data generator.
#
# Usage:
#   bash test-setup.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DATA="$REPO_DIR/test-mlx-data"
TEST_PROJECT="$REPO_DIR/TEST/test-project"

echo "── Creating test project at $TEST_PROJECT"

# Clean previous test run if it exists
if [ -d "$TEST_PROJECT" ]; then
  echo "   Removing previous test project..."
  rm -rf "$TEST_PROJECT"
fi

# Create project directory and copy model data
mkdir -p "$TEST_PROJECT"
cp -R "$TEST_DATA/single_route"   "$TEST_PROJECT/single_route"
cp -R "$TEST_DATA/multiple_route" "$TEST_PROJECT/multiple_route"

echo "✓ Copied test model data"

# Copy dashboard files
cp -R "$REPO_DIR/dashboard" "$TEST_PROJECT/dashboard"

echo "✓ Copied dashboard/"

# Patch setup-dashboard.Rmd with the correct PHASE_MAP
sed -i '' 's/^PHASE_MAP <- list($/PHASE_MAP <- list(\
  "single_route"   = "Single Route",\
  "multiple_route"  = "Multiple Route"/' \
  "$TEST_PROJECT/dashboard/setup-dashboard.Rmd"

# Remove the commented-out placeholder lines that follow the list(
sed -i '' '/^  # "directory_name"/d' "$TEST_PROJECT/dashboard/setup-dashboard.Rmd"
sed -i '' '/^  # "01-Primary"/d' "$TEST_PROJECT/dashboard/setup-dashboard.Rmd"
sed -i '' '/^  # "02-Decay"/d' "$TEST_PROJECT/dashboard/setup-dashboard.Rmd"

echo "✓ Patched PHASE_MAP in setup-dashboard.Rmd"

# Knit the Rmd (working dir = dashboard/ so TARGET_DIR resolves correctly)
echo "── Knitting setup-dashboard.Rmd..."
cd "$TEST_PROJECT/dashboard"
Rscript -e 'rmarkdown::render("setup-dashboard.Rmd", quiet = TRUE)'

echo "✓ Knitted setup-dashboard.Rmd"

# Verify model-explorer.html was created one level up
if [ -f "$TEST_PROJECT/model-explorer.html" ]; then
  echo "✓ model-explorer.html created"
else
  echo "✗ model-explorer.html NOT found — setup failed"
  exit 1
fi

# Run the data generator
echo "── Running generate-explorer-data.R..."
cd "$TEST_PROJECT"
bash dashboard/update-dashboard.sh

echo ""
echo "══════════════════════════════════════════"
echo "  Test complete!"
echo "  Open: $TEST_PROJECT/model-explorer.html"
echo "══════════════════════════════════════════"
