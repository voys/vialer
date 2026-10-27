#!/bin/bash
# Builds a signed .ipa of the native SwiftUI app in native-swift-ui for the scheme in
# $NATIVE_SCHEME, using development signing so the result installs directly on registered devices.
# Nothing here publishes anywhere; the .ipa is only kept as a build artifact.
set -e

# The native app reads its third-party keys from the repo .env (see native-swift-ui/scripts/generate_env.sh).
export SEGMENT_IOS_KEY="${SEGMENT_IOS_KEY:-$SEGMENT_IOS_WRITE_KEY}"
. utils/ci/codemagic/bin/prepare_environment_file.sh .env.example

brew list xcodegen >/dev/null 2>&1 || brew install xcodegen

cd native-swift-ui
xcodegen generate

defaults write com.apple.dt.Xcode IDEClonedSourcePackagesDirPathOverride -string "$HOME/spm_cache"
xcodebuild -resolvePackageDependencies -project Vialer.xcodeproj -scheme "$NATIVE_SCHEME" \
    -clonedSourcePackagesDirPath "$HOME/spm_cache"

keychain initialize
app-store-connect fetch-signing-files "$BUNDLE_ID" \
    --type "$IOS_SIGNING_TYPE" \
    --create
keychain add-certificates
xcode-project use-profiles --project Vialer.xcodeproj

xcode-project build-ipa \
    --project Vialer.xcodeproj \
    --scheme "$NATIVE_SCHEME" \
    --config "Release-$NATIVE_SCHEME" \
    --export-options-plist /Users/builder/export_options.plist \
    --archive-flags "-clonedSourcePackagesDirPath $HOME/spm_cache" \
    --archive-xcargs "COMPILER_INDEX_STORE_ENABLE=NO CURRENT_PROJECT_VERSION=$BUILD_NR"
