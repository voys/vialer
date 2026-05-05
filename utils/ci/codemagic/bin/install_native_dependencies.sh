#!/bin/bash
set -e

retry() {
  local max_attempts=10
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    "$@" && return 0
    if [ $attempt -lt $max_attempts ]; then
      echo "⚠️ Attempt $attempt/$max_attempts failed, retrying..."
      sleep 5
    fi
    attempt=$((attempt + 1))
  done
  echo "❌ Command failed after $max_attempts attempts"
  return 1
}
export -f retry

echo "Configuring Flutter build and installing Gradle dependencies..."
retry flutter build apk --config-only \
  --target=lib/presentation/main.dart \
  --dart-define-from-file="brands/$BRAND.json"

echo "Installing Xcode package dependencies..."
defaults write com.apple.dt.Xcode IDEClonedSourcePackagesDirPathOverride -string "$HOME/spm_cache"
(cd ios && retry xcodebuild -resolvePackageDependencies -workspace Runner.xcworkspace -scheme Runner -clonedSourcePackagesDirPath "$HOME/spm_cache") || echo "⚠️ Package resolution failed, will attempt to use cached packages"

echo "Pre-caching bundle ID detection..."
xcode-project detect-bundle-id
