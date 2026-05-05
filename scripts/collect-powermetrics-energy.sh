#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO="${1:-manual}"
SAMPLE_COUNT="${2:-60}"
SAMPLE_RATE_MS="${3:-1000}"
OUT_DIR="${ROOT_DIR}/build/m1_5-energy-evidence"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_FILE="${OUT_DIR}/${TIMESTAMP}-${SCENARIO}-powermetrics.txt"
META_FILE="${OUT_DIR}/${TIMESTAMP}-${SCENARIO}-meta.txt"

usage() {
  cat <<USAGE
Usage: sudo $0 <scenario> [sample-count] [sample-rate-ms]

Examples:
  sudo $0 scenario-a-hidden-idle 600 1000
  sudo $0 scenario-b-warm-open-close 90 1000
  sudo $0 scenario-c-provider-writes 120 1000
  sudo $0 scenario-d-manual-refresh 60 1000

Writes evidence under:
  ${OUT_DIR}
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "powermetrics requires root. Re-run with sudo:" >&2
  echo "  sudo $0 ${SCENARIO} ${SAMPLE_COUNT} ${SAMPLE_RATE_MS}" >&2
  exit 77
fi

if ! [[ "${SAMPLE_COUNT}" =~ ^[0-9]+$ ]] || [[ "${SAMPLE_COUNT}" -lt 1 ]]; then
  echo "sample-count must be a positive integer" >&2
  exit 64
fi

if ! [[ "${SAMPLE_RATE_MS}" =~ ^[0-9]+$ ]] || [[ "${SAMPLE_RATE_MS}" -lt 100 ]]; then
  echo "sample-rate-ms must be an integer >= 100" >&2
  exit 64
fi

mkdir -p "${OUT_DIR}"

AGENT_PIDS="$(pgrep -x agents-widget || true)"
{
  echo "timestamp=${TIMESTAMP}"
  echo "scenario=${SCENARIO}"
  echo "sample_count=${SAMPLE_COUNT}"
  echo "sample_rate_ms=${SAMPLE_RATE_MS}"
  echo "agents_widget_pids=${AGENT_PIDS:-none}"
  echo "command=powermetrics --show-process-energy --show-process-samp-norm --show-usage-summary -i ${SAMPLE_RATE_MS} -n ${SAMPLE_COUNT}"
} > "${META_FILE}"

powermetrics \
  --show-process-energy \
  --show-process-samp-norm \
  --show-usage-summary \
  -i "${SAMPLE_RATE_MS}" \
  -n "${SAMPLE_COUNT}" \
  > "${OUT_FILE}"

echo "metadata: ${META_FILE}"
echo "powermetrics: ${OUT_FILE}"
if [[ -n "${AGENT_PIDS}" ]]; then
  echo
  echo "Agents Widget excerpts:"
  grep -i -C 3 "agents-widget\\|Agents Widget" "${OUT_FILE}" || true
fi
