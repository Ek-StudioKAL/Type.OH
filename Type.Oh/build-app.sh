#!/bin/bash
# Build Type.Oh.app on macOS 13 / Intel without Xcode.
#
# Requirements (see notes in the Claude workspace):
#   - Command Line Tools (SDK) — /Library/Developer/CommandLineTools
#   - A swift.org toolchain in ~/Library/Developer/Toolchains (Swift ≥ 5.10)
#
# Usage:  ./build-app.sh [debug|release]      (default: release)
# Output: build/ventura/Type.Oh.app
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build/ventura"
APP="$OUT/Type.Oh.app"
SRC="$ROOT/Type.Oh"

# --- toolchain -------------------------------------------------------------
if [[ -n "${TYPEOH_TOOLCHAIN:-}" ]]; then
    TC="$TYPEOH_TOOLCHAIN"
else
    # Prefer Swift 5.10.x: the swift.org 6.0.x optimizer aborts inside
    # WhisperKit ("GenericSpecializer" crash) on this setup.
    TC="$(ls -d "$HOME"/Library/Developer/Toolchains/swift-5.10*-RELEASE.xctoolchain /Library/Developer/Toolchains/swift-5.10*-RELEASE.xctoolchain 2>/dev/null | sort -V | tail -1 || true)"
    if [[ -z "$TC" ]]; then
        TC="$(ls -d "$HOME"/Library/Developer/Toolchains/swift-*-RELEASE.xctoolchain /Library/Developer/Toolchains/swift-*-RELEASE.xctoolchain 2>/dev/null | sort -V | tail -1 || true)"
    fi
fi
if [[ -z "$TC" || ! -x "$TC/usr/bin/swift" ]]; then
    echo "No swift.org toolchain found. Install one from https://www.swift.org/install/macos/ (per-user install is fine)." >&2
    exit 1
fi
SWIFT="$TC/usr/bin/swift"
echo "==> Toolchain: $TC"
"$SWIFT" --version

# --- compile ---------------------------------------------------------------
# Extra swiftc flags can be injected with TYPEOH_SWIFT_FLAGS (space separated).
SWIFT_FLAGS=()
if [[ -n "${TYPEOH_SWIFT_FLAGS:-}" ]]; then read -r -a SWIFT_FLAGS <<< "$TYPEOH_SWIFT_FLAGS"; fi

echo "==> swift build -c $CONFIG"
cd "$ROOT"
"$SWIFT" build -c "$CONFIG" --product Type_Oh ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
"$SWIFT" build -c "$CONFIG" --product TypeOhStrip ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
BIN="$("$SWIFT" build -c "$CONFIG" --show-bin-path)"

# --- bundle ----------------------------------------------------------------
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Type_Oh" "$APP/Contents/MacOS/Type.Oh"

# Resource bundles produced by dependencies (if any)
for b in "$BIN"/*.bundle; do
    [[ -d "$b" ]] && cp -R "$b" "$APP/Contents/Resources/"
done

# App icon: iconutil needs a .iconset with canonical names.
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
A="$SRC/Assets.xcassets/AppIcon.appiconset"
cp "$A/ty_18.png"       "$ICONSET/icon_16x16.png"
cp "$A/ty_32.png"       "$ICONSET/icon_16x16@2x.png"
cp "$A/ty_32 1.png"     "$ICONSET/icon_32x32.png"
cp "$A/ty_64.png"       "$ICONSET/icon_32x32@2x.png"
cp "$A/ty_ 128.png"     "$ICONSET/icon_128x128.png"
cp "$A/ty_256.png"      "$ICONSET/icon_128x128@2x.png"
cp "$A/ty_256 1.png"    "$ICONSET/icon_256x256.png"
cp "$A/ty_512.png"      "$ICONSET/icon_256x256@2x.png"
cp "$A/ty_512 1.png"    "$ICONSET/icon_512x512.png"
cp "$A/ty_1024.png"     "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Menu bar icon (NSImage(named: "menuBarIcon") finds loose PNGs in Resources)
M="$SRC/Assets.xcassets/menuBarIcon.appiconset"
cp "$M/TypeOh-icons_9Shape - Flat color negative_Artboard 133.png" "$APP/Contents/Resources/menuBarIcon.png"
cp "$M/TypeOh-icons_9Shape - Flat color negative_Artboard 164.png" "$APP/Contents/Resources/menuBarIcon@2x.png"

# App icon set (vector PDFs from tools/build-icons.swift; AppIcon loads them
# from Contents/Resources — Xcode copies the same folder automatically).
cp "$SRC"/Icons/icon-*.pdf "$APP/Contents/Resources/"

# Touch Bar Control Strip helper (see Type.Oh/UI/ControlStrip.swift).
HELPER="$APP/Contents/Helpers/TypeOhStrip.app"
mkdir -p "$HELPER/Contents/MacOS"
cp "$BIN/TypeOhStrip" "$HELPER/Contents/MacOS/TypeOhStrip"
cat > "$HELPER/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>                 <string>TypeOhStrip</string>
	<key>CFBundleIdentifier</key>                 <string>noob-noob420.Type-Oh.strip</string>
	<key>CFBundleInfoDictionaryVersion</key>      <string>6.0</string>
	<key>CFBundleName</key>                       <string>Type.OH Control Strip</string>
	<key>CFBundlePackageType</key>                <string>APPL</string>
	<key>CFBundleShortVersionString</key>         <string>1.0</string>
	<key>CFBundleVersion</key>                    <string>1</string>
	<key>LSMinimumSystemVersion</key>             <string>13.0</string>
	<key>LSUIElement</key>                        <true/>
</dict>
</plist>
PLIST
plutil -lint "$HELPER/Contents/Info.plist" >/dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>          <string>en</string>
	<key>CFBundleDisplayName</key>                <string>Type.OH</string>
	<key>CFBundleExecutable</key>                 <string>Type.Oh</string>
	<key>CFBundleIconFile</key>                   <string>AppIcon</string>
	<key>CFBundleIdentifier</key>                 <string>noob-noob420.Type-Oh</string>
	<key>CFBundleInfoDictionaryVersion</key>      <string>6.0</string>
	<key>CFBundleName</key>                       <string>Type.Oh</string>
	<key>CFBundlePackageType</key>                <string>APPL</string>
	<key>CFBundleShortVersionString</key>         <string>1.0</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>            <string>Type.OH actions</string>
			<key>CFBundleURLSchemes</key>         <array><string>typeoh</string></array>
			<key>LSHandlerRank</key>              <string>Owner</string>
		</dict>
	</array>
	<key>CFBundleVersion</key>                    <string>1</string>
	<key>LSApplicationCategoryType</key>          <string>public.app-category.productivity</string>
	<key>LSMinimumSystemVersion</key>             <string>13.0</string>
	<key>LSUIElement</key>                        <true/>
	<key>NSHighResolutionCapable</key>            <true/>
	<key>NSHumanReadableCopyright</key>           <string></string>
	<key>NSMicrophoneUsageDescription</key>       <string>Type.OH needs your microphone for voice recording.</string>
	<key>NSPrincipalClass</key>                   <string>NSApplication</string>
	<key>NSSupportsAutomaticTermination</key>     <false/>
	<key>NSSupportsSuddenTermination</key>        <false/>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
echo "APPL????" > "$APP/Contents/PkgInfo"

# Ad-hoc signature so TCC (Accessibility / Microphone) can identify the app.
# Note: every rebuild changes the code hash, so macOS may ask you to re-grant
# Accessibility after rebuilding.
codesign --force --deep --sign - --entitlements "$SRC/Type.Oh.entitlements" "$APP"
# Tell Launch Services about the bundle (URL scheme) without launching it.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
codesign --verify --verbose=2 "$APP" 2>&1 | tail -2
echo "==> Done: $APP"
