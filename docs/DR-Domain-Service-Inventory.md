# DR Domain and Service Inventory

> Comprehensive mapping of domains, clusters, and services between production and disaster recovery environments

## Table of Contents

- [AWS Account and Access](#aws-account-and-access)
- [Domain Architecture](#domain-architecture)
- [Cluster Mappings](#cluster-mappings)
- [Service URL Inventory](#service-url-inventory)
- [DNS Cutover Reference](#dns-cutover-reference)
- [Network Flow](#network-flow)

---

## AWS Account and Access

### AWS Account Structure

| Environment | AWS Account ID | Region | Purpose | Access Method |
|-------------|----------------|--------|---------|---------------|
| **Production** | `128765541338` | us-east-1 | Production workloads and management tools | StrongDM (SDM) |
| **Disaster Recovery** | `051826732093` | us-east-2 | DR workloads and air-gapped infrastructure | Tailscale VPN |

### Access Methods

#### Production Account (128765541338)

**Access via StrongDM:**

```bash
# Configure AWS CLI with SDM
aws configure --profile prod-sdm

# Access EKS clusters
aws eks update-kubeconfig --name mgmt-use1-eks-1 --region us-east-1 --profile prod-sdm
aws eks update-kubeconfig --name prod-use1-eks-1 --region us-east-1 --profile prod-sdm

# Example kubectl commands
kubectl config use-context arn:aws:eks:us-east-1:128765541338:cluster/mgmt-use1-eks-1
kubectl get nodes
```

**StrongDM Resources:**
- EKS clusters
- RDS databases
- EC2 instances
- All production infrastructure

#### DR Account (051826732093)

**Access via Tailscale VPN:**

```bash
# Ensure Tailscale is connected
tailscale status

# Configure AWS CLI for DR
aws configure --profile dr
# AWS Access Key ID: [your-dr-key]
# AWS Secret Access Key: [your-dr-secret]
# Default region: us-east-2

# Access EKS clusters
aws eks update-kubeconfig --name mgmt-use2-eks-1 --region us-east-2 --profile dr
aws eks update-kubeconfig --name prod-eks-1 --region us-east-2 --profile dr

# Example kubectl commands
kubectl config use-context arn:aws:eks:us-east-2:051826732093:cluster/mgmt-use2-eks-1
kubectl get nodes
```

**Tailscale Access Requirements:**
- Tailscale VPN connection active
- Access to DR subnet ranges
- IAM credentials for AWS account 051826732093

**Access Verification:**
```bash
# Verify Tailscale connection
tailscale status | grep "aws-dr"

# Verify AWS access
aws sts get-caller-identity --profile dr

# Expected output:
# {
#     "UserId": "...",
#     "Account": "051826732093",
#     "Arn": "arn:aws:iam::051826732093:user/..."
# }
```

### Security Model

**Air-Gapped Architecture:**
- DR account (051826732093) is isolated from production
- No direct network connectivity between accounts
- Transit Gateway connection on hold to maintain isolation
- Backup/restore via Clumio as primary data transfer mechanism

**Access Control:**
- Production: Multi-layered access via StrongDM
- DR: Direct access via Tailscale VPN (controlled by Tailscale ACLs)
- Separate IAM credentials for each environment
- MFA required for console access to both accounts

---

## Domain Architecture

### Domain Strategy

The disaster recovery environment uses a four-domain structure to maintain clear separation between production and DR, as well as between management, internal, and public services.

| Environment | Domain | Purpose | Region | DNS Cutover |
|-------------|--------|---------|--------|-------------|
| **Production Management** | `lkeymgmt.com` | Production management services | us-east-1 | No |
| **DR Management** | `lkeymgmtdr.com` | DR management services (Artifactory, ArgoCD, AWX) | us-east-2 | No |
| **DR Internal Services** | `lkeyproddr.com` | DR internal services (Vault, Solr, internal apps) | us-east-2 | No |
| **Production (Public)** | `lkeyprod.com` | Public-facing production services | us-east-1 → us-east-2 | Yes |

### Domain Naming Convention

All management services follow this pattern:

```
Production:  <service>.lkeymgmt.com     → mgmt-use1-eks-1
DR:          <service>.lkeymgmtdr.com   → mgmt-use2-eks-1
```

### Domain Hierarchy

```
lkeymgmt.com (Production Management Domain)
├── artifactory.lkeymgmt.com
├── argocd.lkeymgmt.com
├── awx.lkeymgmt.com
└── vault.lkeymgmt.com

lkeymgmtdr.com (DR Management Domain)
├── artifactory.lkeymgmtdr.com
├── argocd.lkeymgmtdr.com
├── awx.lkeymgmtdr.com
└── [Vault runs on lkeyproddr.com in DR]

lkeyproddr.com (DR Internal Services Domain)
├── vault.lkeyproddr.com          # HashiCorp Vault
├── solr.lkeyproddr.com            # Solr search cluster
├── acumatica.lkeyproddr.com       # Acumatica ERP
├── latitude.lkeyproddr.com        # Latitude app
└── [Other internal Windows apps]

lkeyprod.com (Public Production Domain - DNS Cutover Domain)
├── api.lkeyprod.com               # Kong API Gateway
├── greenhouse.lkeyprod.com        # Greenhouse recruiting
├── verify.lkeyprod.com            # Verification services
├── storage.lkeyprod.com           # Storage API
├── integration.lkeyprod.com       # Integration API
└── ppapi.lkeyprod.com             # Payment processing
```

---

## Cluster Mappings

### Production Environment (us-east-1)

| Cluster Name | Domain Suffix | Purpose | Services |
|--------------|---------------|---------|----------|
| **mgmt-use1-eks-1** | `.lkeymgmt.com` | Management & Platform Tools | ArgoCD, Artifactory, AWX, Vault, Jenkins |
| **prod-use1-eks-1** | `.lkeyprod.com` | Production Applications | Kong, Greenhouse, APIs |

### Disaster Recovery Environment (us-east-2)

| Cluster Name | Domain Suffix | Purpose | Services |
|--------------|---------------|---------|----------|
| **mgmt-use2-eks-1** | `.lkeymgmtdr.com` | DR Management & Platform Tools | ArgoCD, Artifactory, Vault |
| **prod-eks-1** | `.lkeyprod.com` (after cutover) | DR Production Applications | Kong, Greenhouse, APIs |
| **EC2 (Standalone)** | `.lkeymgmtdr.com` | Automation Platform | AWX/Ansible (runs in Minikube) |

**Note:** AWX/Ansible in DR runs on a dedicated EC2 instance with Minikube, not in the EKS cluster. This provides isolation for infrastructure automation.

---

## Service URL Inventory

### Management Services

#### Artifactory

| Environment | URL | Cluster | Status |
|-------------|-----|---------|--------|
| **Production** | `https://artifactory.lkeymgmt.com/` | mgmt-use1-eks-1 | Active |
| **DR** | `https://artifactory.lkeymgmtdr.com/` | mgmt-use2-eks-1 | Standby/Testing |

**Repository Types:**
- Docker: `artifactory.lkeymgmtdr.com/docker-*`
- Helm: `artifactory.lkeymgmtdr.com/helm-*`
- Maven: `artifactory.lkeymgmtdr.com/maven-*`
- NPM: `artifactory.lkeymgmtdr.com/npm-*`
- PyPI: `artifactory.lkeymgmtdr.com/pypi-*`
- NuGet: `artifactory.lkeymgmtdr.com/nuget-*`

**DR-Specific Configuration:**
```bash
# Docker login
docker login artifactory.lkeymgmtdr.com

# Helm repo add
helm repo add lk-helm https://artifactory.lkeymgmtdr.com/artifactory/helm

# Maven settings.xml
<mirror>
  <id>artifactory</id>
  <url>https://artifactory.lkeymgmtdr.com/artifactory/maven</url>
</mirror>
```

#### ArgoCD

| Environment | URL | Cluster | Status |
|-------------|-----|---------|--------|
| **Production** | `https://argocd.lkeymgmt.com/` | mgmt-use1-eks-1 | Active |
| **DR** | `https://argocd.lkeymgmtdr.com/` | mgmt-use2-eks-1 | Deployed |

**Access:**
```bash
# Production
argocd login argocd.lkeymgmt.com

# DR
argocd login argocd.lkeymgmtdr.com
```

#### AWX / Ansible

| Environment | URL | Deployment | Status |
|-------------|-----|------------|--------|
| **Production** | `https://awx.lkeymgmt.com/` | mgmt-use1-eks-1 (or EC2) | Active |
| **DR** | `https://awx.lkeymgmtdr.com/` | EC2 + Minikube | Deployed |

**DR Deployment Architecture:**

AWX in the DR environment runs on a dedicated EC2 instance with Minikube, providing:
- **Isolation:** Separates infrastructure automation from application workloads
- **Stability:** Independent from EKS cluster lifecycle
- **Bootstrap capability:** Can rebuild EKS clusters if needed

**Access:**
```bash
# Via Tailscale VPN (required for DR account access)
tailscale status

# SSH to AWX EC2 instance
ssh -i ~/.ssh/dr-key.pem ubuntu@awx-dr-instance

# Access Minikube on the instance
minikube status
kubectl get pods -n awx

# Access AWX UI
# https://awx.lkeymgmtdr.com/
```

**Key Differences from Production:**
- Production: May run in EKS or dedicated EC2
- DR: Always runs on EC2 + Minikube for isolation and resilience

#### Vault

| Environment | URL | Deployment | Status |
|-------------|-----|------------|--------|
| **Production** | `https://vault.lkeymgmt.com/` | mgmt-use1-eks-1 | Active |
| **DR** | `https://vault.lkeyproddr.com/` | 3-node EC2 cluster (m5.large) | Planning |

**DR Deployment Architecture:**

Vault in DR runs on a dedicated 3-node EC2 cluster with integrated storage (Raft), providing:
- **High Availability:** 3 nodes across 3 availability zones
- **Integrated Storage:** Raft consensus algorithm (no external storage dependency)
- **Instance Type:** m5.large per node
- **Domain:** vault.lkeyproddr.com (note: different domain from management services)

**Terraform:** Managed at `lk/aws/us-east-2/prod/vault-integrated-storage/`

**Key Differences from Production:**
- Production: May run in EKS
- DR: Always runs on dedicated EC2 cluster for stability and bootstrap capability

#### Jenkins

| Environment | URL | Cluster | Status |
|-------------|-----|---------|--------|
| **Production** | `https://jenkins.lkeymgmt.com/` | mgmt-use1-eks-1 | Active |
| **DR** | `https://jenkins.lkeymgmtdr.com/` | mgmt-use2-eks-1 | TBD |

### Production Application Services

These services use `lkeyprod.com` and will be cut over via DNS during DR activation.

#### Kong API Gateway

| Environment | URL | Cluster | DNS Cutover |
|-------------|-----|---------|-------------|
| **Production** | `https://api.lkeyprod.com/` | prod-use1-eks-1 | Active (us-east-1) |
| **DR** | `https://api.lkeyprod.com/` | prod-eks-1 | Standby (us-east-2) |

**Kong Admin API:**
- Production: `https://kong-admin.lkeymgmt.com/`
- DR: `https://kong-admin.lkeymgmtdr.com/`

#### Greenhouse (Recruiting)

| Environment | URL | Cluster | DNS Cutover |
|-------------|-----|---------|-------------|
| **Production** | `https://greenhouse.lkeyprod.com/` | prod-use1-eks-1 | Active (us-east-1) |
| **DR** | `https://greenhouse.lkeyprod.com/` | prod-eks-1 | Standby (us-east-2) |

#### Verify API

| Environment | URL | Cluster | DNS Cutover |
|-------------|-----|---------|-------------|
| **Production** | `https://verify.lkeyprod.com/` | prod-use1-eks-1 | Active (us-east-1) |
| **DR** | `https://verify.lkeyprod.com/` | prod-eks-1 | Standby (us-east-2) |

#### Storage API

| Environment | URL | Cluster | DNS Cutover |
|-------------|-----|---------|-------------|
| **Production** | `https://storage.lkeyprod.com/` | prod-use1-eks-1 | Active (us-east-1) |
| **DR** | `https://storage.lkeyprod.com/` | prod-eks-1 | Standby (us-east-2) |

#### Integration API

| Environment | URL | Cluster | DNS Cutover |
|-------------|-----|---------|-------------|
| **Production** | `https://integration.lkeyprod.com/` | prod-use1-eks-1 | Active (us-east-1) |
| **DR** | `https://integration.lkeyprod.com/` | prod-eks-1 | Standby (us-east-2) |

#### PPAPI (Payment Processing)

| Environment | URL | Cluster | DNS Cutover |
|-------------|-----|---------|-------------|
| **Production** | `https://ppapi.lkeyprod.com/` | prod-use1-eks-1 | Active (us-east-1) |
| **DR** | `https://ppapi.lkeyprod.com/` | prod-eks-1 | Standby (us-east-2) |

---

## DNS Cutover Reference

### DNS Management Strategy

#### Management Services (No Cutover)

Management services maintain separate DNS records and do NOT cut over during DR activation:

- `*.lkeymgmt.com` - Always points to us-east-1 (mgmt-use1-eks-1)
- `*.lkeymgmtdr.com` - Always points to us-east-2 (mgmt-use2-eks-1)

**Rationale:** Management tools are accessed directly by their specific domain, allowing both environments to coexist.

#### Production Services (DNS Cutover)

Production services use a single domain (`lkeyprod.com`) that is cut over during DR activation:

**Pre-Cutover (Normal Operations):**
```
*.lkeyprod.com → us-east-1 load balancers (prod-use1-eks-1)
```

**Post-Cutover (DR Active):**
```
*.lkeyprod.com → us-east-2 load balancers (prod-eks-1)
```

### DNS Cutover Procedure

#### Step 1: Reduce TTL (Pre-Cutover)

Reduce DNS TTL to 60 seconds for faster propagation:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.lkeyprod.com",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [{"Value": "<current-prod-ip>"}]
      }
    }]
  }'
```

**Wait for TTL expiration (300 seconds default) before proceeding.**

#### Step 2: Update DNS Records to DR

Update A records to point to DR load balancers:

```bash
# Get DR load balancer addresses
kubectl config use-context arn:aws:eks:us-east-2:051826732093:cluster/prod-eks-1
kubectl get svc -n kong kong-proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Update Route53
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch file://dr-dns-cutover.json
```

**Example `dr-dns-cutover.json`:**
```json
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.lkeyprod.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z215JYRZR1TBD5",
          "DNSName": "a1234567890abcdef-123456789.us-east-2.elb.amazonaws.com",
          "EvaluateTargetHealth": false
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "greenhouse.lkeyprod.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z215JYRZR1TBD5",
          "DNSName": "a1234567890abcdef-123456789.us-east-2.elb.amazonaws.com",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
```

#### Step 3: Verify DNS Propagation

```bash
# Check DNS resolution from multiple locations
dig api.lkeyprod.com +short
dig @8.8.8.8 api.lkeyprod.com +short
dig @1.1.1.1 api.lkeyprod.com +short

# Verify traffic is reaching DR
curl -I https://api.lkeyprod.com/health
```

#### Step 4: Monitor Traffic

```bash
# Watch Kong access logs in DR
kubectl logs -n kong -l app=kong -f

# Monitor error rates
kubectl get pods -n kong -w
```

### DNS Records Summary

#### Records Requiring Cutover

| Record | Type | Current (us-east-1) | DR (us-east-2) | Priority |
|--------|------|---------------------|----------------|----------|
| `api.lkeyprod.com` | A/ALIAS | prod-use1-eks-1 LB | prod-eks-1 LB | Critical |
| `greenhouse.lkeyprod.com` | A/ALIAS | prod-use1-eks-1 LB | prod-eks-1 LB | High |
| `verify.lkeyprod.com` | A/ALIAS | prod-use1-eks-1 LB | prod-eks-1 LB | High |
| `storage.lkeyprod.com` | A/ALIAS | prod-use1-eks-1 LB | prod-eks-1 LB | High |
| `integration.lkeyprod.com` | A/ALIAS | prod-use1-eks-1 LB | prod-eks-1 LB | Medium |
| `ppapi.lkeyprod.com` | A/ALIAS | prod-use1-eks-1 LB | prod-eks-1 LB | Critical |

#### Records NOT Requiring Cutover

| Record | Type | Target | Notes |
|--------|------|--------|-------|
| `artifactory.lkeymgmt.com` | A/ALIAS | mgmt-use1-eks-1 LB | Prod only |
| `artifactory.lkeymgmtdr.com` | A/ALIAS | mgmt-use2-eks-1 LB | DR only |
| `argocd.lkeymgmt.com` | A/ALIAS | mgmt-use1-eks-1 LB | Prod only |
| `argocd.lkeymgmtdr.com` | A/ALIAS | mgmt-use2-eks-1 LB | DR only |
| `awx.lkeymgmt.com` | A/ALIAS | mgmt-use1-eks-1 or EC2 | Prod only |
| `awx.lkeymgmtdr.com` | A/ALIAS | EC2 + MiniKube | DR only |
| `vault.lkeymgmt.com` | A/ALIAS | mgmt-use1-eks-1 LB | Prod only |
| `vault.lkeymgmtdr.com` | A/ALIAS | mgmt-use2-eks-1 LB | DR only |

---

## Network Flow

### Production (Normal Operations)

```
User Request
    ↓
*.lkeyprod.com (DNS → us-east-1)
    ↓
AWS ALB/NLB (us-east-1)
    ↓
Kong API Gateway (prod-use1-eks-1)
    ↓
Applications (prod-use1-eks-1)
    ↓
RDS/Aurora (us-east-1)
```

### DR (After Cutover)

```
User Request
    ↓
*.lkeyprod.com (DNS → us-east-2)
    ↓
AWS ALB/NLB (us-east-2)
    ↓
Kong API Gateway (prod-eks-1)
    ↓
Applications (prod-eks-1)
    ↓
RDS/Aurora (us-east-2, restored from Clumio)
```

### Management Tool Access

**During DR Operations:**

```
Platform Team
    ↓
Tailscale VPN + StrongDM
    ↓
┌─────────────────────────┬─────────────────────────┐
│ Production Management   │ DR Management           │
│ *.lkeymgmt.com          │ *.lkeymgmtdr.com        │
│ mgmt-use1-eks-1         │ mgmt-use2-eks-1         │
│ (us-east-1)             │ (us-east-2)             │
└─────────────────────────┴─────────────────────────┘
```

**Key Points:**
- Management services are accessed independently via their specific domains
- No DNS cutover required for management services
- Both production and DR management tools can be accessed simultaneously

---

## Configuration Management

### Kubernetes Configuration Changes

#### Applications Requiring URL Updates

Applications that reference management services need updated configurations for DR:

**Artifactory Registry:**
```yaml
# Production
image: artifactory.lkeymgmt.com/docker-local/myapp:latest

# DR
image: artifactory.lkeymgmtdr.com/docker-local/myapp:latest
```

**Helm Chart Repositories:**
```bash
# Production
helm repo add lk-helm https://artifactory.lkeymgmt.com/artifactory/helm

# DR
helm repo remove lk-helm
helm repo add lk-helm https://artifactory.lkeymgmtdr.com/artifactory/helm
helm repo update
```

**ArgoCD Applications:**
```yaml
# Production
spec:
  source:
    repoURL: https://argocd.lkeymgmt.com/git/myrepo.git

# DR
spec:
  source:
    repoURL: https://argocd.lkeymgmtdr.com/git/myrepo.git
```

#### Environment Variables

Applications may have environment variables pointing to management services:

```bash
# Production
ARTIFACTORY_URL=https://artifactory.lkeymgmt.com
VAULT_ADDR=https://vault.lkeymgmt.com
AWX_URL=https://awx.lkeymgmt.com

# DR
ARTIFACTORY_URL=https://artifactory.lkeymgmtdr.com
VAULT_ADDR=https://vault.lkeymgmtdr.com
AWX_URL=https://awx.lkeymgmtdr.com
```

### Configuration via ConfigMaps

**Recommended approach:** Use ConfigMaps for environment-specific URLs:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: platform-urls
  namespace: default
data:
  ARTIFACTORY_URL: "https://artifactory.lkeymgmtdr.com"
  ARGOCD_URL: "https://argocd.lkeymgmtdr.com"
  VAULT_URL: "https://vault.lkeymgmtdr.com"
  AWX_URL: "https://awx.lkeymgmtdr.com"
```

---

## Verification Procedures

### Management Service Verification

After DR activation, verify all management services are accessible:

```bash
# Test Artifactory
curl -s -o /dev/null -w "%{http_code}" https://artifactory.lkeymgmtdr.com/artifactory/api/system/ping
# Expected: 200

# Test ArgoCD
curl -s -o /dev/null -w "%{http_code}" https://argocd.lkeymgmtdr.com/api/version
# Expected: 200

# Test AWX
curl -s -o /dev/null -w "%{http_code}" https://awx.lkeymgmtdr.com/api/v2/ping/
# Expected: 200

# Test Vault (if deployed)
curl -s -o /dev/null -w "%{http_code}" https://vault.lkeymgmtdr.com/v1/sys/health
# Expected: 200 or 429 (sealed)
```

### Production Service Verification (Post-Cutover)

After DNS cutover, verify production services:

```bash
# Verify DNS resolution
dig api.lkeyprod.com +short
# Should show us-east-2 load balancer

# Test Kong API Gateway
curl -I https://api.lkeyprod.com/health
# Expected: HTTP 200

# Test Greenhouse
curl -I https://greenhouse.lkeyprod.com/health
# Expected: HTTP 200

# Test Verify API
curl -I https://verify.lkeyprod.com/health
# Expected: HTTP 200

# Test Storage API
curl -I https://storage.lkeyprod.com/health
# Expected: HTTP 200
```

---

## Troubleshooting

### Common Issues

#### DNS Not Resolving to DR

**Symptoms:**
- DNS still resolving to us-east-1 IPs
- Traffic not reaching DR environment

**Resolution:**
```bash
# Check DNS propagation status
dig api.lkeyprod.com @8.8.8.8 +short
dig api.lkeyprod.com @1.1.1.1 +short

# Flush local DNS cache
# Linux
sudo systemd-resolve --flush-caches
# macOS
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

# Wait for TTL expiration (check SOA record)
dig lkeyprod.com SOA
```

#### Artifactory Image Pull Failures in DR

**Symptoms:**
- Pods failing with `ImagePullBackOff`
- Error: `repository does not exist or may require 'docker login'`

**Resolution:**
```bash
# Update image pull secrets to use DR Artifactory
kubectl create secret docker-registry artifactory-dr \
  --docker-server=artifactory.lkeymgmtdr.com \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email>

# Update deployment to use new secret
kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "artifactory-dr"}]}'
```

#### Certificate Errors

**Symptoms:**
- SSL certificate warnings
- Certificate name mismatch errors

**Resolution:**
```bash
# Verify certificate is valid for domain
openssl s_client -connect artifactory.lkeymgmtdr.com:443 -servername artifactory.lkeymgmtdr.com < /dev/null | openssl x509 -noout -text | grep DNS

# Check certificate expiration
echo | openssl s_client -connect artifactory.lkeymgmtdr.com:443 2>/dev/null | openssl x509 -noout -dates
```

---

## Related Documentation

- [Main DR README](../README.md)
- [EKS Cluster Access Guide](DR-EKS-Cluster-Access.md)
- [Artifactory Xray Cache Fix](../artifactory-xray-cache-fix.md)

---

**Last Updated:** 2025-10-27
**Maintained By:** Platform Engineering Team
**Review Frequency:** Quarterly or after any domain/service changes
