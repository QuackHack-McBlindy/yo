#!/usr/bin/env bash
set -e

CARGO=./packages/yo-rs/Cargo.toml

if [ ! -f "$CARGO" ]; then
    echo "Error: File not found: $CARGO"
    exit 1
fi

current_version=$(grep '^version =' "$CARGO" | sed 's/version = "\(.*\)"/\1/')
echo "Current version: $current_version"

IFS='.' read -r major minor patch <<< "$current_version"
new_patch=$((patch + 1))
new_version="$major.$minor.$new_patch"
echo "New version: $new_version"

# Update Cargo.toml
sed -i.bak "s/^version = \".*\"/version = \"$new_version\"/" "$CARGO"
rm "$CARGO.bak"

git add .
git commit -m "Bump version to $new_version"
git tag "v$new_version"

# Push to origin (main branch)
git push origin main --tags

echo "Released version $new_version"
