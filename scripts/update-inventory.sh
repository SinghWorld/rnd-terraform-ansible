#!/bin/bash
###############################################################
# update-inventory.sh
# Updates ansible/inventory.ini with the new EC2 public IP
# Called automatically by Terraform local-exec provisioner
###############################################################

set -e

PUBLIC_IP="$1"
INVENTORY_FILE="${2:-../ansible/inventory.ini}"

if [[ -z "$PUBLIC_IP" ]]; then
  echo "ERROR: Public IP not provided"
  exit 1
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
  echo "ERROR: Inventory file not found: $INVENTORY_FILE"
  exit 1
fi

# Use awk to replace only the first IP-like line under [windows] section
awk -v ip="$PUBLIC_IP" '
/^\[windows\]/ { in_windows=1; print; next }
/^\[/ { in_windows=0 }
in_windows && /^[0-9]/ { $0 = ip; in_windows=0 }
{ print }
' "$INVENTORY_FILE" > "${INVENTORY_FILE}.tmp" && mv "${INVENTORY_FILE}.tmp" "$INVENTORY_FILE"

echo "SUCCESS: Updated $INVENTORY_FILE with public IP: $PUBLIC_IP"