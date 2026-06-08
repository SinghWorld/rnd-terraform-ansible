# rnd-terraform-ansible

Provision a **Windows EC2 Spot Instance** on AWS using Terraform, then configure it automatically via **Ansible** over WinRM. Zero manual RDP required after deploy.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         YOUR LOCAL MACHINE                       │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │ Terraform    │    │ WinRM        │    │ Ansible          │  │
│  │ (spot-*.tf)  │───▶│ bootstrap    │───▶│ (windows_setup)  │  │
│  │              │    │ (PowerShell) │    │                  │  │
│  └──────┬───────┘    └──────────────┘    └──────────────────┘  │
│         │                                                       │
│         │  1. Generate RSA key pair                             │
│         │  2. Request spot instance                             │
│         │  3. Inject userdata.ps1 (WinRM setup)                │
│         │  4. null_resource → update-inventory.sh              │
│         │  5. Ansible connects via WinRM port 5985             │
└─────────┼───────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      AWS us-east-1                               │
│                                                                  │
│  ┌──────────────────────┐    ┌───────────────────────────────┐ │
│  │ Default VPC          │    │ WinRM Security Group          │ │
│  │                      │    │   - TCP 5985 (HTTP)           │ │
│  │  ┌────────────────┐  │    │   - TCP 5986 (HTTPS)          │ │
│  │  │ Windows 2022   │◀─┼────│   - TCP 3389 (RDP)            │ │
│  │  │ Spot Instance  │  │    │                               │ │
│  │  │ t3.medium      │  │    └───────────────────────────────┘ │
│  │  └────────────────┘  │                                      │
│  └──────────────────────┘                                      │
└─────────────────────────────────────────────────────────────────┘
```

### Component Map

| File | Purpose |
|---|---|
| `terraform/spot-instance.tf` | Core Terraform: key pair, SG, spot instance request, auto-inventory |
| `terraform/spot-variables.tf` | All tunable variables (region, instance type, spot price, etc.) |
| `terraform/spot-outputs.tf` | Outputs: public IP, connection strings, Ansible one-liner |
| `terraform/spot-userdata.ps1` | PowerShell bootstrap run on first boot — enables WinRM, creates admin |
| `scripts/deploy.sh` | Orchestrates password injection + terraform init/apply |
| `scripts/update-inventory.sh` | Called by Terraform null_resource — writes public IP to `inventory.ini` |
| `scripts/verify_winrm.sh` | Polls port 5985 until WinRM is ready, prints next steps |
| `ansible/inventory.ini` | Dynamic inventory — IP updated automatically by Terraform |
| `ansible/ansible.cfg` | Ansible configuration (WinRM transport, host key checking off) |
| `ansible/playbooks/windows_setup.yml` | Example playbook: win_ping, file create, shell echo |

---

## Prerequisites

### Required on Your Local Machine

| Tool | Version | Install |
|---|---|---|
| **Terraform** | ≥ 1.5.0 | [hashicorp.com/terraform](https://developer.hashicorp.com/terraform/install) |
| **Ansible** | ≥ 2.9 | `pip install ansible` or [docs.ansible.com](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) |
| **AWS CLI** | v2 | `brew install awscli` or [aws.amazon.com/cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| **Bash 4+** | ≥ 4.0 | macOS: `brew install bash`; Linux: already present |
| **netcat** (nc) | any | Pre-installed on most Linux/macOS; for WinRM port polling |
| **curl** | any | Pre-installed; used for WinRM health check |

### AWS Account Requirements

| Requirement | Detail |
|---|---|
| **AWS Account** | Must have permissions to: `ec2:RunInstances`, `ec2:CreateKeyPair`, `ec2:Describe*`, `ec2:DeleteKeyPair`, `ec2:CancelSpotInstanceRequests`, `iam:CreateServiceLinkedRole` (if required) |
| **Servicequotas** | Ensure you have EC2 spot instance quota for `t3.medium` (or your chosen type) in `us-east-1` |
| **Default VPC** | Must exist in `us-east-1` with at least one available subnet. The Terraform uses the **default VPC** automatically. |
| **AWS Region** | Defaults to `us-east-1`. Change `var.aws_region` in `terraform/spot-variables.tf` to use another region. |

### Python / Ansible Windows Dependencies

Ansible's `win_*` modules require the `pywinrm` library on the **control node** (your machine):

```bash
pip install pywinrm
```

---

## Setup Instructions

### 1. Clone and Navigate

```bash
git clone https://github.com/SinghWorld/rnd-terraform-ansible.git
cd rnd-terraform-ansible
```

### 2. Authenticate to AWS

```bash
# Verify you're logged in
aws sts get-caller-identity

# If not logged in:
aws configure
# Follow prompts to set AWS Access Key ID, Secret Access Key, default region (us-east-1)
```

### 3. Install Local Dependencies

**macOS / Linux:**

```bash
# Terraform
brew install terraform        # macOS
# or: sudo apt install terraform   # Ubuntu/Debian
# or: download from https://developer.hashicorp.com/terraform/downloads

# Ansible + pywinrm
pip install ansible pywinrm

# Verify
terraform version
ansible --version
```

**Windows (WSL2 recommended):**

```bash
# In WSL2 Ubuntu:
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
pip install ansible pywinrm
```

### 4. Deploy the Spot Instance

```bash
# Set your Windows admin password (must be ≥12 characters)
export TF_VAR_winrm_password="YourStr0ngP@ss!"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/update-inventory.sh scripts/verify_winrm.sh

# Run the deploy
./scripts/deploy.sh
```

**What `deploy.sh` does:**

1. Reads `TF_VAR_winrm_password` and validates length ≥ 12
2. Injects the password into `terraform/spot-userdata.ps1` (restores original afterwards — never committed)
3. Runs `terraform init` and `terraform validate`
4. Runs `terraform apply -auto-approve`
5. The `null_resource.update_inventory` provisioner calls `update-inventory.sh` to write the new public IP to `ansible/inventory.ini`
6. Restores the original `userdata.ps1` (no secrets left on disk)

### 5. Wait for Windows to Boot + WinRM to Start

```bash
./scripts/verify_winrm.sh
```

This script:
- Reads the public IP from `terraform output`
- Polls port 5985 every 15 seconds (up to 10 minutes)
- Performs an HTTP health check against `http://<IP>:5985/wsman`
- Prints connection strings and Ansible test commands

> **Windows takes 5–8 minutes** from `terraform apply` to WinRM being fully operational. The `verify_winrm.sh` script handles the wait automatically.

### 6. Run Ansible

```bash
cd ansible
ansible-playbook -i inventory.ini playbooks/windows_setup.yml
```

Expected output:

```
TASK [ping : PING]
ok: [3.235.x.x]

TASK [dir : DIR - Create TestDirectory on C drive]
changed: [3.235.x.x]

TASK [file : FILE - Create test.txt]
changed: [3.235.x.x]
...
```

---

## Configuration

### Terraform Variables

Override by setting environment variables before `terraform apply`:

| Variable | Env Var | Default | Description |
|---|---|---|---|
| `aws_region` | `TF_VAR_aws_region` | `us-east-1` | AWS region |
| `spot_project_name` | `TF_VAR_spot_project_name` | `win-spot-demo` | Prefix for all resource names |
| `spot_key_name` | `TF_VAR_spot_key_name` | `win-spot-key` | EC2 key pair name |
| `spot_instance_type` | `TF_VAR_spot_instance_type` | `t3.medium` | EC2 instance type (t3.medium minimum for Windows) |
| `spot_price` | `TF_VAR_spot_price` | `0.05` | Max $/hour bid for spot instance |
| `spot_interruption_behavior` | `TF_VAR_spot_interruption_behavior` | `stop` | `stop` \| `hibernate` \| `terminate` on interruption |
| `winrm_password` | `TF_VAR_winrm_password` | *(none — required)* | Windows local admin password |

Example:

```bash
export TF_VAR_spot_instance_type="t3.large"
export TF_VAR_spot_price="0.08"
export TF_VAR_winrm_password="MyStr0ngP@ss!"
./scripts/deploy.sh
```

### Spot Price Guidance

| Instance Type | Approximate On-Demand/hr | Suggested Spot Ceiling | Notes |
|---|---|---|---|
| `t3.medium` | ~$0.05 | `$0.05–0.06` | Minimum for Windows |
| `t3.large` | ~$0.08 | `$0.08–0.10` | Better for active workloads |
| `t3.xlarge` | ~$0.15 | `$0.15–0.18` | Headroom for price spikes |

Set `spot_price` to the on-demand price as a safe starting point. The instance will not be fulfilled if the current spot price exceeds your ceiling.

---

## How It Works — Technical Deep Dive

### Phase 1: Terraform Apply

```
1. tls_private_key.ec2_key
   → Generates a 4096-bit RSA key pair locally
   → Public key is sent to AWS to create an EC2 Key Pair
   → Private key is written to scripts/<key_name>.pem (0600 permissions)

2. aws_key_pair.ec2_key
   → Registers the public key with AWS under key_name
   → Allows SSH/RDP password decryption using the private .pem file

3. data "aws_ami" "windows"
   → Queries AWS for the most recent Windows_Server-2022-English-Full-Base AMI
   → Owned by amazon, hvm virtualization, x86_64 architecture

4. data "aws_vpc" "default" + data "aws_subnets" "default"
   → Auto-discovers your default VPC and its subnets
   → Picks the first subnet for instance placement

5. aws_security_group.windows_spot
   → Creates a security group in the default VPC
   → Inbound: TCP 5985 (WinRM HTTP), 5986 (WinRM HTTPS), 3389 (RDP)
   → Outbound: all traffic allowed

6. aws_spot_instance_request.windows_spot
   → Requests a spot instance (not on-demand)
   → user_data = the spot-userdata.ps1 script (base64-encoded by AWS)
   → wait_for_fulfillment = true  → terraform blocks until instance is active
   → Spot price ceiling from var.spot_price; if market price > ceiling, request waits

7. local_sensitive_file.private_key
   → Writes the RSA private key PEM to scripts/<key_name>.pem
   → file_permission = "0600" — owner read/write only

8. null_resource.update_inventory (provisioner)
   → Runs AFTER spot instance is fulfilled (depends_on)
   → Calls ../scripts/update-inventory.sh <public_ip> ../ansible/inventory.ini
   → Uses awk to replace the IP under [windows] section
```

### Phase 2: Windows Bootstrap (userdata.ps1)

Executed by EC2 instance on first boot, running as **SYSTEM**:

```powershell
# Steps (see terraform/spot-userdata.ps1 for full script):

1. Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force
   → Allows local PowerShell scripts to run (required for Enable-PSRemoting)

2. New-LocalUser "ansible_admin"  +  Add-LocalGroupMember "Administrators"
   → Creates the account Ansible authenticates as
   → Password set from TF_VAR_winrm_password (injected before apply)

3. Set-Service WinRM -StartupType Automatic + Start-Service WinRM
   → Ensures the WinRM Windows service is running

4. Enable-PSRemoting -Force -SkipNetworkProfileCheck
   → Registers WinRM endpoints and creates HTTP listener on 0.0.0.0:5985

5. winrm set winrm/config/service '@{AllowUnencrypted="true"}'
   winrm set winrm/config/service/auth '@{Basic="true"}'
   → Enables unencrypted Basic auth over HTTP (required for Ansible pywinrm basic auth)

6. winrm create winrm/config/listener?Address=*+Transport=HTTP
   → Explicitly creates the HTTP listener on all interfaces if not already present

7. netsh advfirewall firewall add rule ... (TCP 5985, 5986) + set allprofiles state off
   → Opens firewall ports AND disables Windows Firewall completely
   → Note: restrict 0.0.0.0/0 ingress in production via AWS SG

8. Restart-Service WinRM -Force
   → Applies all configuration changes

9. netstat -an | Select-String "0.0.0.0:5985"
   → Confirms port 5985 is listening
```


### Wait then verify (critical — Windows needs 5–8 min)
```sh
cd ..
chmod +x scripts/verify_winrm.sh
./scripts/verify_winrm.sh
# This polls port 5985 and tells you when it's ready
```

### Get the IP
```sh
cd terraform && terraform output -raw public_ip
# e.g. 54.123.45.67

# Edit ansible/inventory.ini — replace WINDOWS_PUBLIC_IP and REPLACE_WITH_YOUR_PASSWORD
```

### Phase 3: Ansible Configuration

The `ansible.cfg`:

```ini
[defaults]
inventory           = inventory.ini
host_key_checking   = False   # WinRM has no host keys
retry_files_enabled = False
stdout_callback     = yaml    # Human-readable output
timeout             = 60
```

The `inventory.ini` (auto-updated by Terraform):

```ini
[windows]
<PUBLIC_IP>    # ← replaced by update-inventory.sh

[windows:vars]
ansible_user=ansible_admin
ansible_password=<TF_VAR_winrm_password>
ansible_connection=winrm           # Use WinRM, not SSH
ansible_winrm_transport=basic      # Username/password auth
ansible_winrm_port=5985
ansible_winrm_scheme=http          # Unencrypted HTTP
ansible_winrm_server_cert_validation=ignore  # No TLS cert needed
ansible_winrm_operation_timeout_sec=120
ansible_winrm_read_timeout_sec=150
```

### Phase 4: Spot Interruption Handling

| Behavior | What Happens |
|---|---|
| `stop` (default) | Instance is stopped. When restarted, userdata does **not** re-run. Data on instance store is lost. EBS volume persists. |
| `hibernate` | Instance is hibernated. Requires Hibernate to be enabled on the instance (not enabled by default). |
| `terminate` | Instance is terminated. All data lost. Terraform will need to re-apply. |

**Recommendation:** For dev/test workloads, use `stop`. For production, use `hibernate` if supported, or implement a termination notice handler using SQS + CloudWatch Events to gracefully drain workloads before interruption.

---

## Directory Structure

```
.
├── README.md                     # This file
├── .gitignore
│
├── terraform/
│   ├── spot-instance.tf          # Core resources (keypair, SG, spot instance, null_resource)
│   ├── spot-variables.tf         # All variables + defaults
│   ├── spot-outputs.tf           # All outputs (IPs, connection strings)
│   └── spot-userdata.ps1         # PowerShell bootstrap (WinRM setup)
│
├── scripts/
│   ├── deploy.sh                 # Full deploy pipeline (password injection + terraform apply)
│   ├── update-inventory.sh       # Updates ansible/inventory.ini with new public IP
│   ├── verify_winrm.sh           # Polls WinRM port until ready
│   └── win-spot-key.pem          # Private key (gitignored, generated on terraform apply)
│
└── ansible/
    ├── ansible.cfg               # Ansible defaults (WinRM transport, YAML output)
    ├── inventory.ini             # Dynamic inventory (auto-updated by Terraform)
    └── playbooks/
        └── windows_setup.yml     # Example playbook (win_ping, file, shell)
```

---

## Troubleshooting

### `terraform apply` fails with "Instance limit exceeded"

Your AWS account has a limit on running `t3.medium` instances in `us-east-1`. Request a limit increase via AWS Console → Support → Service Quotas, or switch to a smaller type (`t3.small`) temporarily.

### Spot request fulfilled but WinRM never comes up

1. **Wait longer** — Windows takes 5–8 minutes to fully boot and run userdata.
2. **Check the setup log:** RDP into the instance and run `Get-Content C:\winrm_setup.log`.
3. **Check AWS Console:** Go to EC2 → Spot Requests → check the status history.
4. **Try RDP first** (port 3389) to verify the instance itself is reachable.
5. **Verify Security Group** — ensure inbound TCP 5985 is allowed from your IP (currently `0.0.0.0/0` — restrict in production).

### `ansible-playbook` fails with `ntlm` or `certificate` error

Ensure `ansible_winrm_transport=basic` and `ansible_winrm_server_cert_validation=ignore` are set in `inventory.ini`. The current config has these; do not remove them.

### `win_update` module fails or times out

WinRM has a default shell memory limit of 150MB. The `winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'` in userdata.ps1 raises this to 1GB. If you still hit memory limits, adjust `MaxMemoryPerShellMB` higher.

### Private key (.pem) not found after deploy

The private key is written to `scripts/<key_name>.pem` by the `local_sensitive_file` Terraform resource. If you need it for RDP password decryption:

```bash
# Get the private key path from terraform output
cd terraform && terraform output private_key_path

# Make sure it's readable
chmod 600 scripts/win-spot-key.pem

# Use it to decrypt the Windows admin password (from AWS console)
```

### `update-inventory.sh` fails

The script depends on `awk`. Ensure `gawk` or `awk` is installed (standard on Linux/macOS). Also verify `inventory.ini` exists at the expected path relative to the script.

---

## Security Notes

| Concern | Current State | Production Recommendation |
|---|---|---|
| **WinRM port 5985** | Open to `0.0.0.0/0` | Restrict to your IP range via `var.winrm_cidr_blocks` in `spot-instance.tf` |
| **RDP port 3389** | Open to `0.0.0.0/0` | Restrict to your IP only |
| **Basic auth over HTTP** | Enabled (required for Ansible) | Use HTTPS + certificate validation in production |
| **Windows Firewall** | Disabled in userdata.ps1 | Keep firewall on, only open required ports |
| **Private key on disk** | Written to `scripts/*.pem` | Store in AWS Secrets Manager instead |
| **Password in env var** | `TF_VAR_winrm_password` | Use AWS Secrets Manager or Vault to inject at runtime |
| **Terraform state** | Local `terraform.tfstate` | Use S3 backend with DynamoDB locking |

---

## Cleanup

To destroy all resources created by Terraform:

```bash
cd terraform
terraform destroy -auto-approve
```

This will cancel the spot request and terminate the instance. The key pair and security group will also be deleted. The `inventory.ini` will retain the last known IP — update it manually or re-run `deploy.sh` for a fresh instance.

---

## License

MIT