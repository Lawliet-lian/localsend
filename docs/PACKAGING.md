# 桌面端和 Android 打包

以下命令从仓库根目录执行。项目使用 FVM 管理 Flutter，版本见 `.fvmrc`；先安装 FVM 和对应版本，并安装 Rust 工具链。构建使用本机平台：macOS 在 macOS 上构建，Windows 在 Windows 上构建。首次构建可先运行 `fvm flutter doctor` 检查环境。

## macOS：分别构建 arm64 和 x86_64

需要 Xcode、Xcode 命令行工具，以及 CocoaPods。安装两个 Rust 编译目标：

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
cd app
fvm flutter pub get
```

分别构建并保存 `.app`。Flutter 3.41.9 将 `FLUTTER_XCODE_ARCHS` 传给 Xcode 的 `ARCHS` 设置。以下命令在子 shell 中运行，任一步失败就停止，避免打包旧产物；每次构建前清理，并在复制前检查主程序架构：

```bash
(
set -e
# Apple Silicon (arm64)
fvm flutter clean
fvm flutter pub get
FLUTTER_XCODE_ARCHS=arm64 fvm flutter build macos --release
test "$(lipo -archs build/macos/Build/Products/Release/LocalSend.app/Contents/MacOS/LocalSend)" = arm64
rm -rf dist/macos-arm64/LocalSend.app
mkdir -p dist/macos-arm64
ditto build/macos/Build/Products/Release/LocalSend.app dist/macos-arm64/LocalSend.app
lipo -archs dist/macos-arm64/LocalSend.app/Contents/MacOS/LocalSend
)

(
set -e
# x86_64
fvm flutter clean
fvm flutter pub get
FLUTTER_XCODE_ARCHS=x86_64 fvm flutter build macos --release
test "$(lipo -archs build/macos/Build/Products/Release/LocalSend.app/Contents/MacOS/LocalSend)" = x86_64
rm -rf dist/macos-x86_64/LocalSend.app
mkdir -p dist/macos-x86_64
ditto build/macos/Build/Products/Release/LocalSend.app dist/macos-x86_64/LocalSend.app
lipo -archs dist/macos-x86_64/LocalSend.app/Contents/MacOS/LocalSend
)
```

检查 `lipo` 输出分别为 `arm64` 和 `x86_64`；这只检查主程序，交付前还应在对应架构的 Mac 上启动验证。只需要一种架构时，执行对应的一组即可。制作包含“应用程序”快捷方式的 DMG，先安装 `create-dmg`（`brew install create-dmg`），然后在 `app` 目录执行所需的一组：

```bash
create-dmg --overwrite --volname LocalSend --window-size 500 300 \
  --icon LocalSend.app 130 110 --app-drop-link 360 110 \
  dist/LocalSend-macos-arm64.dmg dist/macos-arm64

create-dmg --overwrite --volname LocalSend --window-size 500 300 \
  --icon LocalSend.app 130 110 --app-drop-link 360 110 \
  dist/LocalSend-macos-x86_64.dmg dist/macos-x86_64
```

上述 DMG 适合本地测试；对外分发还需使用自己的 Developer ID 签名并通过 Apple 公证。仓库的 `support/scripts/compile_mac_dmg.sh` 展示了签名、公证和装订流程，但包含维护者的签名身份和占位账户信息，使用前须修改。

## Windows：分别构建 x86_64 和 ARM64

### 目标和限制

本节生成可解压运行的 Release ZIP，包含 `localsend_app.exe` 及其依赖文件。Flutter 的 Windows 应用必须在 Windows 环境中构建；可以使用 Windows 实机、Windows 虚拟机或 Windows CI。以下命令使用 **PowerShell**，不要在 macOS 终端执行。

项目固定的 Flutter 3.41.9 根据运行 Flutter 工具的主机架构选择 Windows 目标，不提供在本流程中指定目标架构的参数。请分别使用原生 x86_64 和 ARM64 Windows 环境，确保 Flutter/Dart 进程也以对应架构运行；不要假定 ARM64 Windows 上的 x86_64 仿真进程会生成 ARM64 包。两种架构分别构建和验证，不能仅通过修改文件名转换架构。

### 1. 准备环境

1. 获取完整的项目源码，在 PowerShell 中进入仓库根目录，即包含 `app`、`packages` 和 `.fvmrc` 的目录。保留当前已有的修改，不要执行 `git reset` 或删除项目文件。
2. 安装 Visual Studio 和“使用 C++ 的桌面开发”工作负载，以及 Windows SDK。ARM64 构建还需通过 Visual Studio Installer 安装 ARM64 的 MSVC C++ 构建工具。Visual Studio Code 不能替代 Visual Studio 的 C++ 工具链。
3. 安装 FVM，并按仓库 `.fvmrc` 安装 Flutter 3.41.9；安装 Rust/rustup，仓库 `rust-toolchain.toml` 指定 Rust 版本。新安装工具后重新打开 PowerShell，确保命令可用。
4. 在仓库根目录运行下面的检查；缺少工具时先安装，不要忽略 `flutter doctor` 中 Windows 工具链的错误。首次获取依赖和编译可能需要联网：

```powershell
Get-Location
Get-ComputerInfo | Select-Object OsArchitecture
fvm --version
fvm install
fvm flutter --version
fvm flutter doctor -v
rustup --version
rustc -vV
cargo --version
```

`OsArchitecture` 只能辅助确认操作系统架构，并不能证明 Flutter 进程的架构；最终以构建产物的 PE 架构检查为准。`rustc -vV` 的 `host` 可用来检查 Rust 工具链架构。

### 2. 构建并打包

在仓库根目录按目标架构只选择一组命令。每条命令成功后再执行下一条；失败时保留完整错误输出并修复，不要继续打包旧产物。`flutter clean` 会清除 Flutter 构建产物，再重新获取依赖。

**x86_64 Windows：**

```powershell
rustup target add x86_64-pc-windows-msvc
cd app
fvm flutter clean
fvm flutter pub get
fvm flutter build windows --release
Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath LocalSend-windows-x86_64.zip -Force
```

**ARM64 Windows：**

```powershell
rustup target add aarch64-pc-windows-msvc
cd app
fvm flutter clean
fvm flutter pub get
fvm flutter build windows --release
Compress-Archive -Path build/windows/arm64/runner/Release/* -DestinationPath LocalSend-windows-arm64.zip -Force
```

`x64` 是 Flutter 实际生成的目录名，对应 x86_64。ZIP 位于 `app/`，分别名为 `LocalSend-windows-x86_64.zip` 和 `LocalSend-windows-arm64.zip`。必须打包 Release 目录中的全部文件和子目录，不能只复制 exe。

### 3. 检查架构和运行

在 `app` 目录，将下面第一行的路径替换为本次构建的 exe 路径，再执行。PE machine 值 `0x8664` 表示 x86_64，`0xAA64` 表示 ARM64；与目标不符时不要交付。

```powershell
$exePath = 'build/windows/x64/runner/Release/localsend_app.exe' # ARM64 改为 build/windows/arm64/runner/Release/localsend_app.exe
$stream = [System.IO.File]::OpenRead((Resolve-Path $exePath))
try {
    $reader = [System.IO.BinaryReader]::new($stream)
    $stream.Seek(0x3c, [System.IO.SeekOrigin]::Begin) | Out-Null
    $peOffset = $reader.ReadInt32()
    $stream.Seek($peOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
    if ($reader.ReadUInt32() -ne 0x00004550) { throw '无效的 PE 文件' }
    'PE machine: 0x{0:X4}' -f $reader.ReadUInt16()
} finally { $stream.Dispose() }
```

将 ZIP 解压到新的空目录，在对应架构的 Windows 环境中启动其中的 `localsend_app.exe`，确认应用打开且依赖文件齐全。交付时注明包名、架构、验证结果；若无法在目标环境运行，应明确说明未完成运行验证。

### 4. 常见问题

- 找不到 `fvm`、`rustup` 或 `cargo`：检查安装和 PATH，重新打开 PowerShell 后重试。
- `flutter doctor` 报 Visual Studio 或 Windows SDK 缺失：在 Visual Studio Installer 补装 C++ 工作负载和 SDK；ARM64 同时检查 ARM64 C++ 工具。
- 构建失败或找不到预期目录：检查完整日志、Flutter 版本及实际产物架构；不要打包之前遗留的文件。
- 安装程序不是本节的 ZIP：仓库 `support/scripts/compile_windows_exe.ps1` 和 Inno Setup 配置面向 x86_64，使用固定的 `D:\inno` 路径，不能直接用于 ARM64，使用前需检查和调整。

## Android：arm64-v8a

需要 Android SDK、Flutter 要求的 Java 环境和 Rust Android 交叉编译环境。生成仅包含 arm64-v8a 的 APK：

```bash
cd app
fvm flutter pub get
fvm flutter build apk --release --target-platform android-arm64 --split-per-abi
```

APK 位于 `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。正式发布前需配置自己的 Android 发布签名；请检查构建日志和签名配置，勿将密钥提交到仓库。仓库中的 `support/scripts/compile_android_apk.sh` 面向 F-Droid 可复现构建，不是上述常规本地打包流程。
