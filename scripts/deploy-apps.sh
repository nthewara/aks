#!/usr/bin/env bash
# Deploy 9 namespaces + 3 apps (frontend, api, data) across 3 envs (dev, test, prod).
# Manifests are templated with `__ENV__` and substituted per-env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_DIR="$REPO_ROOT/manifests"

ENVS=(dev test prod)
APPS=(frontend api data)

echo "→ Applying namespaces"
kubectl apply -f "$MANIFEST_DIR/namespaces.yaml"

for env in "${ENVS[@]}"; do
  for app in "${APPS[@]}"; do
    echo "→ Applying $app in $env-$app"
    sed "s/__ENV__/$env/g" "$MANIFEST_DIR/$app.yaml" | kubectl apply -f -
  done
done

echo
echo "→ Waiting for deployments to roll out (timeout 5m each)"
for env in "${ENVS[@]}"; do
  for app in "${APPS[@]}"; do
    ns="$env-$app"
    kubectl -n "$ns" rollout status deploy/"$app" --timeout=5m
  done
done

echo
echo "→ Pod summary"
for env in "${ENVS[@]}"; do
  for app in "${APPS[@]}"; do
    ns="$env-$app"
    kubectl -n "$ns" get pods -o wide --no-headers | awk -v ns="$ns" '{print ns"\t"$1"\t"$3}'
  done
done

echo
echo "Done."
