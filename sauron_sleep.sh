#!/bin/bash
# Sauron - The All-Seeing Eye closes
# Stop monitoring stack

set -e

echo "👁️  The Eye of Sauron closes..."
echo ""

# Stop Sauron services
docker compose down

echo ""
echo "✅ Monitoring stack stopped"
echo "💤 Sauron sleeps (but data persists)"
