# 👁️ Sauron

**The All-Seeing Eye** - Infrastructure monitoring and observability for your services.

Sauron watches halfmoon's infra and forwards it to Grafana Cloud. As of the 2026-08-20 migration, halfmoon runs **one** collector (Grafana Alloy) plus the two exporters that can only be pulled (cAdvisor, node-exporter) — everything else (metrics storage, log storage, trace storage, alert evaluation, alert delivery) lives in Grafana Cloud, not on this box.

---

## 🎯 Purpose

Monitor multiple projects from a single pane of glass:
- **ca** — the chief-of-staff assistant (own repo, `buritica/ca`); pushes its own telemetry straight to Cloud, independent of this stack
- **Morgan** - Media server infrastructure
- **Retiro** - HLS streaming service
- **Host System** - halfmoon: disk, CPU, memory, network, containers

---

## 🏗️ Architecture

```
ca (any host — halfmoon today, severo later)
    │  OTLP push, direct — bypasses this stack entirely
    ▼
Grafana Cloud OTLP gateway (metrics + logs + traces, one endpoint)

halfmoon:
  node-exporter (:9100)  ┐
  cadvisor (:8083)       ┤─→ Alloy (:12345) ─→ Grafana Cloud Mimir  (curated keep-list)
  docker container logs  ┤
  deploy-apps/cron/      ┤─→ Alloy          ─→ Grafana Cloud Loki   (all, no filter)
    runner-ca file logs  ┘

Grafana (:3030, OPTIONAL local mirror) ──→ Grafana Cloud datasources
```

**Why this shape:** halfmoon was running the full self-hosted stack (Prometheus, Loki, Tempo, Promtail, OTel Collector, Alertmanager) — real resource cost on a box that also runs ca and several media-server containers. Moving alert *evaluation* to Cloud is also a strict reliability upgrade, not just a resource save: a Cloud-side dead-man's-switch (`config/grafana-cloud/alert-rules.yml`'s `cloud_liveness` group) detects halfmoon going fully dark, which a local Alertmanager never could — it dies with the box it's watching. See that file's comments for the full reasoning.

**What moved where:**

| Was (removed) | Now |
|---|---|
| Prometheus (local TSDB, 30d retention) | Grafana Cloud Mimir (remote_write from Alloy + direct OTLP from ca) |
| Loki (local log storage) | Grafana Cloud Loki (push from Alloy) |
| Tempo (local trace storage) | Grafana Cloud Tempo (direct OTLP from ca) |
| Promtail (log scraper) | Alloy (`loki.source.docker` / `loki.source.file` components) |
| OTel Collector (OTLP fan-out) | Nothing — ca pushes OTLP directly to Cloud's gateway |
| Alertmanager (local alert routing) | Grafana Cloud Alertmanager (`config/grafana-cloud/alertmanager.yml`) |

---

## 🚀 Quick Start

### Start Sauron

```bash
docker compose up -d
```

Alloy starts but does **nothing** until Cloud credentials are filled in — see [Grafana Cloud](#☁️-grafana-cloud-migration) below. Bringing the stack up before that point is safe (no crash, no data loss) but nothing is collected yet.

### Stop Sauron

```bash
docker compose down
```

### Access Services

- **Grafana**: https://sauron.buriti.ca (Tailscale-only) or http://localhost:3030 — optional local mirror, see below
  - Anonymous access enabled (Viewer role)
  - Admin login: `admin` / password from `GRAFANA_PASSWORD` env var
- **Alloy UI**: http://localhost:12345 — component graph, live debugging, whether the pipeline is actually flowing
- **cAdvisor**: http://localhost:8083
- **node-exporter**: http://localhost:9100/metrics

There is no local Prometheus/Loki/Tempo/Alertmanager to browse anymore — query everything through Grafana Cloud's own UI (or the local Grafana mirror once its datasources are repointed).

---

## 📊 What's Monitored

### Metrics (Grafana Cloud Mimir)
- ✅ Container metrics (cAdvisor → Alloy → Cloud, curated keep-list)
- ✅ Host system metrics (node-exporter → Alloy → Cloud, curated keep-list)
- ✅ ca's own application metrics (direct OTLP push from ca, all `ca_*` shipped — already cardinality-trimmed at the source)

### Logs (Grafana Cloud Loki)
- ✅ All Docker container logs on halfmoon (Alloy `loki.source.docker`, same as every promtail-scraped container before)
- ✅ Pino JSON app logs under `~/deploy/*/var/logs/*.log` (Alloy `loki.source.file` + `loki.process`)
- ✅ Cron job logs, GH Actions runner diagnostics (same file-scrape pattern)
- ✅ ca's own structured logs (direct OTLP push — a second copy also lands via the Docker-log job above while ca runs on halfmoon; harmless, different label set)

### Traces (Grafana Cloud Tempo)
- ✅ Distributed tracing via ca's direct OTLP push
- Span-metrics/service-graph generation (the old Tempo `metrics_generator` feature) needs re-enabling as a Cloud Portal stack setting — it's not a local config file anymore. Check Cloud Portal → Tempo → Service Graph / Span Metrics.

### Alerts (Grafana Cloud Alertmanager)
- ✅ Service down, disk space, CPU/memory thresholds, container restart loops, high network errors, ca-specific brain/migration/streaming alerts — see `config/grafana-cloud/alert-rules.yml`
- ✅ **New:** dead-man's-switch rules (`cloud_liveness` group) — catch ca or halfmoon going fully dark, not just a metric threshold crossing
- 📣 Still edge-triggered, still delivered to the same `#alerts` Slack channel — now via Cloud's Alertmanager instead of a local one. See [Grafana Cloud migration](#☁️-grafana-cloud-migration).

---

## 📁 Directory Structure

```
sauron/
├── docker-compose.yml              # alloy, grafana (optional), cadvisor, node-exporter
├── config/
│   ├── alloy/
│   │   ├── config.alloy            # Scrape + relabel + remote_write/loki.write — DISABLED until activated
│   │   └── grafana-cloud-password  # gitignored, created by you at activation time
│   ├── grafana-cloud/
│   │   ├── alert-rules.yml         # Mimir-ruler rule groups (load via mimirtool)
│   │   └── alertmanager.yml        # Cloud Alertmanager config (load via mimirtool)
│   └── grafana/
│       └── provisioning/
│           ├── datasources/        # repoint at Cloud once activated
│           └── dashboard-files/    # provisioned dashboards (local Grafana mirror only)
├── data/                           # Persistent data (gitignored) — just grafana/ now
├── .env                            # Environment variables
└── README.md                       # This file
```

---

## 🔧 Configuration

### Environment Variables

Create a `.env` file:

```bash
# Grafana
GRAFANA_PASSWORD=sauron_sees_all
```

Alert delivery is configured entirely in Grafana Cloud now (Contact points / Notification policies UI, or `mimirtool alertmanager load config/grafana-cloud/alertmanager.yml`) — not an env var, not a local file mount.

### Adding Morgan / Retiro Monitoring

Add a new `prometheus.scrape` block to `config/alloy/config.alloy` (inside the activated pipeline), pointing at the service's `/metrics` endpoint, and extend the `keep_list` relabel regex if it exposes metrics you actually want in Cloud. `docker compose restart alloy` to pick it up.

---

## ☁️ Grafana Cloud (migration)

Sauron used to be fully self-hosted. As of 2026-08-20 it's Alloy-first: everything forwards to Cloud, nothing is stored on halfmoon except what Alloy buffers in transit. See the [Architecture](#🏗️-architecture) table above for what moved where and why.

**Why ca's own metrics ship wholesale but host/container metrics don't:** ca's `ca_*` metrics are already cardinality-trimmed at the source (see `buritica/ca#2328`), so shipping all of them is cheap and future-proof — no README edit needed when ca adds a new counter. Host/container metrics are the opposite: `node-exporter-full`/cadvisor's FULL collector output is hundreds to thousands of series on its own, and nothing here queries more than the ~15 names `alert-rules.yml` + the non-cost dashboard panels actually use. The full `node-exporter-full`/cadvisor community dashboards (still importable, IDs 1860/14282) only work against a full local scrape — they're not part of this migration's scope.

**To activate:**

1. **Metrics + Logs:** Cloud Portal → your stack → Connections → Prometheus (metrics) and Loki (logs), each has a "Send data" page with a push URL, an instance ID (username), and a "Generate API key" button. One Access Policy token scoped to `metrics:write` + `logs:write` can cover both.
2. `echo -n 'YOUR_TOKEN' > config/alloy/grafana-cloud-password` (gitignored, never commit) — on halfmoon, not in this repo checkout.
3. Uncomment the ENTIRE pipeline in `config/alloy/config.alloy` (it's commented out as one block deliberately — see its header), fill in the four TODOs (metrics URL, metrics instance ID, logs URL, logs instance ID).
4. `docker compose restart alloy` (no live-reload endpoint like Prometheus had — a restart is the reload).
5. Confirm at http://localhost:12345 that every component shows healthy, then confirm in the Cloud Portal that metrics/logs are actually arriving (Explore → pick the datasource → query `up` or `{job=~".+"}`).
6. Load the alert rules and Alertmanager config:
   ```bash
   mimirtool rules load config/grafana-cloud/alert-rules.yml \
     --address=https://<your-stack>.grafana.net --id=<instance-id> --key=<token-with-ruler-write>
   mimirtool alertmanager load config/grafana-cloud/alertmanager.yml \
     --address=https://<your-stack>.grafana.net --id=<instance-id> --key=<token-with-alertmanager-write>
   ```
   Set the Slack webhook URL in the Cloud Portal's Contact points UI (there's no local secret file for Cloud's Alertmanager to read).
7. Confirm in the Cloud Portal's "Cardinality Management" view that active series stay under the free-tier's 10k-series budget — the keep regex is a starting point, not a guarantee against a future metric explosion.

**Point ca at Cloud too** (separate repo, `buritica/ca`): set `OTEL_EXPORTER_OTLP_ENDPOINT` to Cloud's OTLP gateway URL and `OTEL_EXPORTER_OTLP_HEADERS` to a Basic-auth header carrying the instance ID + token (Cloud Portal → Connections → OpenTelemetry → "Send data" has the exact values). This is independent of everything above — ca's telemetry never touches halfmoon's Alloy.

**Deferred to a follow-up, once the above is proven working:** folding node-exporter and cadvisor into Alloy's own `prometheus.exporter.unix`/`prometheus.exporter.cadvisor` components (both exist, both could drop a container each) — held back because the current standalone cAdvisor config is the product of a real incident-driven tuning pass, and Alloy's embedded fork has its own separate compatibility history that hasn't been verified against this OrbStack setup.

**⚠️ Everything in `config/alloy/` and `config/grafana-cloud/` is UNTESTED against a live Alloy instance or real Cloud credentials** — written by translating the removed configs faithfully, not by running them. Verify component names/arguments against Alloy's own docs before trusting this blind, and watch http://localhost:12345 closely on first activation.

---

## 📈 Grafana Dashboards

Grafana Cloud has its own hosted Grafana UI with the same dashboards (`config/grafana/provisioning/dashboard-files/`) — that's the primary place to view them now. The local Grafana container (`:3030`) is an optional mirror; if you keep it, repoint its Prometheus/Loki/Tempo datasources at Cloud's query endpoints (`config/grafana/provisioning/datasources/`) since there's no local Prometheus/Loki/Tempo for it to query anymore.

### Pre-built Dashboards to Import (local Grafana only — need a full local scrape)

1. **Docker Container & Host Metrics** (ID: 893)
2. **Node Exporter Full** (ID: 1860)
3. **cAdvisor** (ID: 14282)

---

## 🔍 Useful Queries (PromQL, via Cloud's Explore or local Grafana repointed at Cloud)

### Container Memory Usage
```promql
container_memory_usage_bytes{name!=""}
```

### Disk Space Remaining
```promql
node_filesystem_avail_bytes / node_filesystem_size_bytes
```

### CPU Usage by Container
```promql
rate(container_cpu_usage_seconds_total[5m])
```

Note: only the metrics in `config/alloy/config.alloy`'s keep-list actually exist in Cloud — the full node-exporter/cadvisor catalog (e.g. per-interface network byte counters) only exists in the local scrape, which nothing stores anymore. Widen the keep-list first if a query comes back empty.

---

## 🛠️ Maintenance

### Backup Configuration

```bash
tar -czf sauron-backup-$(date +%Y%m%d).tar.gz data/grafana config/
```

There's no local Prometheus/Loki/Tempo data to back up anymore — that's Grafana Cloud's job now (per their retention policy).

### Update Services

```bash
docker compose pull
docker compose up -d
```

### View Logs

```bash
docker compose logs -f alloy
```

---

## 🐛 Troubleshooting

### Grafana won't start
- Check if port 3000 is already in use: `lsof -i :3000`
- Verify data directory permissions: `ls -la data/grafana`

### Alloy not sending data
- Check http://localhost:12345 — the component graph shows errors inline (auth failures, connection refused, etc.)
- `docker compose logs -f alloy`
- Confirm `config/alloy/grafana-cloud-password` exists and isn't empty
- Confirm the pipeline in `config.alloy` is actually uncommented — a syntax error there crash-loops the container silently past a quick `docker ps` glance

### cAdvisor privileged mode
- cAdvisor requires privileged mode to access container metrics — this is normal and expected

### No alerts firing
- Confirm rules loaded: Cloud Portal → Alerting → Alert rules (or `mimirtool rules print`)
- Confirm the Alertmanager config loaded: Cloud Portal → Alerting → Contact points
- Test the Slack contact point directly from the Cloud Portal UI

---

## 🔐 Security

### Access Control
- Grafana anonymous access enabled (Viewer role) for Tailscale users
- Admin login available with password from `GRAFANA_PASSWORD` env var
- Grafana accessible via HTTPS at sauron.buriti.ca (Caddy reverse proxy in morgan stack)
- Alloy's UI (`:12345`) has no auth — only accessible locally or via Tailscale

### Network Isolation
- All services run on isolated `sauron` Docker network
- Only necessary ports exposed to host
- Remote access via Tailscale VPN only

---

## 🎓 Learning Resources

- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [Grafana Cloud Documentation](https://grafana.com/docs/grafana-cloud/)
- [mimirtool Documentation](https://grafana.com/docs/mimir/latest/manage/tools/mimirtool/)
- [PromQL Tutorial](https://prometheus.io/docs/prometheus/latest/querying/basics/)

---

## 🤝 Contributing

This is a personal infrastructure project. Improvements welcome!

---

**Sauron** - One monitoring stack to rule them all 👁️
