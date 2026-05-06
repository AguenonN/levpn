#!/bin/bash
set -euo pipefail

REGION="${1:-}"
VALID_REGIONS="us eu asia sa"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"
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
  echo "Erreur : $TFVARS introuvable."
  exit 1
fi

CURRENT=$(grep "enable_${REGION}" "$TFVARS" | grep -o 'true\|false')
if [ "$CURRENT" = "false" ]; then
  echo "La région $REGION est déjà désactivée."
  exit 0
fi

echo "╔══════════════════════════════════════╗"
echo "║  Désactivation région : $REGION"
echo "╚══════════════════════════════════════╝"

sed -i "s/enable_${REGION} *= *true/enable_${REGION} = false/" "$TFVARS"
echo "✓ enable_${REGION} = false"

cd "$INFRA_DIR"
echo "→ terraform apply..."
terraform apply -auto-approve

echo "→ Invalidation CloudFront..."
aws cloudfront create-invalidation \
  --distribution-id "$CLOUDFRONT_ID" \
  --paths "/pac/proxy-${REGION}.pac" \
  --output text --query 'Invalidation.Id' 2>/dev/null || true

echo ""
echo "✓ Région $REGION désactivée."
grep "enable_" "$TFVARS" | grep "true" | sed 's/enable_/  ✓ /' | sed 's/ *= *true//'
