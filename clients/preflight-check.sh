#!/usr/bin/env bash
# Run this BEFORE installing any log-forwarding agent (rsyslog forward,
# NXLog, Fluent Bit, etc.) on a Linux/macOS device you want to monitor.
# It confirms the device can actually reach the collector over the
# network first - the single most common source of "it's not working"
# once an agent is configured, and one no agent-side troubleshooting
# can fix if the answer is no.
set -uo pipefail

COLLECTOR="${1:-}"
if [[ -z "$COLLECTOR" ]]; then
  echo "Usage: $0 <collector-ip-or-hostname>"
  exit 1
fi

pass=0
fail=0

check_tcp() {
  local port="$1" label="$2"
  if timeout 3 bash -c "echo >/dev/tcp/${COLLECTOR}/${port}" 2>/dev/null; then
    echo "[PASS] TCP ${port} (${label}) reachable"
    ((pass++))
  else
    echo "[FAIL] TCP ${port} (${label}) NOT reachable"
    ((fail++))
  fi
}

echo "Checking connectivity to syslog collector at ${COLLECTOR} ..."
echo

if ping -c 1 -W 2 "$COLLECTOR" >/dev/null 2>&1; then
  echo "[PASS] ICMP ping reachable"
  ((pass++))
else
  echo "[WARN] ICMP ping failed (not fatal - some networks block ping while still allowing the ports below)"
fi

check_tcp 514 "syslog TCP"
check_tcp 20514 "syslog RELP"
check_tcp 3100 "Loki push API"

echo
echo "UDP 514 (syslog UDP) can't be definitively tested without a listener ack -"
echo "if the TCP 514 check above passed, UDP to the same host/port is almost"
echo "always fine too (same host, same firewall path)."

echo
echo "Result: ${pass} passed, ${fail} failed."
if (( fail > 0 )); then
  echo "Fix network reachability (routing/firewall) before configuring any agent."
  exit 1
else
  echo "Network path looks good - safe to proceed with agent setup."
fi
