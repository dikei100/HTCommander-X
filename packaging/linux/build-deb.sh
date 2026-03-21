#!/bin/bash
# Build HTCommander-X .deb package for Debian/Ubuntu
# Usage: ./build-deb.sh [Release|Debug]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="${1:-Release}"
VERSION=$(grep -oPm1 '(?<=<Version>)[^<]+' "$ROOT_DIR/HTCommander.Desktop/HTCommander.Desktop.csproj")
PKGNAME="htcommander"
DEBDIR="$ROOT_DIR/packaging/linux/${PKGNAME}_${VERSION}_amd64"
OUTPUT_DIR="$ROOT_DIR/releases"

echo "=== Building HTCommander-X .deb package ==="

# Build the project
echo "Building HTCommander.Desktop..."
dotnet publish "$ROOT_DIR/HTCommander.Desktop/HTCommander.Desktop.csproj" \
    -c "$CONFIG" \
    -r linux-x64 \
    --self-contained true \
    -p:PublishSingleFile=false \
    -p:PublishTrimmed=false \
    -o "$DEBDIR/opt/htcommander"

# Create deb structure
mkdir -p "$DEBDIR/DEBIAN"
mkdir -p "$DEBDIR/usr/bin"
mkdir -p "$DEBDIR/usr/share/applications"
mkdir -p "$DEBDIR/usr/share/icons/hicolor/256x256/apps"

# Control file
cat > "$DEBDIR/DEBIAN/control" << EOF
Package: $PKGNAME
Version: $VERSION
Section: hamradio
Priority: optional
Architecture: amd64
Depends: libportaudio2, bluez
Recommends: espeak-ng
Maintainer: Ylian Saint-Hilaire
Description: HTCommander-X - Cross-platform Ham Radio Commander
 HTCommander-X is a cross-platform application for controlling
 Bluetooth-enabled ham radio handhelds. Supports UV-PRO, VR-N75,
 VR-N76, VR-N7500, and other compatible radios.
 Features: APRS, packet radio, voice, BBS, mail, maps, and more.
Homepage: https://github.com/dikei100/HTCommander
EOF

# Symlink to /usr/bin
cat > "$DEBDIR/usr/bin/htcommander" << 'LAUNCHER'
#!/bin/bash
exec /opt/htcommander/HTCommander.Desktop "$@"
LAUNCHER
chmod +x "$DEBDIR/usr/bin/htcommander"

# Desktop file
cp "$SCRIPT_DIR/HTCommander.desktop" "$DEBDIR/usr/share/applications/"
sed -i "s|Exec=HTCommander.Desktop|Exec=/opt/htcommander/HTCommander.Desktop|" \
    "$DEBDIR/usr/share/applications/HTCommander.desktop"

# Build .deb
mkdir -p "$OUTPUT_DIR"
dpkg-deb --build "$DEBDIR" "$OUTPUT_DIR/${PKGNAME}_${VERSION}_amd64.deb"

echo ""
echo "=== .deb package built successfully ==="
echo "Output: $OUTPUT_DIR/${PKGNAME}_${VERSION}_amd64.deb"

# Cleanup
rm -rf "$DEBDIR"
