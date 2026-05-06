#!/bin/bash
# ─── loadtest.sh — Générer du trafic via les proxys levpn ───────────────────
#
# Usage : ./loadtest.sh
#
# Génère ~40% de charge sur les t3.micro :
#   - 10 connexions parallèles par région
#   - Mix de requêtes légères (API) et lourdes (downloads)
#   - Durée : 60 secondes
# ─────────────────────────────────────────────────────────────────────────────

DURATION=60
PARALLEL=10
PASSWORD="CHANGE_ME"

TARGETS_LIGHT=(
  "https://ipinfo.io/json"
  "https://httpbin.org/get"
  "https://api.github.com"
  "https://jsonplaceholder.typicode.com/posts"
  "https://httpbin.org/headers"
  "https://httpbin.org/ip"
  "https://www.google.com"
  "https://www.cloudflare.com"
  "https://example.com"
  "https://httpbin.org/user-agent"
)

TARGETS_HEAVY=(
  "https://speed.cloudflare.com/__down?bytes=10000000"
  "https://speed.cloudflare.com/__down?bytes=5000000"
  "https://proof.ovh.net/files/1Mb.dat"
)

PROXIES=(
  "http://us.aguenonnvpn.com:8080"
  "http://eu.aguenonnvpn.com:8080"
)

echo "╔══════════════════════════════════════════════════════╗"
echo "║  levpn load test                                    ║"
echo "║  ${#PROXIES[@]} proxies × $PARALLEL parallel × ${DURATION}s          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Fonction pour un worker
worker() {
  local proxy=$1
  local id=$2
  local end=$((SECONDS + DURATION))

  while [ $SECONDS -lt $end ]; do
    # 70% requêtes légères, 30% lourdes
    if [ $((RANDOM % 10)) -lt 7 ]; then
      url="${TARGETS_LIGHT[$((RANDOM % ${#TARGETS_LIGHT[@]}))]}"
    else
      url="${TARGETS_HEAVY[$((RANDOM % ${#TARGETS_HEAVY[@]}))]}"
    fi

    curl -s --max-time 10 \
      --proxytunnel -x "$proxy" \
      --proxy-user "levpn:$PASSWORD" \
      "$url" > /dev/null 2>&1

    # Petit délai aléatoire entre requêtes (100-500ms)
    sleep 0.$((RANDOM % 4 + 1))
  done
}

# Lancer les workers
PIDS=()
START=$SECONDS

for proxy in "${PROXIES[@]}"; do
  region=$(echo "$proxy" | grep -oP '//\K[^.]+')
  echo "→ $region : lancement de $PARALLEL workers..."

  for i in $(seq 1 $PARALLEL); do
    worker "$proxy" "$i" &
    PIDS+=($!)
  done
done

TOTAL_WORKERS=${#PIDS[@]}
echo ""
echo "  $TOTAL_WORKERS workers actifs. Durée : ${DURATION}s"
echo "  Ouvre le dashboard pour voir le trafic en temps réel."
echo ""

# Barre de progression
while [ $((SECONDS - START)) -lt $DURATION ]; do
  ELAPSED=$((SECONDS - START))
  PCT=$((ELAPSED * 100 / DURATION))
  BAR=$(printf "%-${PCT}s" "=" | tr ' ' '=')
  EMPTY=$(printf "%-$((100 - PCT))s" " ")
  printf "\r  [%.50s%.50s] %d/%ds " "$BAR" "$EMPTY" "$ELAPSED" "$DURATION"
  sleep 1
done

echo ""
echo ""
echo "→ Arrêt des workers..."

for pid in "${PIDS[@]}"; do
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
done

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Load test terminé."
echo "  Vérifie les metrics :"
echo "    curl -s http://us.aguenonnvpn.com:8080/metrics | python3 -m json.tool"
echo "    curl -s http://eu.aguenonnvpn.com:8080/metrics | python3 -m json.tool"
echo "═══════════════════════════════════════════════════════"
