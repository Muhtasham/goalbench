#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/bootstrap-programbench.sh [target-dir]

Clones or updates the ProgramBench evaluator checkout. If target-dir is omitted,
the script uses a sibling ../ProgramBench directory so run-sweep.sh can
auto-detect it.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$TARGET" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TARGET="$(cd "$SCRIPT_DIR/.." && pwd)/../ProgramBench"
fi

if [[ -d "$TARGET/.git" ]]; then
  git -C "$TARGET" pull --ff-only
else
  git clone https://github.com/facebookresearch/ProgramBench.git "$TARGET"
fi

uv sync --project "$TARGET"

echo "ProgramBench ready at $(cd "$TARGET" && pwd)"
