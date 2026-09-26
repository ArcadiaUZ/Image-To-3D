#!/usr/bin/env python3
"""TRELLIS.2: rasm -> teksturali 3D GLB (Windows, Vulkan/RTX).

Foydalanish:
    python generate.py rasm.png [seed] [steps] [texture_steps]
"""
import os
import sys
import time
import urllib.request
import uuid

ROOT = os.path.dirname(os.path.abspath(__file__))
URL = "http://127.0.0.1:8742"
OUT = os.path.join(ROOT, "out")


def post_multipart(fields, file_field, file_path):
    """POST a multipart/form-data request without extra dependencies."""
    boundary = uuid.uuid4().hex
    sep = f"--{boundary}\r\n".encode()
    parts = []
    for k, v in fields.items():
        parts.append(sep + f'Content-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    with open(file_path, "rb") as f:
        fname = os.path.basename(file_path)
        parts.append(
            sep
            + f'Content-Disposition: form-data; name="{file_field}"; filename="{fname}"\r\n'
            .encode()
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
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read().decode()


def get(path):
    with urllib.request.urlopen(f"{URL}{path}", timeout=600) as r:
        return r.read()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    image = sys.argv[1]
    if not os.path.isfile(image):
        print(f"[XATO] Fayl topilmadi: {image}")
        return 1
    seed = sys.argv[2] if len(sys.argv) > 2 else "0"
    steps = sys.argv[3] if len(sys.argv) > 3 else "12"
    tsteps = sys.argv[4] if len(sys.argv) > 4 else "12"

    try:
        get("/api/jobs")
    except Exception:
        print("[XATO] Server ishlamayapti. Avval start_server.bat ni ishga tushiring.")
        return 1

    print(f"[1/3] Rasm yuborilmoqda: {image}")
    fields = {
        "source": "512", "background": "0", "seed": seed,
        "steps": steps, "guidance": "7.5", "texture_steps": tsteps,
    }
    import json
    job = json.loads(post_multipart(fields, "image", image))["job"]
    print(f"      job: {job}")

    print("[2/3] Kutamiz...")
    last = ""
    while True:
        info = json.loads(get(f"/api/job/{job}").decode())
        if info.get("state") == "done":
            break
        if info.get("state") == "error":
            print(f"[XATO] {info.get('error')}")
            return 1
        if info.get("stage") and info["stage"] != last:
            last = info["stage"]
            print(f"      {last} ({info.get('step', 0)}/{info.get('total', 0)})")
        time.sleep(5)

    print(f"[3/3] GLB yuklanmoqda ({info.get('durationMs', 0) // 1000}s)")
    os.makedirs(OUT, exist_ok=True)
    base = os.path.splitext(os.path.basename(image))[0]
    dest = os.path.join(OUT, f"{base}_{job}.glb")
    with open(dest, "wb") as f:
        f.write(get(f"/api/glb/{job}?texture=2048"))

    size = os.path.getsize(dest) / 1024 / 1024
    print()
    print("=" * 60)
    print(f"  TAYYOR:  {dest}  ({size:.1f} MB)")
    print("  Ochish:  Blender / Windows 3D Viewer / meshlab.net")
    print("=" * 60)
    return 0


if __name__ == "__main__":
    sys.exit(main())
