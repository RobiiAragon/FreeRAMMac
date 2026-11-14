#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -project "Free RAM Mac.xcodeproj" -scheme "Free RAM Mac" -configuration Release -derivedDataPath Build/DerivedData build "$@"
codesign --verify --strict "Build/Products/Release/Free RAM Mac.app"
