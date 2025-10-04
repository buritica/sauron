#!/bin/bash
# Sauron - The All-Seeing Eye awakens
# Start monitoring stack

set -e

echo "👁️  The Eye of Sauron awakens..."
echo ""

# Check if Colima is running
if ! colima status &>/dev/null; then
    echo "🐳 Starting Colima..."
    colima start
    echo "✅ Colima started"
else
    echo "✅ Colima already running"
fi

# Start Sauron services
echo ""
echo "🔥 Igniting the monitoring stack..."
docker compose up -d

echo ""
echo "👁️  Sauron is watching..."
echo ""
echo "Access services at:"
echo "  📊 Grafana:       http://localhost:3000"
echo "  📈 Prometheus:    http://localhost:9090"
echo "  🚨 Alertmanager:  http://localhost:9093"
echo "  🐳 cAdvisor:      http://localhost:8080"
echo ""
echo "Default Grafana login: admin / sauron_sees_all"
