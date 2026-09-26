# Image-To-3D

**Rasm → 3D model.** Windows'da bitta fayl bilan ishlaydigan, GPU'da
ishlaydigan pipeline: oddiy PNG/JPG rasmini mato va o'lchamlari saqlangan
teksturali 3D modelga aylantiradi.

TRELLIS.2-4B asosida qurilgan, lekin **PyTorch'siz** — C++/ggml (GGUF)
runtime'da. Shu sababli CUDA toolkit ham, Vulkan SDK ham kerak emas.

```
DINOv3  ->  sparse structure  ->  Shape-SLAT  ->  shape decoder  ->  PBR texture  ->  GLB
```

---

## Tez ishga tushirish

```bat
setup.bat                              :: hammasini o'rnatadi (modellar ~15 GB)
start_server.bat                       :: serverni ishga tushiradi
generate_auto.bat rasm.png 6 20 20      :: 6 variant -> eng yaxshisi
```

Web interfeys: **http://127.0.0.1:8742/**

Natija `out\` papkasida `.glb` — Blender, Windows 3D Viewer yoki
[meshlab.net](https://meshlab.net) da ochiladi.

> Birinchi marta `setup.bat` Visual Studio Build Tools ni o'rnatishi mumkin.
> Undan keyin terminalni **qayta ochib** `setup.bat` ni yana ishga tushiring.

---

## Buyruqlar

| Fayl | Vazifasi |
|---|---|
| `setup.bat` | To'liq o'rnatish: vositalar, kod, build, modellar, Python |
| `update.bat` | Yetishmaganlarni tekshiradi va yuklaydi (`-Check` = faqat hisobot, `-Force` = qayta) |
| `start_server.bat` | Serverni mustaqil (detached) ishga tushiradi |
| `generate_auto.bat` | **Ko'p seed → eng rasmga o'xshashini tanlaydi** (eng yaxshi sifat) |
| `generate.bat` | Bitta rasm → GLB (tez) |
| `run_stage1.bat` | Juda tez: rasm → sodda OBJ, matovasiz, serversiz |

### `generate_auto.bat` — tavsiya etiladi

```
generate_auto.bat <rasm.png> [n_seeds] [steps] [texture_steps] [bosh_seed]
                  0            4         16         16              0
```

Bitta rasm bilan ishlashdagi asosiy muammo — model yon tomonni noto'g'ri
taxmin qiladi va butun geometriya buziladi. Shuning uchun bir necha seed
bilan variant yaratilib, har birining **silueti** (ko'rinishi) rasm
silueti bilan solishtiriladi (IoU metrikasi) va eng o'xshashi tanlanadi.

```
    0.722   seed 1      <-- eng yaxshi, avtomatik tanlandi
    0.698   seed 0
    0.638   seed 2
```

Siluet taqqoslash o'lcham va joylashuvga bog'liq emas — faqat **shakl**ni
o'lchaydi, shuning uchun xolis natija beradi.

---

## Nima uchun aynan shu yo'l

**Ko'p-qirrali (multi-view) ishlatilmadi.** TRELLIS.2 ning rasmiy
PyTorch versiyasi 6 ta rasmni (old/orqa/chap/o'ng/yuqori/past) qabul qiladi,
lekin bu C++/GGUF portida `t2_generate` **bitta rasm** oladi. Shu sababli
ko'p seed + IoU tanlash — bu pipeline uchun mavjud eng kuchli aniqlik
oshirgich.

**Vulkan CUDA o'rniga.** CUKit o'rnatish uchun ~4 GB va aniq MSVC versiyasi
kerak. Vulkan esa faqat **drayver** talab qiladi: `setup.bat` sarlavhalarni
git bilan, `glslc` ni MSYS2 dan, `vulkan-1.lib` ni esa Windows`dagi
`vulkan-1.dll` dan `lib.exe` yordamida **generatsiya** qiladi — admin
huquqlari umuman kerak bo'lmaydi.

**Model o'zi yuklanmaydi.** 15 GB lik vaznlar `setup.bat` da ko'rsatilgan
Hugging Face repositoriylaridan olinadi va hech qachon git'ga qo'shilmaydi.

---

## Talablar

| Nima | Talab |
|---|---|
| GPU | Vulkan 1.2+ ni qo'llab-quvvatlaydigan GPU (NVIDIA, AMD, Intel) |
| VRAM | ~6 GB (1024 rejim uchun ~13 GB, bu portda faqat 512 qo'llab-quvvatlanadi) |
| RAM | 16 GB |
| OS | Windows 10/11 x64 |
| Internet | `setup.bat` uchun ~16 GB |

`setup.bat` o'zi o'rnatadi: Git, CMake, Visual Studio Build Tools, Python,
Go, Vulkan qismlari va model vaznlari.

---

## Tuzatilgan muammolar

`patches/` papkasida saqlangan o'zgarishlar:

1. **`M_PI`** — MSVC uni belgilamaydi, `trellis2.cpp` kompilyatsiya
   qilinmaydi. Yechim: `#ifndef M_PI` himoyasi qo'shildi.
2. **Go server Windows'da ishlamaydi** — `purego.Dlopen` faqat POSIX
   platformalar uchun. `server/dlib_windows.go` da `syscall.LoadDLL` bilan
   almashtirildi, `purego` v0.8.2 → v0.11.1 ko'tarildi.

---

## Cheklovlar

- **1024 cascade ishlamaydi** — 12.7 GB graf xotirasi kerak. Server
  `-no-1024` bilan ishga tushadi: 512 fine + to'liq PBR tekstura.
- Bir vaqtda bitta rasm.
- Server ishlayotganda boshqa GPU dasturlarini (o'yin, boshqa AI modellari)
  ishga tushirmang — VRAM yetmaydi va `ggml_gallocr_alloc_graph failed`
  xatosi chiqadi.

## Masalalar

| Xato | Yechim |
|---|---|
| `curl: (7) Failed to connect` | Server o'chgan — `start_server.bat` |
| `ggml_gallocr_alloc_graph failed` | VRAM yetishmaydi, boshqa dasturlarni yoping |
| `[XATO] Server ishlamayapti` | `start_server.bat` hali ishga tushmagan |
| `image probe failed` | Format qo'llab-quvvatlanmaydi (PNG/JPG ishlating) |
| `setup.bat` to'xtaydi, keyin "terminalni qayta oching" | Tabiiy — VS o'rnatilgan, qayta ishga tushiring |

Batafsil jurnallar: `provision.log`, `server.log`, `build.log`.

---

## Litsenziya

MIT — [LICENSE](LICENSE) faylini ko'ring.

Ushbu repo **avtomatlashtirish qatlami** bo'lib, u ustida qurilgan
loyihalar o'z litsenziyalariga ega (TRELLIS.2, ggml, purego — hammasi MIT).
Model vaznlari shu repositoriyada saqlanmaydi va o'z litsenziyalariga bo'ysunadi.
