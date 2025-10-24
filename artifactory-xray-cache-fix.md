# Artifactory DR - Xray Cache Issue Fix

## Problem Description

After restoring Artifactory from backup to the DR environment in AWS us-east-1, Helm repository index queries are failing with HTTP 500 errors:

```bash
curl -s -k -u $JFROGAUTH -X GET https://artifactory.lkeymgmtdr.com/artifactory/helm/index.yaml
```

**Error Response:**
```json
{
  "errors" : [ {
    "status" : 500,
    "message" : "Internal error"
  } ]
}
```

## Root Cause

Log analysis reveals the issue is related to Xray integration:

```
[jfrt ] [ERROR] [1c09bd49729b9c5e] [ySupportedTypesHandlerImpl:134] [http-nio-8081-exec-5] - Xray supported types cache is empty.
[jfrt ] [WARN ] [1c09bd49729b9c5e] [.r.ArtifactoryResponseBase:144] [http-nio-8081-exec-5] - Sending HTTP error code 500: Internal error
```

The Artifactory instance is trying to communicate with Xray (JFrog's security scanning service), but the Xray supported types cache was not properly restored/populated after the backup restoration.

## Solution Options

### Option 1: Rebuild Xray Cache (if Xray is needed in DR)

Use this option if Xray is deployed and should be functional in the DR environment.

**Step 1: Verify Xray is running**
```bash
# Check if Xray service is running
kubectl get pods -n <namespace> | grep xray

# Check Xray service endpoint
kubectl get svc -n <namespace> | grep xray
```

**Step 2: Rebuild Xray cache**
```bash
# Trigger Xray cache rebuild
curl -X POST -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/system/xray/cache/rebuild

# Or sync with Xray
curl -X POST -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/xray/supportedTypes/sync
```

**Step 3: Test the index endpoint**
```bash
curl -s -k -u $JFROGAUTH -X GET https://artifactory.lkeymgmtdr.com/artifactory/helm/index.yaml
```

---

### Option 2: Disable Xray Integration on Helm Repository (RECOMMENDED for DR)

Use this option if Xray is not running in DR or not required for disaster recovery operations.

**Step 1: Get current repository configuration**
```bash
curl -s -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/repositories/helm > helm-config.json
```

**Step 2: Disable Xray indexing**
```bash
curl -X POST -u $JFROGAUTH \
  -H "Content-Type: application/json" \
  -d '{"key":"helm","xrayIndex":false}' \
  https://artifactory.lkeymgmtdr.com/artifactory/api/repositories/helm
```

**Step 3: Clear cache and recalculate index**
```bash
# Clear the Helm repository cache
curl -X DELETE -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/caches/helm

# Recalculate the Helm index
curl -X POST -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/helm/helm/reindex
```

**Step 4: Test the index endpoint**
```bash
curl -s -k -u $JFROGAUTH -X GET https://artifactory.lkeymgmtdr.com/artifactory/helm/index.yaml
```

---

### Option 3: Disable Xray Integration Globally

Use this option if Xray should be disabled across all repositories in the DR environment.

**Step 1: Check current Xray configuration**
```bash
curl -s -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/system/configuration | grep -i xray
```

**Step 2: Disable Xray integration**

This requires accessing the Artifactory UI as an admin:
1. Navigate to: **Administration > Xray > Settings**
2. Disable Xray integration
3. Save configuration

Alternatively, edit the system configuration XML to disable Xray (requires system restart).

**Step 3: Restart Artifactory**
```bash
kubectl rollout restart statefulset/artifactory -n <namespace>
```

**Step 4: Recalculate indexes after restart**
```bash
# Clear all caches
curl -X DELETE -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/caches

# Recalculate Helm index
curl -X POST -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/helm/helm/reindex
```

---

## Additional Troubleshooting Commands

### Clear Cache Commands
```bash
# Clear cache for specific index.yaml file
curl -X DELETE -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/caches/helm/index.yaml

# Clear cache for entire Helm repository
curl -X DELETE -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/caches/helm

# Clear all caches (use with caution)
curl -X DELETE -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/caches
```

### Repository Health Checks
```bash
# Get repository configuration
curl -s -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/repositories/helm

# Check storage info
curl -s -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/storageinfo

# List all repositories
curl -s -u $JFROGAUTH https://artifactory.lkeymgmtdr.com/artifactory/api/repositories
```

### Check Artifactory Logs
```bash
# View recent logs
kubectl logs -n <namespace> artifactory-0 --tail=100 | grep -i "error\|exception"

# Follow logs in real-time
kubectl logs -n <namespace> artifactory-0 -f

# Check service log file
kubectl exec -n <namespace> artifactory-0 -- tail -100 /var/opt/jfrog/artifactory/log/artifactory-service.log
```

---

## Recommended Approach

For a DR environment, **Option 2** is recommended:
1. Xray is typically not critical for disaster recovery operations
2. Disabling Xray per-repository is quick and non-invasive
3. Docker images are already pulling successfully
4. This avoids the complexity of Xray deployment/configuration in DR

**Action Plan:**
1. Disable Xray indexing on repositories (per-repo or globally)
2. Clear caches for all affected repositories
3. Delete old index files (index.yaml for Helm, metadata for Maven/NPM)
4. Regenerate indexes using repository-specific reindex APIs
5. Test the repositories
6. Repeat for any other repositories experiencing similar issues

### Automated Scripts

Two scripts have been created to automate this process:

**1. `clear-helm-indexes.sh` - Helm repositories only**
```bash
cd ~/disaster-recovery-k8s
export JFROGAUTH="username:password"
./clear-helm-indexes.sh
```

This script will:
- Find all Helm repositories (local, remote, virtual)
- Clear virtual repository caches (forces re-aggregation)
- Zap remote repository caches (forces re-fetch)
- Delete old index.yaml files from local repositories
- Regenerate index.yaml files for local repositories

**2. `clear-all-artifactory-caches.sh` - All repositories**
```bash
cd ~/disaster-recovery-k8s
export JFROGAUTH="username:password"
./clear-all-artifactory-caches.sh
```

This script will:
- Find ALL repositories (Helm, Maven, NPM, Docker, PyPI, NuGet, etc.)
- Clear caches based on repository type (virtual/remote/local)
- Delete old index/metadata files
- Regenerate indexes using package-specific APIs:
  - Helm: Delete index.yaml + reindex
  - Maven: Recalculate metadata
  - NPM: Reindex
  - PyPI: Reindex
  - NuGet: Recalculate metadata
- Report success/failure with HTTP status codes

---

## Prevention for Future DR Restores

When performing future Artifactory backup restorations to DR:

1. **Before restoration:** Document which services (Xray, etc.) will not be available in DR
2. **During restoration:** Include Xray data in backup if Xray will be running in DR
3. **After restoration:** Run post-restore scripts to:
   - Disable Xray integration on all repositories (if not running in DR)
   - Clear all caches
   - Recalculate all repository indexes
   - Verify critical repository endpoints

**Post-restore script example:**
```bash
#!/bin/bash
# Disable Xray and rebuild indexes for all repositories

REPOS=("helm" "docker-local" "npm" "maven")

for repo in "${REPOS[@]}"; do
  echo "Processing repository: $repo"

  # Disable Xray
  curl -X POST -u $JFROGAUTH \
    -H "Content-Type: application/json" \
    -d "{\"key\":\"$repo\",\"xrayIndex\":false}" \
    https://artifactory.lkeymgmtdr.com/artifactory/api/repositories/$repo

  # Clear cache
  curl -X DELETE -u $JFROGAUTH \
    https://artifactory.lkeymgmtdr.com/artifactory/api/caches/$repo

  echo "Completed: $repo"
done

# Recalculate Helm indexes specifically
for repo in "${REPOS[@]}"; do
  if [[ $repo == *"helm"* ]]; then
    curl -X POST -u $JFROGAUTH \
      https://artifactory.lkeymgmtdr.com/artifactory/api/helm/$repo/reindex
  fi
done
```

---

## References

- [Artifactory REST API - Cache Management](https://www.jfrog.com/confluence/display/JFROG/Artifactory+REST+API#ArtifactoryRESTAPI-CacheManagement)
- [Helm Repository Configuration](https://www.jfrog.com/confluence/display/JFROG/Helm+Chart+Repositories)
- [Xray Integration](https://www.jfrog.com/confluence/display/JFROG/Xray+Integration)
