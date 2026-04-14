#!/usr/bin/env bash
# test-setup-py.sh — End-to-end test using the Python setup script
#
# Creates a temporary project directory, copies test model data and dashboard
# files, patches the Python config, runs setup_dashboard.py, and runs the
# data generator.
#
# Usage:
#   bash test-setup-py.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DATA="$REPO_DIR/test-mlx-data"
TEST_PROJECT="$REPO_DIR/TEST/test-project-py"

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

# Patch setup_dashboard.py with the correct PHASE_MAP
sed -i '' 's/^PHASE_MAP = {$/PHASE_MAP = {\
    "single_route": "Single Route",\
    "multiple_route": "Multiple Route",/' \
  "$TEST_PROJECT/dashboard/setup_dashboard.py"

# Remove the commented-out placeholder lines
sed -i '' '/^    # "directory_name"/d' "$TEST_PROJECT/dashboard/setup_dashboard.py"
sed -i '' '/^    # "01-Primary"/d' "$TEST_PROJECT/dashboard/setup_dashboard.py"
sed -i '' '/^    # "02-Decay"/d' "$TEST_PROJECT/dashboard/setup_dashboard.py"

echo "✓ Patched PHASE_MAP in setup_dashboard.py"

# Run the Python setup script
echo "── Running setup_dashboard.py..."
cd "$TEST_PROJECT/dashboard"
python3 setup_dashboard.py

echo "✓ Python setup complete"

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
echo "  Test complete! (Python setup)"
echo "  Open: $TEST_PROJECT/model-explorer.html"
echo "══════════════════════════════════════════"
