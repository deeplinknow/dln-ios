#!/bin/bash

# Recovery script for 1.0.1 deployment
# This pushes the existing 1.0.1 version to the public repo

set -e

MONOREPO_ROOT="$(git rev-parse --show-toplevel)"
PUBLIC_REPO_URL="git@github.com:jvgeee/dln-ios.git"
SUBTREE_PREFIX="packages/dln-ios"
VERSION="1.0.1"

echo "Recovering 1.0.1 deployment..."
cd "$MONOREPO_ROOT"

# Push current state to public iOS repository using git subtree
# Note: Using force push since the repos have diverged during monorepo migration
echo "Pushing to public iOS repository..."
git subtree split --prefix="$SUBTREE_PREFIX" -b temp-ios-deploy
git push "$PUBLIC_REPO_URL" temp-ios-deploy:main --force
git branch -D temp-ios-deploy

# Tag the release in the public repo
echo "Tagging public repository with $VERSION..."
TEMP_DIR=$(mktemp -d)
git clone "$PUBLIC_REPO_URL" "$TEMP_DIR"
cd "$TEMP_DIR"
git tag "$VERSION"
git push origin "$VERSION"
cd "$MONOREPO_ROOT"
rm -rf "$TEMP_DIR"

echo "✅ Successfully pushed version $VERSION to public repository"
echo ""
echo "You can now continue with CocoaPods publishing:"
echo "  cd packages/dln-ios"
echo "  pod spec lint DeepLinkNow.podspec --allow-warnings"
echo "  pod trunk push DeepLinkNow.podspec --allow-warnings"
