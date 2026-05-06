#!/bin/bash
set -euo pipefail

TARGET="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
INFRA_DIR="$PROJECT_DIR/infra"
KEY="$HOME/.ssh/id_rsa"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $KEY"

echo "→ Compilation server-linux..."
cd "$PROJECT_DIR"
GOOS=linux GOARCH=amd64 go build -o server-linux ./cmd/server/
echo "✓ Compilé"

cd "$INFRA_DIR"
declare -A NODES

for region in us eu asia sa; do
  IP=$(terraform output -json "${region}" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['ip'] if d else '')" 2>/dev/null || echo "")
  [ -n "$IP" ] && NODES["$region"]="$IP"
done

if [ ${#NODES[@]} -eq 0 ]; then
  echo "Aucune région active."
  exit 1
fi

if [ "$TARGET" != "all" ]; then
  if [ -z "${NODES[$TARGET]:-}" ]; then
    echo "Erreur : région '$TARGET' non active."
    exit 1
  fi
  IP="${NODES[$TARGET]}"
  unset NODES
  declare -A NODES
  NODES["$TARGET"]="$IP"
fi

for region in "${!NODES[@]}"; do
  IP="${NODES[$region]}"
  echo "── $region ($IP) ──"
  ssh $SSH_OPTS "ubuntu@$IP" "sudo systemctl stop levpn" 2>/dev/null || true
  scp $SSH_OPTS "$PROJECT_DIR/server-linux" "ubuntu@$IP:/home/ubuntu/server"
  ssh $SSH_OPTS "ubuntu@$IP" "chmod +x /home/ubuntu/server && sudo systemctl start levpn"
  echo "  ✓ OK"
done
