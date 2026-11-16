#!/usr/bin/env bash
# Writes a release tag, without its leading v, into Version.swift, so the
# binary's --version says which release it is. Fails on a tag that is not a
# version, which also keeps it from breaking the sed below.
set -euo pipefail

TAG="${1:?usage: stamp-version.sh <tag>}"
if ! [[ "$TAG" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+[0-9A-Za-z.+-]*$ ]]; then
  echo "::error::$TAG is not a version."
  exit 1
fi

VERSION="${TAG#v}"
FILE=Sources/runners/Version.swift
sed "s/static let current = \"dev\"/static let current = \"$VERSION\"/" "$FILE" > "$FILE.stamped"
mv "$FILE.stamped" "$FILE"
grep -F "static let current = \"$VERSION\"" "$FILE"
