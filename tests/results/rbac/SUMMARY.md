# RBAC Test Results

Generated: 2026-05-21T12:01:33Z

| Persona | Total | Passed | Failed |
|---|---:|---:|---:|
| ops-admin | 46 | 46 | 0 |
| app-admin-frontend-nonprod | 15 | 15 | 0 |
| app-admin-frontend-prod | 11 | 11 | 0 |
| app-admin-api-nonprod | 15 | 15 | 0 |
| app-admin-api-prod | 11 | 11 | 0 |
| app-admin-data-nonprod | 15 | 15 | 0 |
| app-admin-data-prod | 11 | 11 | 0 |

**Totals:** 124/124 passed (0 failed)

## Notes

- Impersonation uses Entra group OIDs as both `--as` and `--as-group`.
- Azure RBAC for Kubernetes Authorization evaluates the impersonated principal via the AKS webhook.
- App-admin personas have the **Azure Kubernetes Service RBAC Reader** role at their scoped namespace(s), which permits read verbs but not create/update/delete.
- Ops-admin has **Azure Kubernetes Service RBAC Cluster Admin** + **Cluster Admin Role** at the cluster scope.
