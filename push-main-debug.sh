#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_URL="${REMOTE_URL:-git@github.com:wxyjay/cffinder-releases.git}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-chore: update release install scripts}"

cd "$ROOT_DIR"

if [[ ! -d .git ]]; then
  git init
  git branch -M main
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "$REMOTE_URL"
fi

git config user.name "wxyjay"
git config user.email "wxyjay@users.noreply.github.com"

git switch main >/dev/null 2>&1 || git switch -c main
git add -A
if ! git diff --cached --quiet; then
  git commit -m "$COMMIT_MESSAGE"
else
  echo "No staged changes to commit."
fi

echo "Pushing main..."
git push -u origin main

echo "Pushing the same commit to debug..."
if ! git push -u origin main:debug; then
  echo
  echo "Failed to update debug with a fast-forward push."
  echo "If debug intentionally diverged, merge main into debug manually and push again."
  exit 1
fi

echo "Done."
