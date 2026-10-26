#!/bin/bash
# Builds Adega's Wine: CrossOver's open-source Wine (LGPL) + patches/, for macOS x86_64.
#
# Run on an Intel Mac (the GitHub workflow uses macos-15-intel) with the Homebrew
# packages listed in .github/workflows/build.yml. Produces out/adega-wine-<version>.tar.xz
# (top folder "wine/": bin, lib, share) and its .sha256.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

CX_VERSION=26.3.0
CX_SHA256=ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
MONO_VERSION=10.4.1
MONO_SHA256=a16606ef0724202e6a6848ece6e0cbba64d11e2f11aefe744af1d93c6d9f99bb
GECKO_VERSION=2.47.4
GECKO_X86_SHA256=2cfc8d5c948602e21eff8a78613e1826f2d033df9672cace87fed56e8310afb6
GECKO_X86_64_SHA256=fd88fc7e537d058d7a8abf0c1ebc90c574892a466de86706a26d254710a82814

VERSION=${ADEGA_WINE_VERSION:-cx$CX_VERSION-$(git rev-parse --short HEAD 2>/dev/null || echo local)}
WORK=$ROOT/work
DL=$WORK/downloads
SRC=$WORK/src
BUILD=$WORK/build
STAGE=$WORK/stage/wine
OUT=$ROOT/out
JOBS=$(sysctl -n hw.ncpu)

[ "$(uname -m)" = x86_64 ] || { echo "Build on an Intel Mac (Wine for macOS is x86_64-only)." >&2; exit 1; }
export MACOSX_DEPLOYMENT_TARGET=14.0
export PATH="$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$PATH"

fetch() {  # url sha256 -> path
    local file=$DL/$(basename "$1")
    mkdir -p "$DL"
    [ -f "$file" ] || { curl -fL --retry 3 -o "$file.part" "$1" && mv "$file.part" "$file"; }
    echo "$2  $file" | shasum -a 256 -c - >&2
    echo "$file"
}

echo "== sources"
cx=$(fetch "https://media.codeweavers.com/pub/crossover/source/crossover-sources-$CX_VERSION.tar.gz" $CX_SHA256)
rm -rf "$SRC" && mkdir -p "$SRC"
tar xzf "$cx" -C "$SRC" --strip-components 1 sources/wine
for patch in "$ROOT"/patches/*.patch; do
    patch -d "$SRC/wine" -p1 --quiet < "$patch"
    echo "applied $(basename "$patch")"
done

echo "== configure"
# Same options as Gcenx's wine-devel build (macports-wine), minus GStreamer for now.
# Vulkan: no vulkan-loader installed, so configure links MoltenVK directly, like CrossOver.
rm -rf "$BUILD" && mkdir -p "$BUILD"
cd "$BUILD"
CFLAGS="-O2" CROSSCFLAGS="-O2" "$SRC/wine/configure" \
    --prefix=/opt/adega-wine \
    --enable-archs=i386,x86_64 --enable-win64 \
    --disable-tests --disable-winebth_sys \
    --without-alsa --without-capi --with-coreaudio --with-cups --without-dbus \
    --without-ffmpeg --without-fontconfig --with-freetype --with-gettext --without-gettextpo \
    --without-gphoto --with-gnutls --without-gssapi --without-gstreamer --without-inotify \
    --without-krb5 --without-netapi --with-opencl --without-opengl --without-oss \
    --with-pcap --with-pcsclite --with-pthread --without-pulse --without-sane --with-sdl \
    --without-udev --without-usb --without-v4l2 --with-vulkan --without-wayland --without-x \
    > configure.log 2>&1 || { tail -40 configure.log; exit 1; }
grep -E "^configure: (WARNING|error)" configure.log || true
grep -E "#define SONAME_" include/config.h

echo "== make"
make -j"$JOBS" > make.log 2>&1 || { tail -60 make.log; exit 1; }
rm -rf "$WORK/stage" && make install-lib DESTDIR="$WORK/stage-root" > install.log 2>&1
mkdir -p "$WORK/stage" && mv "$WORK/stage-root/opt/adega-wine" "$STAGE" && rm -rf "$WORK/stage-root"

echo "== addons (Mono $MONO_VERSION, Gecko $GECKO_VERSION)"
mkdir -p "$STAGE/share/wine/mono" "$STAGE/share/wine/gecko"
tar xJf "$(fetch "https://dl.winehq.org/wine/wine-mono/$MONO_VERSION/wine-mono-$MONO_VERSION-x86.tar.xz" $MONO_SHA256)" -C "$STAGE/share/wine/mono"
tar xJf "$(fetch "https://dl.winehq.org/wine/wine-gecko/$GECKO_VERSION/wine-gecko-$GECKO_VERSION-x86.tar.xz" $GECKO_X86_SHA256)" -C "$STAGE/share/wine/gecko"
tar xJf "$(fetch "https://dl.winehq.org/wine/wine-gecko/$GECKO_VERSION/wine-gecko-$GECKO_VERSION-x86_64.tar.xz" $GECKO_X86_64_SHA256)" -C "$STAGE/share/wine/gecko"

echo "== bundle dylibs"
# Libraries Wine dlopen()s by name (SONAME_*), resolved in Homebrew.
dlopened=()
for name in $(sed -n 's/^#define SONAME_[A-Z0-9_]* "\(.*\)"$/\1/p' include/config.h); do
    path=$(brew --prefix)/lib/$name
    [ -e "$path" ] && dlopened+=("$path") || echo "not bundled (system or absent): $name"
done
"$ROOT/scripts/bundle-libs.sh" "$STAGE" ${dlopened[@]+"${dlopened[@]}"}

echo "== sources notice"
mkdir -p "$STAGE/share/doc/adega-wine"
cp "$SRC/wine/COPYING.LIB" "$SRC/wine/LICENSE" "$STAGE/share/doc/adega-wine/"
cat > "$STAGE/share/doc/adega-wine/SOURCE.txt" <<EOF
Adega Wine $VERSION
Built from CrossOver $CX_VERSION sources (https://media.codeweavers.com/pub/crossover/source/)
with the patches and build scripts at https://github.com/dockplusai-ops/adega-wine
EOF

echo "== package"
mkdir -p "$OUT"
archive=$OUT/adega-wine-$VERSION.tar.xz
tar cJf "$archive" -C "$WORK/stage" wine
(cd "$OUT" && shasum -a 256 "$(basename "$archive")" | tee "$(basename "$archive").sha256")
du -sh "$archive"
