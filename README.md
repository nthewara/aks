# aks — AKS Lab: Cilium Network Policies + Entra RBAC

Hands-on lab demonstrating two AKS security primitives, built with **Bicep** (infra) and **bash** (deploy + test):

1. **AKS with Azure CNI Overlay + Cilium dataplane** → pod-to-pod and namespace-to-namespace restriction with **CiliumNetworkPolicy**.
2. **Entra ID integration** → AKS-managed Entra + Azure RBAC for Kubernetes Authorization, with two persona Entra groups (`aks-ops-admins`, `aks-app-admins`) mapped to scoped roles.

Three sample apps live in three namespaces (`frontend`, `api`, `data`) to drive the policy + RBAC tests.

See **[PLAN.md](./PLAN.md)** for the full design and phased plan.
See **[ARCHITECTURE.md](./ARCHITECTURE.md)** for diagrams.

## Status
🚧 Phase 0 — scaffolding + plan. Issues filed, no Azure resources deployed yet.

## Quick start (planned)
```bash
RG=aks-lab-$(openssl rand -hex 2)
az group create -n $RG -l australiaeast
./scripts/deploy.sh $RG
./scripts/run-tests.sh $RG
```
