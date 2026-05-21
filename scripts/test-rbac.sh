#!/usr/bin/env bash
# Validate per-persona RBAC for the 7 Entra groups.
#
# Since we don't have credentials for each persona, we use SubjectAccessReview
# impersonation from an ops-admin context:
#   kubectl auth can-i <verb> <resource> -n <ns> --as=<oid> --as-group=<oid>
#
# Azure RBAC for Kubernetes Authorization checks the impersonated principal
# via the AKS authorization webhook, so impersonating by group OID is enough
# to validate the role assignments produced by setup-rbac.sh.
#
# Output:
#   tests/results/rbac/<persona>.json   — full per-check matrix
#   tests/results/rbac/SUMMARY.md       — human readable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/tests/results/rbac"
GROUPS_FILE="${GROUPS_FILE:-$HOME/workspace/tfvars/aks-lab-groups.env}"
mkdir -p "$OUT_DIR"

[[ -f "$GROUPS_FILE" ]] || { echo "missing $GROUPS_FILE — run setup-entra.sh first" >&2; exit 1; }
# shellcheck disable=SC1090
source "$GROUPS_FILE"

# Persona definitions:
#   name | oid | expected_ns_list (space sep) | denied_ns_list (space sep)
# Ops admin gets cluster-admin so we check a cluster-scope verb too.
PERSONAS=(
  "ops-admin|$AKS_OPS_ADMINS_OID|dev-frontend test-frontend prod-frontend dev-api test-api prod-api dev-data test-data prod-data|"
  "app-admin-frontend-nonprod|$AKS_APP_ADMINS_FRONTEND_NONPROD_OID|dev-frontend test-frontend|prod-frontend dev-api prod-api dev-data prod-data"
  "app-admin-frontend-prod|$AKS_APP_ADMINS_FRONTEND_PROD_OID|prod-frontend|dev-frontend test-frontend dev-api prod-api dev-data prod-data"
  "app-admin-api-nonprod|$AKS_APP_ADMINS_API_NONPROD_OID|dev-api test-api|prod-api dev-frontend prod-frontend dev-data prod-data"
  "app-admin-api-prod|$AKS_APP_ADMINS_API_PROD_OID|prod-api|dev-api test-api dev-frontend prod-frontend dev-data prod-data"
  "app-admin-data-nonprod|$AKS_APP_ADMINS_DATA_NONPROD_OID|dev-data test-data|prod-data dev-api prod-api dev-frontend prod-frontend"
  "app-admin-data-prod|$AKS_APP_ADMINS_DATA_PROD_OID|prod-data|dev-data test-data dev-api prod-api dev-frontend prod-frontend"
)

# Single can-i check → "yes"|"no" (always exits 0 via `|| true`).
check() {
  local oid="$1"; local verb="$2"; local resource="$3"; local ns="${4:-}"
  local nsflag=()
  [[ -n "$ns" ]] && nsflag=(-n "$ns")
  kubectl auth can-i "$verb" "$resource" \
    --as="$oid" --as-group="$oid" \
    "${nsflag[@]}" 2>/dev/null || true
}

emit_json_entry() {
  local key="$1" expected="$2" actual="$3"
  local pass=$([[ "$expected" == "$actual" ]] && echo true || echo false)
  printf '    {"check":"%s","expected":"%s","actual":"%s","pass":%s}' \
    "$key" "$expected" "$actual" "$pass"
}

SUMMARY="$OUT_DIR/SUMMARY.md"
{
  echo "# RBAC Test Results"
  echo
  echo "Generated: $(date -u +%FT%TZ)"
  echo
  echo "| Persona | Total | Passed | Failed |"
  echo "|---|---:|---:|---:|"
} > "$SUMMARY"

GRAND_TOTAL=0; GRAND_PASS=0; GRAND_FAIL=0

for entry in "${PERSONAS[@]}"; do
  IFS='|' read -r name oid allow_ns deny_ns <<<"$entry"
  out="$OUT_DIR/${name}.json"
  echo "→ $name ($oid)"

  total=0; passed=0; failed=0
  results=()

  # 1. Ops-admin only: cluster-scope check.
  if [[ "$name" == "ops-admin" ]]; then
    a=$(check "$oid" get nodes)
    exp="yes"
    total=$((total+1))
    [[ "$a" == "$exp" ]] && passed=$((passed+1)) || failed=$((failed+1))
    results+=("$(emit_json_entry "cluster:get nodes" "$exp" "$a")")
  fi

  # 2. Reader-style verbs in allowed namespaces → yes.
  for ns in $allow_ns; do
    for verb_res in "get:pods" "list:pods" "get:services" "list:deployments.apps"; do
      verb="${verb_res%%:*}"; res="${verb_res#*:}"
      a=$(check "$oid" "$verb" "$res" "$ns")
      # Ops-admin should see all; app-admins (RBAC Reader) too.
      exp="yes"
      total=$((total+1))
      [[ "$a" == "$exp" ]] && passed=$((passed+1)) || failed=$((failed+1))
      results+=("$(emit_json_entry "$ns:$verb $res" "$exp" "$a")")
    done

    # Write-style verb — ops-admin yes, app-admins (Reader) no.
    a=$(check "$oid" create pods "$ns")
    if [[ "$name" == "ops-admin" ]]; then exp="yes"; else exp="no"; fi
    total=$((total+1))
    [[ "$a" == "$exp" ]] && passed=$((passed+1)) || failed=$((failed+1))
    results+=("$(emit_json_entry "$ns:create pods" "$exp" "$a")")
  done

  # 3. Denied namespaces → reads should be "no" for app-admins.
  for ns in $deny_ns; do
    a=$(check "$oid" get pods "$ns")
    # ops-admin has no denied list; app-admins must be denied here.
    exp="no"
    total=$((total+1))
    [[ "$a" == "$exp" ]] && passed=$((passed+1)) || failed=$((failed+1))
    results+=("$(emit_json_entry "$ns:get pods (deny-expected)" "$exp" "$a")")
  done

  # Write JSON
  {
    echo "{"
    echo "  \"persona\": \"$name\","
    echo "  \"oid\": \"$oid\","
    echo "  \"timestamp\": \"$(date -u +%FT%TZ)\","
    echo "  \"total\": $total,"
    echo "  \"passed\": $passed,"
    echo "  \"failed\": $failed,"
    echo "  \"checks\": ["
    rcount=${#results[@]}
    for i in "${!results[@]}"; do
      printf '%s' "${results[$i]}"
      [[ $i -lt $((rcount-1)) ]] && echo "," || echo
    done
    echo "  ]"
    echo "}"
  } > "$out"

  echo "| $name | $total | $passed | $failed |" >> "$SUMMARY"
  GRAND_TOTAL=$((GRAND_TOTAL+total))
  GRAND_PASS=$((GRAND_PASS+passed))
  GRAND_FAIL=$((GRAND_FAIL+failed))
done

{
  echo
  echo "**Totals:** $GRAND_PASS/$GRAND_TOTAL passed ($GRAND_FAIL failed)"
  echo
  echo "## Notes"
  echo
  echo "- Impersonation uses Entra group OIDs as both \`--as\` and \`--as-group\`."
  echo "- Azure RBAC for Kubernetes Authorization evaluates the impersonated principal via the AKS webhook."
  echo "- App-admin personas have the **Azure Kubernetes Service RBAC Reader** role at their scoped namespace(s), which permits read verbs but not create/update/delete."
  echo "- Ops-admin has **Azure Kubernetes Service RBAC Cluster Admin** + **Cluster Admin Role** at the cluster scope."
} >> "$SUMMARY"

echo
echo "→ $GRAND_PASS/$GRAND_TOTAL passed. Details in $OUT_DIR/"
[[ $GRAND_FAIL -eq 0 ]]
