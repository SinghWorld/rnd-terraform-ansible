# rnd-terraform-ansible

Provision a **Windows EC2 Spot Instance** on AWS using Terraform, then configure it automatically via **Ansible** over WinRM. Zero manual RDP required after deploy.

Supports **local development** and **GitHub Actions CI/CD** via OIDC federation — no long-lived AWS credentials required.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        LOCAL MACHINE / GITHUB ACTIONS             │
│                                                                   │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐ │
│  │ Terraform    │   │ PowerShell   │   │ Ansible              │ │
│  │ (spot-*.tf)  │──▶│ userdata     │──▶│ (windows_setup.yml)  │ │
│  │              │   │ bootstrap    │   │                      │ │
│  └──────┬───────┘   └──────────────┘   └──────────────────────┘ │
│         │                                                        │
│         │  1. Generate RSA 4096-bit key pair                     │
│         │  2. Request spot instance with userdata.ps1            │
│         │  3. null_resource → update-inventory.sh               │
│         │  4. Ansible connects via WinRM port 5985               │
└─────────┼────────────────────────────────────────────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────────────┐
│                         AWS us-east-1                              │
│                                                                   │
│  ┌────────────────────┐   ┌────────────────────────────────────┐ │
│  │ Default VPC        │   │ WinRM Security Group               │ │
│  │                    │   │   TCP 5985 (HTTP)                  │ │
│  │  ┌──────────────┐  │   │   TCP 5986 (HTTPS)                 │ │
│  │  │ Windows 2022 │◀──┼───│   TCP 3389 (RDP)                  │ │
│  │  │ Spot Instance│  │   └────────────────────────────────────┘ │
│  │  │ t3.medium    │  │                                          │
│  │  └──────────────┘  │                                          │
│  └────────────────────┘                                          │
└──────────────────────────────────────────────────────────────────┘
```

### Component Map

| File | Purpose |
|---|---|
| `terraform/spot-instance.tf` | Core Terraform: key pair, SG, spot instance request, auto-inventory |
| `terraform/spot-variables.tf` | All tunable variables (region, instance type, spot price, etc.) |
| `terraform/spot-outputs.tf` | Outputs: public IP, connection strings, Ansible one-liner |
| `terraform/spot-userdata.ps1` | PowerShell bootstrap — enables WinRM, creates admin account |
| `terraform/backend.tf` | S3 remote state backend (Object Lock, no DynamoDB) |
| `terraform/terraform.tfvars` | Non-sensitive defaults committed to repo |
| `scripts/01_setup_aws_oidc.sh` | Creates IAM OIDC Provider + Role, sets GitHub secrets |
| `scripts/02_setup_s3_backend.sh` | Creates S3 bucket for remote state, updates `backend.tf` |
| `scripts/05_destroy_resources.sh` | Tears down all AWS resources |
| `scripts/update-inventory.sh` | Writes public IP to `inventory.ini` after instance creation |
| `scripts/verify_winrm.sh` | Polls port 5985 until WinRM is ready |
| `ansible/inventory.ini` | Dynamic inventory — IP updated automatically by Terraform |
| `ansible/ansible.cfg` | Ansible configuration (WinRM transport, host key checking off) |
| `ansible/playbooks/windows_setup.yml` | Example playbook: win_ping, directory create, file write |
| `.github/workflows/terraform-plan.yml` | CI: runs `terraform plan` on every PR |
| `.github/workflows/terraform-apply.yml` | CI: runs `terraform apply` on PR merge, triggers Ansible |
| `.github/workflows/terraform-destroy.yml` | CI: destroys resources on workflow dispatch |
| `.github/workflows/ansible.yml` | CI: runs Ansible playbook after successful apply |

---

## Prerequisites

### Required on Your Local Machine (Local Development)

| Package | Version | Install |
|---|---|---|
| **Terraform** | ≥ 1.5.0 (CI uses 1.9.0) | [hashicorp.com/terraform](https://developer.hashicorp.com/terraform/install) |
| **Ansible** | ≥ 2.9 | `pip install ansible` or [docs.ansible.com](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) |
| **AWS CLI** | v2 | `brew install awscli` or [aws.amazon.com/cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| **Bash** | ≥ 4.0 | macOS: `brew install bash`; Linux: pre-installed |
| **git** | any | `brew install git` or system package manager |
| **gh CLI** | ≥ 2.0 | `brew install gh` or [github.com/cli](https://cli.github.com) |

### Python / Ansible Windows Dependencies

Ansible's `win_*` modules require `pywinrm` on the **control node**:

```bash
pip install pywinrm
```

### GitHub Actions CI/CD (No Local Credentials Required)

| Tool | Purpose |
|---|---|
| **GitHub repo** | Source of truth; workflows run on `ubuntu-latest` |
| **OIDC Provider** | Set up by `scripts/01_setup_aws_oidc.sh` — no long-lived keys |
| **S3 bucket** | Created by `scripts/02_setup_s3_backend.sh` — remote state |
| **GitHub Secrets** | `AWS_ROLE_ARN`, `TF_VAR_winrm_password`, `TF_VAR_tf_state_bucket` |

### AWS Account Requirements

| Requirement | Detail |
|---|---|
| **AWS Account** | Must have permissions for: `ec2:RunInstances`, `ec2:CreateKeyPair`, `ec2:Describe*`, `ec2:DeleteKeyPair`, `ec2:CancelSpotInstanceRequests`, `iam:CreateOpenIDConnectProvider`, `iam:CreateRole`, `iam:AttachRolePolicy`, `s3:*` |
| **Service Quotas** | EC2 spot instance quota for `t3.medium` (or your chosen type) in `us-east-1` |
| **Default VPC** | Must exist in `us-east-1` with at least one available subnet |
| **AWS Region** | Defaults to `us-east-1`. Override with `TF_VAR_aws_region` |

---

## Quick Start

### One-Time Setup (GitHub Actions)

```bash
git clone https://github.com/SinghWorld/rnd-terraform-ansible.git
cd rnd-terraform-ansible

# Step 1: Create OIDC provider + IAM role + GitHub secrets
./scripts/01_setup_aws_oidc.sh

# Step 2: Create S3 backend bucket + GitHub secret
./scripts/02_setup_s3_backend.sh
```

This script will:
- Create an IAM OIDC Provider linked to `token.actions.githubusercontent.com`
- Create an IAM Role with `AmazonEC2FullAccess`, `AmazonS3FullAccess`, `AmazonDynamoDBFullAccess`, `IAMFullAccess`
- Create an S3 bucket with Object Lock (7-day GOVERNANCE retention) and AES-256 encryption
- Set GitHub Secrets: `AWS_ROLE_ARN`, `TF_VAR_winrm_password`, `TF_VAR_tf_state_bucket`
- Update `terraform/backend.tf` automatically

### Local Development

```bash
# Authenticate to AWS
aws sts get-caller-identity
aws configure   # if not logged in

# Set your Windows admin password (≥12 characters)
export TF_VAR_winrm_password="YourStr0ngP@ss!"

# Install dependencies
brew install terraform ansible awscli gh

# Make scripts executable
chmod +x scripts/*.sh

# Deploy
./scripts/deploy.sh
```

### Wait for WinRM

```bash
./scripts/verify_winrm.sh
# Polls port 5985 every 15 seconds (up to 10 minutes)
# Windows takes 5–8 minutes from apply to WinRM ready
```

### Run Ansible

```bash
cd ansible
ansible-playbook -i inventory.ini playbooks/windows_setup.yml
```

---

## CI/CD Pipeline

### Workflow Overview

```
PR opened
  └── terraform-plan.yml     → validates + plans (no changes applied)
       └── terraform-apply.yml (merged) → terraform apply
                                          └── ansible.yml → win_ping + setup
```

### terraform-plan.yml

- **Trigger:** Every pull request touching `terraform/**`, `scripts/**`, `.github/workflows/terraform-*.yml`
- **What it does:** `terraform init`, `validate`, `plan`
- **Artifacts:** `tfplan` file uploaded for review
- **Security:** Injects `TF_VAR_winrm_password` into `userdata.ps1` only for plan, then restores original file via `git checkout`

### terraform-apply.yml

- **Trigger:** PR merged to main, or manual `workflow_dispatch`
- **What it does:**
  1. Injects password into `userdata.ps1` (restores via `git checkout` after apply)
  2. `terraform init -upgrade`, `validate`, `apply -auto-approve`
  3. Uploads private key and public IP as artifacts
  4. Triggers `ansible.yml` via `repository_dispatch` event
  5. Posts PR comment with public IP on merge

### terraform-destroy.yml

- **Trigger:** Manual `workflow_dispatch`
- **What it does:** `terraform destroy -auto-approve` for all AWS resources

### ansible.yml

- **Trigger:** `repository_dispatch` event type `ansible-run`
- **What it does:** Runs `windows_setup.yml` against the deployed Windows instance
- **Inputs:** `public_ip` passed from `terraform-apply.yml`

---

## Configuration

### Terraform Variables

Override by setting `TF_VAR_*` environment variables:

| Variable | Env Var | Default | Description |
|---|---|---|---|
| `aws_region` | `TF_VAR_aws_region` | `us-east-1` | AWS region |
| `spot_project_name` | `TF_VAR_spot_project_name` | `win-demo` | Prefix for all resource names |
| `spot_key_name` | `TF_VAR_spot_key_name` | `win-demo-key` | EC2 Key Pair name |
| `spot_instance_type` | `TF_VAR_spot_instance_type` | `t3.medium` | EC2 instance type |
| `spot_price` | `TF_VAR_spot_price` | `0.05` | Max $/hour bid for spot |
| `spot_interruption_behavior` | `TF_VAR_spot_interruption_behavior` | `stop` | `stop` \| `hibernate` \| `terminate` |
| `winrm_username` | `TF_VAR_winrm_username` | `ansible_admin` | Windows admin user |
| `winrm_password` | `TF_VAR_winrm_password` | *(required)* | Windows admin password |

### Spot Price Guidance

| Instance Type | Approx. On-Demand/hr | Suggested Spot Ceiling |
|---|---|---|
| `t3.medium` | ~$0.05 | $0.05–0.06 |
| `t3.large` | ~$0.08 | $0.08–0.10 |
| `t3.xlarge` | ~$0.15 | $0.15–0.18 |

Set `spot_price` to the on-demand price as a safe starting point.

---

## Technical Deep Dive

### Phase 1: Terraform Apply

```
tls_private_key.ec2_key
  → Generates 4096-bit RSA key pair locally
  → Public key sent to AWS to create EC2 Key Pair
  → Private key written to scripts/<key_name>.pem (0600 permissions)

aws_key_pair.ec2_key
  → Registers public key with AWS

data "aws_ami" "windows"
  → Queries latest Windows_Server-2022-English-Full-Base AMI
  → Owned by amazon, hvm virtualization, x86_64

data "aws_vpc" "default" + data "aws_subnets" "default"
  → Auto-discovers default VPC and first available subnet

aws_security_group.windows_spot
  → Inbound: TCP 5985 (WinRM HTTP), 5986 (WinRM HTTPS), 3389 (RDP)
  → Outbound: all traffic

aws_spot_instance_request.windows_spot
  → Requests spot instance (not on-demand)
  → user_data = base64-encoded spot-userdata.ps1
  → wait_for_fulfillment = true  → blocks until instance is active

local_sensitive_file.private_key
  → Writes RSA private key PEM to scripts/<key_name>.pem

null_resource.update_inventory (provisioner)
  → Runs AFTER spot instance is fulfilled (depends_on)
  → Calls scripts/update-inventory.sh to write IP to ansible/inventory.ini
```

### Phase 2: Windows Bootstrap (userdata.ps1)

Executed by EC2 as **SYSTEM** on first boot:

```powershell
# Step 1: Set-ExecutionPolicy Unrestricted
Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force

# Step 2: Create local admin for Ansible
New-LocalUser "ansible_admin" (password from TF_VAR_winrm_password)
Add-LocalGroupMember "Administrators" → ansible_admin

# Step 3: Ensure WinRM service is running
Set-Service WinRM -StartupType Automatic
Start-Service WinRM

# Step 4: Enable-PSRemoting
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Step 5: Configure WinRM
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'
winrm set winrm/config '@{MaxTimeoutms="1800000"}'

# Step 6: Create HTTP listener on all interfaces
winrm create winrm/config/listener?Address=*+Transport=HTTP

# Step 7: Firewall rules + disable Windows Firewall
netsh advfirewall firewall add rule → TCP 5985, 5986 allow
netsh advfirewall set allprofiles state off

# Step 8: Restart WinRM
Restart-Service WinRM -Force

# Step 9: Confirm port 5985 is listening
netstat -an | Select-String "0.0.0.0:5985"
```

Log file: `C:\winrm_setup.log` on the instance.

### Phase 3: Ansible Configuration

`ansible.cfg`:
```ini
[defaults]
inventory           = inventory.ini
host_key_checking   = False
retry_files_enabled = False
stdout_callback     = yaml
timeout             = 60
```

`inventory.ini` (auto-updated by Terraform):
```ini
[windows]
TARGET_IP

[windows:vars]
ansible_user=ansible_admin
ansible_connection=winrm
ansible_winrm_transport=basic
ansible_winrm_port=5985
ansible_winrm_scheme=http
ansible_winrm_server_cert_validation=ignore
ansible_winrm_operation_timeout_sec=120
ansible_winrm_read_timeout_sec=150
```

### Phase 4: S3 Backend with Object Lock

- **Bucket:** Created by `02_setup_s3_backend.sh` with Object Lock (GOVERNANCE, 7 days)
- **No DynamoDB:** Uses S3 native `use_lockfile = true` instead of DynamoDB locking
- **Encryption:** AES-256 via `put-bucket-encryption`
- **Public access:** Blocked via `put-public-access-block`

### Phase 5: OIDC Authentication

- **Provider URL:** `https://token.actions.githubusercontent.com`
- **Thumbprint:** `6938fd4d98bab03faadb97b34396831e3780aea1`
- **Condition:** `sub: repo:SinghWorld/rnd-terraform-ansible:*` — only this repo can assume the role
- **No long-lived keys:** AWS credentials are short-lived, obtained via `aws-actions/configure-aws-credentials@v4`

---

## Directory Structure

```
.
├── README.md
├── .gitignore
│
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml      # PR: init → validate → plan
│       ├── terraform-apply.yml     # Merge/dispatch: apply → trigger Ansible
│       ├── terraform-destroy.yml   # Dispatch: destroy all resources
│       └── ansible.yml             # Dispatch: run windows_setup.yml
│
├── terraform/
│   ├── spot-instance.tf            # Key pair, SG, spot instance, null_resource
│   ├── spot-variables.tf           # All variables
│   ├── spot-outputs.tf             # All outputs
│   ├── spot-userdata.ps1           # PowerShell bootstrap (WinRM setup)
│   ├── backend.tf                  # S3 remote state (auto-updated)
│   └── terraform.tfvars            # Non-sensitive defaults
│
├── scripts/
│   ├── 01_setup_aws_oidc.sh        # OIDC provider + IAM role + GitHub secrets
│   ├── 02_setup_s3_backend.sh      # S3 bucket + backend.tf update
│   ├── 05_destroy_resources.sh     # Destroy all AWS resources
│   ├── update-inventory.sh         # Write IP to inventory.ini (called by Terraform)
│   └── verify_winrm.sh             # Poll port 5985 until WinRM ready
│
└── ansible/
    ├── ansible.cfg                 # WinRM transport, YAML output
    ├── inventory.ini               # Dynamic inventory (auto-updated)
    └── playbooks/
        └── windows_setup.yml       # win_ping, directory, file write
```

---

## Troubleshooting

### Terraform fails with "Instance limit exceeded"

Request a limit increase via AWS Console → Support → Service Quotas, or switch to a smaller type (`t3.small`) temporarily.

### Spot request fulfilled but WinRM never comes up

1. **Wait longer** — Windows takes 5–8 minutes to fully boot
2. **Check the setup log:** RDP in and run `Get-Content C:\winrm_setup.log`
3. **Check AWS Console:** EC2 → Spot Requests → status history
4. **Verify Security Group:** inbound TCP 5985 allowed from your IP

### `ansible-playbook` fails with NTLM or certificate error

Ensure `ansible_winrm_transport=basic` and `ansible_winrm_server_cert_validation=ignore` are set in `inventory.ini`. The current config has these — do not remove them.

### `update-inventory.sh` fails

The script depends on `awk`. Ensure `gawk` or `awk` is installed (standard on Linux/macOS).

### Private key not found after deploy

```bash
cd terraform && terraform output -raw private_key_path
chmod 600 scripts/win-spot-key.pem
# Use it to decrypt Windows admin password from AWS console
```

---

## Security Notes

| Concern | Current State | Production Recommendation |
|---|---|---|
| **WinRM port 5985** | Open to `0.0.0.0/0` | Restrict to your IP range in `spot-instance.tf` |
| **RDP port 3389** | Open to `0.0.0.0/0` | Restrict to your IP only |
| **Basic auth over HTTP** | Enabled (required for Ansible) | Use HTTPS + certificate validation in production |
| **Windows Firewall** | Disabled in userdata.ps1 | Keep firewall on, only open required ports |
| **Private key on disk** | Written to `scripts/*.pem` | Store in AWS Secrets Manager instead |
| **Password in env var** | `TF_VAR_winrm_password` | Use AWS Secrets Manager or Vault |
| **Terraform state** | S3 with Object Lock | Already remote; add versioning + access logging |
| **OIDC Role** | `AmazonEC2FullAccess` (wide) | Replace with least-privilege IAM policy |

---

## Cleanup

### Local

```bash
cd terraform
terraform destroy -auto-approve
```

### GitHub Actions (all resources)

```bash
# Via workflow dispatch in the GitHub UI:
# Actions → terraform-destroy → Run workflow
```

The `05_destroy_resources.sh` script also provides a local destroy option.

---

## License

MIT