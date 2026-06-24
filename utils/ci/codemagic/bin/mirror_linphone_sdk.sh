#!/bin/bash

# Mirrors the flaky Linphone SDK repo locally and points the gitlab URL at it via
# git insteadOf, so SPM resolves from disk during the build. Gitlab outages fail
# (and retry) here instead of mid-build.

set -euo pipefail

GITLAB_URL="https://gitlab.linphone.org/BC/public/linphone-sdk-swift-ios.git"
LOCAL_MIRROR="$HOME/linphone-sdk-swift-ios-mirror.git"
TIMEOUT_SECONDS=300
DELAY_SECONDS=2

CLONE_LOG="$(mktemp)"

echo "Cloning Linphone SDK from gitlab into a local mirror..."
SECONDS=0
attempt=0
while true; do
  attempt=$((attempt + 1))
  rm -rf "$LOCAL_MIRROR"
  if git clone --mirror "$GITLAB_URL" "$LOCAL_MIRROR" >"$CLONE_LOG" 2>&1; then
    break
  fi
  if [ "$SECONDS" -ge "$TIMEOUT_SECONDS" ]; then
    echo "❌ Failed to clone Linphone SDK from gitlab after $attempt attempt(s) over ${TIMEOUT_SECONDS}s"
    cat "$CLONE_LOG"
    exit 1
  fi
  sleep "$DELAY_SECONDS"
done

# Point the gitlab URL at the local clone.
git config --global "url.file://$LOCAL_MIRROR.insteadOf" "$GITLAB_URL"

echo "✅ Linphone SDK mirrored locally after $attempt attempt(s); gitlab URL now resolves from $LOCAL_MIRROR"
