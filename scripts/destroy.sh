#!/bin/bash
# scripts/destroy.sh
# ------------------
# 1. Takes your password from env var TF_VAR_winrm_password
# 2. Injects it into userdata.ps1 (replaces the placeholder)
# 3. Runs terraform destroy
#
# Usage:
#   export TF_VAR_winrm_password="MyStr0ngP@ss2024!"
#   chmod +x scripts/destroy.sh
#   ./scripts/destroy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"
USERDATA="$TF_DIR/spot-userdata.ps1"
USERDATA_RENDERED="$TF_DIR/userdata_rendered.ps1"

# ---- Check password env var ----
if [ -z "${TF_VAR_winrm_password:-}" ]; then
  echo ""
  echo "ERROR: TF_VAR_winrm_password is not set."
  echo ""
  echo "Run:  export TF_VAR_winrm_password=\"MyStr0ngP@ss2024!\""
  echo "Then: ./scripts/destroy.sh"
  echo ""
  exit 1
fi

echo "==> Password env var detected ✓"

# ---- Password complexity check ----
PWD_LEN=${#TF_VAR_winrm_password}
if [ "$PWD_LEN" -lt 12 ]; then
  echo "ERROR: Password must be at least 12 characters."
  exit 1
fi

# ---- Inject password into userdata ----
echo "==> Injecting password into userdata.ps1..."
sed "s|REPLACE_WITH_YOUR_PASSWORD|${TF_VAR_winrm_password}|g" \
    "$USERDATA" > "$USERDATA_RENDERED"

# Point main.tf to the rendered file
cp "$USERDATA" "${USERDATA}.bak"
cp "$USERDATA_RENDERED" "$USERDATA"

echo "==> userdata.ps1 updated ✓"

# ---- Terraform ----
cd "$TF_DIR"

echo ""
echo "==> terraform init..."
terraform init

echo ""
echo "==> terraform validate..."
terraform validate

echo ""
echo "==> terraform destroy..."
terraform destroy -auto-approve

# ---- Restore original userdata (never commit password in file) ----
cp "${USERDATA}.bak" "$USERDATA"
rm -f "${USERDATA}.bak" "$USERDATA_RENDERED"

echo ""
echo "=============================================="
echo "Destroy complete!"
echo ""
echo "All AWS resources have been terminated."
echo "=============================================="