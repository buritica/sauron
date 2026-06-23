# 👁️ Sauron

**The All-Seeing Eye** - Infrastructure monitoring and observability for your services.

Sauron is a centralized monitoring stack using Prometheus, Grafana, and Alertmanager to provide complete visibility into your infrastructure.

---

## 🎯 Purpose

Monitor multiple projects from a single dashboard:
- **Morgan** - Media server infrastructure
- **Retiro** - HLS streaming service
- **Host System** - Colima, disk, CPU, memory, network

---

## 🏗️ Architecture

```
App (OTLP gRPC/HTTP)
    │
    ▼
OTel Collector (:4317 gRPC, :4318 HTTP)
    ├── traces  ──→ Tempo (distributed tracing)
    ├── metrics ──→ Prometheus (remote write)
    └── logs    ──→ Loki (OTLP push)

Promtail ──→ Loki (Docker container logs)

Prometheus (:9090)
    ├── cAdvisor (container metrics)
    └── Node Exporter (host metrics)
    └── Alertmanager (alert routing)

Grafana (:3030) ──→ Prometheus, Loki, Tempo
```

---

## 🚀 Quick Start

### Start Sauron

```bash
docker compose up -d
```

### Stop Sauron

```bash
docker compose down
```

### Access Services

- **Grafana**: https://sauron.buriti.ca (Tailscale-only) or http://localhost:3030
  - Anonymous access enabled (Viewer role)
  - Admin login: `admin` / password from `GRAFANA_PASSWORD` env var

- **Prometheus**: http://localhost:9090
- **Alertmanager**: http://localhost:9093
- **cAdvisor**: http://localhost:8083
- **Loki**: http://localhost:3100 (log queries via Grafana)
- **OTel Collector**: localhost:4317 (gRPC), localhost:4318 (HTTP)

---

## 📊 What's Monitored

### Metrics (Prometheus)
- ✅ Container metrics (via cAdvisor)
- ✅ Host system metrics (via Node Exporter) - CPU, memory, disk, network
- ✅ OTLP metrics ingestion (via OTel Collector → Prometheus remote write)

### Logs (Loki)
- ✅ All Docker container logs (via Promtail docker_sd_configs)
- ✅ Aurelio application logs (via Promtail static config with JSON pipeline)

### Traces (Tempo)
- ✅ Distributed tracing via OTLP (via OTel Collector → Tempo)
- ✅ Trace-to-log correlation (Loki derived fields link traceId to Tempo)

### Alerts (Alertmanager)
- ✅ Service down, disk space, CPU/memory thresholds
- ✅ Container restart loops, high network errors
- 📣 Edge-triggered (fire once on detect, once on recovery) → delivered via a direct Slack webhook to `#alerts`, host-tagged. See [Alerts](#-alerts).

---

## 📁 Directory Structure

```
sauron/
├── docker-compose.yml           # Service definitions
├── config/
│   ├── prometheus/
│   │   ├── prometheus.yml      # Scrape configuration
│   │   └── alerts.yml          # Alert rules
│   ├── alertmanager/
│   │   └── alertmanager.yml    # Notification routing
│   ├── grafana/
│   │   └── provisioning/
│   │       ├── datasources/    # Prometheus, Loki, Tempo
│   │       └── dashboard-files/ # Provisioned dashboards
│   ├── loki/
│   │   └── loki.yml            # Log aggregation config
│   ├── promtail/
│   │   └── promtail.yml        # Log collection config
│   ├── tempo/
│   │   └── tempo.yml           # Distributed tracing config
│   └── otel-collector/
│       └── otel-collector.yml  # OTLP ingestion and fan-out
├── data/                        # Persistent data (gitignored)
│   ├── prometheus/             # Time-series database
│   ├── grafana/                # Dashboards and settings
│   ├── alertmanager/           # Alert state
│   ├── loki/                   # Log storage
│   └── tempo/                  # Trace storage
├── .env                        # Environment variables
└── README.md                   # This file
```

---

## 🔧 Configuration

### Environment Variables

Create a `.env` file:

```bash
# Grafana
GRAFANA_PASSWORD=sauron_sees_all
```

Alert delivery is **not** a webhook env var — alerts post to a Slack incoming webhook (see [Alerts](#-alerts)). The URL lives in the gitignored `config/alertmanager/slack-webhook-url`, not `.env`.

### Adding Morgan Monitoring

1. **Enable Docker metrics** in Morgan (optional):
   ```json
   # /etc/docker/daemon.json
   {
     "metrics-addr": "0.0.0.0:9323",
     "experimental": true
   }
   ```

2. **Uncomment Morgan scrape config** in `config/prometheus/prometheus.yml`:
   ```yaml
   - job_name: 'morgan'
     static_configs:
       - targets: ['host.docker.internal:9323']
   ```

3. **Reload Prometheus**:
   ```bash
   docker compose restart prometheus
   ```

### Adding Retiro Monitoring

Configure Retiro to expose metrics, then add to `prometheus.yml`.

---

## 🚨 Alerts

### Notification model — edge-triggered (Datadog-style)

Alerts fire **once when an event is detected** and **once when it clears** — no recurring re-notification while a condition holds. Prometheus + Alertmanager is level-based underneath (a rule is "firing" for as long as its condition is true), so this is achieved by configuration, not a native "notify once" flag:

- `repeat_interval: 1y` in `alertmanager.yml` — effectively never re-page an unchanged firing alert.
- `send_resolved: true` on the receiver — deliver the one RESOLVED when it clears.
- `group_by: [alertname]` — collapse all instances of one alert into a single message (the receiver renders the count, e.g. `ServiceDown (5)`), so a burst is one notification, not dozens.
- `inhibit_rules` — a critical mutes the matching warning; `ServiceDown` mutes the derived `PrometheusTargetsDown` (dependency muting).

This matches Datadog's default (notify on state transition, renotify off). To re-enable a safety nudge for persistent criticals, add a child route with a finite `repeat_interval` for `severity: critical` only.

### Delivery — direct Slack incoming webhook → `#alerts`

All alerts route to a single `slack-alerts` receiver that posts **directly to a Slack incoming webhook** (channel `#alerts`) — no intermediary. This means alerts deliver even when ca (the assistant) is down or restarting; the monitoring path has no dependency on it. ca's own operational alerts (deploys, online, stuck tasks) are separate and stay in `#watch-ca`.

- The incoming-webhook URL lives in `config/alertmanager/slack-webhook-url` (gitignored, mounted into the container; referenced as `api_url_file`). Provisioned via the ca Slack app → Incoming Webhooks. Never commit it.
- Messages are **host-tagged**: the title carries the `site` external label (e.g. `[halfmoon]`) and each line shows the alert's `instance`/`mountpoint`.
- Template gotcha: alertmanager's template engine has **no `default` function** (that's sprig/Helm). Using `| default` renders the whole message empty at send time, and `amtool check-config` won't catch it (syntax-only). Use `if/else`.
- Reload after editing `alertmanager.yml`: recreate the container (`docker compose up -d --force-recreate alertmanager`). A plain SIGHUP can miss the change if virtiofs is serving a stale snapshot of the mounted file.

### Rules (`config/prometheus/alerts.yml`)

**Critical:** Service down (2m), disk < 5%, Prometheus config-reload failed.
**Warning:** disk < 15%, memory > 90%, CPU > 80% (10m), high network errors, container restart-looping.

Notes baked into the rules from real incidents:
- **Disk** rules evaluate every **10m** (`sauron_disk` group `interval`), not the 15s global — disk fills slowly; faster eval just adds flapping. Real host disk comes from the **native halfmoon node_exporter** (`halfmoon-host` target, `host.docker.internal:9100`); the containerized node-exporter only sees the Colima VM disk.
- **`ContainerRestarting`** uses `changes(container_start_time_seconds[15m]) > 2`. The old `rate(container_last_seen[5m]) > 0` was broken — `container_last_seen` ticks up ~1/s for every *running* container, so it fired for everything permanently and never measured restarts.

### Tuning gotchas (in `docker-compose.yml`)

- **cadvisor** disables the expensive `disk,diskIO,...` metrics + `--docker_only` + `--housekeeping_interval=30s`. Without this it chokes on per-container filesystem scans (minutes-long on a busy overlayfs) and hangs its endpoint → false `ServiceDown`/`ContainerDown` cascades. Per-container fs panels are lost; host disk still comes from node-exporter.
- **loki** has its own `1G` memory limit (not the shared 384M `*common-settings`). At 384M it OOM-looped (exit 137) — loki 3.x single-binary settles at ~480–520M and spikes higher under query load.

---

## 📈 Grafana Dashboards

### Pre-built Dashboards to Import

1. **Docker Container & Host Metrics** (ID: 893)
   - Navigate to Grafana → Dashboards → Import → Enter `893`

2. **Node Exporter Full** (ID: 1860)
   - Complete host system overview

3. **cAdvisor** (ID: 14282)
   - Container-specific metrics

### Creating Custom Dashboards

1. Access Grafana at https://sauron.buriti.ca or http://localhost:3030
2. Click "+" → Dashboard → Add visualization
3. Select data source: Prometheus (metrics), Loki (logs), or Tempo (traces)
4. Build your queries

---

## 🔍 Useful Prometheus Queries

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

### Network Traffic
```promql
rate(node_network_receive_bytes_total[5m])
```

---

## 🛠️ Maintenance

### Backup Configuration

```bash
# Backup Grafana dashboards and settings
tar -czf sauron-backup-$(date +%Y%m%d).tar.gz data/grafana config/

# Backup Prometheus data (optional, large)
tar -czf prometheus-data-$(date +%Y%m%d).tar.gz data/prometheus
```

### Update Services

```bash
docker compose pull
docker compose up -d
```

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f prometheus
docker compose logs -f grafana
```

### Clear Data (caution!)

```bash
docker compose down -v  # Removes volumes and all data
```

---

## 🐛 Troubleshooting

### Grafana won't start
- Check if port 3000 is already in use: `lsof -i :3000`
- Verify data directory permissions: `ls -la data/grafana`

### Prometheus not scraping targets
- Check Prometheus targets: http://localhost:9090/targets
- Verify network connectivity from Sauron to target services
- Check Prometheus logs: `docker logs prometheus`

### cAdvisor privileged mode
- cAdvisor requires privileged mode to access container metrics
- This is normal and expected for monitoring

### No alerts firing
- Verify Alertmanager is connected: http://localhost:9090/config
- Check alert rules: http://localhost:9090/alerts
- Test notification channel in Alertmanager UI

---

## 🔐 Security

### Access Control
- Grafana anonymous access enabled (Viewer role) for Tailscale users
- Admin login available with password from `GRAFANA_PASSWORD` env var
- Grafana accessible via HTTPS at sauron.buriti.ca (Caddy reverse proxy in morgan stack)
- Prometheus and Alertmanager have no auth (only accessible locally or via Tailscale)

### Network Isolation
- All services run on isolated `sauron` Docker network
- Only necessary ports exposed to host
- Remote access via Tailscale VPN only

---

## 🎓 Learning Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [PromQL Tutorial](https://prometheus.io/docs/prometheus/latest/querying/basics/)

---

## 🤝 Contributing

This is a personal infrastructure project. Improvements welcome!

---

## 📝 Todo

- [ ] Configure notification channels (Slack/Discord)
- [ ] Add Morgan service monitoring
- [ ] Add Retiro HLS metrics
- [ ] Create custom Grafana dashboards
- [ ] Set up automated backups
- [ ] Document retention policies
- [ ] Add more alert rules for specific services

---

**Sauron** - One monitoring stack to rule them all 👁️
