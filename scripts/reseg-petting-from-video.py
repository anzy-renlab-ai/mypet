#!/usr/bin/env python3
"""Re-segment the petting sprite FROM the source Kling video (not the existing
APNG frames), with a per-frame white-edge self-check.

Pipeline: extract N frames from the 1920x1080 mp4 -> isnet-general-use matte
-> numpy defringe (alpha threshold + 1px erode + cut white-ish edge pixels)
-> per-frame white-edge audit -> stable union crop -> scale to match the
current sprite -> assemble APNG at the original display rate.

Run with the REAL python that has rembg installed:
  PYTHONPATH=~/Library/Python/3.9/site-packages \
  /usr/bin/python3 scripts/reseg-petting-from-video.py
"""
import os, sys, subprocess, tempfile, glob
import numpy as np
from PIL import Image
from scipy import ndimage
from rembg import remove, new_session

VIDEO = os.path.expanduser(
    "~/Downloads/kling_20260518_作品_____shot___5556_0.mp4")
OUT_APNG = os.path.expanduser(
    "~/work/mypet/Sources/MyPet/Resources/sprites/cat-petting.apng")

N_FRAMES = 58            # match current sprite frame count
DISPLAY_FPS = "35/6"     # match current avg_frame_rate (~5.83fps)
TARGET_H = 211           # match current sprite height
PAD = 10                 # px padding around the union bbox
ALPHA_FLOOR = 30         # alpha below this -> fully transparent
WHITE_MIN = 205          # min(R,G,B) above this on a soft edge = white halo
EDGE_AUDIT_WHITE = 238   # luminance above this on the boundary = flagged

def log(*a):
    print(*a, flush=True)

def extract_frames(tmp):
    log(f"[1/5] extracting {N_FRAMES} frames from {os.path.basename(VIDEO)}")
    # 5.0417s video -> N evenly spaced frames
    fps = N_FRAMES / 5.0417
    subprocess.run(
        ["ffmpeg", "-v", "error", "-i", VIDEO,
         "-vf", f"fps={fps:.5f}", "-frames:v", str(N_FRAMES),
         os.path.join(tmp, "raw_%03d.png"), "-y"],
        check=True)
    frames = sorted(glob.glob(os.path.join(tmp, "raw_*.png")))
    log(f"      got {len(frames)} raw frames")
    return frames

def defringe(rgba):
    """alpha threshold + 1px erode + cut white-ish soft-edge pixels."""
    arr = np.array(rgba).astype(np.int16)
    r, g, b, a = arr[..., 0], arr[..., 1], arr[..., 2], arr[..., 3]
    # 1. hard threshold
    a = np.where(a < ALPHA_FLOOR, 0, a)
    mask = a > 0
    # 2. erode the silhouette by 1px to drop the outermost (haloed) ring
    eroded = ndimage.binary_erosion(mask, iterations=1)
    a = np.where(eroded, a, 0)
    # 3. on soft edges (partial alpha), kill near-white pixels = matte halo
    minrgb = np.minimum(np.minimum(r, g), b)
    soft = (a > 0) & (a < 255)
    whiteish = soft & (minrgb >= WHITE_MIN)
    a = np.where(whiteish, 0, a)
    out = np.dstack([r, g, b, a]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")

def audit_white_edge(rgba):
    """count boundary pixels that are still white-ish (halo residue)."""
    arr = np.array(rgba)
    a = arr[..., 3]
    mask = a > 0
    boundary = mask & ~ndimage.binary_erosion(mask, iterations=1)
    if boundary.sum() == 0:
        return 0, 0
    r, g, b = arr[..., 0].astype(int), arr[..., 1].astype(int), arr[..., 2].astype(int)
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    white = boundary & (lum >= EDGE_AUDIT_WHITE)
    return int(white.sum()), int(boundary.sum())

def main():
    if not os.path.exists(VIDEO):
        log(f"FATAL: source video missing: {VIDEO}")
        sys.exit(1)
    session = new_session("isnet-general-use")
    tmp = tempfile.mkdtemp(prefix="petting_reseg_")
    log(f"workdir: {tmp}")
    raws = extract_frames(tmp)

    # 2: segment + defringe every frame, hold in memory as RGBA
    log("[2/5] segmenting + defringing (isnet-general-use)")
    cut = []
    for i, fp in enumerate(raws):
        src = Image.open(fp).convert("RGB")
        out = remove(src, session=session, post_process_mask=True)
        out = defringe(out.convert("RGBA"))
        cut.append(out)
        if i % 10 == 0:
            log(f"      frame {i+1}/{len(raws)}")

    # 3: per-frame white-edge audit
    log("[3/5] white-edge audit (flag = halo residue on boundary)")
    flagged = 0
    for i, im in enumerate(cut):
        w, tot = audit_white_edge(im)
        pct = (100.0 * w / tot) if tot else 0
        if pct > 2.0:
            flagged += 1
            log(f"      frame {i:03d}: {w}/{tot} white edge px ({pct:.1f}%)  FLAG")
    log(f"      {flagged}/{len(cut)} frames flagged (>2% white boundary)")

    # 4: stable union crop across all frames, then scale to target height
    log("[4/5] union-crop + scale")
    union = None
    for im in cut:
        a = np.array(im)[..., 3]
        ys, xs = np.where(a > 10)
        if len(xs) == 0:
            continue
        bb = [xs.min(), ys.min(), xs.max(), ys.max()]
        union = bb if union is None else [
            min(union[0], bb[0]), min(union[1], bb[1]),
            max(union[2], bb[2]), max(union[3], bb[3])]
    W, H = cut[0].size
    x0 = max(0, union[0] - PAD); y0 = max(0, union[1] - PAD)
    x1 = min(W, union[2] + PAD); y1 = min(H, union[3] + PAD)
    log(f"      union bbox {union} -> crop ({x0},{y0},{x1},{y1})")
    cropw, croph = x1 - x0, y1 - y0
    scale = TARGET_H / croph
    tw = int(round(cropw * scale)); th = TARGET_H
    log(f"      crop {cropw}x{croph} -> scale {tw}x{th}")
    final_dir = os.path.join(tmp, "final")
    os.makedirs(final_dir, exist_ok=True)
    for i, im in enumerate(cut):
        c = im.crop((x0, y0, x1, y1)).resize((tw, th), Image.LANCZOS)
        c.save(os.path.join(final_dir, f"f_{i:03d}.png"))

    # 5: assemble APNG at original display rate, loop forever
    log("[5/5] assembling APNG")
    subprocess.run(
        ["ffmpeg", "-v", "error", "-framerate", DISPLAY_FPS,
         "-i", os.path.join(final_dir, "f_%03d.png"),
         "-f", "apng", "-plays", "0", OUT_APNG, "-y"],
        check=True)
    sz = os.path.getsize(OUT_APNG)
    log(f"DONE: wrote {OUT_APNG} ({sz//1024} KB, {tw}x{th}, {len(cut)} frames)")
    log(f"      flagged frames: {flagged} (0 = clean)")

if __name__ == "__main__":
    main()
