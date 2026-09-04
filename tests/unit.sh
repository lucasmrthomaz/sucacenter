#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
while IFS= read -r -d '' file; do bash -n "$file"; done < <(find . -not -path './.git/*' -type f \( -name '*.sh' -o -path './commands/cluster*' \) -print0)
python3 -m unittest discover -s tests -p 'test_*.py' -v
