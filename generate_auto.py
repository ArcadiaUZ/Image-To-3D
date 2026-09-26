#!/usr/bin/env python3
"""TRELLIS.2 — rasmdan 3D, KO'P SEED + AVTOMATIK ENG YAXSHINI TANLASH.

Single-view pipeline bitta rasm bilan ishlaydi, lekin bitta seed ba'zan yon
tomonni noto'g'ri taxmin qiladi va butun geometriya buziladi. Shu sababli:

  1. N ta seed bilan N ta model yaratiladi
  2. Har bir modelning silueti (ko'rinishi) input rasm silueti bilan solishtiriladi
  3. Eng o'xshash (eng katta IoU) model tanlanadi

Siluet taqqoslash scale/translation ga bog'liq emas: ikkalasi ham o'z bbox'iga
moslashtiriladi, shuning uchun faqat SHAKL ni solishtiradi.

Foydalanish:
    python generate_auto.py rasm.png [n_seeds] [steps] [texture_steps]
    python generate_auto.py rasm.png 6 16 16
"""
import io
import json
import os
import sys
import time
import urllib.request
import uuid

import numpy as np
from PIL import Image
from scipy import ndimage

import trimesh

ROOT = os.path.dirname(os.path.abspath(__file__))
URL = "http://127.0.0.1:8742"
OUT = os.path.join(ROOT, "out")
GRID = 192  # silhouette raster resolution


# ---------------------------------------------------------------- HTTP

def _get(path):
    with urllib.request.urlopen(f"{URL}{path}", timeout=900) as r:
        return r.read()


def _post_multipart(fields, file_field, file_path):
    boundary = uuid.uuid4().hex
    sep = f"--{boundary}\r\n".encode()
    parts = []
    for k, v in fields.items():
        parts.append(sep + f'Content-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    with open(file_path, "rb") as f:
        parts.append(
            sep
            + f'Content-Disposition: form-data; name="{file_field}"; filename="{os.path.basename(file_path)}"\r\n'.encode()
            + b"Content-Type: application/octet-stream\r\n\r\n"
            + f.read()
            + b"\r\n"
        )
    body = b"".join(parts) + f"--{boundary}--\r\n".encode()
    req = urllib.request.Request(
        f"{URL}/api/generate",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.loads(r.read().decode())


def generate_one(image, seed, steps, tsteps, label=""):
    """Run one generation; return (job_id, glb_bytes, seconds)."""
    fields = {
        "source": "512", "background": "0", "seed": str(seed),
        "steps": str(steps), "guidance": "7.5", "texture_steps": str(tsteps),
    }
    t0 = time.time()
    job = _post_multipart(fields, "image", image)["job"]
    if label:
        print(f"    {label} job: {job}", end="", flush=True)
    while True:
        info = json.loads(_get(f"/api/job/{job}").decode())
        st = info.get("state")
        if st == "error":
            print(f"\n    [XATO seed={seed}] {info.get('error')}")
            return None, None, time.time() - t0
        if st == "done":
            if label:
                print(f"  -> {time.time() - t0:.0f}s", end="", flush=True)
            return job, _get(f"/api/glb/{job}?texture=2048"), time.time() - t0
        time.sleep(4)


# ---------------------------------------------------------------- silhouettes

def _normalize_to_grid(mask, grid=GRID):
    """Crop a binary mask to its bbox and resample to grid x grid."""
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return np.zeros((grid, grid), bool)
    sub = mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h, w = sub.shape
    # nearest-neighbour resample (fast, and we only need coverage)
    yi = (np.arange(grid) * (h / grid)).astype(np.int32).clip(0, h - 1)
    xi = (np.arange(grid) * (w / grid)).astype(np.int32).clip(0, w - 1)
    return sub[yi][:, xi]


def image_silhouette(path):
    """Foreground mask of the input image: real alpha, else border-connected
    near-black/near-white removal (same heuristic the pipeline uses)."""
    im = Image.open(path)
    if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
        im = im.convert("RGBA")
        alpha = np.array(im)[:, :, 3]
        if alpha.min() < 250:
            return alpha > 8

    rgb = np.array(im.convert("RGB")).astype(np.int16)
    h, w, _ = rgb.shape
    # near-white OR near-black
    near_white = (rgb.min(axis=2) > 238)
    near_black = (rgb.max(axis=2) < 17)
    bgish = near_white | near_black

    # keep only bgish pixels connected to the border (so interior white stays)
    border = np.zeros_like(bgish)
    border[0, :] = border[-1, :] = True
    border[:, 0] = border[:, -1] = True
    seeds = bgish & border
    lab, n = ndimage.label(bgish)
    keep = set(np.unique(lab[seeds])) - {0}
    bg = np.isin(lab, list(keep)) if keep else np.zeros_like(bgish)
    fg = ~bg
    if fg.sum() < 0.02 * h * w:          # removal went wrong -> use everything
        fg = np.ones((h, w), bool)
    return fg


def mesh_silhouettes(glb_bytes):
    """Six axis-aligned orthographic silhouettes of the mesh, each normalized."""
    scene = trimesh.load(io.BytesIO(glb_bytes), file_type="glb", force="mesh", process=False)
    v = np.asarray(scene.vertices, dtype=np.float64)
    if v.ndim != 2 or len(v) == 0:
        return []

    out = []
    for axis in range(3):
        other = [a for a in range(3) if a != axis]
        for flip in (1, -1):
            uv = v[:, other] * flip
            lo, hi = uv.min(axis=0), uv.max(axis=0)
            span = np.maximum(hi - lo, 1e-9)
            g = ((uv - lo) / span * (GRID - 1)).astype(np.int32)
            flat = g[:, 0] * GRID + g[:, 1]
            splat = np.zeros(GRID * GRID, bool)
            splat[flat] = True
            splat = splat.reshape(GRID, GRID)
            # densify: vertices are dense but may leave pinholes
            splat = ndimage.binary_closing(splat, np.ones((3, 3)))
            out.append(splat)
    return out


def iou(a, b):
    u = np.logical_or(a, b).sum()
    return float(np.logical_and(a, b).sum() / u) if u else 0.0


def best_iou(ref_norm, silhs):
    """Silhouettes are compared already normalized to the grid."""
    return max((iou(ref_norm, s) for s in silhs), default=0.0)


# ---------------------------------------------------------------- main

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    image = sys.argv[1]
    if not os.path.isfile(image):
        print(f"[XATO] Fayl topilmadi: {image}")
        return 1
    n_seeds = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    steps = int(sys.argv[3]) if len(sys.argv) > 3 else 16
    tsteps = int(sys.argv[4]) if len(sys.argv) > 4 else 16
    base_seed = int(sys.argv[5]) if len(sys.argv) > 5 else 0

    try:
        _get("/api/jobs")
    except Exception:
        print("[XATO] Server ishlamayapti. Avval start_server.bat ni ishga tushiring.")
        return 1

    os.makedirs(OUT, exist_ok=True)
    ref = _normalize_to_grid(image_silhouette(image))
    print(f"Input silhouette: {ref.mean() * 100:.1f}% to'lgan ({GRID}x{GRID})")
    print(f"{n_seeds} ta variant yaratilmoqda (steps={steps}, texture={tsteps}) ...")
    print()

    results = []
    for i in range(n_seeds):
        seed = base_seed + i
        job, glb, secs = generate_one(image, seed, steps, tsteps, label=f"  [{i + 1}/{n_seeds}] seed={seed:<3}")
        if job is None:
            continue
        score = best_iou(ref, mesh_silhouettes(glb))
        results.append((score, job, glb, secs))
        print(f"      -> siluet mosligi (IoU): {score:.3f}")

    if not results:
        print("[XATO] Hech bir variant yaratilmadi.")
        return 1

    print()
    print("=" * 64)
    print("  Natijalar (IoU = qanchalik rasmga o'xshaydi, 1.0 = mukammal):")
    for score, job, _, _ in sorted(results, key=lambda r: -r[0]):
        print(f"    {score:.3f}   seed/job {job}")
    best_score, best_job, best_glb, _ = max(results, key=lambda r: r[0])
    print()

    base = os.path.splitext(os.path.basename(image))[0]
    dest = os.path.join(OUT, f"{base}_best_{best_job}.glb")
    with open(dest, "wb") as f:
        f.write(best_glb)

    # Keep the runner-ups on disk so you can open and compare them side by side.
    for score, job, _, _ in results:
        if job == best_job:
            continue
        alt = os.path.join(OUT, f"{base}_alt{score:.2f}_{job}.glb")
        if not os.path.exists(alt):
            with open(alt, "wb") as f:
                f.write(dict((j, g) for _, j, g, _ in results)[job])

    print("=" * 64)
    print(f"  ENG YAXSHI:  {dest}")
    print(f"  IoU: {best_score:.3f}   vaqt: {sum(r[3] for r in results) / 60:.1f} min "
          f"({n_seeds} ta variant)")
    print("  Ochish:  Blender / Windows 3D Viewer / meshlab.net")
    print("=" * 64)
    return 0


if __name__ == "__main__":
    sys.exit(main())
