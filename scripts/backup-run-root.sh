#!/usr/bin/env bash
set -euo pipefail

BATCH_NAME=""
RUN_VERSION=""
OUTPUT_DIR="${OUTPUT_DIR:-local_state/backups}"
RUNS_ROOT="${RUNS_ROOT:-$HOME/pb-goal-runs}"
STATE_ROOT="${STATE_ROOT:-local_state/batches}"

usage() {
  cat <<'EOF'
Usage:
  scripts/backup-run-root.sh --batch-name NAME --run-version VERSION [--output-dir DIR]

Creates a private tar.gz backup containing:
  - local_state/batches/<batch>/<version>
  - ~/pb-goal-runs/<batch>/<version>

Environment:
  OUTPUT_DIR   Backup destination (default: local_state/backups)
  RUNS_ROOT    Run artifact root (default: ~/pb-goal-runs)
  STATE_ROOT   Batch state root (default: local_state/batches)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch-name)
      BATCH_NAME="$2"
      shift 2
      ;;
    --run-version)
      RUN_VERSION="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$BATCH_NAME" || -z "$RUN_VERSION" ]]; then
  usage >&2
  exit 2
fi

STATE_DIR="$STATE_ROOT/$BATCH_NAME/$RUN_VERSION"
RUN_DIR="$RUNS_ROOT/$BATCH_NAME/$RUN_VERSION"
STATE_DIR="$(cd "$STATE_DIR" && pwd)"
RUN_DIR="$(cd "$RUN_DIR" && pwd)"
STATE_BASE="$(cd "$STATE_ROOT/.." && pwd)"
RUNS_BASE="$(cd "$RUNS_ROOT/.." && pwd)"

if [[ ! -d "$STATE_DIR" ]]; then
  echo "batch state not found: $STATE_DIR" >&2
  exit 1
fi

if [[ ! -d "$RUN_DIR" ]]; then
  echo "run root not found: $RUN_DIR" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT="$OUTPUT_DIR/${BATCH_NAME}-${RUN_VERSION}-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"

tar -czf "$OUTPUT" \
  -C "$STATE_BASE" "batches/$BATCH_NAME/$RUN_VERSION" \
  -C "$RUNS_BASE" "pb-goal-runs/$BATCH_NAME/$RUN_VERSION"

sha256sum "$OUTPUT" > "$OUTPUT.sha256"
echo "$OUTPUT"
echo "$OUTPUT.sha256"
