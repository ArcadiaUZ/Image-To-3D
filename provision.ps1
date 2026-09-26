<#
.SYNOPSIS
  Image-To-3D provisioner — installs/checks every dependency, model and binary.

.DESCRIPTION
  Idempotent: every step is skipped when the target already exists.
    .\provision.ps1            full install (skips what is present)
    .\provision.ps1 -Check     only report what is missing, download nothing
    .\provision.ps1 -Force     re-download/rebuild even if present

  Steps
    1. tools      git, cmake, MSVC build tools, Python, Go
    2. source     clone trellis2cpp (+ggml submodule) and apply patches
    3. vulkan     Vulkan headers, glslc, and a vulkan-1.lib built from the
                  driver DLL — so no admin rights and no Vulkan SDK needed
    4. build      compile trellis2 + the Go server against the Vulkan backend
    5. models     the 10 GGUF files (~15 GB) from Hugging Face
    6. python     virtualenv with the Python client dependencies
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Force
)

# Native tools (git, curl, tar, pip, winget) write progress to stderr, which
# Windows PowerShell surfaces as error records. With 'Stop' that would abort
# the whole run, so keep 'Continue' and validate each result explicitly below.
$ErrorActionPreference = 'Continue'
$Root      = $PSScriptRoot
$Work      = Join-Path $Root 'workspace'
$Src       = Join-Path $Work 'trellis2cpp'
$Models    = Join-Path $Root 'models'
$Out       = Join-Path $Root 'out'
$Vk        = Join-Path $Root '.vulkan'
$Venv      = Join-Path $Root '.venv'
$Log       = Join-Path $Root 'provision.log'

$RepoUrl   = 'https://github.com/localai-org/trellis2cpp'
$RepoRev   = '2f3e6e26edbbaaf8ce93d092f16f46968a366a6a'
$VkhUrl    = 'https://github.com/KhronosGroup/Vulkan-Headers.git'
$ShadercUrl= 'https://repo.msys2.org/mingw/mingw64/mingw-w64-x86_64-shaderc-2026.3-1-any.pkg.tar.zst'

# GGUF weights: repo -> files. Total ~15 GB.
$ModelMap = [ordered]@{
    'LocalAI-io/dinov3-vitl16-pretrain-lvd1689m-GGUF' = @('dino_f16.gguf')
    'LocalAI-io/TRELLIS-image-large-GGUF'              = @('ss_dec_f16.gguf')
    'LocalAI-io/TRELLIS.2-4B-GGUF'                    = @(
        'ss_flow_f16.gguf', 'slat_flow_f16.gguf', 'slat_flow_1024_f16.gguf',
        'shape_dec_f16.gguf', 'shape_enc_f16.gguf', 'tex_dec_f16.gguf',
        'tex_slat_flow_512_f16.gguf', 'tex_slat_flow_1024_f16.gguf'
    )
}

$script:Missing = 0
$script:Fetched  = 0
$script:Failed   = @()

function Write-Step($m) { Write-Host "`n=== $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Write-Info($m) { Write-Host "  [..]   $m" -ForegroundColor Gray }
function Write-Warn($m) { Write-Host "  [!!]   $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red }

function Say($m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $m
    Add-Content -Path $Log -Value $line
}

function Test-Size($path, [long]$min) {
    if (-not (Test-Path $path)) { return $false }
    return ((Get-Item $path).Length -ge $min)
}

function Download-File($url, $dest, [long]$minBytes = 0) {
    $name = Split-Path $dest -Leaf
    if ((-not $Force) -and (Test-Size $dest $minBytes)) {
        Write-Ok "$name (allaqachon bor)"
        return $true
    }
    if ($Check) {
        $script:Missing++
        Write-Warn "$name — yuklanmagan"
        return $false
    }
    Write-Info "$name yuklanmoqda..."
    $dir = Split-Path $dest -Parent
    New-Item -ItemType Directory -Force $dir | Out-Null
    & curl.exe -L -C - --retry 5 --retry-delay 3 -o $dest $url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Size $dest $minBytes)) {
        Write-Err "$name — yuklab bo'lmadi"
        $script:Failed += $name
        return $false
    }
    $script:Fetched++
    Write-Ok ("{0} ({1:N1} MB)" -f $name, ((Get-Item $dest).Length / 1MB))
    return $true
}

function Get-PythonExe {
    foreach ($c in @(
        (Join-Path $Venv 'Scripts\python.exe'),
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
    )) { if (Test-Path $c) { return $c } }
    return $null
}

function Get-CmakeDir {
    foreach ($c in @('C:\Program Files\CMake\bin', 'C:\Program Files (x86)\CMake\bin')) {
        if (Test-Path (Join-Path $c 'cmake.exe')) { return $c }
    }
    return $null
}

function Import-VcEnv($vcvars) {
    # Pull INCLUDE/LIB/PATH out of vcvars64.bat into this process so cmake and
    # the compiler can be invoked directly — no fragile `cmd /c "a && b"` string.
    $out = & cmd /c "`"$vcvars`" >nul 2>&1 && set"
    foreach ($line in $out) {
        if ($line -match '^([^=]+)=(.*)$') {
            Set-Item -Path "env:$($matches[1])" -Value $matches[2] -ErrorAction SilentlyContinue
        }
    }
    if (-not $env:VCToolsInstallDir) {
        Write-Err 'MSVC muhiti import qilinmadi'
        return $false
    }
    return $true
}

function Invoke-Winget($id, $name, $extra) {
    if ($Check) {
        Write-Warn "$name — winget orqali o'rnatilishi kerak"
        $script:Missing++
        return
    }
    Write-Info "$name o'rnatilmoqda (winget $id)..."
    & winget install -e --id $id --source winget --accept-package-agreements --accept-source-agreements --silent 2>&1 |
        Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "$name o'rnatilmadi (kod $LASTEXITCODE). Qo'lda o'rnating: https://aka.ms/winget/$id"
    }
}

# ---------------------------------------------------------------- 1. tools
function Step-Tools {
    Write-Step '1/6  Vositalar (tools)'
    $env:Path = "C:\Program Files\Git\cmd;C:\Program Files\Go\bin;$env:Path"

    if (Get-Command git -ErrorAction SilentlyContinue) { Write-Ok 'git' }
    else { Invoke-Winget 'Git.Git' 'git'; $script:Missing++ }

    $cmakeDir = Get-CmakeDir
    if ($cmakeDir) { $env:Path = "$cmakeDir;$env:Path"; Write-Ok 'cmake' }
    else { Invoke-Winget 'Kitware.CMake' 'cmake'; $script:Missing++ }

    $vc = $null
    foreach ($c in @(
        'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat',
        'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat',
        'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
    )) { if (Test-Path $c) { $vc = $c; break } }
    if ($vc) { Write-Ok 'MSVC (Visual Studio Build Tools)' }
    else {
        Write-Warn 'MSVC topilmadi'
        if ($Check) { $script:Missing++ } else {
            Write-Info 'Visual Studio Build Tools o''rnatilmoqda (bir necha daqiqa)...'
            & winget install -e --id Microsoft.VisualStudio.2022.BuildTools --source winget `
                --accept-package-agreements --accept-source-agreements --silent `
                --override "--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" 2>&1 | Out-Null
            Write-Warn 'VS o''rnatildi. Terminalni QAYTA OCHING va setup.bat ni yana ishga tushiring.'
            exit 2
        }
    }
    $script:VcVars = $vc

    if (Get-Command go -ErrorAction SilentlyContinue) { Write-Ok 'go' }
    else { Invoke-Winget 'GoLang.Go' 'Go'; $script:Missing++ }

    if (Get-PythonExe) { Write-Ok 'python' }
    else { Invoke-Winget 'Python.Python.3.12' 'Python'; $script:Missing++ }
}

# ---------------------------------------------------------------- 2. source
function Step-Source {
    Write-Step '2/6  Manba kodi (trellis2cpp + patchlar)'
    if (Test-Path (Join-Path $Src '.git')) {
        Write-Ok "trellis2cpp (bor, rev $RepoRev)"
    } elseif ($Check) {
        Write-Warn 'trellis2cpp klonlanmagan'
        $script:Missing++
    } else {
        New-Item -ItemType Directory -Force $Work | Out-Null
        Write-Info 'klonlanmoqda (shallow, ~500 MB)...'
        & git clone --recursive $RepoUrl $Src 2>&1 | Out-Null
        if (-not (Test-Path (Join-Path $Src '.git'))) {
            Write-Err 'klonlash muvaffaqiyatsiz'
            $script:Failed += 'trellis2cpp'
            return
        }
        Write-Ok 'klonlandi'
    }
    if (-not (Test-Path (Join-Path $Src '.git'))) { return }

    if ($Check) { return }

    # pin the exact revision we validated against
    $cur = (& git -C $Src rev-parse HEAD).Trim()
    if ($cur -ne $RepoRev) {
        Write-Info "rev $RepoRev ga o'tilmoqda..."
        & git -C $Src fetch --depth 1 origin $RepoRev 2>&1 | Out-Null
        & git -C $Src checkout -q $RepoRev 2>&1 | Out-Null
    }
    if (-not (Test-Path (Join-Path $Src 'ggml\ggml.c'))) {
        Write-Info 'ggml submodule...'
        & git -C $Src submodule update --init --recursive 2>&1 | Out-Null
    }
    Write-Ok "rev $RepoRev"

    # apply our Windows/MSVC patches (idempotent: skipped if already applied)
    $applied = (Select-String -Path (Join-Path $Src 'trellis2.cpp') -Pattern 'M_PI 3.14159' -Quiet)
    if (-not $applied) {
        Write-Info 'patch: M_PI (MSVC)...'
        & git -C $Src apply (Join-Path $Root 'patches\0001-cpp-msvc-M_PI.patch') 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Err 'M_PI patch muvaffaqiyatsiz'
            $script:Failed += 'patch M_PI'
        } else { Write-Ok 'patch: M_PI' }
    } else { Write-Ok 'patch: M_PI (allaqachon)' }

    # Detect via engine.go, not the presence of dlib_windows.go: the dlib files
    # are copied separately and can exist even when the patch itself failed.
    $engineGo = Join-Path $Src 'server\engine.go'
    $goFix = (Test-Path $engineGo) -and
             (Select-String -Path $engineGo -Pattern 'openLib\(libPath\)' -Quiet)
    if (-not $goFix) {
        Write-Info 'patch: server Windows purego...'
        & git -C $Src apply (Join-Path $Root 'patches\0002-server-windows-purego.patch') 2>&1 | Out-Null
        $rc = $LASTEXITCODE
        Copy-Item (Join-Path $Root 'server\dlib_windows.go') (Join-Path $Src 'server\') -Force
        Copy-Item (Join-Path $Root 'server\dlib_unix.go')  (Join-Path $Src 'server\') -Force
        if ($rc -eq 0) { Write-Ok 'patch: server Windows purego' }
        else {
            Write-Err 'purego patch muvaffaqiyatsiz'
            $script:Failed += 'patch purego'
        }
    } else { Write-Ok 'patch: server (allaqachon)' }
}

# ---------------------------------------------------------------- 3. vulkan
function Step-Vulkan {
    Write-Step '3/6  Vulkan (admin''siz: headers + glslc + lib)'
    $hdrInc = Join-Path $Vk 'headers\include'
    $glslc  = Join-Path $Vk 'glslc\mingw64\bin\glslc.exe'
    $lib    = Join-Path $Vk 'lib\vulkan-1.lib'

    # 3a. headers
    if (Test-Path (Join-Path $hdrInc 'vulkan\vulkan_core.h')) { Write-Ok 'Vulkan headers' }
    elseif ($Check) { Write-Warn 'Vulkan headers'; $script:Missing++ }
    else {
        Write-Info 'Vulkan headers klonlanmoqda...'
        & git clone --depth 1 $VkhUrl (Join-Path $Vk 'headers') 2>&1 | Out-Null
        if (Test-Path (Join-Path $hdrInc 'vulkan\vulkan_core.h')) { Write-Ok 'Vulkan headers' }
        else { Write-Err 'Vulkan headers yuklanmadi'; $script:Failed += 'vulkan headers' }
    }

    # 3b. glslc (shader compiler required by ggml)
    if (Test-Path $glslc) { Write-Ok 'glslc' }
    elseif ($Check) { Write-Warn 'glslc'; $script:Missing++ }
    else {
        New-Item -ItemType Directory -Force $Vk | Out-Null
        $pkg = Join-Path $Vk 'shaderc.tar.zst'
        $glslcDir = Join-Path $Vk 'glslc'
        New-Item -ItemType Directory -Force $glslcDir | Out-Null
        Write-Info 'glslc (shaderc) yuklanmoqda...'
        & curl.exe -L --retry 5 -o $pkg $ShadercUrl
        & tar -xf $pkg -C $glslcDir
        Remove-Item $pkg -ErrorAction SilentlyContinue
        if (Test-Path $glslc) { Write-Ok 'glslc' }
        else { Write-Err 'glslc topilmadi'; $script:Failed += 'glslc' }
    }

    # 3c. vulkan-1.lib — generated from the driver DLL, so no SDK is needed
    if (Test-Size $lib 10000) { Write-Ok 'vulkan-1.lib' }
    elseif ($Check) { Write-Warn 'vulkan-1.lib'; $script:Missing++ }
    else {
        $dll = "$env:SystemRoot\System32\vulkan-1.dll"
        if (-not (Test-Path $dll)) {
            Write-Err 'vulkan-1.dll yo''q — GPU driverini yangilang'
            $script:Failed += 'vulkan-1.dll'
            return
        }
        $msvcBin = Get-ChildItem (Join-Path $script:VcVars '..\..\..\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
                   Sort-Object Name -Descending | Select-Object -First 1
        if (-not $msvcBin) { Write-Err 'MSVC bin topilmadi'; $script:Failed += 'vulkan-1.lib'; return }
        $bin = Join-Path $msvcBin.FullName 'bin\Hostx64\x64'
        Write-Info 'vulkan-1.lib generatsiya qilinmoqda...'
        $def = Join-Path $Vk 'vulkan-1.def'
        New-Item -ItemType Directory -Force (Split-Path $def -Parent) | Out-Null
        $names = & (Join-Path $bin 'dumpbin.exe') /exports $dll |
                 ForEach-Object { if ($_ -match '^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+(vk\w+)\s*$') { $matches[1] } } |
                 Sort-Object -Unique
        if (-not $names) { Write-Err 'eksportlar topilmadi'; $script:Failed += 'vulkan-1.lib'; return }
        ("EXPORTS`r`n" + ($names -join "`r`n")) | Set-Content -Encoding ASCII $def
        New-Item -ItemType Directory -Force (Split-Path $lib -Parent) | Out-Null
        & (Join-Path $bin 'lib.exe') /nologo /def:$def /machine:x64 /out:$lib | Out-Null
        if (Test-Size $lib 10000) { Write-Ok ("vulkan-1.lib ({0} eksport)" -f $names.Count) }
        else { Write-Err 'vulkan-1.lib yaratilmadi'; $script:Failed += 'vulkan-1.lib' }
    }
}

# ---------------------------------------------------------------- 4. build
function Step-Build {
    Write-Step '4/6  Kompilyatsiya (Vulkan backend)'
    $exe = Join-Path $Src 'build\examples\ss_mesh.exe'
    $srv = Join-Path $Src 'server\trellis2-server.exe'
    $dll = Join-Path $Src 'build\trellis2.dll'
    if ((Test-Path $exe) -and (Test-Path $srv) -and (Test-Path $dll) -and -not $Force) {
        Write-Ok 'build mavjud'
        Copy-Item $dll $Root -Force
        $binDir = Join-Path $Src 'build\bin'
        if (Test-Path $binDir) { Copy-Item (Join-Path $binDir '*.dll') $Root -Force }
        return
    }
    if ($Check) { Write-Warn 'build'; $script:Missing++; return }

    if (-not (Import-VcEnv $script:VcVars)) { $script:Failed += 'MSVC env'; return }

    $bld = Join-Path $Src 'build'
    $log = Join-Path $Root 'build.log'
    Write-Info 'cmake configure...'
    & cmake -S $Src -B $bld -G Ninja -DCMAKE_BUILD_TYPE=Release `
        -DGGML_VULKAN=ON `
        "-DVulkan_INCLUDE_DIR=$(Join-Path $Vk 'headers\include')" `
        "-DVulkan_LIBRARY=$(Join-Path $Vk 'lib\vulkan-1.lib')" `
        "-DVulkan_GLSLC_EXECUTABLE=$(Join-Path $Vk 'glslc\mingw64\bin\glslc.exe')" 2>&1 |
        Tee-Object -FilePath $log | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'cmake configure muvaffaqiyatsiz'
        $script:Failed += 'cmake configure'
        return
    }

    Write-Info 'build (shaderlar uchun 10-20 daqiqa) ...'
    & cmake --build $bld -j 8 2>&1 | Tee-Object -FilePath $log -Append | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warn "cmake --build chiqish kodi: $LASTEXITCODE" }

    if (-not (Test-Path $exe)) { Write-Err 'C++ build muvaffaqiyatsiz — build.log ni ko''ring'; $script:Failed += 'cpp build'; return }
    Write-Ok 'C++ build (Vulkan)'

    # Get-Command returns a CommandInfo, not a path — Test-Path would always be
    # false, so resolve to an actual file path.
    $goExe = (Get-Command go -ErrorAction SilentlyContinue).Source
    if (-not $goExe) {
        foreach ($c in @('C:\Program Files\Go\bin\go.exe', "$env:LOCALAPPDATA\Programs\Go\bin\go.exe")) {
            if (Test-Path $c) { $goExe = $c; break }
        }
    }
    if ($goExe -and (Test-Path $goExe)) {
        Write-Info "go build ($goExe)..."
        Push-Location (Join-Path $Src 'server')
        & $goExe get github.com/ebitengine/purego@v0.11.1 2>&1 | Out-Null
        & $goExe build -o trellis2-server.exe . 2>&1 | Tee-Object -FilePath (Join-Path $Root 'go-build.log') | Out-Null
        $goRc = $LASTEXITCODE
        Pop-Location
        if ($goRc -ne 0) { Write-Warn "go build chiqish kodi: $goRc (go-build.log ni ko'ring)" }
    } else { Write-Err 'go.exe topilmadi' }
    if (Test-Path $srv) { Write-Ok 'Go server build' }
    else { Write-Err 'Go server build muvaffaqiyatsiz'; $script:Failed += 'go build' }

    # collect the runtime DLLs next to the scripts so start_server.bat finds them
    $dll = Join-Path $Src 'build\trellis2.dll'
    if (Test-Path $dll) {
        Copy-Item $dll $Root -Force
        $binDir = Join-Path $Src 'build\bin'
        if (Test-Path $binDir) { Copy-Item (Join-Path $binDir '*.dll') $Root -Force }
        Write-Ok 'runtime DLL''lar nusxalandi'
    } else { Write-Warn 'trellis2.dll topilmadi' }
}

# ---------------------------------------------------------------- 5. models
function Step-Models {
    Write-Step '5/6  Modellar (GGUF, ~15 GB)'
    $py = Get-PythonExe
    $total = $ModelMap.Values | ForEach-Object { $_.Count } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $present = 0
    foreach ($repo in $ModelMap.Keys) {
        foreach ($f in $ModelMap[$repo]) {
            $dest = Join-Path $Models $f
            if ((-not $Force) -and (Test-Size $dest 1000000)) { $present++ }
        }
    }
    if ($present -eq $total) { Write-Ok "barcha $total ta model bor"; return }
    if ($Check) { Write-Warn "$($total - $present) ta model yetishmayapti"; $script:Missing += ($total - $present); return }

    if (-not $py) { Write-Err 'python yo''q — modellarni yuklab bo''lmadi'; $script:Failed += 'models'; return }
    & $py -m pip install -q huggingface_hub 2>&1 | Out-Null
    $env:HF_HUB_DISABLE_XET = '1'
    foreach ($repo in $ModelMap.Keys) {
        foreach ($f in $ModelMap[$repo]) {
            $dest = Join-Path $Models $f
            if ((-not $Force) -and (Test-Size $dest 1000000)) {
                Write-Ok "$f (bor)"
                continue
            }
            Write-Info "$f yuklanmoqda (sekin internet bo'lsa uzoq turadi)..."
            $code = @"
from huggingface_hub import hf_hub_download
print(hf_hub_download('$repo', '$f', local_dir=r'$Models'))
"@
            & $py -c $code 2>&1 | Out-Null
            if (Test-Size $dest 1000000) { $script:Fetched++; Write-Ok "$f" }
            else { Write-Err "$f yuklanmadi"; $script:Failed += $f }
        }
    }
}

# ---------------------------------------------------------------- 6. python
function Step-Python {
    Write-Step '6/6  Python muhiti'
    $req = Join-Path $Root 'requirements.txt'
    $py = Get-PythonExe
    if (-not $py) { Write-Warn 'python yo''q'; return }

    if (-not (Test-Path (Join-Path $Venv 'Scripts\python.exe'))) {
        if ($Check) { Write-Warn '.venv yaratilmagan'; $script:Missing++; return }
        Write-Info '.venv yaratilmoqda...'
        & $py -m venv $Venv
    }
    $vp = Join-Path $Venv 'Scripts\python.exe'

    # NOTE: a native command that prints nothing evaluates to $null, and
    # `if (<null>)` is false — so test the exit code, never the output.
    & $vp -c 'import trimesh, scipy, numpy, PIL' 2>&1 | Out-Null
    $haveDeps = ($LASTEXITCODE -eq 0)
    if ($haveDeps -and -not $Force) { Write-Ok 'python paketlari'; return }
    if ($Check) { Write-Warn 'python paketlari yetishmayapti'; $script:Missing++; return }

    Write-Info 'pip paketlari o''rnatilmoqda...'
    & $vp -m pip install -q --upgrade pip 2>&1 | Out-Null
    & $vp -m pip install -q -r $req 2>&1 | Out-Null
    & $vp -c 'import trimesh, scipy, numpy, PIL' 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok 'python paketlari' }
    else { Write-Err 'python paketlari muvaffaqiyatsiz'; $script:Failed += 'python deps' }
}

# ---------------------------------------------------------------- main
New-Item -ItemType Directory -Force $Root | Out-Null
Set-Content -Path $Log -Value ("{0}  --- provision {1} ---" -f (Get-Date), $(if ($Check) { 'CHECK' } else { 'INSTALL' }))

if ($Check) {
    Write-Host "`nImage-To-3D — TEKSHIRUV (hech nima yuklanmaydi)" -ForegroundColor Yellow
} else {
    Write-Host "`nImage-To-3D — O'RNATISH" -ForegroundColor Cyan
    Write-Host "  Ish papkasi: $Root"
}

Step-Tools
Step-Source
Step-Vulkan
Step-Build
Step-Models
Step-Python

Write-Step 'Natija'
if ($Check) {
    if ($script:Missing -eq 0) {
        Write-Host "  Hamma narsa o'rnatilgan. Ishga tushiring: .\start_server.bat" -ForegroundColor Green
    } else {
        Write-Host ("  Yetishmayotgan: {0} ta element. Ularni o'rnatish uchun .\setup.bat" -f $script:Missing) -ForegroundColor Yellow
    }
} else {
    Write-Host ("  Yuklangan: {0}   xato: {1}" -f $script:Fetched, $script:Failed.Count)
    if ($script:Failed.Count -gt 0) {
        Write-Host "  Muvaffaqiyatsiz: $($script:Failed -join ', ')" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Tayyor. Keyingi qadam: .\start_server.bat" -ForegroundColor Green
}
