#!/usr/bin/env bash
if ! git rev-parse HEAD >/dev/null 2>&1; then
  echo "SKIP_NO_HEAD:${REPO_PATH}"
  exit 0
fi
head=$(git rev-parse HEAD)
short=$(git rev-parse --short HEAD)
branch=$(git symbolic-ref -q --short HEAD 2>/dev/null || echo DETACHED)
dirty=$(git status --porcelain | wc -l)
if git show-ref --verify --quiet "refs/heads/${BACKUP_BRANCH}"; then
  git branch -f "${BACKUP_BRANCH}" HEAD || { echo "FAIL_BRANCH:${REPO_PATH}"; exit 0; }
else
  git branch "${BACKUP_BRANCH}" HEAD || { echo "FAIL_BRANCH:${REPO_PATH}"; exit 0; }
fi
if git show-ref --verify --quiet "refs/tags/${BACKUP_TAG}"; then
  git tag -f "${BACKUP_TAG}" HEAD || { echo "FAIL_TAG:${REPO_PATH}"; exit 0; }
else
  git tag "${BACKUP_TAG}" HEAD || { echo "FAIL_TAG:${REPO_PATH}"; exit 0; }
fi
echo "OK:${REPO_PATH}|${head}|${short}|${branch}|dirty=${dirty}"
