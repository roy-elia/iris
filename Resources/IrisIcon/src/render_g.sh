#!/bin/zsh
# Renders each direction's SVGs with headless Chrome: 1024 px PNGs, menu-bar glyph PNGs, and a
# preview sheet comparing the directions.
set -e
cd "${0:A:h}/.."
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
T=$(mktemp -d)
shot() { "$C" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 --window-size=$2,$2 --screenshot=$3 "$1" 2>/dev/null; }
for v in iris-f iris-g; do
  shot "file://$PWD/$v/AppIcon.svg" 1024 $v/AppIcon-1024.png
  shot "file://$PWD/$v/AppIcon-Dark.svg" 1024 $v/AppIcon-Dark-1024.png
  print "<html><body style='margin:0'><img src='file://$PWD/$v/HotbarIcon.svg' style='width:288px;height:288px;display:block'></body></html>" > $T/g.html
  shot "file://$T/g.html" 288 $T/g-$v.png
  for s in 1 2; do magick $T/g-$v.png -filter Lanczos -resize $((18*s))x$((18*s)) $v/HotbarIcon$([[ $s == 1 ]] || print "@${s}x").png; done
  magick $T/g-$v.png -channel RGB -negate +channel $T/gw-$v.png
done
row() { # variant y
  v=$1; y=$2
  magick -size 1500x420 xc:'#ECEEF3' \
    \( $v/AppIcon-1024.png -resize 340x340 \) -geometry +30+40 -composite \
    \( $v/AppIcon-1024.png -resize 96x96 \) -geometry +400+40 -composite \
    \( $v/AppIcon-1024.png -resize 48x48 \) -geometry +400+160 -composite \
    \( $v/AppIcon-1024.png -resize 32x32 \) -geometry +470+160 -composite \
    \( -size 750x420 xc:'#17181C' \) -geometry +750+0 -composite \
    \( $v/AppIcon-Dark-1024.png -resize 340x340 \) -geometry +780+40 -composite \
    \( $v/AppIcon-Dark-1024.png -resize 96x96 \) -geometry +1150+40 -composite \
    \( $v/AppIcon-Dark-1024.png -resize 48x48 \) -geometry +1150+160 -composite \
    \( -size 330x40 xc:'#F6F6F8' \) -geometry +400+260 -composite \
    \( $T/g-$v.png -resize 18x18 \) -geometry +600+271 -composite \
    \( $T/g-$v.png -resize 120x120 \) -geometry +400+300 -composite \
    \( -size 330x40 xc:'#2A2B30' \) -geometry +1150+260 -composite \
    \( $T/gw-$v.png -resize 18x18 \) -geometry +1350+271 -composite \
    \( $T/gw-$v.png -resize 120x120 \) -geometry +1150+300 -composite \
    $T/row-$v.png
}
row iris-f; row iris-g
magick $T/row-iris-f.png $T/row-iris-g.png -append preview-iris-g.png
rm -rf $T
