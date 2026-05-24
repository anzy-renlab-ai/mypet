#!/usr/bin/env bash
#
# Re-segment sprite APNGs to remove leftover background (e.g. the white wedge
# between the tail and the body) using rembg + BiRefNet — the same "good"
# segmentation idle got, applied to the states that were later cut with a
# lazier method.
#
# This re-derives the ALPHA only; it preserves each sprite's existing framing,
# size, and timing (it does NOT re-generate from the Kling videos).
#
# Run on a machine where rembg installs (this repo's agent sandbox can't —
# its pinned pip index has no onnxruntime wheel):
#
#   pip install "rembg[cli]"          # pulls onnxruntime + the model runtime
#   scripts/fix-sprite-alpha.sh cat-petting cat-eating cat-purring ...
#   # or process every non-idle state:
#   scripts/fix-sprite-alpha.sh all
#
# Requires: ffmpeg, ffprobe, rembg. Model: BiRefNet (override with MODEL=...).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SPRITES="$REPO/Sources/MyPet/Resources/sprites"
MODEL="${MODEL:-birefnet-general}"

command -v rembg >/dev/null  || { echo "rembg not found — pip install 'rembg[cli]'"; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg not found"; exit 1; }

states=("$@")
if [ "${1:-}" = "all" ]; then
  states=()
  for f in "$SPRITES"/cat-*.apng; do
    n="$(basename "$f" .apng)"
    [ "$n" = "cat-idle" ] && continue   # idle is already clean
    states+=("$n")
  done
fi
[ ${#states[@]} -gt 0 ] || { echo "usage: $0 cat-petting [cat-eating ...] | all"; exit 2; }

for name in "${states[@]}"; do
  src="$SPRITES/$name.apng"
  [ -f "$src" ] || { echo "skip $name (missing)"; continue; }

  read -r W H <<<"$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=' ' "$src")"
  fps="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$src")"
  [ -z "$fps" ] || [ "$fps" = "0/0" ] && fps="12"

  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  echo "[$name] ${W}x${H} @ $fps — extracting frames…"
  # Flatten each frame onto white so the segmenter sees the same background the
  # cat was shot on (Kling white-ish), then it cleanly excludes ALL of it —
  # including the wedge the previous pass missed.
  ffmpeg -y -i "$src" -vf "color=white:s=${W}x${H}[bg];[bg][0:v]overlay,format=rgb24" "$tmp/in_%04d.png" 2>/dev/null

  echo "[$name] re-segmenting with $MODEL…"
  mkdir -p "$tmp/out"
  rembg p -m "$MODEL" "$tmp" "$tmp/out" 2>/dev/null

  echo "[$name] reassembling APNG…"
  ffmpeg -y -framerate "$fps" -i "$tmp/out/in_%04d.png" -plays 0 -f apng "$src" 2>/dev/null
  echo "[$name] done → $src"

  rm -rf "$tmp"; trap - EXIT
done

echo "All set. Rebuild the app (swift build) and re-check the alpha:"
echo "  ffmpeg -sseof -1 -i <apng> -vf alphaextract -frames:v 1 /tmp/a.png && open /tmp/a.png"
