#!/bin/bash

# Script to clear caches AND regenerate indexes for all Artifactory repositories
# Usage: ./clear-all-artifactory-caches.sh

set -e

if [ -z "$JFROGAUTH" ]; then
  echo "Error: JFROGAUTH environment variable not set"
  echo "Usage: export JFROGAUTH='username:password' or 'username:api-key'"
  exit 1
fi

ARTIFACTORY_URL="https://artifactory.lkeymgmtdr.com/artifactory"

echo "=========================================="
echo "Artifactory Cache Cleanup & Reindex Script"
echo "=========================================="
echo ""

# Get all repositories
echo "Fetching list of all repositories..."
REPOS=$(curl -s -u "$JFROGAUTH" "$ARTIFACTORY_URL/api/repositories" | jq -r '.[].key')

if [ -z "$REPOS" ]; then
  echo "Error: Could not fetch repositories list"
  exit 1
fi

REPO_COUNT=$(echo "$REPOS" | wc -l)
echo "Found $REPO_COUNT repositories"
echo ""

# Counter for progress
COUNTER=0

# Loop through each repository
for REPO in $REPOS; do
  COUNTER=$((COUNTER + 1))
  echo "[$COUNTER/$REPO_COUNT] Processing: $REPO"

  # Get repository type and package type
  REPO_INFO=$(curl -s -u "$JFROGAUTH" "$ARTIFACTORY_URL/api/repositories/$REPO")
  RCLASS=$(echo "$REPO_INFO" | jq -r '.rclass')
  PACKAGE_TYPE=$(echo "$REPO_INFO" | jq -r '.packageType')

  echo "  Type: $RCLASS, Package: $PACKAGE_TYPE"

  # Clear cache based on repository type
  case $RCLASS in
    virtual)
      echo "  - Clearing virtual repository cache..."
      RESULT=$(curl -s -w "%{http_code}" -o /dev/null -X POST -u "$JFROGAUTH" \
        "$ARTIFACTORY_URL/api/virtual/$REPO/cache/cleanup")
      if [ "$RESULT" = "200" ] || [ "$RESULT" = "204" ]; then
        echo "  ✓ Virtual cache cleared"
      else
        echo "  ⚠ Virtual cache cleanup failed (HTTP $RESULT)"
      fi
      ;;
    remote)
      echo "  - Zapping remote repository cache..."
      RESULT=$(curl -s -w "%{http_code}" -o /dev/null -X POST -u "$JFROGAUTH" \
        "$ARTIFACTORY_URL/api/repositories/$REPO/zap")
      if [ "$RESULT" = "200" ] || [ "$RESULT" = "204" ]; then
        echo "  ✓ Remote cache zapped"
      else
        echo "  ⚠ Remote cache zap failed (HTTP $RESULT)"
      fi
      ;;
    local)
      echo "  - Local repository (no remote cache)"
      ;;
  esac

  # Package-specific operations: delete old indexes + regenerate
  case $PACKAGE_TYPE in
    helm)
      if [ "$RCLASS" = "local" ]; then
        echo "  - Deleting old Helm index.yaml..."
        DELETE_RESULT=$(curl -s -w "%{http_code}" -o /dev/null -X DELETE -u "$JFROGAUTH" \
          "$ARTIFACTORY_URL/$REPO/index.yaml")
        if [ "$DELETE_RESULT" = "204" ] || [ "$DELETE_RESULT" = "200" ]; then
          echo "  ✓ Old index.yaml deleted"
        elif [ "$DELETE_RESULT" = "404" ]; then
          echo "  - No existing index.yaml found"
        else
          echo "  ⚠ Failed to delete index.yaml (HTTP $DELETE_RESULT)"
        fi

        echo "  - Regenerating Helm index..."
        REINDEX_RESULT=$(curl -s -w "%{http_code}" -o /dev/null -X POST -u "$JFROGAUTH" \
          "$ARTIFACTORY_URL/api/helm/$REPO/reindex")
        if [ "$REINDEX_RESULT" = "200" ] || [ "$REINDEX_RESULT" = "204" ]; then
          echo "  ✓ Helm index regenerated"
        else
          echo "  ⚠ Helm reindex failed (HTTP $REINDEX_RESULT)"
        fi
      else
        echo "  - Helm $RCLASS repository (index handled by aggregation/cache)"
      fi
      ;;
    maven)
      if [ "$RCLASS" = "local" ]; then
        echo "  - Recalculating Maven metadata..."
        RESULT=$(curl -s -w "%{http_code}" -o /dev/null -X POST -u "$JFROGAUTH" \
          "$ARTIFACTORY_URL/api/maven/calculateMetadata/$REPO")
        if [ "$RESULT" = "200" ] || [ "$RESULT" = "204" ]; then
          echo "  ✓ Maven metadata recalculated"
        else
          echo "  ⚠ Maven metadata calculation failed (HTTP $RESULT)"
        fi
      fi
      ;;
    npm)
      if [ "$RCLASS" = "local" ]; then
        echo "  - Reindexing NPM repository..."
        RESULT=$(curl -s -w "%{http_code}" -o /dev/null -X POST -u "$JFROGAUTH" \
          "$ARTIFACTORY_URL/api/npm/$REPO/reindex")
        if [ "$RESULT" = "200" ] || [ "$RESULT" = "204" ]; then
          echo "  ✓ NPM repository reindexed"
        else
          echo "  ⚠ NPM reindex failed (HTTP $RESULT)"
        fi
      fi
      ;;
    pypi)
      if [ "$RCLASS" = "local" ]; then
        echo "  - Reindexing PyPI repository..."
        RESULT=$(curl -s -w "%{http_code}" -o /dev/null -X POST -u "$JFROGAUTH" \
          "$ARTIFACTORY_URL/api/pypi/$REPO/reindex")
        if [ "$RESULT" = "200" ] || [ "$RESULT" = "204" ]; then
          echo "  ✓ PyPI repository reindexed"
        else
          echo "  ⚠ PyPI reindex failed (HTTP $RESULT)"
        fi
      fi
      ;;
    nuget)
      if [ "$RCLASS" = "local" ]; then
        echo "  - Recalculating NuGet metadata..."
        RESULT=$(curl -s -w "%{http_code}" -o /dev/null -X POST -u "$JFROGAUTH" \
          "$ARTIFACTORY_URL/api/nuget/$REPO/reindex")
        if [ "$RESULT" = "200" ] || [ "$RESULT" = "204" ]; then
          echo "  ✓ NuGet metadata recalculated"
        else
          echo "  ⚠ NuGet reindex failed (HTTP $RESULT)"
        fi
      fi
      ;;
    docker)
      echo "  - Docker repository (no index regeneration needed)"
      ;;
    *)
      echo "  - $PACKAGE_TYPE repository (no specific reindex operation)"
      ;;
  esac

  echo "  ✓ Repository processing completed"
  echo ""
done

echo "=========================================="
echo "Cache cleanup and reindexing completed"
echo "=========================================="
echo ""
echo "Post-processing steps:"
echo ""
echo "1. Recalculate storage info:"
echo "   curl -X POST -u \$JFROGAUTH $ARTIFACTORY_URL/api/storageinfo/calculate"
echo ""
echo "2. Check Artifactory logs:"
echo "   kubectl logs -n <namespace> artifactory-0 --tail=100"
echo ""
echo "3. Test Helm repository:"
echo "   curl -s -k -u \$JFROGAUTH $ARTIFACTORY_URL/helm/index.yaml | head -20"
echo ""
