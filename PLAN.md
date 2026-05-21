# PLAN.md — AKS Lab

## Goals

1. Deploy an **AKS cluster** with **Azure CNI Overlay + Cilium dataplane** (Microsoft "Azure CNI powered by Cilium").
2. Demonstrate **pod-to-pod and namespace-to-namespace traffic restriction** using **CiliumNetworkPolicy** (CNP) and Kubernetes `NetworkPolicy`.
3. Integrate **Entra ID** for both authentication and authorization:
   - **AKS-managed Entra** for cluster login (no local accounts).
   - **Azure RBAC for Kubernetes Authorization** (no Kubernetes ClusterRoleBindings managed by us).
   - Two persona Entra groups:
     - `aks-ops-admins` → **full cluster admin** at the AKS resource scope + Kubernetes data-plane admin.
     - `aks-app-admins` → **namespace-scoped read-only** on their owned namespaces only.
4. **Three apps in three namespaces** (`frontend`, `api`, `data`) hosted in the same cluster.
5. **Validation built into the deployment** — every issue carries a test script that writes results back into `tests/results/` and the PR description.

## High-level Architecture

```
Entra ID
├── group: aks-ops-admins     → Azure RBAC: "Azure Kubernetes Service RBAC Cluster Admin" @ cluster
│                              + "Azure Kubernetes Service Cluster Admin Role" @ cluster
└── group: aks-app-admins     → Azure RBAC: "Azure Kubernetes Service RBAC Reader" @ namespace scope
                               (one binding per app namespace)

Azure:
  RG: aks-lab-<suffix>
  ├── VNet 10.50.0.0/16
  │   └── snet-aks 10.50.0.0/22  (overlay pod CIDR 10.244.0.0/16, separate from VNet)
  ├── Log Analytics workspace
  └── AKS cluster (1.30+)
       ├── networkPlugin=azure  networkPluginMode=overlay  networkDataplane=cilium
       ├── managed Entra: enableAzureRBAC=true, adminGroupObjectIDs=[ ops-admins ]
       ├── system nodepool: 2× Standard_D2s_v5 (Linux, AzureLinux)
       └── apps:
            ├── ns/frontend  (nginx hello)
            ├── ns/api       (httpbin)
            └── ns/data      (redis)
```

## Personas

| Persona | Entra Group | Azure RBAC roles | Scope | What they can do |
|---|---|---|---|---|
| Ops admin | `aks-ops-admins` | `Azure Kubernetes Service RBAC Cluster Admin` + `Azure Kubernetes Service Cluster Admin Role` | Cluster (AKS resource) | Full kubectl admin; pull admin kubeconfig; cluster lifecycle |
| App admin | `aks-app-admins` | `Azure Kubernetes Service RBAC Reader` | Each app namespace (one binding per ns) | `kubectl get/describe` namespace-scoped only; no other namespaces, no cluster-scoped reads |

`aks-app-admins` does NOT get `Azure Kubernetes Service Cluster User Role` at cluster scope; instead they get it on the cluster + RBAC Reader on each namespace, which is the supported scope-down pattern.

## Cilium Network Policy Plan

We exercise four CNP scenarios. Each one ships with a test script that emits PASS/FAIL into `tests/results/`.

| # | Policy | Expected |
|---|---|---|
| NP-1 | `default-deny` in every ns (deny all ingress + egress) | All pod-to-pod traffic blocked except where explicitly allowed |
| NP-2 | `frontend → api` allow on TCP/80 (pod label `app=httpbin`) | frontend curl httpbin → 200; api → data still blocked |
| NP-3 | `api → data` allow on TCP/6379 (redis) | api can talk to redis; frontend cannot |
| NP-4 | Cross-namespace deny: `api → kube-system` blocked except DNS to `kube-dns` (UDP/53) | Pods resolve DNS, but no other cross-ns chatter |

Each scenario uses ephemeral debug pods + `kubectl exec` to run `curl`/`nc`/`redis-cli` and asserts via exit codes.

## Bicep Layout

```
bicep/
├── main.bicep              # orchestrator
└── modules/
    ├── vnet.bicep
    ├── log-analytics.bicep
    ├── entra-groups.bicep   # creates 2 Entra groups (via AAD Microsoft.Graph extension OR az ad cli)
    ├── aks.bicep            # AKS with Cilium overlay + managed Entra + Azure RBAC
    └── rbac.bicep           # Azure role assignments for the two personas
```

> Note: Entra groups + role assignments to AAD principals are deployed via az CLI side-car in `scripts/deploy.sh`, since Bicep's Microsoft.Graph types still require a special extension and many tenants restrict it. Group object IDs are then passed back into `aks.bicep` as parameters.

## Bash Scripts

| Script | Purpose |
|---|---|
| `scripts/deploy.sh` | End-to-end: create Entra groups → deploy bicep → install CNPs → deploy apps |
| `scripts/test-rbac.sh` | Validate persona access using `az aks get-credentials` + `kubectl auth can-i` |
| `scripts/test-network-policy.sh` | Run NP-1..NP-4 scenarios, write results to `tests/results/<scenario>.json` + `.md` |
| `scripts/run-tests.sh` | Wrapper that runs both test scripts and updates `tests/results/SUMMARY.md` |
| `scripts/destroy.sh` | `az group delete --no-wait` + Entra group cleanup + tracker update |

## Phased Delivery (one GitHub issue per phase)

| # | Issue | Branch | Output |
|---|---|---|---|
| 1 | Bicep scaffolding: VNet, LAW, AKS (Cilium overlay, managed Entra, Azure RBAC) | `feat/01-bicep-aks` | deployable cluster (no apps, no policies) |
| 2 | Entra groups + Azure RBAC bindings (ops-admin cluster scope, app-admin namespace scope) | `feat/02-entra-rbac` | groups created, role assignments in place |
| 3 | Three namespaces + sample apps (`frontend`, `api`, `data`) | `feat/03-namespaces-apps` | apps running |
| 4 | Cilium network policies (NP-1..NP-4) | `feat/04-cilium-policies` | policies applied |
| 5 | RBAC test harness (`scripts/test-rbac.sh`) — validates ops-admin/app-admin behaviour | `feat/05-rbac-tests` | test results in `tests/results/rbac/` |
| 6 | Network policy test harness (`scripts/test-network-policy.sh`) | `feat/06-np-tests` | test results in `tests/results/network/` |
| 7 | Architecture diagram (Mermaid) + final docs | `feat/07-docs-diagram` | `ARCHITECTURE.md` + README polish |
| 8 | Lab tracker entry + tear-down script | `feat/08-teardown` | `scripts/destroy.sh` |

## Validation Results Layout

```
tests/
├── results/
│   ├── SUMMARY.md             # high-level PASS/FAIL table (auto-generated)
│   ├── rbac/
│   │   ├── ops-admin.json
│   │   └── app-admin.json
│   └── network/
│       ├── NP-1-default-deny.json
│       ├── NP-2-frontend-to-api.json
│       ├── NP-3-api-to-data.json
│       └── NP-4-cross-ns-deny.json
└── fixtures/                  # debug pods, test manifests
```

Test scripts MUST commit their results JSON + Markdown into the PR for that issue so reviewers see real evidence.

## Cost (rough, australiaeast)

- AKS control plane (Free SKU): $0
- 2× D2s_v5 nodes: ~$6/day
- Log Analytics ingest: <$1/day at lab volume
- **~$7/day**. Stop node pool when idle to drop near-zero.

## Open Questions

1. **Naming for Entra groups** — `aks-ops-admins` / `aks-app-admins` OK, or prefix with project tag?
2. **Cluster admin scope** — Cluster-scope Azure RBAC Cluster Admin is fine for ops, or should we constrain to a single management RG hosting all clusters?
3. **AzureLinux vs Ubuntu nodes** — default to AzureLinux (smaller attack surface) unless you want Ubuntu for tooling familiarity.

Default answers assumed in the issues, ping if you want changes.
