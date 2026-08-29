# Syslog Stack - rsyslog + Promtail + Loki + Grafana

A self-hosted centralized logging system: any device that can send syslog
(Linux servers, network switches/firewalls, routers, IoT gear) ships logs
here, and Grafana gives you dashboards, filtering, and log search.

## Architecture

```mermaid
flowchart LR
    A[Remote hosts / network devices] -- UDP/TCP 514, RELP 20514 --> B[rsyslog]
    B -- JSON lines per host --> C[(/var/log/rsyslog/hosts/*/*.json)]
    D[Promtail] -- tails files, parses JSON, extracts labels --> E[Loki]
    C --> D
    F[Grafana] -- LogQL queries --> E
    G[logrotate + cron] -.rotates/compresses.-> C
```

- **rsyslog** - receives syslog over UDP/TCP port 514 and RELP port 20514
  (reliable TCP), writes one JSON object per line, one file per source
  host, under `data/rsyslog/hosts/<hostname>/syslog.json`.
- **Promtail** - tails those JSON files, parses each line, and promotes
  `host`, `severity`, `facility`, `app` to Loki labels.
- **Loki** - stores and indexes the log stream (filesystem backend, TSDB
  index, 14-day retention via the compactor).
- **Grafana** - pre-provisioned with the Loki datasource and a "Syslog
  Overview" dashboard (log volume, severity/facility breakdowns, top
  hosts/apps, live log streams, error feed).
- **logrotate + cron** run inside the rsyslog container so the JSON log
  files don't grow unbounded (daily rotation, 14 generations, gzip).

## Quick start

```bash
cd /home/d4rk_katt/syslog
docker compose up -d --build
```

Then open Grafana at **http://localhost:3000**.

- Username: `admin`
- Password: see `.env` (`GRAFANA_ADMIN_PASSWORD`) - it was generated
  randomly during setup. Change it after first login.

The "Syslog Overview" dashboard lives in the **Syslog** folder and is
provisioned automatically - no manual import needed.

## Verifying it works

Generate some sample traffic (spans 5 fake hosts, 6 fake apps, a mix of
severities, over both UDP and TCP):

```bash
./scripts/generate-test-logs.sh
```

Then check:

```bash
# raw files rsyslog wrote
ls data/rsyslog/hosts/
tail -f data/rsyslog/hosts/web01/syslog.json

# confirm Loki has ingested them
curl -s http://localhost:3100/loki/api/v1/label/host/values | jq
```

...and refresh the Grafana dashboard - you should see log volume, host,
and severity panels populate within a few seconds.

## Pointing real systems at this collector

Replace `<this-host>` with this machine's IP/hostname.

**Linux server (rsyslog client, forward everything):**
Copy [`clients/linux/rsyslog-forward.conf`](clients/linux/rsyslog-forward.conf)
to `/etc/rsyslog.d/60-forward.conf` on the client, replace
`SYSLOG_SERVER` with this machine's IP/hostname, and
`sudo systemctl restart rsyslog`.

**Linux server (systemd/journald, no rsyslog installed):**
Install `rsyslog` (it picks up journald automatically via `imjournal`) and
use the forwarding rule above, or point `systemd-journal-upload` at a
separate collector if you'd rather avoid rsyslog on the client.

**Windows server (via NXLog):**
Windows Event Log isn't syslog, so it needs a converter. Install
[NXLog Community Edition](https://nxlog.co/community) on the Windows
host, then use
[`clients/windows/nxlog.conf`](clients/windows/nxlog.conf) as
`C:\Program Files\nxlog\conf\nxlog.conf` (replace `SYSLOG_SERVER` with
this machine's IP/hostname, then restart the `nxlog` service). It ships
Application/System/Security event log entries as RFC5424 syslog - the
Windows host then shows up in the Grafana dashboard's host filter
exactly like a Linux box, using its Windows computer name, with no
separate config needed on this side.

If you want richer Windows-specific fields (Event ID, Provider Name,
Channel) instead of just the flattened message text, the alternative is
running Promtail directly on the Windows host with its built-in
`windows_events` scrape target, pushing straight to
`http://<this-host>:3100/loki/api/v1/push`. That bypasses rsyslog
entirely and lands under a different Loki `job` label, so it needs its
own dashboard panels rather than showing up in the existing ones - ask
if you want this wired up instead of/alongside NXLog.

**Network devices (Cisco/Juniper/pfSense/OPNsense/UniFi, etc.):**
Every vendor has a "syslog server" field in system logging settings - set
it to `<this-host>` on UDP port 514. Most also let you pick a minimum
severity to forward; start with `info` and narrow later once you see
volume.

**Reliable delivery (RELP):** if UDP loss is a concern (e.g. WAN links),
point clients that support RELP (`rsyslog` with `omrelp`) at port
`20514/tcp` instead of 514.

## Data layout & retention

- Raw JSON logs: `data/rsyslog/hosts/<hostname>/syslog.json`, rotated
  daily and kept for 14 days (gzip after 1 day) - see
  `rsyslog/logrotate.conf`.
- Loki chunks/index: `data/loki/` - retained 14 days
  (`limits_config.retention_period` in `loki/loki-config.yml`), enforced
  by the compactor. Change that value (and re-run `docker compose up -d`)
  to keep logs longer or shorter.
- Grafana state (dashboards, users, prefs): `data/grafana/`.

All three are bind-mounted under `./data/` so `docker compose down` never
loses data; only `docker compose down -v` touches the named
`promtail-positions` volume (safe - it just re-reads existing files from
the start on next boot, so you may see a batch of "old" logs re-ingested
once).

## Security notes (read before exposing this beyond your LAN)

This setup is tuned for a home lab / internal network:

- Syslog over UDP/TCP 514 is **plaintext and unauthenticated** - anyone
  who can reach port 514 can inject fake log entries. Keep it behind a
  firewall/VPN; don't expose it to the public internet.
- RELP on 20514 is more reliable than UDP but is **not encrypted** in
  this config. For encryption in transit, rsyslog supports TLS-wrapped
  RELP (`tls="on"` + certificates) - ask if you want this wired up.
- Grafana is served over plain HTTP on port 3000. Put it behind a
  reverse proxy with TLS (Caddy/nginx/Traefik) if it needs to be reached
  outside `localhost`.
- Change the generated Grafana admin password after first login.
  Self-registration is already disabled (`GF_USERS_ALLOW_SIGN_UP=false`)
  so nobody else can create an account.

## Extending

- **Alerting**: add a Grafana alert rule on the "Error/Critical.../range"
  stat panel (e.g. fire when > N errors in 5m) and wire a contact point
  (Slack/email/webhook).
- **More label extraction**: edit `promtail/promtail-config.yml` to pull
  additional structured fields (e.g. HTTP status codes from nginx logs)
  into labels or just leave them in the log line for full-text search.
- **High log volume**: if a single app/host produces very high
  cardinality values, avoid turning those into Loki labels (keep them in
  the log body) - Loki performance degrades with high label cardinality.
- **Scale out**: this is a single-node stack. For larger fleets, Loki
  can run in distributed mode with object storage (S3/GCS) instead of
  the local filesystem backend used here.

## Troubleshooting

```bash
docker compose logs -f rsyslog     # confirm messages are being received
docker compose logs -f promtail    # confirm files are being tailed/shipped
docker compose logs -f loki        # confirm ingestion, check for errors
docker compose ps                  # all 4 containers should be "Up"
```

If Promtail shows `permission denied` reading log files, check
`data/rsyslog/hosts/*/*.json` are world-readable (rsyslog creates them
`0644` by default - see `rsyslog/rsyslog.conf`).
