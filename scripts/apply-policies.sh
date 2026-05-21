#!/usr/bin/env bash
# Apply the 5 Cilium NetworkPolicy scenarios from PLAN.md.
# Order matters only for clarity; Cilium re-converges idempotently.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_DIR="$(cd "$SCRIPT_DIR/../policies" && pwd)"

POLICIES=(
  np-1-default-deny.yaml
  np-5-dns-egress.yaml
  np-2-frontend-to-api.yaml
  np-3-api-to-data.yaml
  np-4-cross-env-deny.yaml
)

for p in "${POLICIES[@]}"; do
  echo "→ apply $p"
  kubectl apply -f "$POLICY_DIR/$p"
done

echo
echo "→ Cluster-wide policies:"
kubectl get ciliumclusterwidenetworkpolicy

echo
echo "→ Namespaced policies:"
kubectl get ciliumnetworkpolicy --all-namespaces

echo
echo "Done."
