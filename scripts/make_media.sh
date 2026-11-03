#!/bin/sh
# AdaFlip: a combat racer in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# The pictures in docs/: the game itself with the AI at the wheel.
# Needs a display, ImageMagick (convert) and ffmpeg.
#
#   scripts/make_media.sh             all of them
#   scripts/make_media.sh shot NAME TRACK SKIP [CAMERA]
#   scripts/make_media.sh gif  NAME TRACK SKIP SECONDS [CAMERA] [stunt]
#
# SKIP is seconds raced before the picture (the countdown is the first 4).
# bin/scan TRACK [stunt] lists the lively moments to choose them by.
# "stunt": the AI at the player's wheel rides the walls and roofs.
set -e
cd "$(dirname "$0")/.."
for tool in convert ffmpeg; do
   if ! command -v $tool > /dev/null 2>&1; then
      echo "make_media.sh needs $tool: sudo apt install imagemagick ffmpeg"
      exit 1
   fi
done
OUT=docs
mkdir -p "$OUT/screenshots" "$OUT/gifs"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run() {   # TRACK SKIP CAMERA, then more environment
   track=$1; skip=$2; cam=$3; shift 3
   env ADAFLIP_TRACK="$track" ADAFLIP_AUTOSTART=1 ADAFLIP_AUTOPILOT=1 ADAFLIP_SKIP="$skip" \
       ADAFLIP_CAMERA="$cam" ADAFLIP_VOLUME=0 "$@" timeout 300 ./bin/adaflip > /dev/null
}

shot() {   # NAME TRACK SKIP [CAMERA]
   run "$2" "$3" "${4:-CHASE}" ADAFLIP_SHOT="$TMP/s.ppm" ADAFLIP_SHOT_FRAME=60
   convert "$TMP/s.ppm" -quality 90 "$OUT/screenshots/$1.jpg"
   echo "$OUT/screenshots/$1.jpg"
}

title() {   # NAME TRACK
   env ADAFLIP_TRACK="$2" ADAFLIP_VOLUME=0 ADAFLIP_SHOT="$TMP/s.ppm" ADAFLIP_SHOT_FRAME=200 \
       timeout 300 ./bin/adaflip > /dev/null
   convert "$TMP/s.ppm" -quality 90 "$OUT/screenshots/$1.jpg"
   echo "$OUT/screenshots/$1.jpg"
}

gif() {   # NAME TRACK SKIP SECONDS [CAMERA] [stunt]
   rm -f "$TMP"/f*.ppm
   frames=$(( $4 * 30 ))
   stunt=; [ "$6" = stunt ] && stunt=1
   run "$2" "$3" "${5:-CHASE}" ADAFLIP_RECORD="$TMP" ADAFLIP_RECORD_FROM=10 ADAFLIP_RECORD_COUNT="$frames" \
       ADAFLIP_NO_HUD=1 ADAFLIP_STUNT="$stunt"
   ffmpeg -loglevel error -y -framerate 30 -i "$TMP/f%04d.ppm" \
      -vf "fps=15,scale=560:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
      "$OUT/gifs/$1.gif"
   echo "$OUT/gifs/$1.gif ($(du -h "$OUT/gifs/$1.gif" | cut -f1))"
}

make -s game > /dev/null
if [ $# -gt 0 ]; then
   kind=$1; shift
   "$kind" "$@"
   exit
fi

title title 1
shot  grid       1 0
shot  tunnel     1 32
shot  harbour    2 55 FAR_CHASE
shot  halfpipe   2 39
shot  frostline  3 47
gif   roof       1 34 5 CHASE stunt
gif   pipe       2 69 4 CHASE stunt
gif   frostline  3 32 5 CHASE stunt
gif   combat     1 37 5
