<#
.SYNOPSIS
  Windows 本地构建：前端静态导出 + 内嵌进单二进制（-tags embedui）。

.DESCRIPTION
  ARTEX 的 Web UI 必须内嵌才有界面；不带 -tags embedui 构建出来的
  二进制只提供 API，访问根路径会返回
  「前端未内嵌到此二进制（开发用 next dev；发布用 -tags embedui 构建）」。

  本脚本按顺序完成：
    1. 检查 node / npm / go
    2. web/ 下 npm ci（node_modules 缺失时才跑）
    3. NEXT_EXPORT=1 npm run build  -> web/out
    4. 拷贝 web/out -> server/webui/dist
    5. go build -tags embedui -o artex.exe ./cmd/artex

  幂等：已存在的 node_modules / dist 会复用，可反复执行。

.PARAMETER Output
  产物路径，默认 ./artex.exe

.PARAMETER SkipNpmCi
  跳过 npm ci（依赖已装好时用，省 1~2 分钟）

.PARAMETER ForceFrontend
  即使 web/out 已存在也重新构建前端

.PARAMETER Clean
  先删除 web/out 和 server/webui/dist 再构建

.EXAMPLE
  ./build-local.ps1
  ./build-local.ps1 -SkipNpmCi -Output D:\AI\artex-lab\bin\artex.exe
#>
[CmdletBinding()]
param(
    [string]$Output = "artex.exe",
    [switch]$SkipNpmCi,
    [switch]$ForceFrontend,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$webDir = Join-Path $root "web"
$distDir = Join-Path $root "server\webui\dist"
$outDir = Join-Path $webDir "out"

function Info($m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

# ---------- 0. 前置检查 ----------
Info "检查工具链"
foreach ($tool in @("node", "npm", "go")) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if (-not $cmd) { Die "找不到 $tool，请先安装并加入 PATH" }
}
$nodeVer = (node --version).Trim()
$npmVer  = (npm --version).Trim()
$goVer   = (go version) -replace '^go version go([\d.]+).*', '$1'
Ok "node $nodeVer / npm $npmVer / go $goVer"

if (-not (Test-Path (Join-Path $webDir "package.json"))) {
    Die "找不到 web/package.json，确认脚本放在仓库根目录"
}

# ---------- 1. 清理 ----------
if ($Clean) {
    Info "清理旧产物"
    Remove-Item $outDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $distDir -Recurse -Force -ErrorAction SilentlyContinue
    Ok "已清理 web/out 与 server/webui/dist"
}

# ---------- 2. npm ci ----------
$nm = Join-Path $webDir "node_modules"
$needInstall = (-not (Test-Path $nm)) -or (-not (Test-Path (Join-Path $nm ".package-lock.json")))
if ($SkipNpmCi) {
    if (-not (Test-Path $nm)) { Die "node_modules 不存在，不能 -SkipNpmCi" }
    Warn "跳过 npm ci"
} elseif ($needInstall) {
    Info "安装前端依赖（npm ci，约 1~2 分钟）"
    Push-Location $webDir
    try {
        npm ci --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { Die "npm ci 失败（退出码 $LASTEXITCODE）" }
    } finally { Pop-Location }
    Ok "依赖已安装"
} else {
    Ok "node_modules 已存在，跳过 npm ci（-Clean 也不会重装）"
}

# ---------- 3. 前端静态导出 ----------
if ((Test-Path (Join-Path $outDir "index.html")) -and -not $ForceFrontend) {
    Ok "web/out 已存在，跳过前端构建（-ForceFrontend 可强制重建）"
} else {
    Info "构建前端静态导出（NEXT_EXPORT=1 next build）"
    Push-Location $webDir
    try {
        $env:NEXT_EXPORT = "1"
        $env:NODE_ENV = "production"
        npm run build
        if ($LASTEXITCODE -ne 0) { Die "前端构建失败（退出码 $LASTEXITCODE）" }
    } finally {
        Remove-Item Env:NEXT_EXPORT -ErrorAction SilentlyContinue
        Pop-Location
    }
    if (-not (Test-Path (Join-Path $outDir "index.html"))) {
        Die "构建结束但 web/out/index.html 不存在，检查 next.config.mjs 的 output 设置"
    }
    $files = Get-ChildItem $outDir -Recurse -File
    $mb = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
    Ok "前端构建完成：$($files.Count) 文件 / $mb MB"
}

# ---------- 4. 拷进内嵌目录 ----------
Info "同步前端到 server/webui/dist"
Remove-Item $distDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $distDir -Force | Out-Null
Copy-Item (Join-Path $outDir "*") $distDir -Recurse -Force
$n = (Get-ChildItem $distDir -Recurse -File | Measure-Object).Count
if ($n -eq 0) { Die "拷贝后 dist 为空" }
Ok "dist 就绪（$n 文件）"

# ---------- 5. 编译内嵌二进制 ----------
Info "编译（-tags embedui）"
Push-Location $root
try {
    go build -tags embedui -o $Output ./cmd/artex
    if ($LASTEXITCODE -ne 0) { Die "go build 失败（退出码 $LASTEXITCODE）" }
} finally { Pop-Location }

$outPath = if ([IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $root $Output }
if (-not (Test-Path $outPath)) { Die "编译结束但产物不存在：$outPath" }
$size = [math]::Round((Get-Item $outPath).Length / 1MB, 1)
Ok "产物：$outPath（$size MB）"

Write-Host ""
Write-Host "  启动示例：" -ForegroundColor Yellow
Write-Host "    `$env:ARTEX_PG_DSN = 'postgres://user:pass@127.0.0.1:5432/artex?sslmode=disable'"
Write-Host "    `$env:ARTEX_SKILL_DIR = '$root\skills'"
Write-Host "    & '$outPath' -addr :8787 -proxy 127.0.0.1:8788"
Write-Host ""
Write-Host "  验证 UI 已内嵌：" -ForegroundColor Yellow
Write-Host "    (Invoke-WebRequest http://127.0.0.1:8787/ -UseBasicParsing).Content -match '<html'"
Write-Host ""
