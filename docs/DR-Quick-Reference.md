# DR Quick Reference Guide

> Essential information for disaster recovery operations - Keep this handy during DR testing and activation

## AWS Accounts

| Environment | AWS Account | Region | Access Method | Purpose |
|-------------|-------------|--------|---------------|---------|
| **Production** | `128765541338` | us-east-1 | StrongDM (SDM) | Production workloads |
| **DR** | `051826732093` | us-east-2 | Tailscale VPN | Disaster recovery |

## Critical URLs

### DR Management Services (lkeymgmtdr.com)

| Service | URL | Location | Notes |
|---------|-----|----------|-------|
| **ArgoCD** | https://argocd.lkeymgmtdr.com/ | mgmt-use2-eks-1 | GitOps deployment |
| **Artifactory** | https://artifactory.lkeymgmtdr.com/ | mgmt-use2-eks-1 | Artifact repository |
| **AWX** | https://awx.lkeymgmtdr.com/#/login | EC2 + Minikube | Ansible automation |

### DR Internal Services (lkeyproddr.com)

| Service | URL | Location | Notes |
|---------|-----|----------|-------|
| **Vault** | https://vault.lkeyproddr.com/ | 3-node EC2 cluster | Secrets management |
| **Solr** | https://solr.lkeyproddr.com/ | EC2 | Search cluster v8 |
| **Acumatica** | https://acumatica.lkeyproddr.com/ | EC2 | ERP system |
| **Latitude** | https://latitude.lkeyproddr.com/ | EC2 | Multi-tier app |

### Production Services (lkeyprod.com) - DNS Cutover Required

| Service | URL | Location (after cutover) |
|---------|-----|--------------------------|
| **Kong API** | https://api.lkeyprod.com/ | prod-eks-1 (us-east-2) |
| **Greenhouse** | https://greenhouse.lkeyprod.com/ | prod-eks-1 (us-east-2) |
| **Verify API** | https://verify.lkeyprod.com/ | prod-eks-1 (us-east-2) |
| **Storage API** | https://storage.lkeyprod.com/ | prod-eks-1 (us-east-2) |
| **Integration API** | https://integration.lkeyprod.com/ | prod-eks-1 (us-east-2) |
| **PPAPI** | https://ppapi.lkeyprod.com/ | prod-eks-1 (us-east-2) |

## EKS Clusters

### DR Clusters (us-east-2)

| Cluster | Purpose | Services |
|---------|---------|----------|
| **mgmt-use2-eks-1** | Management & Platform | ArgoCD, Artifactory, Vault |
| **prod-eks-1** | Production Applications | Kong, Apps, APIs |

### Access Commands

```bash
# Connect to Tailscale (required)
tailscale up
tailscale status

# Configure AWS CLI for DR
export AWS_PROFILE=dr
aws sts get-caller-identity  # Should show 051826732093

# Access management cluster
aws eks update-kubeconfig --name mgmt-use2-eks-1 --region us-east-2 --profile dr
kubectl config use-context arn:aws:eks:us-east-2:051826732093:cluster/mgmt-use2-eks-1
kubectl get nodes

# Access production cluster
aws eks update-kubeconfig --name prod-eks-1 --region us-east-2 --profile dr
kubectl config use-context arn:aws:eks:us-east-2:051826732093:cluster/prod-eks-1
kubectl get nodes
```

### Inspecting DR Resources with AWS CLI

Once AWS_PROFILE=dr is set, you can inspect all DR resources:

```bash
# Set DR profile
export AWS_PROFILE=dr

# List VPCs
aws ec2 describe-vpcs --region us-east-2

# List EC2 instances
aws ec2 describe-instances --region us-east-2 \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# List RDS instances
aws rds describe-db-instances --region us-east-2

# List FSx file systems
aws fsx describe-file-systems --region us-east-2

# List S3 buckets (all buckets, filter manually)
aws s3 ls

# List EKS clusters
aws eks list-clusters --region us-east-2

# List security groups
aws ec2 describe-security-groups --region us-east-2

# List Route53 hosted zones
aws route53 list-hosted-zones

# List load balancers
aws elbv2 describe-load-balancers --region us-east-2

# List idle/stopped instances
aws ec2 describe-instances --region us-east-2 \
  --filters "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

## Common Commands

### Artifactory Cache Cleanup

After restoring Artifactory:

```bash
# Set credentials
export JFROGAUTH="username:password"  # or "username:api-key"

# Clear Helm indexes
./clear-helm-indexes.sh

# Clear all repository caches
./clear-all-artifactory-caches.sh

# Recalculate storage
curl -X POST -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/storageinfo/calculate
```

### Verify Service Health

```bash
# ArgoCD
curl -s -o /dev/null -w "%{http_code}" https://argocd.lkeymgmtdr.com/api/version
# Expected: 200

# Artifactory
curl -s -o /dev/null -w "%{http_code}" https://artifactory.lkeymgmtdr.com/artifactory/api/system/ping
# Expected: 200

# AWX
curl -s -o /dev/null -w "%{http_code}" https://awx.lkeymgmtdr.com/api/v2/ping/
# Expected: 200
```

### DNS Cutover Commands

```bash
# Reduce TTL (do this before cutover)
aws route53 change-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --profile dr \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.lkeyprod.com",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [{"Value": "<current-ip>"}]
      }
    }]
  }'

# Verify DNS resolution
dig api.lkeyprod.com +short
dig @8.8.8.8 api.lkeyprod.com +short
```

## Important Notes

### Management Services (lkeymgmtdr.com)
- Do NOT require DNS cutover
- Always accessible via `.lkeymgmtdr.com` domain
- Independent of production services

### Production Services (lkeyprod.com)
- REQUIRE DNS cutover during DR activation
- Same domain as production
- Traffic routes to DR via Route53 update

### AWX/Ansible
- Runs on EC2 + Minikube (NOT in EKS)
- SSH access: `ssh -i ~/.ssh/dr-key.pem ubuntu@awx-instance`
- Web UI: https://awx.lkeymgmtdr.com/#/login

### Access Requirements
- **Tailscale VPN** must be active for all DR access
- AWS credentials for account 051826732093
- IAM permissions for EKS cluster access

## Post-Restore Checklist

After restoring DR environment:

- [ ] Connect to Tailscale VPN
- [ ] Verify AWS access (`aws sts get-caller-identity`)
- [ ] Access EKS clusters with kubectl
- [ ] Restore databases from Clumio
- [ ] Restore storage (EFS/FSx) from Clumio
- [ ] Restore Artifactory from S3
- [ ] Run Artifactory cache cleanup scripts
- [ ] Verify ArgoCD connectivity
- [ ] Deploy applications via ArgoCD
- [ ] Verify application health checks
- [ ] Update DNS records for lkeyprod.com
- [ ] Monitor traffic and error rates

## Emergency Contacts

**Platform Team:**
- Mike Masseo - DNS, Infrastructure
- Augusto Peralta - ArgoCD, Artifactory
- Johann Ramos - EKS, AWX
- Fernando Eickhoff - Vault, Active Directory
- Mark Fahey - Windows infrastructure, FSx

## Key Documentation

- [Main DR README](../README.md)
- [Domain and Service Inventory](DR-Domain-Service-Inventory.md)
- [EKS Cluster Access Guide](DR-EKS-Cluster-Access.md)
- [Testing Issues Log](DR-Testing-Issues-Log.md)
- [Artifactory Cache Fix](../artifactory-xray-cache-fix.md)

---

**Last Updated:** 2025-10-27
**Print and keep accessible during DR operations**
