#!/bin/bash
set -euo pipefail

APP_NAME="LimpezaMac"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 Compilando ${APP_NAME} (Release)..."
swift build -c release

BIN_PATH=".build/release/${APP_NAME}"
if [ ! -f "$BIN_PATH" ]; then
    echo "❌ Binário não encontrado em $BIN_PATH"
    exit 1
fi

echo "📦 Empacotando ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "${MACOS_DIR}/${APP_NAME}"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LimpezaMac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.luirdi.LimpezaMac</string>
    <key>CFBundleName</key>
    <string>LimpezaMac</string>
    <key>CFBundleDisplayName</key>
    <string>LimpezaMac</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Ad-hoc code signing so macOS Gatekeeper/TCC recognizes the bundle cleanly
codesign --force --deep --sign - "$APP_DIR"

# Register with LaunchServices so macOS recognizes the app bundle
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" || true

echo "✅ ${APP_DIR} criado com sucesso!"
echo "👉 Para abrir: open ${APP_DIR}"
