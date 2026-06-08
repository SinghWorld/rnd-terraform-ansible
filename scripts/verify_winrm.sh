#!/bin/bash
# scripts/verify_winrm.sh
# ------------------------
# After terraform apply, run this script to:
#   1. Get the public IP from terraform output
#   2. Wait until WinRM port 5985 is open
#   3. Do a curl health check
#   4. Print the Ansible test command
#
# Usage:
#   cd terraform/
#   terraform apply  (done)
#   cd ..
#   ./scripts/verify_winrm.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"
MAX_WAIT=600
INTERVAL=15

# ---- Get IP from terraform ----
cd "$TF_DIR"
PUBLIC_IP=$(terraform output -raw public_ip 2>/dev/null)

if [ -z "$PUBLIC_IP" ]; then
  echo "ERROR: Could not read public_ip from terraform output."
  echo "Make sure you are inside the terraform/ directory and apply has run."
  exit 1
fi

echo "==> Windows EC2 Public IP: $PUBLIC_IP"
echo "==> Waiting for WinRM on port 5985 (up to ${MAX_WAIT}s)..."
echo "    (Windows takes 5-8 min to fully boot + run userdata)"
echo ""

ELAPSED=0
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  if nc -z -w 5 "$PUBLIC_IP" 5985 2>/dev/null; then
    echo "✓ Port 5985 is open after ${ELAPSED}s"
    break
  fi
  echo "  [${ELAPSED}s] Not ready yet — retrying in ${INTERVAL}s..."
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
  echo ""
  echo "ERROR: WinRM did not open within ${MAX_WAIT}s."
  echo "Check the instance console in AWS for errors."
  exit 1
fi

# ---- HTTP check ----
echo ""
echo "==> Performing HTTP health check on WinRM endpoint..."
HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  --connect-timeout 10 \
  "http://${PUBLIC_IP}:5985/wsman" 2>/dev/null || echo "000")

if [ "$HTTP_RESPONSE" = "200" ] || [ "$HTTP_RESPONSE" = "401" ]; then
  echo "✓ WinRM HTTP responded with code $HTTP_RESPONSE (expected: 200 or 401)"
else
  echo "⚠ WinRM HTTP returned: $HTTP_RESPONSE"
  echo "  Port is open but WinRM may still be initialising. Wait 1-2 min more."
fi

# ---- Print next steps ----
echo ""
echo "=============================================="
echo " WinRM is UP — $PUBLIC_IP:5985"
echo "=============================================="
echo ""
echo "Test with Ansible (ad-hoc ping):"
echo ""
echo "  ansible windows -i '${PUBLIC_IP},' \\"
echo "    -m win_ping \\"
echo "    -e 'ansible_user=ansible_admin' \\"
echo "    -e 'ansible_password=<YOUR_PASSWORD>' \\"
echo "    -e 'ansible_connection=winrm' \\"
echo "    -e 'ansible_winrm_transport=basic' \\"
echo "    -e 'ansible_winrm_port=5985' \\"
echo "    -e 'ansible_winrm_scheme=http' \\"
echo "    -e 'ansible_winrm_server_cert_validation=ignore'"
echo ""
echo "Or run the full playbook:"
echo "  cd ansible/"
echo "  ansible-playbook -i inventory.ini playbooks/windows_setup.yml"
echo ""
echo "RDP into the instance:"
echo "  Host: ${PUBLIC_IP}:3389"
echo "  User: ansible_admin"
echo ""
echo "View the WinRM setup log (via RDP or SSM):"
echo "  Get-Content C:\\winrm_setup.log"
echo "=============================================="
