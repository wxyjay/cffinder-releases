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

SAVED_STASH_REF=""

report_preserved_stash() {
  local exit_code=$?
  if [[ -n "$SAVED_STASH_REF" ]]; then
    echo "Publishing stopped before local changes were restored." >&2
    echo "Your changes remain preserved in ${SAVED_STASH_REF}." >&2
  fi
  return "$exit_code"
}

trap report_preserved_stash EXIT

has_local_changes() {
  ! git diff --quiet ||
    ! git diff --cached --quiet ||
    [[ -n "$(git ls-files --others --exclude-standard)" ]]
}

save_local_changes() {
  if ! has_local_changes; then
    return
  fi

  echo "Temporarily saving local changes before syncing main..."
  git stash push --include-untracked \
    --message "push-main-debug auto-stash $(date -u +%Y%m%dT%H%M%SZ)" >/dev/null
  SAVED_STASH_REF="stash@{0}"
}

restore_local_changes() {
  if [[ -z "$SAVED_STASH_REF" ]]; then
    return
  fi

  echo "Restoring local changes on top of the latest main..."
  if ! git stash apply --index "$SAVED_STASH_REF"; then
    echo "Failed to restore local changes automatically." >&2
    echo "Your changes remain preserved in ${SAVED_STASH_REF}; resolve the conflict, then drop it manually." >&2
    exit 1
  fi
  git stash drop --quiet "$SAVED_STASH_REF"
  SAVED_STASH_REF=""
}

sync_remote_branch() {
  local branch="$1"
  if git fetch origin "${branch}:refs/remotes/origin/${branch}" >/dev/null 2>&1; then
    if git merge-base --is-ancestor HEAD "origin/${branch}"; then
      git merge --ff-only "origin/${branch}"
    elif git merge-base --is-ancestor "origin/${branch}" HEAD; then
      echo "Local ${branch} already contains origin/${branch}."
    else
      echo "Rebasing unpublished ${branch} commits onto origin/${branch}..."
      git rebase "origin/${branch}"
    fi
  else
    echo "Remote ${branch} branch does not exist yet."
  fi
}

if [[ -n "$(git rev-parse -q --verify MERGE_HEAD 2>/dev/null || true)" ]] ||
  [[ -d "$(git rev-parse --git-path rebase-merge)" ]] ||
  [[ -d "$(git rev-parse --git-path rebase-apply)" ]]; then
  echo "A merge or rebase is already in progress. Finish or abort it before publishing." >&2
  exit 1
fi

save_local_changes
git switch main >/dev/null 2>&1 || git switch -c main
echo "Syncing main with origin/main..."
sync_remote_branch main
restore_local_changes

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
  sync_remote_branch debug
else
  echo "Remote debug branch does not exist; creating it from main."
  git switch debug >/dev/null 2>&1 || git switch -c debug main
fi

git merge --no-edit main
git push -u origin debug
git switch main >/dev/null

echo "Done."
