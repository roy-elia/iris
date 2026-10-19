#!/bin/zsh
# Downloads, verifies and builds the command-line helpers the app bundles:
#   ffmpeg + ffprobe 9.0.2  built from source, LGPL only, with LAME 3.100 (MP3), libvpx 1.17.0
#                           (VP8/VP9 for WebM), opencore-amr 0.1.6 and vo-amrwbenc 0.1.3
#                           (AMR-NB/WB) and VideoToolbox
#   cwebp 1.6.0             Google's signed macOS arm64 release
#   ExifTool 13.59          Phil Harvey's Perl distribution
#   mac 13.30               Monkey's Audio's command-line encoder (APE), built from its SDK
# Everything comes from the projects' official download locations and is checked against
# a pinned SHA-256 before use. Output goes to Vendor/out (not committed); scripts/bundle.sh
# copies it into the app's Contents/Helpers.
#
# Usage: scripts/fetch-tools.sh            (skips anything already built)
#        scripts/fetch-tools.sh --clean    (rebuilds from scratch)
set -euo pipefail

ROOT=${0:A:h:h}
VENDOR=$ROOT/Vendor
DL=$VENDOR/downloads
SRC=$VENDOR/src
OUT=$VENDOR/out
PREFIX=$VENDOR/prefix
JOBS=$(sysctl -n hw.ncpu)
export MACOSX_DEPLOYMENT_TARGET=26.0

FFMPEG_VER=9.0.2
FFMPEG_SHA=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
LAME_VER=3.100
LAME_SHA=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
WEBP_VER=1.6.0
WEBP_SHA=bc6bf84cc70f3f8574fba797d1e4a7dea4feebe9fa4be919f202413ea2b3b8f2
VPX_TAG=v1.17.0
# The tag's commit on chromium.googlesource.com, matched against github.com/webmproject.
VPX_COMMIT=6df3ec34557879fff673706f4a1d9fbd0f3a6f0e
AMR_VER=0.1.6
AMR_SHA=483eb4061088e2b34b358e47540b5d495a96cd468e361050fae615b1809dc4a1
AMRWBENC_VER=0.1.3
AMRWBENC_SHA=5652b391e0f0e296417b841b02987d3fd33e6c0af342c69542cbb016a71d9d4e
# Monkey's Audio publishes no checksum; this is the SDK as downloaded on 2026-10-19.
MAC_VER=1330
MAC_SHA=9f74ffc0300d0b664e0530186d543e060f50e8776ae9325ec7b3f8fb1eb3f230
EXIF_VER=13.59
EXIF_SHA=668ea3acececb7235fbd0f4900e72d5f12c9b07e5c778fd36cb1e9b5828fd65a

if [[ ${1:-} == --clean ]]; then rm -rf "$SRC" "$OUT" "$PREFIX"; fi
mkdir -p "$DL" "$SRC" "$OUT/bin" "$PREFIX"

# fetch <url> <file> <sha256>: download once into its own folder, refuse a hash mismatch.
fetch() {
  local url=$1 file=$DL/$2 sha=$3
  if [[ ! -f $file ]]; then
    echo "Downloading $2"
    curl -fL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  local got=$(shasum -a 256 "$file" | cut -d' ' -f1)
  if [[ $got != $sha ]]; then
    echo "SHA-256 mismatch for $2: expected $sha, got $got" >&2
    rm -f "$file"
    exit 1
  fi
}

fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz" "ffmpeg-$FFMPEG_VER.tar.xz" $FFMPEG_SHA
fetch "https://downloads.sourceforge.net/project/lame/lame/$LAME_VER/lame-$LAME_VER.tar.gz" \
  "lame-$LAME_VER.tar.gz" $LAME_SHA
fetch "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP_VER-mac-arm64.tar.gz" \
  "libwebp-$WEBP_VER-mac-arm64.tar.gz" $WEBP_SHA
fetch "https://sourceforge.net/projects/exiftool/files/Image-ExifTool-$EXIF_VER.tar.gz/download" \
  "Image-ExifTool-$EXIF_VER.tar.gz" $EXIF_SHA
fetch "https://downloads.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-$AMR_VER.tar.gz" \
  "opencore-amr-$AMR_VER.tar.gz" $AMR_SHA
fetch "https://downloads.sourceforge.net/project/opencore-amr/vo-amrwbenc/vo-amrwbenc-$AMRWBENC_VER.tar.gz" \
  "vo-amrwbenc-$AMRWBENC_VER.tar.gz" $AMRWBENC_SHA
fetch "https://monkeysaudio.com/files/MAC_${MAC_VER}_SDK.zip" "MAC_${MAC_VER}_SDK.zip" $MAC_SHA

# LAME: static library only, linked into ffmpeg.
if [[ ! -f $PREFIX/lib/libmp3lame.a ]]; then
  echo "Building LAME $LAME_VER"
  rm -rf "$SRC/lame-$LAME_VER" && tar -xzf "$DL/lame-$LAME_VER.tar.gz" -C "$SRC"
  (cd "$SRC/lame-$LAME_VER" &&
    ./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-frontend \
      --disable-dependency-tracking CFLAGS="-O2 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" >/dev/null &&
    # LAME 3.100 exports a symbol that no longer exists; drop it so the link succeeds.
    sed -i '' '/lame_init_old/d' include/libmp3lame.sym &&
    make -j$JOBS >/dev/null && make install >/dev/null)
fi

# libvpx: cloned at a pinned tag from the WebM project's official repository; the commit
# must match exactly. Static library only, linked into ffmpeg.
if [[ ! -f $PREFIX/lib/libvpx.a ]]; then
  echo "Building libvpx $VPX_TAG"
  if [[ ! -d $SRC/libvpx ]]; then
    git clone -q --depth 1 --branch "$VPX_TAG" https://chromium.googlesource.com/webm/libvpx "$SRC/libvpx"
  fi
  got=$(git -C "$SRC/libvpx" rev-parse HEAD)
  if [[ $got != $VPX_COMMIT ]]; then
    echo "libvpx commit mismatch: expected $VPX_COMMIT, got $got" >&2
    exit 1
  fi
  (cd "$SRC/libvpx" &&
    ./configure --prefix="$PREFIX" --target=arm64-darwin25-gcc --enable-vp8 --enable-vp9 --enable-pic \
      --disable-examples --disable-tools --disable-docs --disable-unit-tests --disable-shared --enable-static \
      --extra-cflags="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" >"$VENDOR/libvpx-configure.log" &&
    make -j$JOBS >"$VENDOR/libvpx-make.log" 2>&1 && make install >/dev/null)
fi

# opencore-amr (AMR-NB encode/decode, AMR-WB decode) and vo-amrwbenc (AMR-WB encode), both
# Apache-2.0: static libraries only, linked into ffmpeg (which needs --enable-version3 for them).
for lib in opencore-amr-$AMR_VER vo-amrwbenc-$AMRWBENC_VER; do
  name=${lib%-*}
  [[ $name == opencore-amr ]] && check=libopencore-amrnb.a || check=libvo-amrwbenc.a
  if [[ ! -f $PREFIX/lib/$check ]]; then
    echo "Building $lib"
    rm -rf "$SRC/$lib" && tar -xzf "$DL/$lib.tar.gz" -C "$SRC"
    (cd "$SRC/$lib" &&
      ./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-dependency-tracking \
        CFLAGS="-O2 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
        CXXFLAGS="-O2 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" >/dev/null &&
      make -j$JOBS >/dev/null 2>&1 && make install >/dev/null)
  fi
done

# ffmpeg: LGPL build (no --enable-gpl, no --enable-nonfree), hardware codecs via VideoToolbox.
# --disable-autodetect stops configure from picking up Homebrew libraries (X11, SDL, …),
# which would make the binary fail on Macs without them; only macOS system libraries and
# the static LAME, libvpx and AMR libraries are enabled explicitly. An older build without the
# AMR encoders is rebuilt.
if [[ ! -x $OUT/bin/ffmpeg ]] || ! "$OUT/bin/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -q libvo_amrwbenc; then
  echo "Building ffmpeg $FFMPEG_VER (takes a few minutes)"
  rm -rf "$SRC/ffmpeg-$FFMPEG_VER" && tar -xJf "$DL/ffmpeg-$FFMPEG_VER.tar.xz" -C "$SRC"
  (cd "$SRC/ffmpeg-$FFMPEG_VER" &&
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" ./configure --prefix="$PREFIX" --cc=clang --arch=arm64 \
      --disable-gpl --disable-nonfree --enable-version3 \
      --disable-autodetect --enable-libmp3lame --enable-libvpx --enable-videotoolbox --enable-audiotoolbox \
      --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libvo-amrwbenc \
      --enable-zlib --enable-bzlib --enable-iconv --extra-libs=-liconv \
      --disable-ffplay --disable-doc --disable-debug --disable-shared --enable-static \
      --extra-cflags="-I$PREFIX/include -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
      --extra-ldflags="-L$PREFIX/lib -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" >"$VENDOR/ffmpeg-configure.log" &&
    make -j$JOBS >"$VENDOR/ffmpeg-make.log" 2>&1)
  cp "$SRC/ffmpeg-$FFMPEG_VER/ffmpeg" "$SRC/ffmpeg-$FFMPEG_VER/ffprobe" "$OUT/bin/"
  strip -x "$OUT/bin/ffmpeg" "$OUT/bin/ffprobe"
  # Refuse a binary that links anything outside macOS itself.
  if otool -L "$OUT/bin/ffmpeg" "$OUT/bin/ffprobe" | tail -n +2 | grep -vE "^\S|/System/Library/|/usr/lib/"; then
    echo "ffmpeg links non-system libraries (listed above)" >&2
    rm -f "$OUT/bin/ffmpeg" "$OUT/bin/ffprobe"
    exit 1
  fi
fi

# cwebp: prebuilt, signed by the WebP release key.
if [[ ! -x $OUT/bin/cwebp ]]; then
  echo "Unpacking cwebp $WEBP_VER"
  rm -rf "$SRC/libwebp-$WEBP_VER-mac-arm64" && tar -xzf "$DL/libwebp-$WEBP_VER-mac-arm64.tar.gz" -C "$SRC"
  cp "$SRC/libwebp-$WEBP_VER-mac-arm64/bin/cwebp" "$OUT/bin/"
fi

# ExifTool: the Perl script and its library, run with macOS's /usr/bin/perl.
if [[ ! -f $OUT/exiftool/exiftool ]]; then
  echo "Unpacking ExifTool $EXIF_VER"
  rm -rf "$SRC/Image-ExifTool-$EXIF_VER" && tar -xzf "$DL/Image-ExifTool-$EXIF_VER.tar.gz" -C "$SRC"
  mkdir -p "$OUT/exiftool"
  cp -R "$SRC/Image-ExifTool-$EXIF_VER/exiftool" "$SRC/Image-ExifTool-$EXIF_VER/lib" "$OUT/exiftool/"
fi

# Monkey's Audio: the SDK's command-line tool, compiled directly (the SDK's CMake build needs
# CMake, which a Command Line Tools-only Mac lacks). Same sources as its CMakeLists' "mac" target.
if [[ ! -x $OUT/bin/mac ]]; then
  echo "Building Monkey's Audio $MAC_VER"
  rm -rf "$SRC/MAC_SDK" && mkdir -p "$SRC/MAC_SDK" && unzip -q "$DL/MAC_${MAC_VER}_SDK.zip" -d "$SRC/MAC_SDK"
  (cd "$SRC/MAC_SDK" &&
    sources=($(sed -n '/^set(MAC_SHARED_SOURCE_FILES/,/)/p;/^set(MAC_LIBRARY_SOURCE_FILES$/,/)/p' CMakeLists.txt |
      grep -o 'Source/[^ )]*\.cpp' | sort -u)) &&
    clang++ -std=c++11 -O2 -DPLATFORM_APPLE -ISource/Shared -ISource/MACLib \
      -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET "${sources[@]}" Source/Shared/StdLibFileIO.cpp \
      Source/MACLib/NNFilterNeon.cpp Source/Console/Console.cpp -o "$OUT/bin/mac" 2>"$VENDOR/mac-build.log")
  strip -x "$OUT/bin/mac"
fi

# Licences travel with the binaries.
mkdir -p "$OUT/licenses/ffmpeg" "$OUT/licenses/lame" "$OUT/licenses/libvpx" "$OUT/licenses/libwebp" "$OUT/licenses/exiftool" \
  "$OUT/licenses/opencore-amr" "$OUT/licenses/vo-amrwbenc" "$OUT/licenses/monkeys-audio"
cp "$SRC/opencore-amr-$AMR_VER/LICENSE" "$OUT/licenses/opencore-amr/" 2>/dev/null || true
cp "$SRC/vo-amrwbenc-$AMRWBENC_VER/NOTICE" "$SRC/vo-amrwbenc-$AMRWBENC_VER/COPYING" "$OUT/licenses/vo-amrwbenc/" 2>/dev/null || true
cp "$SRC/MAC_SDK/License.txt" "$OUT/licenses/monkeys-audio/" 2>/dev/null || true
cp "$SRC/libvpx/LICENSE" "$SRC/libvpx/PATENTS" "$OUT/licenses/libvpx/" 2>/dev/null || true
cp "$SRC/ffmpeg-$FFMPEG_VER/COPYING.LGPLv3" "$SRC/ffmpeg-$FFMPEG_VER/COPYING.LGPLv2.1" "$SRC/ffmpeg-$FFMPEG_VER/LICENSE.md" \
  "$OUT/licenses/ffmpeg/" 2>/dev/null || true
cp "$SRC/lame-$LAME_VER/COPYING" "$OUT/licenses/lame/" 2>/dev/null || true
cp "$SRC/libwebp-$WEBP_VER-mac-arm64/COPYING" "$SRC/libwebp-$WEBP_VER-mac-arm64/PATENTS" "$OUT/licenses/libwebp/" 2>/dev/null || true
cat >"$OUT/licenses/exiftool/LICENSE" <<'TXT'
ExifTool by Phil Harvey. This is free software; you can redistribute it and/or modify it
under the same terms as Perl itself (the Artistic License or the GNU GPL).
https://exiftool.org
TXT
cat >"$OUT/licenses/SOURCES.txt" <<TXT
ffmpeg $FFMPEG_VER  https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz  sha256 $FFMPEG_SHA
  built LGPLv3 (no --enable-gpl / --enable-nonfree) with libmp3lame, libvpx, opencore-amr, vo-amrwbenc,
  VideoToolbox, AudioToolbox
opencore-amr $AMR_VER  https://sourceforge.net/projects/opencore-amr  sha256 $AMR_SHA  (Apache-2.0)
vo-amrwbenc $AMRWBENC_VER  https://sourceforge.net/projects/opencore-amr  sha256 $AMRWBENC_SHA  (Apache-2.0)
Monkey's Audio SDK $MAC_VER  https://monkeysaudio.com/developers.html  sha256 $MAC_SHA  (3-Clause BSD)
LAME $LAME_VER      https://lame.sourceforge.io  sha256 $LAME_SHA
libvpx $VPX_TAG     https://chromium.googlesource.com/webm/libvpx  commit $VPX_COMMIT
libwebp $WEBP_VER   https://developers.google.com/speed/webp  sha256 $WEBP_SHA
ExifTool $EXIF_VER  https://exiftool.org  sha256 $EXIF_SHA
TXT

echo "Tools ready in $OUT"
ls -la "$OUT/bin"
