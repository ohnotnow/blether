#!/usr/bin/env bash
# Turns one square PNG into a macOS app icon: the artwork on a rounded square matching Apple's icon
# grid (so macOS 26 and later show it as it is instead of inside a grey plate), then the ten sizes an
# Xcode asset catalogue wants, with their Contents.json.
#
# Usage: make-mac-icon.sh SOURCE.png OUT_DIR [TOP_COLOUR BOTTOM_COLOUR]
#
# Writes OUT_DIR/AppIcon.appiconset/ (ten PNGs and Contents.json) and OUT_DIR/icon-1024.png (the
# finished icon at full size, handy for a README or a side-by-side preview). The background is a
# vertical gradient, dark navy by default. Needs ImageMagick (`magick`); sizes are made with the
# built-in `sips`.
set -euo pipefail

if [[ $# -ne 2 && $# -ne 4 ]]; then
    echo "usage: $0 SOURCE.png OUT_DIR [TOP_COLOUR BOTTOM_COLOUR]" >&2
    exit 64
fi
source_png=$1
out_dir=$2
top=${3:-#232a66}
bottom=${4:-#0b0d2a}

command -v magick >/dev/null || { echo "$0: needs ImageMagick's magick (brew install imagemagick)" >&2; exit 69; }
[[ -f $source_png ]] || { echo "$0: no such file: $source_png" >&2; exit 66; }

iconset=$out_dir/AppIcon.appiconset
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$iconset"

# Apple's macOS grid: an 824-point rounded square inset 100 in a 1024 canvas, corner radius about 185.
# The artwork is scaled to 690 so it sits inside the square with a margin, nudged 8 down.
magick -size 824x824 xc:none -fill white -draw "roundrectangle 0,0,823,823,185,185" "$work/mask.png"
magick -size 824x824 "gradient:$top-$bottom" "$work/mask.png" -alpha off -compose CopyOpacity -composite "$work/plate.png"
magick -size 1024x1024 xc:none "$work/plate.png" -geometry +100+100 -composite \
    \( "$source_png" -resize 690x690 \) -gravity center -geometry +0+8 -composite "$out_dir/icon-1024.png"

entries=()
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        pixels=$((size * scale))
        # Not $([[ ... ]] && echo @2x): its failing status would end the script under set -e.
        suffix=""
        if [[ $scale == 2 ]]; then suffix="@2x"; fi
        name="icon_${size}x${size}${suffix}.png"
        sips -z "$pixels" "$pixels" "$out_dir/icon-1024.png" --out "$iconset/$name" >/dev/null
        entries+=("    { \"filename\" : \"$name\", \"idiom\" : \"mac\", \"scale\" : \"${scale}x\", \"size\" : \"${size}x${size}\" }")
    done
done

{
    echo '{'
    echo '  "images" : ['
    (IFS=$'\n'; echo "${entries[*]}") | sed '$!s/$/,/'
    echo '  ],'
    echo '  "info" : { "author" : "xcode", "version" : 1 }'
    echo '}'
} > "$iconset/Contents.json"

echo "wrote $iconset and $out_dir/icon-1024.png"
