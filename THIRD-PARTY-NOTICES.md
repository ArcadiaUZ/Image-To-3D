# Third-party notices

Image-To-3D is an **automation layer**, not a fork. It downloads, patches and
drives third-party projects at install time. None of their code is redistributed
here, and each remains under its own license.

## Projects used at runtime

| Project | License | Role |
|---|---|---|
| [trellis2cpp](https://github.com/localai-org/trellis2cpp) | MIT | C++/ggml port of the TRELLIS.2 pipeline (cloned by `setup.bat`, pinned to rev `2f3e6e26`) |
| [ggml](https://github.com/ggml-org/ggml) | MIT | Tensor library and the Vulkan backend (submodule of trellis2cpp) |
| [TRELLIS.2](https://github.com/microsoft/TRELLIS.2) | MIT | Model architecture and weights, Copyright (c) Microsoft Corporation |
| [DINOv3](https://github.com/facebookresearch/dinov3) | see upstream | Image conditioning encoder |
| [purego](https://github.com/ebitengine/purego) | MIT | cgo-free FFI used by the Go server |
| [msys2 mingw-w64 shaderc](https://www.msys2.org/) | MIT | Provides the prebuilt `glslc` shader compiler |
| [Khronos Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) | Apache-2.0 | Vulkan API headers |

## Patches applied to trellis2cpp

Both patches live in `patches/` and are applied automatically by `setup.bat`.

1. **`0001-cpp-msvc-M_PI.patch`** — MSVC does not define `M_PI`, so
   `trellis2.cpp` fails to compile. Adds an `#ifndef M_PI` fallback.
2. **`0002-server-windows-purego.patch`** — `purego.Dlopen` exists only on
   POSIX. The Go server now calls a platform helper, with the Windows
   implementation in `server/dlib_windows.go` (`syscall.LoadDLL`).

## Model weights

**No weights are distributed in this repository.** `setup.bat` downloads them
from the `LocalAI-io` and `microsoft` Hugging Face repositories:

- `LocalAI-io/dinov3-vitl16-pretrain-lvd1689m-GGUF`
- `LocalAI-io/TRELLIS-image-large-GGUF`
- `LocalAI-io/TRELLIS.2-4B-GGUF`

Those files remain subject to their original licenses and are converted
redistributions of `microsoft/TRELLIS.2-4B` (MIT, © Microsoft Corporation).

## This project

MIT — see [LICENSE](LICENSE).
