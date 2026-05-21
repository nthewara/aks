# Network Policy Test Results

Generated: 2026-05-21T11:55:33Z

| ID | Description | Expected | Actual | Result |
|---|---|---|---|---|
| NP-1 | default-deny: dev-frontend → dev-data:6379 has no allow → DENY | DENY | DENY | ✅ |
| NP-2-dev | frontend → api allowed (dev) | ALLOW | ALLOW | ✅ |
| NP-2-test | frontend → api allowed (test) | ALLOW | ALLOW | ✅ |
| NP-2-prod | frontend → api allowed (prod) | ALLOW | ALLOW | ✅ |
| NP-3-dev | api → data allowed (dev) | ALLOW | ALLOW | ✅ |
| NP-3-test | api → data allowed (test) | ALLOW | ALLOW | ✅ |
| NP-3-prod | api → data allowed (prod) | ALLOW | ALLOW | ✅ |
| NP-4-dev-to-prod | cross-env deny: dev-frontend → prod-api | DENY | DENY | ✅ |
| NP-4-prod-to-dev | cross-env deny: prod-frontend → dev-api | DENY | DENY | ✅ |
| NP-5-dev | DNS works in dev-frontend | ALLOW | ALLOW | ✅ |
| NP-5-prod | DNS works in prod-data | ALLOW | ALLOW | ✅ |

**Totals:** 11 passed, 0 failed (of 11)

## Notes

- Probes run as ephemeral `curlimages/curl:8.10.1` pods (`kubectl run --rm`).
- TCP probes use `curl telnet://`; HTTP probes use `curl http://`.
- A timeout (>5s) is classified as DENY — Cilium drops are silent.
- DNS probes succeed if curl can resolve the target FQDN, regardless of TLS outcome.
