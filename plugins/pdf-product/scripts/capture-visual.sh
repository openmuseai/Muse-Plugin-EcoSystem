#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
workspace_root="$(cd "$plugin_root/../../.." && pwd)"
version="$(node -p "require('$plugin_root/product/product.json').version")"
key_root="${PDF_PRODUCT_LOCAL_KEY_DIR:-$HOME/.local/share/openmuse/pdf-product-dev}"
key_id="$(node -p "require('$key_root/identity.json').keyId")"
evidence="$workspace_root/Muse-Client/dist/pdf-product-evidence-$version"
pdf_app="$workspace_root/ioffice/koffice/pdf/rebuild/pdf-flutter-app"
flutter_root="$(cd "$(dirname "$(command -v flutter)")/.." && pwd)"

test -f "$plugin_root/dist/pdf-$version.mcpb"
test -f "$pdf_app/assets/native/libkspfreetext.dylib"
mkdir -p "$evidence"
cd "$workspace_root/Muse-Client/app/openmuse_host"
PDF_PRODUCT_E2E_BUNDLE="$plugin_root/dist/pdf-$version.mcpb" \
PDF_PRODUCT_E2E_PUBLIC_KEY="$key_root/public.pem" \
PDF_PRODUCT_E2E_KEY_ID="$key_id" \
PDF_PRODUCT_E2E_VERSION="$version" \
KSP_MAC_EDIT_DYLIB="$pdf_app/assets/native/libkspfreetext.dylib" \
PDF_PRODUCT_E2E_SCREENSHOT_DIR="$evidence" \
PDF_PRODUCT_E2E_UI_FONT="${PDF_PRODUCT_VISUAL_FONT:-/Library/Fonts/Arial Unicode.ttf}" \
PDF_PRODUCT_E2E_ICON_FONT="${PDF_PRODUCT_MATERIAL_FONT:-$flutter_root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf}" \
  flutter test --no-pub test/pdf_product_e2e_test.dart
printf 'Visual evidence: %s\n' "$evidence"
