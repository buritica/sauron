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
┌─────────────────────────────────────────┐
│           Sauron Stack                  │
├─────────────────────────────────────────┤
│                                         │
│  Grafana (3000)  ─────┐                │
│       │               │                │
│       │               ▼                │
│       └──────▶  Prometheus (9090)      │
│                     │                   │
│                     ├─▶ Alertmanager   │
│                     │                   │
│                     ├─▶ cAdvisor        │
│                     │   (containers)    │
│                     │                   │
│                     └─▶ Node Exporter   │
│                         (host metrics)  │
└─────────────────────────────────────────┘
              │
              ├─▶ Monitor Morgan
              ├─▶ Monitor Retiro
              └─▶ Monitor other services
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

- **Grafana**: http://localhost:3000
  - Default login: `admin` / `sauron_sees_all`
  - Change password in `.env` file

- **Prometheus**: http://localhost:9090
- **Alertmanager**: http://localhost:9093
- **cAdvisor**: http://localhost:8080

---

## 📊 What's Monitored

### Sauron Itself
- ✅ Prometheus metrics
- ✅ Grafana status
- ✅ Alertmanager health
- ✅ Container metrics (via cAdvisor)
- ✅ Host system metrics (via Node Exporter)

### Host System
- CPU usage
- Memory usage and availability
- Disk space and I/O
- Network traffic and errors
- Filesystem metrics

### Containers
- CPU and memory per container
- Network I/O per container
- Restart count
- Container state

### Ready to Monitor (requires configuration)
- Morgan media server services
- Retiro HLS streaming
- Custom application metrics

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
│   └── grafana/
│       └── provisioning/       # Dashboard auto-provisioning
├── data/                        # Persistent data (gitignored)
│   ├── prometheus/             # Time-series database
│   ├── grafana/                # Dashboards and settings
│   └── alertmanager/           # Alert state
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

# Add notification webhooks
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR/WEBHOOK
```

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

Sauron includes pre-configured alerts for:

### Critical
- Service down (2+ minutes)
- Disk space < 5%
- Prometheus configuration reload failed

### Warning
- Disk space < 15%
- Memory usage > 90%
- CPU usage > 80% (10+ minutes)
- Container high memory usage
- High network errors
- Container restarting repeatedly

### Configuring Notifications

Edit `config/alertmanager/alertmanager.yml` and uncomment your preferred notification method:
- Slack
- Discord
- Email
- PagerDuty
- Webhook

Then restart Alertmanager:
```bash
docker compose restart alertmanager
```

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

1. Access Grafana at http://localhost:3000
2. Click "+" → Dashboard → Add visualization
3. Select Prometheus as data source
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
- Grafana requires authentication (default: admin/sauron_sees_all)
- Change default password in `.env`
- Prometheus and Alertmanager have no auth by default (use VPN or firewall)

### Network Isolation
- All services run on isolated `sauron` Docker network
- Expose only necessary ports
- Consider using Tailscale for remote access

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
