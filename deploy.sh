#!/bin/bash

# DeepLinkNow iOS SDK Deployment Script
# Usage: ./deploy.sh [patch|minor|major] [optional message]

set -e

# Check if version type is provided
if [ -z "$1" ]; then
  echo "Error: Version increment type required (patch, minor, or major)"
  echo "Usage: ./deploy.sh [patch|minor|major] [optional message]"
  exit 1
fi

# Validate version type
VERSION_TYPE=$(echo "$1" | tr '[:upper:]' '[:lower:]')
if [[ "$VERSION_TYPE" != "patch" && "$VERSION_TYPE" != "minor" && "$VERSION_TYPE" != "major" ]]; then
  echo "Error: Version type must be 'patch', 'minor', or 'major'"
  exit 1
fi

# Optional commit message
COMMIT_MESSAGE=${2:-"Bump version"}

# Get current version from podspec
CURRENT_VERSION=$(grep -m 1 "s.version" DeepLinkNow.podspec | sed "s/.*[\"\']\(.*\)[\"\']/\1/")
echo "Current version: $CURRENT_VERSION"

# Split version into components
IFS='.' read -r -a VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR=${VERSION_PARTS[0]}
MINOR=${VERSION_PARTS[1]}
PATCH=${VERSION_PARTS[2]}

# Increment version based on type
if [[ "$VERSION_TYPE" == "major" ]]; then
  MAJOR=$((MAJOR + 1))
  MINOR=0
  PATCH=0
elif [[ "$VERSION_TYPE" == "minor" ]]; then
  MINOR=$((MINOR + 1))
  PATCH=0
else
  PATCH=$((PATCH + 1))
fi

# Create new version string
NEW_VERSION="$MAJOR.$MINOR.$PATCH"
echo "New version: $NEW_VERSION"

# Update version in podspec
sed -i '' "s/s.version[[:space:]]*=[[:space:]]*[\"'].*[\"']/s.version          = '$NEW_VERSION'/g" DeepLinkNow.podspec

# Update version in Package.swift if needed
if grep -q "version:" Package.swift; then
  sed -i '' "s/version:[[:space:]]*\".*\"/version: \"$NEW_VERSION\"/g" Package.swift
fi

# Update version in README.md
sed -i '' "s/Version.*svg/Version](https:\/\/img.shields.io\/cocoapods\/v\/DeepLinkNow.svg/g" README.md

# Git operations
git add DeepLinkNow.podspec Package.swift README.md
git commit -m "$COMMIT_MESSAGE: $NEW_VERSION"
git tag "$NEW_VERSION"
git push origin main
git push origin "$NEW_VERSION"

# Validate podspec
echo "Validating podspec..."
pod spec lint DeepLinkNow.podspec --allow-warnings

# Push to CocoaPods
echo "Publishing to CocoaPods..."
pod trunk push DeepLinkNow.podspec --allow-warnings

echo "✅ Successfully deployed version $NEW_VERSION to CocoaPods!" 