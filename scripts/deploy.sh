#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/deploy.sh <resource-group> [prefix] [ops-admin-group-oid,...]
RG="${1:-${RG:-}}"
PREFIX="${2:-${PREFIX:-akslab}}"
OPS_OIDS="${3:-${OPS_ADMIN_GROUP_OIDS:-}}"

if [[ -z "$RG" ]]; then
  echo "usage: $0 <resource-group> [prefix] [ops-admin-group-oid,...]" >&2
  exit 1
fi

# Build array param for bicep
if [[ -n "$OPS_OIDS" ]]; then
  OIDS_JSON=$(python3 -c "import sys,json; print(json.dumps([x.strip() for x in sys.argv[1].split(',') if x.strip()]))" "$OPS_OIDS")
else
  OIDS_JSON='[]'
fi

echo "Deploying AKS lab to RG=$RG prefix=$PREFIX opsAdminGroupOIDs=$OIDS_JSON"

az deployment group create \
  -g "$RG" \
  -n "aks-lab-phase1" \
  -f bicep/main.bicep \
  -p prefix="$PREFIX" \
     opsAdminGroupObjectIds="$OIDS_JSON" \
  --no-wait

echo "Submitted. Watch with:"
echo "  az deployment group show -g $RG -n aks-lab-phase1 --query properties.provisioningState -o tsv"
