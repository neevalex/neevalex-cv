#!/usr/bin/env bash

set -euo pipefail

# Resolve repo root from this script location so cron can run it from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$SCRIPT_DIR}"
BRANCH="${BRANCH:-main}"
REMOTE="${REMOTE:-origin}"
TARGET_DIR="${TARGET_DIR:-/home/neevalex.com/public_html/cv}"
LOCK_FILE="${LOCK_FILE:-$REPO_DIR/.git/git-sync.lock}"
LOCK_DIR="${LOCK_FILE}.d"

timestamp() {
	date '+%Y-%m-%d %H:%M:%S'
}

log() {
	printf '[%s] %s\n' "$(timestamp)" "$*"
}

sync_to_target() {
	if ! command -v rsync >/dev/null 2>&1; then
		log "ERROR: rsync command not found"
		exit 1
	fi

	mkdir -p "$TARGET_DIR"
	log "Syncing files to $TARGET_DIR"

	rsync -a --delete \
		--exclude '.git/' \
		--exclude '.github/' \
		"$REPO_DIR/" "$TARGET_DIR/"

	log "Target sync completed"
}

if ! command -v git >/dev/null 2>&1; then
	log "ERROR: git command not found"
	exit 1
fi

if [ ! -d "$REPO_DIR/.git" ]; then
	log "ERROR: $REPO_DIR is not a git repository"
	exit 1
fi

cd "$REPO_DIR"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
	log "Another sync process is already running, exiting"
	exit 0
fi

cleanup() {
	rmdir "$LOCK_DIR" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

if [ -n "$(git status --porcelain)" ]; then
	log "WARNING: local uncommitted changes found; skipping sync"
	exit 0
fi

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
	log "ERROR: remote '$REMOTE' not found"
	exit 1
fi

REMOTE_URL="$(git remote get-url "$REMOTE")"
log "Checking updates from $REMOTE_URL ($REMOTE/$BRANCH)"

git fetch --prune "$REMOTE" "$BRANCH"

LOCAL_HASH="$(git rev-parse HEAD)"
REMOTE_HASH="$(git rev-parse "$REMOTE/$BRANCH")"
BASE_HASH="$(git merge-base HEAD "$REMOTE/$BRANCH")"

if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
	log "No updates found"
elif [ "$LOCAL_HASH" = "$BASE_HASH" ]; then
	log "Updates found; applying fast-forward sync"
	git pull --ff-only "$REMOTE" "$BRANCH"
	log "Git sync completed"
elif [ "$REMOTE_HASH" = "$BASE_HASH" ]; then
	log "Local branch is ahead of remote; continuing with target sync"
else
	log "ERROR: local and remote histories diverged; manual intervention required"
	exit 1
fi

sync_to_target
