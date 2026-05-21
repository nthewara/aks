#!/usr/bin/env bash
# Assign Azure RBAC roles to the Entra groups produced by setup-entra.sh.
# Run AFTER the AKS cluster is deployed.
set -euo pipefail

RG="${1:-${RG:-}}"
GROUPS_FILE="${GROUPS_FILE:-$HOME/workspace/tfvars/aks-lab-groups.env}"

if [[ -z "$RG" ]]; then
  echo "usage: $0 <resource-group>" >&2
  exit 1
fi
[[ -f "$GROUPS_FILE" ]] || { echo "missing groups file: $GROUPS_FILE — run scripts/setup-entra.sh first" >&2; exit 1; }
# shellcheck disable=SC1090
source "$GROUPS_FILE"

CLUSTER=$(az aks list -g "$RG" --query "[0].name" -o tsv)
CLUSTER_ID=$(az aks show -g "$RG" -n "$CLUSTER" --query id -o tsv)
echo "Cluster: $CLUSTER_ID"

assign() {
  local oid="$1"; local role="$2"; local scope="$3"
  echo "  · $role @ $scope"
  az role assignment create --assignee-object-id "$oid" --assignee-principal-type Group \
    --role "$role" --scope "$scope" -o none 2>&1 | grep -v "already exists" || true
}

# ops admin: full cluster
echo "→ ops-admins"
assign "$AKS_OPS_ADMINS_OID" "Azure Kubernetes Service RBAC Cluster Admin" "$CLUSTER_ID"
assign "$AKS_OPS_ADMINS_OID" "Azure Kubernetes Service Cluster Admin Role" "$CLUSTER_ID"

# app admins: cluster User Role for kubeconfig + RBAC Reader per namespace
# (parallel arrays — works on bash 3.2)
VARS=(
  "AKS_APP_ADMINS_FRONTEND_NONPROD_OID|dev-frontend test-frontend"
  "AKS_APP_ADMINS_FRONTEND_PROD_OID|prod-frontend"
  "AKS_APP_ADMINS_API_NONPROD_OID|dev-api test-api"
  "AKS_APP_ADMINS_API_PROD_OID|prod-api"
  "AKS_APP_ADMINS_DATA_NONPROD_OID|dev-data test-data"
  "AKS_APP_ADMINS_DATA_PROD_OID|prod-data"
)

for entry in "${VARS[@]}"; do
  var="${entry%%|*}"
  nslist="${entry#*|}"
  oid="$(eval echo \"\${$var:-}\")"
  [[ -z "$oid" ]] && { echo "skip $var (no OID)"; continue; }
  echo "→ $var ($oid)"
  assign "$oid" "Azure Kubernetes Service Cluster User Role" "$CLUSTER_ID"
  for ns in $nslist; do
    assign "$oid" "Azure Kubernetes Service RBAC Reader" "${CLUSTER_ID}/namespaces/${ns}"
  done
done

echo "Done."
