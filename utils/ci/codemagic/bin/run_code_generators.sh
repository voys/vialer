set -e
cp pubspec.lock pubspec_before.lock
flutter packages pub get
if ! diff pubspec.lock pubspec_before.lock ; then
    echo "===ERROR==="
    echo "Your commit should include changes to pubspec.lock after running: flutter pub get"
    exit 1
fi

. "$CM_BUILD_DIR"/utils/bin/pigeon.sh
. "$CM_BUILD_DIR"/utils/bin/strings.sh
flutter config --enable-swift-package-manager
