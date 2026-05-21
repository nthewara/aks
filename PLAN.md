# PLAN.md — AKS Lab

## Goals

1. Deploy an **AKS cluster** with **Azure CNI Overlay + Cilium dataplane** ("Azure CNI powered by Cilium").
2. Host **three apps across three environments in the same cluster** using a **`<env>-<app>` namespace matrix** (9 namespaces total). This is the pattern Microsoft Learn recommends — see *Notes from MS Learn* at the bottom.
3. Demonstrate **multi-layer NetworkPolicy** with Cilium:
   - Default-deny per namespace
   - Intra-environment allow flows (`frontend → api → data`)
   - **Cross-environment deny** (`dev` ↔ `prod` must never talk)
   - DNS allow to kube-dns
4. Demonstrate **Entra ID integration** for both authN and authZ:
   - AKS-managed Entra, `disableLocalAccounts=true`
   - Azure RBAC for Kubernetes Authorization (no in-cluster RoleBindings managed by us)
   - **Ops admins** = full cluster admin
   - **App admins** = namespace-scoped RBAC Reader, scoped per-app **and** per-env-tier (non-prod vs prod)
5. **Validation is part of the build** — every issue ships test scripts that write results into `tests/results/` and reference them in the PR.

## High-level Architecture

```
Entra ID
├── aks-ops-admins                            → AKS RBAC Cluster Admin + Cluster Admin Role @ cluster
├── aks-app-admins-frontend-nonprod           → AKS RBAC Reader @ dev-frontend, test-frontend
├── aks-app-admins-frontend-prod              → AKS RBAC Reader @ prod-frontend
├── aks-app-admins-api-nonprod                → AKS RBAC Reader @ dev-api, test-api
├── aks-app-admins-api-prod                   → AKS RBAC Reader @ prod-api
├── aks-app-admins-data-nonprod               → AKS RBAC Reader @ dev-data, test-data
└── aks-app-admins-data-prod                  → AKS RBAC Reader @ prod-data

Azure:
  RG: aks-lab-<suffix>
  ├── VNet 10.50.0.0/16  /  snet-aks 10.50.0.0/22
  ├── Log Analytics workspace
  └── AKS (1.30+, Azure CNI Overlay + Cilium, managed Entra + Azure RBAC, AzureLinux, 2× D2s_v5)
       Namespaces (each labelled `environment=...` and `app=...`):
        dev-frontend   test-frontend   prod-frontend
        dev-api        test-api        prod-api
        dev-data       test-data       prod-data
```

## Namespace Matrix

3 environments × 3 apps = **9 namespaces**.

| | frontend (nginx) | api (httpbin) | data (redis) |
|---|---|---|---|
| **dev** | `dev-frontend` | `dev-api` | `dev-data` |
| **test** | `test-frontend` | `test-api` | `test-data` |
| **prod** | `prod-frontend` | `prod-api` | `prod-data` |

Every namespace carries labels:
- `environment=dev|test|prod`
- `app=frontend|api|data`
- `purpose=lab`

These labels are the only thing NetworkPolicies and RBAC bindings target — namespace names are free to evolve.

> **Real-world caveat**: in production, MS Learn strongly recommends putting *prod* in a separate cluster from non-prod for blast-radius, upgrade cadence, and compliance reasons. We're keeping it in one cluster here because this is a teaching lab — the patterns transfer directly.

## Personas + RBAC

| Persona | Entra group | Azure RBAC role(s) | Scope |
|---|---|---|---|
| Ops admin | `aks-ops-admins` | `Azure Kubernetes Service RBAC Cluster Admin` + `Azure Kubernetes Service Cluster Admin Role` | Cluster (AKS resource) |
| App admin — frontend non-prod | `aks-app-admins-frontend-nonprod` | `Azure Kubernetes Service Cluster User Role` @ cluster + `Azure Kubernetes Service RBAC Reader` @ ns | `/subscriptions/.../clusters/<c>/namespaces/{dev,test}-frontend` |
| App admin — frontend prod | `aks-app-admins-frontend-prod` | same role pair | `/.../namespaces/prod-frontend` |
| (same shape for `api` and `data`) | | | |

7 Entra groups total (1 ops + 6 app-admin variants). The split of `nonprod` vs `prod` is what lets you grant a team day-to-day access in dev/test without unlocking prod.

## Cilium Network Policy Plan

We exercise five policy scenarios. Each one ships a test script that emits PASS/FAIL into `tests/results/`.

| # | Policy | Selector | Expected |
|---|---|---|---|
| NP-1 | Default-deny ingress+egress in every lab ns | `namespaceSelector: purpose=lab` | All pod-to-pod traffic blocked |
| NP-2 | Allow `frontend → api` on TCP/80 within same env | matchLabels: `environment`, `app=frontend → api` | curl 200 within env; cross-env still blocked |
| NP-3 | Allow `api → data` on TCP/6379 within same env | same | redis ping OK within env |
| NP-4 | **Cross-environment deny** — `dev-*` ↔ `prod-*` traffic blocked even where labels would otherwise allow | namespaceSelector | Killer demo: dev-frontend → prod-api times out |
| NP-5 | Allow DNS egress to kube-dns (UDP/53) from any lab ns | namespaceSelector | DNS resolution works everywhere |

Implementation: Cilium CRDs (`CiliumNetworkPolicy`) — we use `namespaceSelector` + `endpointSelector` together, which standard k8s NetworkPolicy can't express cleanly across namespaces. NP-4 is specifically why we need Cilium-native and not just `networking.k8s.io/v1`.

## Bicep Layout

```
bicep/
├── main.bicep
└── modules/
    ├── vnet.bicep
    ├── log-analytics.bicep
    ├── aks.bicep         # Cilium overlay + managed Entra + Azure RBAC
    └── rbac.bicep        # role assignments (group object IDs come from setup-entra.sh)
```

Entra group creation is **out-of-band via az CLI** in `scripts/setup-entra.sh`, because Bicep+Microsoft.Graph still needs the extension and many tenants restrict it. The group object IDs are written to a tfvars-style `groups.env` file in `~/workspace/tfvars/aks-lab-groups.env`, then passed into the Bicep deploy.

## Bash Scripts

| Script | Purpose |
|---|---|
| `scripts/setup-entra.sh` | Create the 7 Entra groups, write `~/workspace/tfvars/aks-lab-groups.env` |
| `scripts/deploy.sh` | `az deployment group create` with the bicep + group OIDs |
| `scripts/deploy-apps.sh` | `kubectl apply` 9 namespaces + 3 apps × 3 envs |
| `scripts/apply-policies.sh` | Apply CiliumNetworkPolicy CRDs |
| `scripts/setup-rbac.sh` | Assign per-namespace AKS RBAC Reader role to each app-admin group |
| `scripts/test-rbac.sh` | Validate persona access with `kubectl auth can-i` |
| `scripts/test-network-policy.sh` | Run NP-1..NP-5 with ephemeral netshoot pods, write results |
| `scripts/run-tests.sh` | Wrapper: rbac + np + refresh `tests/results/SUMMARY.md` |
| `scripts/destroy.sh` | `az group delete --no-wait` + delete the 7 Entra groups + tracker update |

## Phased Delivery (issues track these)

| # | Issue | Branch | Output |
|---|---|---|---|
| 1 | Bicep: VNet + LAW + AKS (Cilium overlay, managed Entra, Azure RBAC) | `feat/01-bicep-aks` | deployable cluster, placeholder admin group OID |
| 2 | Entra groups + role assignments (`setup-entra.sh`, `setup-rbac.sh`) | `feat/02-entra-rbac` | 7 groups + roles, AKS re-deployed with real admin group |
| 3 | 9 namespaces + 3 apps deployed across 3 envs | `feat/03-namespaces-apps` | apps running |
| 4 | Cilium policies NP-1..NP-5 (incl. cross-env deny) | `feat/04-cilium-policies` | policies applied |
| 5 | RBAC test harness (ops + 6 app-admin variants) | `feat/05-rbac-tests` | results under `tests/results/rbac/` |
| 6 | Network policy test harness | `feat/06-np-tests` | results under `tests/results/network/` |
| 7 | Architecture diagram + final docs | `feat/07-docs-diagram` | ARCHITECTURE.md + README polish |
| 8 | Tear-down + lab tracker entry | `feat/08-teardown` | `scripts/destroy.sh` |

## Validation Results Layout

```
tests/
├── results/
│   ├── SUMMARY.md
│   ├── rbac/
│   │   ├── ops-admin.json
│   │   ├── app-admin-frontend-nonprod.json
│   │   └── ... (6 more)
│   └── network/
│       ├── NP-1-default-deny.json
│       ├── NP-2-frontend-to-api.json
│       ├── NP-3-api-to-data.json
│       ├── NP-4-cross-env-deny.json
│       └── NP-5-dns.json
└── fixtures/
```

Test scripts MUST commit their results JSON + Markdown into the PR for that issue.

## Cost (rough, australiaeast)

- AKS control plane (Free SKU): $0
- 2× D2s_v5 nodes: ~$6/day
- Log Analytics ingest: <$1/day at lab volume
- **~$7/day**. Stop the node pool when idle to drop near-zero.

## Notes from MS Learn (why this design)

- **[Cluster isolation best practices](https://learn.microsoft.com/en-us/azure/aks/operator-best-practices-cluster-isolation)** — namespace is the *primary* logical isolation boundary; "use a single AKS cluster for multiple workloads, teams, or environments".
- **[AKS multitenant guidance](https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/service/aks)** — "separate each tenant and its Kubernetes resources into dedicated namespaces"; enforce isolation with RBAC + NetworkPolicy.
- **[Advanced AKS microservices reference](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks-microservices/aks-microservices-advanced)** — Microsoft's own reference uses `backend-dev`, `backend-prod` style namespaces (env + app).
- **[NetworkPolicy best practices](https://learn.microsoft.com/en-us/azure/aks/network-policy-best-practices)** — recommends combining namespace-scope segmentation with pod-label microsegmentation, exactly what NP-1..NP-5 do.
- **[Managed Namespaces](https://learn.microsoft.com/en-us/azure/aks/managed-namespaces)** — newer AKS feature that gives ARM-managed per-namespace quotas + default NetworkPolicy + RBAC. We don't use it in v1 (kubectl-driven keeps the lab simpler), but a follow-up issue can swap it in.

## Open / Locked Decisions

- ✅ `<env>-<app>` namespaces (9 total) — locked.
- ✅ AzureLinux nodepool.
- ✅ Ops-admin role scoped at cluster.
- ✅ App-admin groups split per-app × `nonprod` vs `prod`.
- ❓ Prod-in-its-own-cluster? Keeping prod inside this cluster for the lab; will call this out in `ARCHITECTURE.md` as a known compromise vs the MS Learn recommendation.
