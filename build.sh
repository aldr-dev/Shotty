#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Shotty"
BUILD="build"
APP="$BUILD/$APP_NAME.app"
DMG="$BUILD/$APP_NAME.dmg"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "→ Компиляция (arm64 + x86_64)"
for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos15.0" Sources/*.swift -o "$BUILD/$APP_NAME-$arch"
done
lipo -create "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64" -output "$BUILD/$APP_NAME"

echo "→ Иконка"
swift Resources/make_icon.swift Resources/AppIcon.svg "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

echo "→ Сборка .app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# A stable certificate keeps the Screen Recording permission valid across rebuilds;
# ad-hoc signatures are tied to the build hash, so macOS forgets the permission each time.
SIGN_ID="$(security find-identity -p codesigning 2>/dev/null | awk -F'"' '/Shotty Local Signing/ {print $0; exit}' | awk '{print $2}')"
if [ -n "$SIGN_ID" ]; then
    codesign --force --deep --sign "$SIGN_ID" --identifier com.aldrmiller.shotty "$APP"
else
    echo "⚠︎ Сертификат «Shotty Local Signing» не найден — ad-hoc подпись (разрешения будут сбрасываться при пересборке)"
    codesign --force --deep --sign - --identifier com.aldrmiller.shotty "$APP"
fi

echo "→ Сборка DMG"
STAGE="$BUILD/dmg"
RW_DMG="$BUILD/$APP_NAME-rw.dmg"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
swift Resources/make_dmg_background.swift "$BUILD/dmg-bg"
tiffutil -cathidpicheck "$BUILD/dmg-bg/background.png" "$BUILD/dmg-bg/background@2x.png" \
    -out "$STAGE/.background/background.tiff" 2>/dev/null

# Finder addresses the volume by name, so detach any leftover copy first
for vol in /Volumes/"$APP_NAME"*; do [ -d "$vol" ] && hdiutil detach "$vol" -force >/dev/null || true; done
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW_DMG" >/dev/null
MOUNT="$(hdiutil attach "$RW_DMG" -noautoopen -nobrowse | awk -F'\t' '/\/Volumes\// {print $NF}')"
cp "$BUILD/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || true

# Window layout must match the icon slots drawn in make_dmg_background.swift
if ! osascript <<EOF >/dev/null
tell application "Finder"
    tell disk "$(basename "$MOUNT")"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 520}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "$APP_NAME.app" of container window to {170, 200}
        set position of item "Applications" of container window to {490, 200}
        -- Dotfiles are visible when Finder shows hidden files. Left unplaced they land above
        -- the top edge and Finder scrolls every icon off its slot, so park them below the window.
        set position of item ".background" of container window to {170, 560}
        set position of item ".VolumeIcon.icns" of container window to {490, 560}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
then
    echo "⚠︎ Finder не дал оформить окно DMG (нужен доступ к Автоматизации) — DMG будет без фона"
fi
# Finder deletes the volume icon while it lays out the window; its saved position survives
cp "$BUILD/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || true
sync
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert "$RW_DMG" -format ULMO -o "$DMG" -ov >/dev/null
rm -f "$RW_DMG"

echo "✓ Готово: $DMG"
