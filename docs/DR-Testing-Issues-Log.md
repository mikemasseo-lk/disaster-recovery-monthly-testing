# DR Testing Issues and Resolutions Log

> Running log of issues encountered during DR testing, resolutions applied, and lessons learned

## Table of Contents

- [Overview](#overview)
- [Issue Template](#issue-template)
- [Active Issues](#active-issues)
- [Resolved Issues](#resolved-issues)
- [Recurring Issues](#recurring-issues)
- [Monthly Test Reports](#monthly-test-reports)
- [Lessons Learned](#lessons-learned)

---

## Overview

### Purpose

This document tracks all issues encountered during disaster recovery testing and activation procedures. It serves as:

- **Knowledge Base:** Central repository of problems and solutions
- **Process Improvement:** Identifies recurring issues for permanent fixes
- **RTO Tracking:** Documents time impact of issues on recovery objectives
- **Runbook Enhancement:** Captures missing steps and edge cases

### Usage Guidelines

1. **Log issues immediately** when encountered during DR testing
2. **Document resolution steps** in detail for future reference
3. **Update status** as issues progress from active to resolved
4. **Tag recurring issues** to prioritize permanent fixes
5. **Review monthly** to identify trends and improvement opportunities

### Issue Severity Levels

| Severity | Impact | Definition |
|----------|--------|------------|
| **Critical** | Blocks DR activation | Prevents critical services from operating |
| **High** | Significantly delays activation | Adds 1+ hours to RTO |
| **Medium** | Minor delays | Adds < 1 hour to RTO |
| **Low** | No impact on RTO | Documentation or non-critical issues |

---

## Issue Template

Copy and use this template when logging new issues:

```markdown
### [YYYY-MM-DD] Issue Title

**Issue ID:** DR-YYYY-MM-NNN
**Date Encountered:** YYYY-MM-DD
**Test Type:** [Monthly Test | Full DR Activation | Partial Test]
**Severity:** [Critical | High | Medium | Low]
**Component:** [EKS | RDS | Artifactory | ArgoCD | DNS | Network | etc.]
**Status:** [Active | In Progress | Resolved | Monitoring]

**Description:**
Detailed description of the issue encountered.

**Impact:**
- Impact on RTO/RPO
- Affected services/components
- Downstream effects

**Environment:**
- Region: us-east-2
- Cluster: [mgmt-use2-eks-1 | prod-eks-1]
- Date/Time: YYYY-MM-DD HH:MM UTC

**Steps to Reproduce:**
1. Step one
2. Step two
3. ...

**Resolution:**
Detailed steps taken to resolve the issue.

**Root Cause:**
Analysis of why the issue occurred.

**Prevention:**
Changes made to prevent recurrence:
- Configuration changes
- Documentation updates
- Process improvements
- Automation/scripts added

**Time Impact:**
- Time to detect: X minutes
- Time to resolve: Y minutes
- Total RTO impact: Z minutes

**Related Issues:** [Links to similar issues]

**Updated By:** [Name]
```

---

## Active Issues

> Issues currently being investigated or worked on

### [2025-10-27] ArgoCD Not Working After Deployment

**Issue ID:** DR-2025-10-001
**Date Encountered:** 2025-10-24 (Friday DR test)
**Test Type:** Monthly Test
**Severity:** High
**Component:** ArgoCD
**Status:** In Progress

**Description:**
ArgoCD was deployed to the mgmt-use2-eks-1 cluster during Friday's DR test but is not functioning correctly. The cluster was scaled down after Friday's test and will be scaled up today (Monday, October 27) to continue troubleshooting.

**Impact:**
- Blocks GitOps-based application deployment
- Cannot sync applications to DR cluster
- Affects ability to deploy production workloads via ArgoCD
- High impact on RTO if not resolved

**Environment:**
- Region: us-east-2
- Cluster: mgmt-use2-eks-1
- Account: 051826732093
- Date/Time: 2025-10-24 (initial testing on Friday)
- Resume: 2025-10-27 (Monday - today)

**Current State:**
- ArgoCD deployed with HA configuration (3 replicas for most components)
- All pods in Pending state (cluster scaled to zero after Friday test)
- Ingress configured at argocd.lkeymgmtdr.com
- Internal ALB: internal-k8s-argocd-mgmtargo-5e3fb4bf02-136895325.us-east-2.elb.amazonaws.com

**Deployed Components:**
- Application Controller (StatefulSet: 0/3)
- ApplicationSet Controller (Deployment: 0/3)
- Repo Server (Deployment: 0/3)
- API Server (Deployment: 0/3)
- Dex Server (Deployment: 0/1)
- Notifications Controller (Deployment: 0/1)
- Redis HA (StatefulSet: 0/3 + HAProxy Deployment: 0/3)

**Steps to Reproduce:**
1. Deploy ArgoCD to mgmt-use2-eks-1 cluster
2. Scale up cluster nodes
3. Wait for pods to start
4. Attempt to access https://argocd.lkeymgmtdr.com/
5. Observe issue (details TBD when cluster scaled up)

**Troubleshooting Steps Planned:**
1. Scale up cluster nodes
2. Verify all pods reach Running state
3. Check ArgoCD server logs
4. Verify ingress/ALB configuration
5. Test DNS resolution for argocd.lkeymgmtdr.com
6. Verify SSL certificates
7. Check ArgoCD configuration (repo access, credentials, etc.)

**Related Configuration:**
- Ingress: `kubectl get ingress -n argocd`
- Service: `kubectl get svc -n argocd mgmt-argocd-server`
- Pods: `kubectl get pods -n argocd`

**Resolution:**
_In progress - being worked on today (Monday, October 27)_

**Time Impact:**
- Time to detect: TBD
- Time to troubleshoot (so far): 4+ hours (Friday session)
- Estimated additional time: TBD
- Total RTO impact: TBD

**Related Issues:** None yet

**Updated By:** Mike Masseo

<!-- Use the template above to add new active issues below -->

---

## Resolved Issues

### [2025-04-15] Artifactory Helm Repository 500 Errors After Restore

**Issue ID:** DR-2025-04-001
**Date Encountered:** 2025-04-15
**Test Type:** Monthly Test
**Severity:** High
**Component:** Artifactory
**Status:** Resolved

**Description:**
After restoring Artifactory from backup to DR environment, all Helm chart queries returned HTTP 500 errors. The Artifactory UI was accessible, but `helm search` and `helm install` commands failed.

**Impact:**
- Blocked deployment of applications via ArgoCD
- Added 2 hours to RTO
- Affected all Helm-based deployments

**Environment:**
- Region: us-east-2
- Cluster: mgmt-use2-eks-1
- Date/Time: 2025-04-15 14:30 UTC

**Steps to Reproduce:**
1. Restore Artifactory data from S3 backup
2. Start Artifactory pods in DR cluster
3. Attempt to query Helm repository: `helm search repo lk-helm`
4. Observe HTTP 500 errors in response

**Resolution:**

Created and ran cache cleanup script:

```bash
export JFROGAUTH="username:api-key"
./clear-helm-indexes.sh
```

Script actions:
1. Cleared virtual repository caches (forced re-aggregation)
2. Zapped remote repository caches (forced re-fetch from upstream)
3. Deleted old `index.yaml` files from local repositories
4. Regenerated `index.yaml` files via Artifactory API

After running script, all Helm repositories returned valid responses.

**Root Cause:**
Artifactory caches and indexes contain references to the production environment (us-east-1) and are not automatically updated when restoring to a different environment (us-east-2). The index files and cached metadata become stale and cause internal server errors.

**Prevention:**
- Added `clear-helm-indexes.sh` script to repository
- Updated DR runbook to include cache clearing as standard post-restore step
- Created expanded `clear-all-artifactory-caches.sh` for all repository types
- Documented in [artifactory-xray-cache-fix.md](../artifactory-xray-cache-fix.md)

**Time Impact:**
- Time to detect: 5 minutes
- Time to troubleshoot: 45 minutes
- Time to develop fix: 30 minutes
- Time to execute fix: 10 minutes
- Total RTO impact: 90 minutes

**Related Issues:** DR-2025-04-002 (Xray integration)

**Updated By:** Mike Masseo

---

### [2025-04-15] Artifactory Xray Integration Errors After Restore

**Issue ID:** DR-2025-04-002
**Date Encountered:** 2025-04-15
**Test Type:** Monthly Test
**Severity:** Medium
**Component:** Artifactory, Xray
**Status:** Resolved

**Description:**
After restoring Artifactory, the Xray integration was failing with errors. Xray is used for security scanning of artifacts, and the integration was pointing to the wrong Xray instance URL.

**Impact:**
- Security scanning not functional
- Did not block application deployment
- Added 30 minutes to RTO for investigation

**Environment:**
- Region: us-east-2
- Cluster: mgmt-use2-eks-1
- Date/Time: 2025-04-15 15:00 UTC

**Steps to Reproduce:**
1. Restore Artifactory from backup
2. Check Xray integration status in Artifactory UI
3. Observe connection errors to Xray service

**Resolution:**
Cleared Artifactory and Xray caches to force re-synchronization:

```bash
# Clear all Artifactory caches
curl -X POST -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/system/storage/gc

# Run comprehensive cache cleanup
./clear-all-artifactory-caches.sh
```

**Root Cause:**
Xray integration configuration and cached connection data referenced production environment URLs and endpoints. After restore, these needed to be cleared and re-established for DR environment.

**Prevention:**
- Documented in [artifactory-xray-cache-fix.md](../artifactory-xray-cache-fix.md)
- Added Xray verification to post-restore checklist
- Included in comprehensive cache cleanup script

**Time Impact:**
- Time to detect: 10 minutes
- Time to resolve: 20 minutes
- Total RTO impact: 30 minutes

**Related Issues:** DR-2025-04-001 (Helm caches)

**Updated By:** Mike Masseo

---

### [2025-03-24] EKS Cluster IAM Access Issues

**Issue ID:** DR-2025-03-001
**Date Encountered:** 2025-03-24
**Test Type:** Monthly Test
**Severity:** High
**Component:** EKS
**Status:** Resolved

**Description:**
Unable to access EKS cluster (mgmt-use2-eks-1) with kubectl after initial deployment. Authentication errors occurred when running `kubectl get nodes`.

**Impact:**
- Complete inability to manage Kubernetes cluster
- Blocked all DR testing activities
- Added 3 hours to initial cluster setup

**Environment:**
- Region: us-east-2
- Cluster: mgmt-use2-eks-1
- Date/Time: 2025-03-24 10:00 UTC

**Steps to Reproduce:**
1. Deploy EKS cluster via Terraform
2. Run `aws eks update-kubeconfig --name mgmt-use2-eks-1 --region us-east-2`
3. Attempt `kubectl get nodes`
4. Receive authentication error

**Resolution:**

1. Added IAM user/role to EKS cluster's aws-auth ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapUsers: |
    - userarn: arn:aws:iam::051826732093:user/platform-admin
      username: platform-admin
      groups:
        - system:masters
```

2. Updated kubeconfig:
```bash
aws eks update-kubeconfig --name mgmt-use2-eks-1 --region us-east-2 --profile dr
```

3. Verified access:
```bash
kubectl get nodes
kubectl get pods -A
```

**Root Cause:**
Terraform configuration did not include IAM mappings for platform team members to access the EKS cluster. The cluster was created but access was not properly configured.

**Prevention:**
- Updated Terraform to include IAM mappings in initial deployment
- Created [DR-EKS-Cluster-Access.md](DR-EKS-Cluster-Access.md) documentation
- Added cluster access verification to deployment checklist

**Time Impact:**
- Time to detect: 5 minutes
- Time to troubleshoot: 120 minutes
- Time to resolve: 45 minutes
- Total RTO impact: 170 minutes

**Related Issues:** None

**Updated By:** Johann Ramos

---

### [2025-03-24] AWX Routing Issues

**Issue ID:** DR-2025-03-002
**Date Encountered:** 2025-03-24
**Test Type:** Monthly Test
**Severity:** Medium
**Component:** AWX/Ansible
**Status:** Resolved

**Description:**
AWX deployed on EC2 instance with MiniKube was accessible internally but could not be reached from outside the VPC via the configured domain name.

**Impact:**
- AWX web UI inaccessible
- Unable to run Ansible playbooks remotely
- Added 1 hour to RTO

**Environment:**
- Region: us-east-2
- Instance: EC2 instance with MiniKube
- Date/Time: 2025-03-24 16:00 UTC

**Steps to Reproduce:**
1. Deploy AWX on EC2 instance with MiniKube
2. Configure DNS record for awx.lkeymgmtdr.com
3. Attempt to access from external network
4. Connection timeout

**Resolution:**

1. Updated security group to allow inbound HTTPS traffic:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxx \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0
```

2. Configured Traefik ingress in MiniKube:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: awx-ingress
spec:
  rules:
  - host: awx.lkeymgmtdr.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: awx-service
            port:
              number: 80
```

3. Verified external access via Tailscale VPN

**Root Cause:**
- Security group did not include necessary inbound rules for HTTPS
- Ingress configuration was not properly set up for external access

**Prevention:**
- Documented security group requirements
- Created Terraform module for AWX deployment with correct networking
- Added to DR runbook verification steps

**Time Impact:**
- Time to detect: 10 minutes
- Time to resolve: 50 minutes
- Total RTO impact: 60 minutes

**Related Issues:** None

**Updated By:** Johann Ramos

---

## Recurring Issues

> Issues that have occurred multiple times across different test cycles

### Artifactory Cache Issues

**Occurrences:** 3 (April 2025, March 2025, February 2025)
**Severity:** High
**Components:** Artifactory (Helm, Maven, NPM, Docker)

**Pattern:**
Every time Artifactory is restored from backup, repository caches become stale and cause various types of failures (500 errors, missing artifacts, index corruption).

**Current Mitigation:**
Run comprehensive cache cleanup scripts after every restore.

**Permanent Fix Status:** In Progress
- **Action:** Investigating Artifactory configuration to disable or minimize caching
- **Action:** Considering automated post-restore cache cleanup via Kubernetes Job
- **Action:** Exploring replication instead of backup/restore

**Assigned To:** Augusto Peralta

---

### DNS Propagation Delays

**Occurrences:** 2 (April 2025, March 2025)
**Severity:** Low
**Components:** Route53 DNS

**Pattern:**
Even with reduced TTL, DNS changes take longer than expected to propagate, causing delays in traffic cutover validation.

**Current Mitigation:**
- Reduce TTL to 60 seconds well in advance of testing
- Wait for full TTL expiration before cutover
- Test DNS from multiple external resolvers

**Permanent Fix Status:** Documented
- Updated runbook with TTL reduction procedures
- Added DNS verification steps to pre-test checklist

**Assigned To:** Mike Masseo

---

## Monthly Test Reports

### Template

```markdown
## [Month Year] DR Test Report

**Test Date:** YYYY-MM-DD
**Test Type:** [Full Activation | Partial Test | Component Test]
**Test Duration:** X hours
**Participants:** [List of team members]

### Test Objectives
- [ ] Objective 1
- [ ] Objective 2
- [ ] Objective 3

### Test Results

**RTO Achieved:** X hours (Target: 6-8 hours)
**RPO Achieved:** X hours (Target: < 4 hours)

**Success Criteria:**
- [ ] All critical services operational
- [ ] Database connectivity verified
- [ ] Application health checks passing
- [ ] DNS cutover successful
- [ ] All integrations functional

### Components Tested

| Component | Status | Notes |
|-----------|--------|-------|
| EKS Clusters | ✅ Pass | |
| RDS Databases | ✅ Pass | |
| Artifactory | ⚠️ Issues | See DR-2025-04-001 |
| ArgoCD | ✅ Pass | |
| Kong API Gateway | 🔵 Not Tested | |

### Issues Encountered

1. [DR-YYYY-MM-001](#) - Brief description - [Severity] - [Status]
2. [DR-YYYY-MM-002](#) - Brief description - [Severity] - [Status]

### Improvements Made

- Added cache cleanup scripts for Artifactory
- Updated documentation with new procedures
- Created automation for X process

### Action Items

- [ ] Action item 1 - Assigned to: [Name] - Due: YYYY-MM-DD
- [ ] Action item 2 - Assigned to: [Name] - Due: YYYY-MM-DD

### Lessons Learned

1. Lesson learned 1
2. Lesson learned 2

### Next Test Date

**Scheduled:** YYYY-MM-DD

```

---

### April 2025 Test Report

**Test Date:** 2025-04-15
**Test Type:** Partial Test (Management Cluster)
**Test Duration:** 4 hours
**Participants:** Mike Masseo, Augusto Peralta, Johann Ramos

#### Test Objectives
- [x] Verify EKS cluster access
- [x] Test Artifactory restoration and functionality
- [x] Deploy ArgoCD and sync applications
- [ ] Test full application deployment (deferred)
- [ ] DNS cutover test (deferred)

#### Test Results

**RTO Achieved:** N/A (partial test)
**RPO Achieved:** 24 hours (Artifactory backup age)

**Success Criteria:**
- [x] EKS management cluster accessible
- [x] Artifactory restored and operational
- [x] ArgoCD deployed and accessible
- [ ] Applications deployed via ArgoCD (deferred)
- [ ] DNS cutover test (deferred)

#### Components Tested

| Component | Status | Notes |
|-----------|--------|-------|
| EKS Management Cluster | ✅ Pass | Access via kubectl working |
| Artifactory | ⚠️ Issues | Required cache cleanup (DR-2025-04-001, DR-2025-04-002) |
| ArgoCD | ✅ Pass | Deployed via Terraform |
| Active Directory | 🟡 In Progress | Restored from Clumio, testing ongoing |
| Kong API Gateway | 🔵 Not Tested | Scheduled for next test |

#### Issues Encountered

1. [DR-2025-04-001](#2025-04-15-artifactory-helm-repository-500-errors-after-restore) - Artifactory Helm 500 errors - High - Resolved
2. [DR-2025-04-002](#2025-04-15-artifactory-xray-integration-errors-after-restore) - Xray integration failures - Medium - Resolved

#### Improvements Made

- Created `clear-helm-indexes.sh` script for post-restore cache cleanup
- Created `clear-all-artifactory-caches.sh` for comprehensive cache management
- Documented Artifactory issues in [artifactory-xray-cache-fix.md](../artifactory-xray-cache-fix.md)
- Updated DR runbook with cache cleanup procedures

#### Action Items

- [ ] Test full application deployment via ArgoCD - Assigned to: Augusto Peralta - Due: 2025-05-01
- [ ] Deploy Kong API Gateway in DR - Assigned to: TBD - Due: 2025-05-15
- [ ] Complete Active Directory testing - Assigned to: Fernando Eickhoff, Mark Fahey - Due: 2025-05-01
- [ ] Test DNS cutover procedures - Assigned to: Mike Masseo - Due: 2025-05-15
- [ ] Investigate Artifactory replication vs backup/restore - Assigned to: Augusto Peralta - Due: 2025-05-31

#### Lessons Learned

1. **Artifactory caches must be cleared after every restore** - This is now a critical step in the runbook
2. **Cache issues impact RTO significantly** - Lost 2 hours due to cache troubleshooting
3. **Scripts are essential for consistency** - Manual cache clearing is error-prone
4. **Documentation must be updated in real-time** - Captured fixes immediately while fresh

#### Next Test Date

**Scheduled:** 2025-05-15 (Full DR Activation Test)

---

### March 2025 Test Report

**Test Date:** 2025-03-24
**Test Type:** Initial Infrastructure Test
**Test Duration:** 6 hours
**Participants:** Mike Masseo, Johann Ramos

#### Test Objectives
- [x] Deploy EKS management cluster
- [x] Configure cluster access via IAM
- [x] Deploy AWX/Ansible
- [x] Test Tailscale VPN connectivity

#### Test Results

**RTO Achieved:** N/A (initial setup)
**RPO Achieved:** N/A

#### Components Tested

| Component | Status | Notes |
|-----------|--------|-------|
| EKS Management Cluster | ⚠️ Issues | IAM access issues (DR-2025-03-001) |
| AWX/Ansible | ⚠️ Issues | Routing issues (DR-2025-03-002) |
| Tailscale VPN | ✅ Pass | Connectivity working |
| StrongDM | ✅ Pass | Access working |

#### Issues Encountered

1. [DR-2025-03-001](#2025-03-24-eks-cluster-iam-access-issues) - EKS IAM access - High - Resolved
2. [DR-2025-03-002](#2025-03-24-awx-routing-issues) - AWX routing - Medium - Resolved

#### Improvements Made

- Created [DR-EKS-Cluster-Access.md](DR-EKS-Cluster-Access.md) documentation
- Updated Terraform to include IAM mappings
- Documented security group requirements for AWX

#### Action Items

- [x] Document EKS cluster access procedures - Completed 2025-03-24
- [x] Fix AWX routing issues - Completed 2025-03-24
- [x] Test Artifactory restoration - Scheduled for April 2025

#### Lessons Learned

1. **IAM access must be configured in Terraform from the start** - Don't rely on manual configuration
2. **Security groups need to be planned carefully** - Include all necessary ingress/egress rules
3. **Documentation is critical** - Created comprehensive cluster access guide

#### Next Test Date

**Scheduled:** 2025-04-15 (Artifactory and ArgoCD Test)

---

## Lessons Learned

### Process Improvements

1. **Cache Management is Critical**
   - Artifactory caches become stale after backup restoration
   - Created automated scripts to handle cache cleanup
   - Added as mandatory post-restore step in runbook

2. **Documentation During Testing**
   - Capture issues and fixes in real-time during tests
   - Don't wait until after test to document
   - Screenshots and logs are valuable for future reference

3. **Automation Reduces Errors**
   - Manual cache cleanup is error-prone and time-consuming
   - Scripts ensure consistency across test cycles
   - Automation significantly reduces RTO

4. **IAM Configuration Must Be in Code**
   - Manual IAM configuration is not reproducible
   - All access controls should be in Terraform
   - Reduces setup time for future deployments

### Technical Insights

1. **Backup/Restore vs Replication**
   - Backup/restore introduces cache invalidation issues
   - Replication may be better for services like Artifactory
   - Investigating alternatives for future improvements

2. **DNS TTL Management**
   - Reduce TTL well in advance of testing
   - Default TTLs (300s) delay cutover validation
   - 60-second TTL provides faster failover

3. **Security Group Planning**
   - Document all required ports and protocols upfront
   - Include in Terraform configuration
   - Test connectivity as part of deployment validation

### Team Coordination

1. **Cross-Team Communication**
   - DR testing requires coordination across multiple teams
   - Establish clear communication channels before testing
   - Document roles and responsibilities

2. **Knowledge Sharing**
   - This issues log serves as knowledge base
   - Review before each test to avoid repeating mistakes
   - Share learnings with broader organization

---

## Contributing to This Document

### When to Add an Issue

Add an issue to this log when:
- An error or problem occurs during DR testing
- A process takes longer than expected
- Documentation is found to be incorrect or incomplete
- A workaround or manual step is required

### When to Update an Issue

Update an issue when:
- Status changes (Active → In Progress → Resolved)
- Additional information is discovered
- Resolution steps are clarified
- Related issues are identified

### Review Cadence

- **Weekly:** Review active issues for progress
- **Monthly:** After each DR test, update with new findings
- **Quarterly:** Analyze recurring issues for permanent fixes
- **Annually:** Review entire log for archival and trend analysis

---

## Related Documentation

- [Main DR README](../README.md)
- [Domain and Service Inventory](DR-Domain-Service-Inventory.md)
- [EKS Cluster Access Guide](DR-EKS-Cluster-Access.md)
- [Artifactory Xray Cache Fix](../artifactory-xray-cache-fix.md)

---

**Last Updated:** 2025-10-27
**Maintained By:** Platform Engineering Team
**Review Frequency:** Updated after each DR test (monthly)
