#!/bin/bash

# Lets pub fetch our private Font Awesome fork from gitlab over HTTPS using the
# FONT_AWESOME_GITLAB_ACCESS_TOKEN access token, so the git dep resolves during pub get.
# See pubspec.yaml for the token's expiry and renewal locations.

set -euo pipefail

git config --global \
  url."https://oauth2:${FONT_AWESOME_GITLAB_ACCESS_TOKEN}@gitlab.wearespindle.com/".insteadOf \
  "git@gitlab.wearespindle.com:"

echo "✅ Configured GitLab access for the private Font Awesome package"
