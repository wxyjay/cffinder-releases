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

echo "Merging main into debug..."
if git fetch origin debug:refs/remotes/origin/debug >/dev/null 2>&1; then
  git switch debug >/dev/null 2>&1 || git switch -c debug --track origin/debug
  if ! git merge --ff-only origin/debug; then
    echo
    echo "Local debug has diverged from origin/debug."
    echo "Please inspect the debug branch manually, then rerun this script."
    exit 1
  fi
else
  echo "Remote debug branch does not exist; creating it from main."
  git switch debug >/dev/null 2>&1 || git switch -c debug main
fi

git merge --no-edit main
git push -u origin debug
git switch main >/dev/null

echo "Done."
