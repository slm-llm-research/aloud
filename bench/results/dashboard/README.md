# Eval dashboard

Published page: https://claude.ai/artifact/M78DfEEEmCtHiX7LGSwRQ7 (private until shared from its Share menu).

- `index.html`: the page source. It runs inside the claude.ai Dashboard type (it uses that type's `dash` data API and d3), so it does not open on its own in a browser.
- `eval-sessions.json`, `eval-modes.json`, `eval-scenarios.json`: the data behind it, exported from the scenario sessions in `bench/results/` on 2026-10-31 (sessions `baseline-1031`, `20261031`, `20261031-reclean`, `replay-20261031`, `replay-20261031-v3`).

To refresh after a new run: `uv run python scenario_eval.py compare <sessions…>` for the numbers, then ask Claude to re-export the JSON and update the page.
