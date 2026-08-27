#!/usr/bin/env bash
# Sends a batch of realistic RFC5424 syslog messages to the local rsyslog
# listener so you can verify the rsyslog -> Promtail -> Loki -> Grafana
# pipeline end to end without needing real remote devices.
set -euo pipefail

TARGET_HOST="${1:-127.0.0.1}"
TARGET_PORT="${2:-514}"
COUNT="${3:-60}"

HOSTS=(web01 web02 db01 fw01 app01)
APPS=(nginx sshd sudo kernel myapp postgres)

# facility*8 + severity = PRI
# facilities: 4=auth,3=daemon,0=kern,16=local0
declare -a SEVERITIES=(
  "4:2:crit login failure detected"
  "4:4:warn multiple failed password attempts"
  "3:6:info service started successfully"
  "3:3:err failed to bind to socket"
  "0:5:notice interface eth0 link up"
  "16:6:info request processed"
  "16:3:err upstream timeout"
  "16:4:warn slow query detected"
  "16:0:emerg disk full - system halting writes"
)

send_udp() {
  local msg="$1"
  exec 3<>"/dev/udp/${TARGET_HOST}/${TARGET_PORT}"
  printf '%s' "$msg" >&3
  exec 3<&-
}

send_tcp() {
  local msg="$1"
  exec 3<>"/dev/tcp/${TARGET_HOST}/${TARGET_PORT}"
  printf '%s\n' "$msg" >&3
  exec 3<&-
}

echo "Sending ${COUNT} test syslog messages to ${TARGET_HOST}:${TARGET_PORT} ..."

for i in $(seq 1 "$COUNT"); do
  host="${HOSTS[$((RANDOM % ${#HOSTS[@]}))]}"
  app="${APPS[$((RANDOM % ${#APPS[@]}))]}"
  entry="${SEVERITIES[$((RANDOM % ${#SEVERITIES[@]}))]}"
  facility="${entry%%:*}"
  rest="${entry#*:}"
  severity="${rest%%:*}"
  text="${rest#*:}"
  pri=$((facility * 8 + severity))
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  pid=$((RANDOM % 60000 + 1000))
  msg="<${pri}>1 ${ts} ${host} ${app} ${pid} - - ${text} (sample #${i})"

  if (( i % 5 == 0 )); then
    send_tcp "$msg" || echo "  tcp send failed for message $i"
  else
    send_udp "$msg" || echo "  udp send failed for message $i"
  fi

  sleep 0.05
done

echo "Done. Check Grafana -> Syslog -> Syslog Overview dashboard."
