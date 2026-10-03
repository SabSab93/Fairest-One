#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.5}"
  FLUTTER_HOME="${VERCEL_CACHE_DIR:-$PWD/.vercel-cache}/flutter-$FLUTTER_VERSION"

  if [[ ! -x "$FLUTTER_HOME/bin/flutter" ]]; then
    mkdir -p "$(dirname "$FLUTTER_HOME")"
    git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  fi

  export PATH="$FLUTTER_HOME/bin:$PATH"
fi

flutter config --no-analytics --enable-web

flutter pub get
flutter build web --release --no-wasm-dry-run --base-href=/
