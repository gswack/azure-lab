# Azure Price-Comparison App — Infrastructure & Deployment

This project reproduces an Azure + Terraform + Ansible mini-project on **Microsoft Azure**, using Azure-native equivalents for every AWS component. It provisions a full network, deploys a containerized frontend/backend Node.js app across public and private subnets, and uses Ansible for configuration/deployment automation.

## Architecture

```
                     Users
                       |
                  HTTP :3000
                       |
        ┌──────────────────────────────┐
        │        Azure VNet             │
        │        10.0.0.0/16            │
        │                                │
        │  ┌────────────┐  ┌───────────┐│
        │  │ Public      │  │ Private   ││
        │  │ Subnet      │  │ Subnet    ││
        │  │ 10.0.0.0/25 │  │10.0.0.128/25│
        │  │             │  │           ││
        │  │ public-vm   │  │private-vm ││
        │  │ (frontend)  │  │private-vm2││
        │  │             │  │(backends) ││
        │  │ ansible-    │  │           ││
        │  │ master      │  │           ││
        │  └────────────┘  └───────────┘│
        │         NAT Gateway ───────────┼──> Internet
        └──────────────────────────────┘
                       |
              Azure Files (NFS)
              EFS-equivalent shared storage
```

## AWS → Azure Component Mapping

| AWS | Azure |
|---|---|
| VPC | Virtual Network (VNet) |
| Subnet | Subnet |
| Internet Gateway | Implicit via Public IP + default routing |
| NAT Gateway | NAT Gateway |
| Route Tables | Route Table |
| EC2 | Virtual Machine |
| Security Groups | Network Security Groups (NSG) + Application Security Groups (ASG) |
| Amazon EFS | Azure Files (Premium, NFS protocol) |
| ECR | Docker Hub / any container registry (images built locally via Ansible) |

## Components

- **public-vm** — frontend Node.js app (Express), containerized, proxies requests to backend VMs, load-balances across both via a random-pick strategy.
- **private-vm / private-vm2** — backend Node.js app (Express + CORS), containerized, serves product data from `seed-data.json`.
- **ansible-master** — runs Ansible playbooks against frontend/backend VMs; has SSH access via a dedicated Application Security Group rule.
- **Azure Files (NFS)** — Premium FileStorage account, network-restricted to the private subnet, mounted at `/mnt/efs` on backend VMs.

## Security Groups (least privilege)

- `frontendSecurityGroup` — SSH (22) only from admin IP; SSH (22) from `ansible-master-asg`; app traffic (3000) open to internet.
- `backendSecurityGroup` — app traffic (3000) only from `frontend-asg`; SSH (22) only from `ansible-master-asg`.
- `ansibleMasterSecurityGroup` — SSH (22) only from admin IP.
- Azure Files storage account — network rules restrict access to the private subnet only (PaaS equivalent of an NSG for EFS).

## Prerequisites

- Azure CLI (`az`), authenticated (`az login`) with an active subscription
- Terraform (`>= 1.x`), AzureRM provider `5.0.0`
- An SSH keypair at `~/.ssh/id_rsa` / `id_rsa.pub`
- Your own public IP (`curl ifconfig.me`) for the `admin_ip` Terraform variable

## Setup — from scratch

### 1. Configure variables

Create `terraform/terraform.tfvars`:
```hcl
admin_ip = "YOUR_PUBLIC_IP/32"
```

### 2. Provision infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This creates the VNet, subnets, NSGs/ASGs, NAT Gateway, Route Table, all VMs, and the Azure Files (NFS) storage — and auto-generates `../ansible/inventory.ini` with the real VM IPs via a `local_file` resource.

### 3. Get onto the Ansible Master VM

```bash
terraform output ansible_master_ip
ssh azureuser@<ansible-master-ip>
```

Copy your SSH private key onto the Master so it can reach the other VMs:
```bash
# from your local machine
scp ~/.ssh/id_rsa azureuser@<ansible-master-ip>:~/.ssh/id_rsa
```
```bash
# on the Ansible Master
chmod 600 ~/.ssh/id_rsa
```

### 4. Clone the app repo onto the Master

```bash
git clone https://github.com/gswack/azure-lab.git
cd azure-lab/ansible
```

### 5. Verify connectivity

```bash
ansible all -i inventory.ini -m ping
```

### 6. Install Docker + Git on frontend/backend

```bash
ansible-playbook -i inventory.ini playbooks/install.yaml
```

### 7. Deploy the application

```bash
ansible-playbook -i inventory.ini playbooks/deploy.yaml
```

This clones the app repo onto each VM, builds Docker images from `backend/` and `frontend/`, runs the containers, and mounts the Azure Files NFS share on backend VMs.

### 8. Verify

Open `http://<public-vm-ip>:3000` in a browser and click "Refresh Products."

## Tearing down

```bash
cd terraform
terraform destroy
```

Or, to guarantee zero lingering charges immediately:
```bash
az group delete --resource-group RG --yes --no-wait
```

## Known issues / gotchas encountered during development

- **AzureRM provider v5.0.0 breaking changes**: `azurerm_subnet`'s `service_endpoints` (list) was replaced by a `service_endpoint { service = "..." }` block; resource provider auto-registration was removed (`resource_provider_registrations = "all"` needed in the `provider` block, or manually `az provider register --namespace Microsoft.Storage`).
- **Azure Files NFS shares require a minimum ~100GB quota** — smaller quotas fail with a generic `InvalidHeaderValue` error that gives no indication the real cause is the quota.
- **NFS requires Premium + FileStorage account kind** — Standard tier does not support NFS shares.
- **cloud-init `write_files` runs before the `users-groups` module** — setting `owner: azureuser:azureuser` in `write_files` fails because that user doesn't exist yet at that point in boot. Fix: omit `owner:` in `write_files`, `chown` in a later `runcmd` step instead.
- **`node:*-alpine` Docker images don't include `curl`** — code using `execFile("curl", ...)` will fail silently inside a container unless `curl` is explicitly installed (`apk add --no-cache curl`), or replaced with native `fetch()`.
- **Terraform state/reality drift**: partially-failed applies (e.g. due to Azure API race conditions like `CanceledAndSupersededDueToAnotherOperation`) can leave resources in a `Failed` state in Azure while Terraform's state is unaware. Symptom: "resource already exists, needs import" followed by further errors even after import. Fix: delete the broken resource directly via `az`, `terraform state rm` it, then re-apply.
- **Git Bash (Windows) path mangling**: absolute paths starting with `/` (e.g. Azure resource IDs passed to `terraform import`) get auto-converted to Windows paths. Prefix the command with `MSYS_NO_PATHCONV=1` to prevent this.
- **ASG-to-NSG rule references** require `source_application_security_group_ids` (list), not `source_address_prefix` (string) — the two are mutually exclusive on the same rule.