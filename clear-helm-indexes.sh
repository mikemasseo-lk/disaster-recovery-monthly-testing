#!/bin/bash

# Script to clear caches AND regenerate Helm index.yaml files from all Helm repositories
# Usage: ./clear-helm-indexes.sh

set -e

if [ -z "$JFROGAUTH" ]; then
  echo "Error: JFROGAUTH environment variable not set"
  echo "Usage: export JFROGAUTH='username:password' or 'username:api-key'"
  exit 1
fi

ARTIFACTORY_URL="https://artifactory.lkeymgmtdr.com/artifactory"

echo "=========================================="
echo "Helm: Clear Caches & Regenerate Indexes"
echo "=========================================="
echo ""

# Get all Helm repositories
echo "Fetching list of Helm repositories..."
HELM_REPOS=$(curl -s -u "$JFROGAUTH" "$ARTIFACTORY_URL/api/repositories" | jq -r '.[] | select(.packageType=="helm") | .key')

if [ -z "$HELM_REPOS" ]; then
  echo "Error: Could not fetch Helm repositories list"
  exit 1
fi

REPO_COUNT=$(echo "$HELM_REPOS" | wc -l)
echo "Found $REPO_COUNT Helm repositories"
echo ""

# Counter for progress
COUNTER=0

# Loop through each Helm repository
for REPO in $HELM_REPOS; do
  COUNTER=$((COUNTER + 1))
  echo "[$COUNTER/$REPO_COUNT] Processing: $REPO"

  # Get repository type
  RCLASS=$(curl -s -u "$JFROGAUTH" "$ARTIFACTORY_URL/api/repositories/$REPO" | jq -r '.rclass')
  echo "  Type: $RCLASS"

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

  # For local repos: Delete old index.yaml and regenerate
  if [ "$RCLASS" = "local" ]; then
    echo "  - Deleting old index.yaml..."
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
      echo "  ✓ Helm index regenerated successfully"
    else
      echo "  ⚠ Helm reindex failed (HTTP $REINDEX_RESULT)"
      # Try to get error details
      ERROR_MSG=$(curl -s -X POST -u "$JFROGAUTH" "$ARTIFACTORY_URL/api/helm/$REPO/reindex")
      if [ -n "$ERROR_MSG" ]; then
        echo "  Error details: $ERROR_MSG"
      fi
    fi
  fi

  echo ""
done

echo "=========================================="
echo "Helm cache cleanup and reindexing completed"
echo "=========================================="
echo ""
echo "Verification steps:"
echo ""
echo "1. Test the helm virtual repository:"
echo "   curl -s -k -u \$JFROGAUTH $ARTIFACTORY_URL/helm/index.yaml | head -30"
echo ""
echo "2. Browse in UI:"
echo "   https://artifactory.lkeymgmtdr.com/ui/native/helm/"
echo ""
echo "3. Check logs for errors:"
echo "   kubectl logs -n <namespace> artifactory-0 --tail=100 | grep -i helm"
echo ""
echo "4. Test a specific chart download:"
echo "   curl -I -u \$JFROGAUTH $ARTIFACTORY_URL/helm/generic-http-server-1.5.0.tgz"
echo ""
