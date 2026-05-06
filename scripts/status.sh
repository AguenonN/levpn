#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TFVARS="$SCRIPT_DIR/../infra/terraform.tfvars"

if [ ! -f "$TFVARS" ]; then
  echo "Erreur : $TFVARS introuvable."
  exit 1
fi

LEVPN_PASSWORD=$(grep "levpn_password" "$TFVARS" | sed 's/.*= *"//' | sed 's/".*//')

echo "╔══════════════════════════════════════════════════════════╗"
echo "║                    levpn — Status                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

for region in us eu asia sa; do
  ENABLED=$(grep "enable_${region}" "$TFVARS" 2>/dev/null | grep -o 'true\|false' || echo "unknown")

  if [ "$ENABLED" != "true" ]; then
    printf "  %-6s │ OFF\n" "$region"
    continue
  fi

  DOMAIN="${region}.aguenonnvpn.com"

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    --proxytunnel -x "http://${DOMAIN}:8080" \
    --proxy-user "levpn:${LEVPN_PASSWORD}" \
    https://ipinfo.io/json 2>/dev/null || echo "000")

  if [ "$HTTP_CODE" = "200" ]; then
    EXIT_IP=$(curl -s --max-time 5 \
      --proxytunnel -x "http://${DOMAIN}:8080" \
      --proxy-user "levpn:${LEVPN_PASSWORD}" \
      https://ipinfo.io/json 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('ip','?'))" 2>/dev/null || echo "?")
    printf "  %-6s │ ✓  │ IP: %s\n" "$region" "$EXIT_IP"
  else
    printf "  %-6s │ ✗  │ HTTP %s\n" "$region" "$HTTP_CODE"
  fi
done

echo ""
