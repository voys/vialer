set -e
flutter packages pub get
. "$CM_BUILD_DIR"/utils/bin/pigeon.sh
. "$CM_BUILD_DIR"/utils/bin/strings.sh
flutter config --enable-swift-package-manager
