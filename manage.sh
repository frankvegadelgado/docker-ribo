#!/usr/bin/env bash
# =============================================================================
# KYC Platform — Management Script
# Usage: ./scripts/manage.sh [command]
# =============================================================================
set -euo pipefail

COMPOSE="docker compose"
PROJECT="kyc-environment"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

info()  { echo -e "${GREEN}[KYC]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

usage() {
  cat <<EOF
KYC Platform Management

Commands:
  up          Build and start all services
  down        Stop all services
  restart     Restart all services
  logs        Tail all logs (Ctrl+C to exit)
  logs-be     Tail backend logs only
  logs-fe     Tail frontend logs only
  status      Show service health
  shell-be    Open shell in backend container
  shell-mongo Open mongo shell
  reset-db    Drop and re-init MongoDB data
  aurora-test Test AWS Aurora connectivity
  gen-secret  Generate a new SECRET_KEY value
  clean       Remove containers, volumes, and images
EOF
}

case "${1:-help}" in

  up)
    info "Starting KYC environment…"
    [ ! -f .env ] && cp .env.example .env && warn "Created .env from example — review before production use"
    $COMPOSE up --build -d
    info "Services started. Access:"
    echo "  App:          http://localhost"
    echo "  API docs:     http://localhost:8000/api/docs"
    echo "  Mongo UI:     http://localhost:8081"
    echo "  Credentials:  admin@kyc.local / admin123"
    ;;

  down)
    info "Stopping services…"
    $COMPOSE down
    ;;

  restart)
    $COMPOSE restart
    info "Services restarted"
    ;;

  logs)
    $COMPOSE logs -f --tail=100
    ;;

  logs-be)
    $COMPOSE logs -f --tail=100 backend
    ;;

  logs-fe)
    $COMPOSE logs -f --tail=100 frontend
    ;;

  status)
    $COMPOSE ps
    ;;

  shell-be)
    $COMPOSE exec backend bash
    ;;

  shell-mongo)
    $COMPOSE exec mongo mongosh \
      "mongodb://kycadmin:kycpassword@localhost:27017/kycdb?authSource=admin"
    ;;

  reset-db)
    warn "This will drop all KYC data. Continue? [y/N]"
    read -r yn; [ "$yn" = "y" ] || exit 0
    $COMPOSE down -v
    $COMPOSE up -d mongo
    sleep 5
    $COMPOSE up -d
    info "Database reset complete"
    ;;

  aurora-test)
    info "Testing AWS Aurora connectivity…"
    $COMPOSE exec backend python -c "
import asyncio, asyncpg, os
async def test():
    conn = await asyncpg.connect(
        host=os.getenv('AURORA_HOST'),
        port=int(os.getenv('AURORA_PORT', 5432)),
        database=os.getenv('AURORA_DB'),
        user=os.getenv('AURORA_USER'),
        password=os.getenv('AURORA_PASSWORD'),
    )
    print('Aurora connection OK:', await conn.fetchval('SELECT version()'))
    await conn.close()
asyncio.run(test())
"
    ;;

  gen-secret)
    python3 -c "import secrets; print(secrets.token_hex(32))"
    ;;

  clean)
    warn "This removes ALL containers, volumes, and built images. Continue? [y/N]"
    read -r yn; [ "$yn" = "y" ] || exit 0
    $COMPOSE down -v --rmi all --remove-orphans
    info "Cleanup complete"
    ;;

  *)
    usage
    ;;
esac
