#!/bin/bash
set -euo pipefail

REGION="${1:-}"
VALID_REGIONS="us eu asia sa"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
INFRA_DIR="$PROJECT_DIR/infra"
TFVARS="$INFRA_DIR/terraform.tfvars"
CLOUDFRONT_ID="E27KNKKU5CUFYT"

if [ -z "$REGION" ]; then
  echo "Usage: $0 <region>"
  echo "Régions valides : $VALID_REGIONS"
  exit 1
fi

if ! echo "$VALID_REGIONS" | grep -qw "$REGION"; then
  echo "Erreur : région '$REGION' invalide."
  exit 1
fi

if [ ! -f "$TFVARS" ]; then
  echo "Erreur : $TFVARS introuvable. cp terraform.tfvars.example terraform.tfvars"
  exit 1
fi

CURRENT=$(grep "enable_${REGION}" "$TFVARS" | grep -o 'true\|false')
if [ "$CURRENT" = "true" ]; then
  echo "La région $REGION est déjà active."
  exit 0
fi

echo "╔══════════════════════════════════════╗"
echo "║  Activation région : $REGION"
echo "╚══════════════════════════════════════╝"

if [ ! -f "$PROJECT_DIR/server-linux" ]; then
  echo "→ server-linux introuvable, compilation..."
  cd "$PROJECT_DIR"
  GOOS=linux GOARCH=amd64 go build -o server-linux ./cmd/server/
  echo "✓ server-linux compilé"
fi

sed -i "s/enable_${REGION} *= *false/enable_${REGION} = true/" "$TFVARS"
echo "✓ enable_${REGION} = true"

cd "$INFRA_DIR"
echo "→ terraform apply..."
terraform apply -auto-approve

echo "→ Invalidation CloudFront..."
aws cloudfront create-invalidation \
  --distribution-id "$CLOUDFRONT_ID" \
  --paths "/pac/proxy-${REGION}.pac" \
  --output text --query 'Invalidation.Id' 2>/dev/null || true

echo ""
echo "✓ Région $REGION activée."
grep "enable_" "$TFVARS" | grep "true" | sed 's/enable_/  ✓ /' | sed 's/ *= *true//'
