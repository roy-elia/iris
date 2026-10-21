#!/bin/zsh
# Renders the SVGs with headless Chrome, then exports PNG sizes, .icns and a preview sheet.
set -e
cd "${0:A:h}/.."
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
T=$(mktemp -d)
shot() { "$C" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 --window-size=$2,$2 --screenshot=$3 "$1" 2>/dev/null; }
shot "file://$PWD/AppIcon.svg" 1024 AppIcon-1024.png
shot "file://$PWD/AppIcon-Dark.svg" 1024 AppIcon-Dark-1024.png
print "<html><body style='margin:0'><img src='file://$PWD/HotbarIcon.svg' style='width:288px;height:288px;display:block'></body></html>" > $T/g.html
shot "file://$T/g.html" 288 $T/g288.png
for s in 1 2 3; do magick $T/g288.png -filter Lanczos -resize $((24*s))x$((24*s)) HotbarIcon$([[ $s == 1 ]] || print "@${s}x").png; done
rm -rf AppIcon.iconset; mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  magick AppIcon-1024.png -filter Lanczos -resize ${s}x${s} AppIcon.iconset/icon_${s}x${s}.png
  magick AppIcon-1024.png -filter Lanczos -resize $((s*2))x$((s*2)) AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
# preview: light + dark icons at several sizes, glyph on light and dark menu bars
W=$T/white.png; magick $T/g288.png -channel RGB -negate +channel $W
magick -size 1600x820 xc:'#ECEEF3' \
  \( AppIcon-1024.png -resize 440x440 \) -geometry +40+40 -composite \
  \( AppIcon-1024.png -resize 128x128 \) -geometry +520+80 -composite \
  \( AppIcon-1024.png -resize 64x64 \) -geometry +680+112 -composite \
  \( AppIcon-1024.png -resize 32x32 \) -geometry +780+128 -composite \
  \( -size 800x820 xc:'#17181C' \) -geometry +800+0 -composite \
  \( AppIcon-Dark-1024.png -resize 440x440 \) -geometry +840+40 -composite \
  \( AppIcon-Dark-1024.png -resize 128x128 \) -geometry +1320+80 -composite \
  \( AppIcon-Dark-1024.png -resize 64x64 \) -geometry +1480+112 -composite \
  \( -size 720x72 xc:'#F6F6F8' \) -geometry +40+560 -composite \
  \( $T/g288.png -resize 54x54 \) -geometry +620+569 -composite \
  \( HotbarIcon.png -scale 400% \) -geometry +40+660 -composite \
  \( -size 720x72 xc:'#2A2B30' \) -geometry +840+560 -composite \
  \( $W -resize 54x54 \) -geometry +1420+569 -composite \
  \( $W -resize 24x24 -scale 400% \) -geometry +840+660 -composite \
  preview.png
rm -rf $T
