#!/bin/bash

nodes=(
  "us.aguenonnvpn.com"
  "eu.aguenonnvpn.com"
  "asia.aguenonnvpn.com"
  "sa.aguenonnvpn.com"
)

for node in "${nodes[@]}"; do
  echo "=== Testing $node ==="
  
  # Test HTTPS
  http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://$node)
  echo "  HTTPS : $http_status"
  
  # Test WebSocket handshake
  ws_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --http1.1 \
    -H "Connection: Upgrade" \
    -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
    -H "Sec-WebSocket-Version: 13" \
    https://$node/tunnel)
  echo "  WebSocket : $ws_status (101 = OK)"
  
  echo ""
done
