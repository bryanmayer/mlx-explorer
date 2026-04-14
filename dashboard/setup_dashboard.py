#!/usr/bin/env python3
"""
setup_dashboard.py — Configure the Model Explorer dashboard.

Does the same thing as setup-dashboard.Rmd:
  1. Copies model-explorer-template.html one level up as a clean model-explorer.html
  2. Patches the config section of generate-explorer-data.R in place

Usage:
    cd dashboard/
    python setup_dashboard.py

Edit the PHASE_MAP and NOTES_EXCLUDE below before running.
"""

import os
import re
import sys

# ── Config ──────────────────────────────────────────────────────────────────
# Keys = exact subdirectory names under the parent directory
# Values = display labels shown as phase tabs in the dashboard
# Example: if your layout has single_route/ and multiple_route/ directories,
#   use: "single_route": "Single Route", "multiple_route": "Multiple Route"
PHASE_MAP = {
    # "directory_name": "Display Label",
    # "01-Primary": "Primary",
    # "02-Decay": "Decay",
}

# Parameters that are always fixed by design; omit from "fixed params" notes
NOTES_EXCLUDE = [
    # "k_pop",
    # "rebound_flag_pop",
]
# ────────────────────────────────────────────────────────────────────────────

def main():
    # This script must be run from the dashboard/ directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)
    target_dir = os.path.dirname(script_dir)

    print(f"Target: {target_dir}")

    # ── 1. Deploy clean HTML ────────────────────────────────────────────────
    template = "model-explorer-template.html"
    if not os.path.exists(template):
        print(f"ERROR: {template} not found next to this script", file=sys.stderr)
        sys.exit(1)

    with open(template, "r", encoding="utf-8") as f:
        html = f.read()

    # Wipe any injected data
    html = re.sub(
        r"(// <!-- MODEL_DATA_START -->).*?(// <!-- MODEL_DATA_END -->)",
        r"\1\nwindow.MODEL_DATA = [];\nwindow.DASHBOARD_META = {};\n\2",
        html,
        flags=re.DOTALL,
    )

    target_html = os.path.join(target_dir, "model-explorer.html")
    with open(target_html, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"\u2713 {target_html}")

    # ── 2. Patch generate-explorer-data.R config ────────────────────────────
    gen_path = "generate-explorer-data.R"
    with open(gen_path, "r", encoding="utf-8") as f:
        gen_lines = f.readlines()

    # Find config section boundaries
    config_start = None
    config_end = None
    for i, line in enumerate(gen_lines):
        if line.startswith("# \u2500\u2500 Config"):
            config_start = i
        if config_start is not None and line.startswith("# \u2500\u2500 Helper"):
            config_end = i
            break

    if config_start is None or config_end is None:
        print("ERROR: Could not find config section markers in generate-explorer-data.R", file=sys.stderr)
        sys.exit(1)

    # Build PHASE_MAP R code
    if PHASE_MAP:
        entries = ",\n".join(f'  "{k}" = "{v}"' for k, v in PHASE_MAP.items())
        phase_str = f"PHASE_MAP <- list(\n{entries}\n)"
    else:
        phase_str = (
            "PHASE_MAP <- list(\n"
            '  # "01-Phase" = "Phase"    # \u2190 fill in your phase directories\n'
            ")"
        )

    # Build NOTES_EXCLUDE R code
    if NOTES_EXCLUDE:
        items = ", ".join(f'"{x}"' for x in NOTES_EXCLUDE)
        exclude_str = f"NOTES_EXCLUDE <- c({items})"
    else:
        exclude_str = "NOTES_EXCLUDE <- c()"

    # Escape backslashes in path for R string
    r_path = target_dir.replace("\\", "/")

    new_config = [
        "# \u2500\u2500 Config \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n",
        f'BASE_DIR   <- "{r_path}"\n',
        'HTML_FILE  <- file.path(BASE_DIR, "model-explorer.html")\n',
        'source(file.path(BASE_DIR, "dashboard", "validate-models.R"))\n',
        "\n",
        f"{phase_str}\n",
        "\n",
        "IGNORE_MODELS <- c()\n",
        "\n",
        "PLOT_DEFAULTS <- list(\n",
        "  lloq           = NA,\n",
        "  yLimitLower    = NA,\n",
        "  dataIsLog      = FALSE,\n",
        "  logY           = FALSE,\n",
        "  allowLogToggle = TRUE\n",
        ")\n",
        "\n",
        f"{exclude_str}\n",
        "\n",
    ]

    patched = gen_lines[:config_start] + new_config + gen_lines[config_end:]

    with open(gen_path, "w", encoding="utf-8") as f:
        f.writelines(patched)
    print(f"\u2713 Patched config in {gen_path}")

    # ── Done ────────────────────────────────────────────────────────────────
    print()
    print("Next steps:")
    print("  1. Edit generate-explorer-data.R if you need to adjust PHASE_MAP,")
    print("     PLOT_DEFAULTS, or IGNORE_MODELS")
    print("  2. Run:  bash dashboard/update-dashboard.sh")
    print("     (or:  Rscript dashboard/generate-explorer-data.R)")
    print("  3. Open model-explorer.html in your browser")


if __name__ == "__main__":
    main()
