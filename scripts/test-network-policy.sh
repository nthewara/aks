#!/usr/bin/env bash
# Network policy validation for NP-1..NP-5.
#
# Strategy: spin up an ephemeral curlimages/curl pod inside a source
# namespace and try to reach a target service/IP. Expected pass/fail per
# scenario is encoded in the CASES table below. Results are persisted as
# tests/results/network/NP-*.json + tests/results/network/SUMMARY.md.
#
# Curl runs with --max-time 5 — any connect that takes longer is treated
# as a block (NetworkPolicy denies usually appear as timeouts, not RSTs).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/tests/results/network"
mkdir -p "$OUT_DIR"

CURL_IMG="curlimages/curl:8.10.1"
TIMEOUT=5

# probe <id> <source-ns> <target-host> <port> <protocol: http|tcp|dns>
# Echoes one of: ALLOW | DENY | ERROR
# - ALLOW = traffic reached the target (200 or open TCP or DNS answer)
# - DENY  = expected NetworkPolicy block (timeout or refused)
probe() {
  local sid="$1" sns="$2" target="$3" port="$4" proto="$5"
  local podname="np-probe-${sid}-$RANDOM"
  local cmd
  case "$proto" in
    http)
      cmd="curl -sS -o /dev/null -w '%{http_code}\n' --max-time $TIMEOUT http://${target}:${port}/"
      ;;
    tcp)
      # nc isn't in curlimages/curl; use bash /dev/tcp instead via a busybox-ish env.
      # Fallback to curl telnet:// which does a raw TCP connect.
      cmd="curl -sS --max-time $TIMEOUT -o /dev/null telnet://${target}:${port}"
      ;;
    dns)
      cmd="curl -sS --max-time $TIMEOUT -o /dev/null https://${target} || echo DNS-FAILED"
      ;;
  esac
  local raw rc
  raw=$(kubectl run "$podname" \
        --rm -i --restart=Never --quiet \
        --image="$CURL_IMG" \
        -n "$sns" \
        --command -- sh -c "$cmd" 2>&1 || true)
  # `kubectl run` exit code reflects the container's, but the wrapper masks
  # it; parse the body. We classify:
  case "$proto" in
    http)
      if echo "$raw" | grep -Eq '^[1-5][0-9][0-9]$'; then echo ALLOW; else echo DENY; fi
      ;;
    tcp)
      # telnet:// returns 0 on connect and non-empty/empty output on failure.
      # If output contains "Connection timed out" / "Could not resolve" / "Failed to connect" → DENY.
      if echo "$raw" | grep -qiE 'timed out|could not resolve|failed to connect|Couldn'\''t connect'; then
        echo DENY
      else
        echo ALLOW
      fi
      ;;
    dns)
      if echo "$raw" | grep -qi "could not resolve\|dns-failed\|name or service not known"; then
        echo DENY
      else
        echo ALLOW
      fi
      ;;
  esac
}

write_result() {
  local id="$1" desc="$2" expected="$3" actual="$4" details="$5"
  local pass=$([[ "$expected" == "$actual" ]] && echo true || echo false)
  cat > "$OUT_DIR/${id}.json" <<JSON
{
  "id": "$id",
  "description": "$desc",
  "expected": "$expected",
  "actual": "$actual",
  "pass": $pass,
  "details": "$details",
  "timestamp": "$(date -u +%FT%TZ)"
}
JSON
}

# ─── Case definitions ───────────────────────────────────────────────
# id | description | source-ns | target | port | proto | expected
CASES=(
  # NP-1: with all policies applied, an *unrelated* pair (frontend → data)
  # has no allow rule, so it must be denied.
  "NP-1|default-deny: dev-frontend → dev-data:6379 has no allow → DENY|dev-frontend|data.dev-data.svc.cluster.local|6379|tcp|DENY"
  # NP-2: allowed same-env frontend → api on 80.
  "NP-2-dev|frontend → api allowed (dev)|dev-frontend|api.dev-api.svc.cluster.local|80|http|ALLOW"
  "NP-2-test|frontend → api allowed (test)|test-frontend|api.test-api.svc.cluster.local|80|http|ALLOW"
  "NP-2-prod|frontend → api allowed (prod)|prod-frontend|api.prod-api.svc.cluster.local|80|http|ALLOW"
  # NP-3: allowed same-env api → data on 6379.
  "NP-3-dev|api → data allowed (dev)|dev-api|data.dev-data.svc.cluster.local|6379|tcp|ALLOW"
  "NP-3-test|api → data allowed (test)|test-api|data.test-data.svc.cluster.local|6379|tcp|ALLOW"
  "NP-3-prod|api → data allowed (prod)|prod-api|data.prod-data.svc.cluster.local|6379|tcp|ALLOW"
  # NP-4: cross-env deny — dev-frontend → prod-api must be blocked.
  "NP-4-dev-to-prod|cross-env deny: dev-frontend → prod-api|dev-frontend|api.prod-api.svc.cluster.local|80|http|DENY"
  "NP-4-prod-to-dev|cross-env deny: prod-frontend → dev-api|prod-frontend|api.dev-api.svc.cluster.local|80|http|DENY"
  # NP-5: DNS should resolve from any lab pod.
  "NP-5-dev|DNS works in dev-frontend|dev-frontend|kubernetes.default.svc.cluster.local|443|dns|ALLOW"
  "NP-5-prod|DNS works in prod-data|prod-data|kubernetes.default.svc.cluster.local|443|dns|ALLOW"
)

SUMMARY="$OUT_DIR/SUMMARY.md"
{
  echo "# Network Policy Test Results"
  echo
  echo "Generated: $(date -u +%FT%TZ)"
  echo
  echo "| ID | Description | Expected | Actual | Result |"
  echo "|---|---|---|---|---|"
} > "$SUMMARY"

PASS=0; FAIL=0
for c in "${CASES[@]}"; do
  IFS='|' read -r id desc sns target port proto expected <<<"$c"
  echo "→ $id ($sns → $target:$port/$proto, expect $expected)"
  actual=$(probe "$id" "$sns" "$target" "$port" "$proto")
  details="$sns → $target:$port/$proto"
  write_result "$id" "$desc" "$expected" "$actual" "$details"

  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS+1))
    mark="✅"
  else
    FAIL=$((FAIL+1))
    mark="❌"
  fi
  echo "| $id | $desc | $expected | $actual | $mark |" >> "$SUMMARY"
done

{
  echo
  echo "**Totals:** $PASS passed, $FAIL failed (of $((PASS+FAIL)))"
  echo
  echo "## Notes"
  echo
  echo "- Probes run as ephemeral \`$CURL_IMG\` pods (\`kubectl run --rm\`)."
  echo "- TCP probes use \`curl telnet://\`; HTTP probes use \`curl http://\`."
  echo "- A timeout (>${TIMEOUT}s) is classified as DENY — Cilium drops are silent."
  echo "- DNS probes succeed if curl can resolve the target FQDN, regardless of TLS outcome."
} >> "$SUMMARY"

echo
echo "→ $PASS/$((PASS+FAIL)) passed. Details in $OUT_DIR/"
[[ $FAIL -eq 0 ]]
