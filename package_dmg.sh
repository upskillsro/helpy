#!/bin/bash
set -e

# Configuration
APP_NAME="Helpy"
EXECUTABLE_NAME="Helpy"
ICON_DEFAULT_SOURCE="Icon Exports/Icon-iOS-Default-1024x1024@1x.png"
ICON_DARK_SOURCE="Icon Exports/Icon-iOS-Dark-1024x1024@1x.png"
ICON_ICNS_OUTPUT="Resources/AppIcon.icns"
ICON_DARK_ICNS_OUTPUT="Resources/AppIconDark.icns"
CUSTOM_LIGHT_ICNS_SOURCE="CustomIcons/AppIcon.icns"
CUSTOM_DARK_ICNS_SOURCE="CustomIcons/AppIconDark.icns"
OUTPUT_DMG="Helpy.dmg"
BUILD_ARCH_DIR=".build/release"
BUNDLED_ASSISTANT_DIR="BundledAssistant"

echo "🚀 Starting Packaging Process..."

# 1. Update Icon
echo "🎨 Updating App Icon..."
if [ ! -f "$ICON_DEFAULT_SOURCE" ]; then
    echo "❌ Missing default icon source: $ICON_DEFAULT_SOURCE"
    exit 1
fi
if [ ! -f "$ICON_DARK_SOURCE" ]; then
    echo "❌ Missing dark icon source: $ICON_DARK_SOURCE"
    exit 1
fi

ICONSET_TMP_PARENT="$(mktemp -d)"
TMP_ICONSET_DIR="$ICONSET_TMP_PARENT/AppIcon.iconset"
TMP_DARK_ICONSET_DIR="$ICONSET_TMP_PARENT/AppIconDark.iconset"
mkdir -p "$TMP_ICONSET_DIR"
mkdir -p "$TMP_DARK_ICONSET_DIR"

if [ -f "$CUSTOM_LIGHT_ICNS_SOURCE" ]; then
    cp "$CUSTOM_LIGHT_ICNS_SOURCE" "$ICON_ICNS_OUTPUT"
    echo "✅ AppIcon.icns copied from $CUSTOM_LIGHT_ICNS_SOURCE"
else
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ICON_DEFAULT_SOURCE" --out "$TMP_ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    done
    
    for size in 16 32 128 256 512; do
        scaled=$((size * 2))
        sips -z "$scaled" "$scaled" "$ICON_DEFAULT_SOURCE" --out "$TMP_ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
    done
    
    if iconutil -c icns "$TMP_ICONSET_DIR" -o "$ICON_ICNS_OUTPUT" >/dev/null 2>&1; then
        echo "✅ AppIcon.icns regenerated from $ICON_DEFAULT_SOURCE"
    else
        echo "⚠️  iconutil could not generate AppIcon.icns on this machine; keeping existing Resources/AppIcon.icns"
    fi
fi

if [ -f "$CUSTOM_DARK_ICNS_SOURCE" ]; then
    cp "$CUSTOM_DARK_ICNS_SOURCE" "$ICON_DARK_ICNS_OUTPUT"
    echo "✅ AppIconDark.icns copied from $CUSTOM_DARK_ICNS_SOURCE"
else
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ICON_DARK_SOURCE" --out "$TMP_DARK_ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    done
    
    for size in 16 32 128 256 512; do
        scaled=$((size * 2))
        sips -z "$scaled" "$scaled" "$ICON_DARK_SOURCE" --out "$TMP_DARK_ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
    done
    
    if iconutil -c icns "$TMP_DARK_ICONSET_DIR" -o "$ICON_DARK_ICNS_OUTPUT" >/dev/null 2>&1; then
        echo "✅ AppIconDark.icns regenerated from $ICON_DARK_SOURCE"
    else
        echo "⚠️  iconutil could not generate AppIconDark.icns on this machine; keeping existing Resources/AppIconDark.icns"
    fi
fi

rm -rf "$ICONSET_TMP_PARENT"

mkdir -p "Sources/Resources"
cp "$ICON_ICNS_OUTPUT" "Sources/Resources/AppIcon.icns"
if [ -f "$ICON_DARK_ICNS_OUTPUT" ]; then
    cp "$ICON_DARK_ICNS_OUTPUT" "Sources/Resources/AppIconDark.icns"
fi
cp "$ICON_DEFAULT_SOURCE" "Sources/Resources/AppIconDefault.png"
cp "$ICON_DARK_SOURCE" "Sources/Resources/AppIconDark.png"

# 2. Build Release
echo "🔨 Building Release Configuration..."
MODULE_CACHE_DIR="$PWD/.build/ModuleCache.noindex"
mkdir -p "$MODULE_CACHE_DIR"
SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swift build -c release

# 3. Create Bundle Structure
echo "📦 Creating App Bundle..."
rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# Copy Binary
cp ".build/release/$EXECUTABLE_NAME" "$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_NAME.app/Contents/MacOS/$EXECUTABLE_NAME"

# Copy Icon
cp "Resources/AppIcon.icns" "$APP_NAME.app/Contents/Resources/AppIcon.icns"

# Copy SwiftPM resource bundle(s) (required for Bundle.module to work once the app is moved)
echo "📎 Embedding SwiftPM resource bundles..."
if [ -d "$BUILD_ARCH_DIR" ]; then
    shopt -s nullglob
    BUNDLES=("$BUILD_ARCH_DIR"/"${EXECUTABLE_NAME}"_*.bundle)
    if [ ${#BUNDLES[@]} -eq 0 ]; then
        BUNDLES=("$BUILD_ARCH_DIR"/*.bundle)
    fi
    shopt -u nullglob
    if [ ${#BUNDLES[@]} -eq 0 ]; then
        echo "⚠️  No .bundle resources found in $BUILD_ARCH_DIR (unexpected for this package)."
    else
        for b in "${BUNDLES[@]}"; do
            echo "  - Copying $(basename "$b")"
            cp -R "$b" "$APP_NAME.app/Contents/Resources/"
        done
    fi
else
    echo "⚠️  Build output directory not found: $BUILD_ARCH_DIR"
fi

if [ -d "$BUNDLED_ASSISTANT_DIR" ]; then
    echo "🤖 Embedding bundled assistant payload..."
    cp -R "$BUNDLED_ASSISTANT_DIR" "$APP_NAME.app/Contents/Resources/"
    if [ -d "$APP_NAME.app/Contents/Resources/BundledAssistant/bin" ]; then
        find "$APP_NAME.app/Contents/Resources/BundledAssistant/bin" -type f -exec chmod +x {} +
    fi
else
    echo "ℹ️  No BundledAssistant payload found. Assistant runtime will use system-installed tools."
fi

# Create Info.plist (ensure icon name matches)
cat <<EOF > "$APP_NAME.app/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.lungusebi.helpy</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSRemindersUsageDescription</key>
    <string>Helpy needs access to your reminders to help you stay on task.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Helpy needs access to your calendar events.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Helpy needs microphone access to record voice notes for local task transcription.</string>
</dict>
</plist>
EOF

# 4. Code Sign
echo "✍️  Code Signing..."
xattr -rc "$APP_NAME.app"
codesign --force --deep --sign - "$APP_NAME.app"

# 5. Create DMG
echo "💿 Creating DMG..."
rm -rf dmg_staging
mkdir -p dmg_staging
cp -r "$APP_NAME.app" dmg_staging/
ln -s /Applications dmg_staging/Applications

rm -f "$OUTPUT_DMG"
hdiutil create -volname "$APP_NAME Installer" -srcfolder dmg_staging -ov -format UDZO "$OUTPUT_DMG"

# Cleanup
rm -rf dmg_staging

echo "✅ Packaging Complete!"
echo "Created: $(pwd)/$OUTPUT_DMG"
