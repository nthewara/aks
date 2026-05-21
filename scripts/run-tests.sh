#!/usr/bin/env bash
# Run RBAC + NetworkPolicy tests and refresh the master SUMMARY.md.
set -uo pipefail  # not -e: we want to capture partial failures.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RES="$REPO_ROOT/tests/results"
mkdir -p "$RES"

echo "════ RBAC tests ════"
"$SCRIPT_DIR/test-rbac.sh"; rbac_rc=$?

echo
echo "════ Network policy tests ════"
"$SCRIPT_DIR/test-network-policy.sh"; np_rc=$?

# Roll up into a top-level SUMMARY.md
{
  echo "# AKS Lab — Validation Summary"
  echo
  echo "Generated: $(date -u +%FT%TZ)"
  echo
  echo "## RBAC"
  echo
  if [[ -f "$RES/rbac/SUMMARY.md" ]]; then
    tail -n +2 "$RES/rbac/SUMMARY.md"
  else
    echo "_no rbac summary found_"
  fi
  echo
  echo "## NetworkPolicy"
  echo
  if [[ -f "$RES/network/SUMMARY.md" ]]; then
    tail -n +2 "$RES/network/SUMMARY.md"
  else
    echo "_no network summary found_"
  fi
  echo
  echo "## Exit codes"
  echo
  echo "- RBAC: \`$rbac_rc\`"
  echo "- NetworkPolicy: \`$np_rc\`"
} > "$RES/SUMMARY.md"

echo
echo "Wrote $RES/SUMMARY.md"
if [[ $rbac_rc -ne 0 || $np_rc -ne 0 ]]; then
  echo "FAILURES — rbac=$rbac_rc np=$np_rc" >&2
  exit 1
fi
