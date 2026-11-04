#!/usr/bin/env bash
set -euo pipefail

# Local PDF product integration gate. The private key stays outside the repos.
plugin_root="$(cd "$(dirname "$0")/.." && pwd)"
workspace_root="$(cd "$plugin_root/../../.." && pwd)"
pdf_app="$workspace_root/ioffice/koffice/pdf/rebuild/pdf-flutter-app"
host="$workspace_root/Muse-Client"
platform="${1:-macos}"
case "$platform" in macos|android|all) ;; *) echo 'usage: quick-verify.sh [macos|android|all]' >&2; exit 2 ;; esac

key_root="${PDF_PRODUCT_LOCAL_KEY_DIR:-$HOME/.local/share/openmuse/pdf-product-dev}"
mkdir -p "$key_root"
if [[ ! -f "$key_root/private.pem" || ! -f "$key_root/public.pem" ]]; then
  node - "$key_root" <<'NODE'
const fs = require('fs');
const crypto = require('crypto');
const root = process.argv[2];
const pair = crypto.generateKeyPairSync('ed25519');
fs.writeFileSync(`${root}/private.pem`, pair.privateKey.export({type:'pkcs8', format:'pem'}), {mode:0o600});
fs.writeFileSync(`${root}/public.pem`, pair.publicKey.export({type:'spki', format:'pem'}));
NODE
fi
saved_key_id=""
if [[ -f "$key_root/identity.json" ]]; then
  saved_key_id="$(node -e "const fs=require('fs'); process.stdout.write(JSON.parse(fs.readFileSync(process.argv[1])).keyId)" "$key_root/identity.json")"
fi
key_id="${PDF_PRODUCT_KEY_ID:-${saved_key_id:-pdf-local-v1}}"
product_version="$(node -e "const fs=require('fs'); process.stdout.write(JSON.parse(fs.readFileSync(process.argv[1])).version)" "$plugin_root/product/product.json")"
printf '{"version":"%s","keyId":"%s"}\n' "$product_version" "$key_id" > "$key_root/identity.json"
bundle="$plugin_root/dist/pdf-$product_version.mcpb"
report="$plugin_root/dist/quick-verify-$platform.json"
macos_built=0
android_built=0
visual_captured=0
write_report() {
  result="$1"
  PDF_QUICK_EXIT="$result" PDF_QUICK_PLATFORM="$platform" \
  PDF_QUICK_BUNDLE="$bundle" PDF_QUICK_REPORT="$report" \
  PDF_QUICK_WORKSPACE="$workspace_root" \
  PDF_QUICK_VERSION="$product_version" \
  PDF_QUICK_MACOS_BUILT="$macos_built" \
  PDF_QUICK_ANDROID_BUILT="$android_built" \
  PDF_QUICK_VISUAL_CAPTURED="$visual_captured" \
  PDF_QUICK_DEVICE="${ANDROID_SERIAL:-}" node <<'NODE' || true
const fs = require('fs');
const crypto = require('crypto');
const path = require('path');
const {execFileSync} = require('child_process');
const root = process.env.PDF_QUICK_WORKSPACE;
const digest = file => fs.existsSync(file) ?
  crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') : null;
const repo = dir => {
  try {
    return {
      commit: execFileSync('git', ['-C', dir, 'rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
      dirty: execFileSync('git', ['-C', dir, 'status', '--porcelain'], {encoding:'utf8'}).trim().length > 0,
    };
  } catch { return null; }
};
const apk = path.join(root, 'Muse-Client/app/openmuse_mobile/build/app/outputs/flutter-apk/OpenMuse-pdf-local.apk');
const visualDir = path.join(root, `Muse-Client/dist/pdf-product-evidence-${process.env.PDF_QUICK_VERSION}`);
const screenshots = fs.existsSync(visualDir) ? fs.readdirSync(visualDir)
  .filter(name => name.endsWith('.png')).sort()
  .map(name => ({name, sha256: digest(path.join(visualDir, name))})) : [];
const completed = {
  macos: process.env.PDF_QUICK_MACOS_BUILT === '1',
  android: process.env.PDF_QUICK_ANDROID_BUILT === '1',
  visual: process.env.PDF_QUICK_VISUAL_CAPTURED === '1' && screenshots.length >= 12,
};
const requested = process.env.PDF_QUICK_PLATFORM;
const passed = process.env.PDF_QUICK_EXIT === '0' &&
  (requested === 'android' || completed.macos && completed.visual) &&
  (requested === 'macos' || completed.android);
const report = {
  at: new Date().toISOString(),
  platform: process.env.PDF_QUICK_PLATFORM,
  device: process.env.PDF_QUICK_DEVICE || null,
  passed,
  exitCode: Number(process.env.PDF_QUICK_EXIT),
  completed,
  repositories: {
    plugin: repo(path.join(root, 'Muse-Plugin-Ecosystem')),
    core: repo(path.join(root, 'ioffice/koffice/pdf/rebuild')),
    host: repo(path.join(root, 'Muse-Client')),
  },
  artifacts: {
    pluginBundle: {path: process.env.PDF_QUICK_BUNDLE, sha256: digest(process.env.PDF_QUICK_BUNDLE)},
    macosZip: {path: path.join(root, `Muse-Client/dist/OpenMuse-pdf-${process.env.PDF_QUICK_VERSION}-macos.zip`),
      sha256: digest(path.join(root, `Muse-Client/dist/OpenMuse-pdf-${process.env.PDF_QUICK_VERSION}-macos.zip`))},
    androidApk: {path: apk, sha256: digest(apk)},
    visualEvidence: {directory: visualDir, screenshots},
  },
};
fs.mkdirSync(path.dirname(process.env.PDF_QUICK_REPORT), {recursive:true});
fs.writeFileSync(process.env.PDF_QUICK_REPORT, JSON.stringify(report, null, 2) + '\n');
process.stdout.write(`Verification report: ${process.env.PDF_QUICK_REPORT}\n`);
NODE
}
trap 'write_report "$?"' EXIT

cd "$workspace_root/Muse-Plugin-Ecosystem"
npm ci
cd "$plugin_root"
npm run pack -- --private-key "$key_root/private.pem" --key-id "$key_id"
npm run verify -- "$bundle" "$key_root/public.pem" "$key_id"
install -m 644 product/chrome.json "$pdf_app/assets/product/chrome.json"
install -m 644 product/icons.json "$pdf_app/assets/product/icons.json"
cmp product/chrome.json "$pdf_app/assets/product/chrome.json"
cmp product/icons.json "$pdf_app/assets/product/icons.json"

if [[ "$platform" == macos || "$platform" == all ]]; then
  cd "$pdf_app"
  bash tool/prepare_macos_native.sh
  flutter test --no-pub
  flutter test --no-pub integration_test/product_flow_test.dart -d macos \
    --dart-define=KSP_PRODUCT_READER=true
  cd "$host/app/openmuse_host"
  flutter pub get
  PDF_PRODUCT_E2E_BUNDLE="$bundle" \
  PDF_PRODUCT_E2E_PUBLIC_KEY="$key_root/public.pem" \
  PDF_PRODUCT_E2E_KEY_ID="$key_id" \
  PDF_PRODUCT_E2E_VERSION="$product_version" \
  KSP_MAC_EDIT_DYLIB="$pdf_app/assets/native/libkspfreetext.dylib" \
    flutter test --no-pub test/pdf_product_e2e_test.dart
  OPENMUSE_CLEAN_BUILD=0 \
  OPENMUSE_PDF_PRODUCT_BUNDLE="$bundle" \
  OPENMUSE_PDF_PRODUCT_PUBLIC_KEY="$key_root/public.pem" \
  OPENMUSE_PDF_PRODUCT_IDENTITY="$key_root/identity.json" \
    bash "$host/scripts/package_macos.sh" --profile release --skip-tests \
      --components pdf --package
  cp -c -p "$host/dist/OpenMuse-macos.zip" "$host/dist/OpenMuse-pdf-$product_version-macos.zip"
  macos_built=1
fi

if [[ "$platform" == macos || "$platform" == all ]]; then
  bash "$plugin_root/scripts/capture-visual.sh"
  visual_captured=1
fi

if [[ "$platform" == android || "$platform" == all ]]; then
  cd "$pdf_app"
  bash tool/prepare_android_native.sh
  "$host/scripts/stage_pdf_product_mobile.sh" \
    "$bundle" "$key_root/public.pem"
  jni="$host/app/openmuse_mobile/android/app/src/main/jniLibs/arm64-v8a"
  mkdir -p "$jni"
  install -m 755 android/app/src/main/jniLibs/arm64-v8a/libkspfreetext.so "$jni/"
  install -m 644 android/app/src/main/jniLibs/arm64-v8a/libpdfium.so "$jni/"
  cd "$host/app/openmuse_mobile"
  flutter pub get
  flutter analyze --no-pub lib/main.dart lib/pdf_product_screen.dart
  if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    flutter test --no-pub integration_test/pdf_product_flow_test.dart \
      -d "$ANDROID_SERIAL"
  fi
  flutter build apk --release --target-platform android-arm64 --no-pub
  echo "Release APK: $host/app/openmuse_mobile/build/app/outputs/flutter-apk/app-release.apk"
  if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    apk_signer="$(find "${ANDROID_HOME:-$HOME/Library/Android/sdk}/build-tools" -name apksigner -type f | sort | tail -1)"
    test -n "$apk_signer"
    "$apk_signer" sign --ks "$HOME/.android/debug.keystore" \
      --ks-pass pass:android --ks-key-alias androiddebugkey \
      --key-pass pass:android \
      --out build/app/outputs/flutter-apk/OpenMuse-pdf-local.apk \
      build/app/outputs/flutter-apk/app-release.apk
    "$apk_signer" verify build/app/outputs/flutter-apk/OpenMuse-pdf-local.apk
    adb -s "$ANDROID_SERIAL" install --no-incremental -r \
      build/app/outputs/flutter-apk/OpenMuse-pdf-local.apk
  fi
  android_built=1
fi
