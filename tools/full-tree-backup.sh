#!/usr/bin/env bash
# Full Lunaris tree backup: branch + tag per repo. No destructive ops.
set -euo pipefail

ROOT="${1:-/home/acer/romlar/lunaris}"
BACKUP_ID="${2:-$(date +%Y%m%d-%H%M)}"
BACKUP_BRANCH="backup-pre-update-${BACKUP_ID}"
BACKUP_TAG="safety-full-local-preserve-${BACKUP_ID}"
MANIFEST="/home/acer/romlar/BACKUP-SNAPSHOT-${BACKUP_ID}.txt"

ok=0
fail=0
skip=0

{
  echo "Lunaris full-tree backup snapshot"
  echo "Created: $(date -Iseconds)"
  echo "Backup branch: ${BACKUP_BRANCH}"
  echo "Safety tag: ${BACKUP_TAG}"
  echo "Tree: ${ROOT}"
  echo "---"
} > "${MANIFEST}"

cd "${ROOT}"

repo forall -p -c '
  if ! git rev-parse HEAD >/dev/null 2>&1; then
    echo "SKIP_NO_HEAD:${REPO_PATH}"
    exit 0
  fi
  head=$(git rev-parse HEAD)
  short=$(git rev-parse --short HEAD)
  branch=$(git symbolic-ref -q --short HEAD 2>/dev/null || echo DETACHED)
  dirty=$(git status --porcelain | wc -l)
  if git show-ref --verify --quiet "refs/heads/'"${BACKUP_BRANCH}"'"; then
    git branch -f "'"${BACKUP_BRANCH}"'" HEAD || { echo "FAIL_BRANCH:${REPO_PATH}"; exit 0; }
  else
    git branch "'"${BACKUP_BRANCH}"'" HEAD || { echo "FAIL_BRANCH:${REPO_PATH}"; exit 0; }
  fi
  if git show-ref --verify --quiet "refs/tags/'"${BACKUP_TAG}"'"; then
    git tag -f "'"${BACKUP_TAG}"'" HEAD || { echo "FAIL_TAG:${REPO_PATH}"; exit 0; }
  else
    git tag "'"${BACKUP_TAG}"'" HEAD || { echo "FAIL_TAG:${REPO_PATH}"; exit 0; }
  fi
  echo "OK:${REPO_PATH}|${head}|${short}|${branch}|dirty=${dirty}"
' 2>&1 | while IFS= read -r line; do
  echo "${line}" >> "${MANIFEST}"
  case "${line}" in
    OK:*) ok=$((ok + 1)) ;;
    FAIL_*) fail=$((fail + 1)) ;;
    SKIP_*) skip=$((skip + 1)) ;;
  esac
done

{
  echo "---"
  echo "STATS ok=${ok} fail=${fail} skip=${skip}"
} >> "${MANIFEST}"

echo "MANIFEST=${MANIFEST}"
echo "STATS ok=${ok} fail=${fail} skip=${skip}"
