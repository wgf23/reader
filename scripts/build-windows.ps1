# build-windows.ps1 —— 在 Windows 上构建 reader 的 Windows 安装包（zip 免安装版）
#
# 前置要求（在 Windows 上）：
#   1. Flutter SDK（stable，含 Windows 桌面支持）已安装且在 PATH
#   2. Rust（rustup stable）已安装且在 PATH（cargo）
#   3. Visual Studio Build Tools：勾选 "使用 C++ 的桌面开发"（MSVC + Windows SDK）
# 用法（在 reader/ 仓库根目录的上级或任意位置）：
#   powershell -ExecutionPolicy Bypass -File reader\scripts\build-windows.ps1
# 产物：reader/dist/reader-windows-vX.Y.Z.zip（含 reader_core.dll 与全部运行时文件）

$ErrorActionPreference = "Stop"

# 仓库根：本脚本位于 <root>/scripts/build-windows.ps1
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Write-Host "[1/4] 构建 Rust 核心（cdylib → reader_core.dll）..."
Push-Location "$Root\core"
cargo build --release
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "cargo build 失败" }
$Dll = "target\release\reader_core.dll"
if (-not (Test-Path $Dll)) { Pop-Location; throw "未找到 $Dll" }
Pop-Location

Write-Host "[2/4] Flutter 依赖与 Windows 桌面构建..."
Push-Location "$Root\app"
flutter pub get
flutter build windows --release
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "flutter build windows 失败" }
Pop-Location

Write-Host "[3/4] 拷贝 Rust 动态库到构建产物..."
$Out = "$Root\app\build\windows\x64\runner\Release"
Copy-Item "$Root\core\$Dll" $Out -Force

Write-Host "[4/4] 打包 zip..."
$Dist = "$Root\dist"
New-Item -ItemType Directory -Force $Dist | Out-Null
$Version = "v0.3.0"   # 如需固定版本，改为读取 pubspec/version
$Zip = "$Dist\reader-windows-$Version.zip"
if (Test-Path $Zip) { Remove-Item $Zip -Force }
Compress-Archive -Path "$Out\*" -DestinationPath $Zip -Force

Write-Host ""
Write-Host "✅ 构建完成：$Zip"
Write-Host "   解压后运行 reader_app.exe 即可（首次运行若提示缺少 WebView2 Runtime，"
Write-Host "   到 https://developer.microsoft.com/microsoft-edge/webview2/ 安装）"
