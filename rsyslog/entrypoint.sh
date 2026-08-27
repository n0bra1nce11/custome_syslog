#!/bin/bash
set -euo pipefail

mkdir -p /var/log/rsyslog/hosts /var/lib/rsyslog /var/lib/logrotate

# Hourly log rotation for the per-host JSON files (14 day retention,
# see logrotate.conf). cron runs in the foreground alongside rsyslogd.
echo "0 * * * * root /usr/sbin/logrotate --state /var/lib/logrotate/status /etc/logrotate.d/rsyslog-json >> /var/log/rsyslog-logrotate.log 2>&1" > /etc/cron.d/rsyslog-logrotate
chmod 0644 /etc/cron.d/rsyslog-logrotate
cron

exec rsyslogd -n -iNONE
