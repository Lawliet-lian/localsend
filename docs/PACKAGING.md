# 桌面端和 Android 打包

以下命令从仓库根目录执行。项目使用 FVM 管理 Flutter，版本见 `.fvmrc`；先安装 FVM 和对应版本，并安装 Rust 工具链。构建使用本机平台：macOS 在 macOS 上构建，Windows 在 Windows 上构建。首次构建可先运行 `fvm flutter doctor` 检查环境。

## macOS：分别构建 arm64 和 x86_64

需要 Xcode、Xcode 命令行工具，以及 CocoaPods。安装两个 Rust 编译目标：

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

分别构建并保存 `.app`。Flutter 3.41.9 将 `FLUTTER_XCODE_ARCHS` 传给 Xcode 的 `ARCHS` 设置。以下命令在子 shell 中运行，任一步失败就停止，避免打包旧产物；每次构建前清理，并在复制前检查主程序架构：

```bash
(
set -e
cd "/Users/lawliet/Documents/WorkSpace/Lawliet-lian/localsend/app"
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
cd "/Users/lawliet/Documents/WorkSpace/Lawliet-lian/localsend/app"
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

检查 `lipo` 输出分别为 `arm64` 和 `x86_64`；这只检查主程序，交付前还应在对应架构的 Mac 上启动验证。只需要一种架构时，执行对应的一组即可。制作包含“应用程序”快捷方式的 DMG，先安装 `create-dmg`（`brew install create-dmg`），然后执行：

```bash
(
set -e
cd "/Users/lawliet/Documents/WorkSpace/Lawliet-lian/localsend/app"
create-dmg --overwrite --volname LocalSend --window-size 500 300 \
  --icon LocalSend.app 130 110 --app-drop-link 360 110 \
  dist/LocalSend-macos-arm64.dmg dist/macos-arm64

create-dmg --overwrite --volname LocalSend --window-size 500 300 \
  --icon LocalSend.app 130 110 --app-drop-link 360 110 \
  dist/LocalSend-macos-x86_64.dmg dist/macos-x86_64
)
```

上述 DMG 适合本地测试；对外分发还需使用自己的 Developer ID 签名并通过 Apple 公证。仓库的 `support/scripts/compile_mac_dmg.sh` 展示了签名、公证和装订流程，但包含维护者的签名身份和占位账户信息，使用前须修改。

## Windows：分别构建 x86_64 和 ARM64

### 目标和限制

本节生成可解压运行的 Release ZIP，包含 `localsend_app.exe` 及其依赖文件。Flutter 的 Windows 应用必须在 Windows 环境中构建；可以使用 Windows 实机、Windows 虚拟机或 Windows CI。以下命令使用 **PowerShell**，不要在 macOS 终端执行。

项目固定的 Flutter 3.41.9 根据运行 Flutter 工具的主机架构选择 Windows 目标，不提供在本流程中指定目标架构的参数。请分别使用原生 x86_64 和 ARM64 Windows 环境，确保 Flutter/Dart 进程也以对应架构运行；不要假定 ARM64 Windows 上的 x86_64 仿真进程会生成 ARM64 包。两种架构分别构建和验证，不能仅通过修改文件名转换架构。

### 1. 准备环境

1. 获取完整的项目源码，在 PowerShell 中进入仓库根目录，即包含 `app`、`packages` 和 `.fvmrc` 的目录。保留当前已有的修改，不要执行 `git reset` 或删除项目文件。
2. 安装 Visual Studio 和“使用 C++ 的桌面开发”工作负载，以及 Windows SDK。该工作负载必须包含“C++ CMake tools for Windows”（组件 ID `Microsoft.VisualStudio.Component.VC.CMake.Project`）：它属于推荐组件，安装时若没有勾选“包含推荐组件”就会缺失，而 Flutter 只调用 VS 安装目录内的 `cmake.exe`（路径由 `visual_studio.cmakePath` 拼出），单独安装的 CMake 不会被使用，缺失时构建会在 INSTALL 阶段失败。ARM64 构建还需通过 Visual Studio Installer 安装 ARM64 的 MSVC C++ 构建工具。Visual Studio Code 不能替代 Visual Studio 的 C++ 工具链。
3. 启用 Windows“开发人员模式”（`设置 → 系统 → 开发者选项`，或在管理员 PowerShell 中执行 `New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -Value 1 -PropertyType DWord -Force`）。Flutter 要为插件创建符号链接（`app/windows/flutter/ephemeral/.plugin_symlinks`），未启用时 `flutter pub get` 会报 `Building with plugins requires symlink support`。注意 PowerShell 5.1 的 `New-Item -ItemType SymbolicLink` 即使已启用开发人员模式仍会提示需要管理员权限（它不带 `ALLOW_UNPRIVILEGED_CREATE` 标志），不能用它判断状态。
4. 安装 Flutter 3.41.9（版本见 `.fvmrc`）；安装 Rust/rustup，仓库 `rust-toolchain.toml` 指定 Rust 版本。新安装工具后重新打开 PowerShell，确保命令可用。FVM 是可选的版本管理器：winget 没有 FVM 包（官方只提供 Chocolatey 与 GitHub Releases 的独立 zip），CI 与 `.github/workflows/*` 也直接使用 `flutter`，仓库没有指向 `.fvm/` 的 IDE 配置，因此本节命令写 `flutter`；已装 FVM 时把 `flutter` 换成 `fvm flutter` 完全等价。直接安装官方 SDK zip 时，可用 `storage.flutter-io.cn` 镜像替换 `storage.googleapis.com`，并用 Flutter 发布清单中的 SHA256 校验下载结果。
5. 在仓库根目录运行下面的检查；缺少工具时先安装，不要忽略 `flutter doctor` 中 Windows 工具链的错误。首次获取依赖和编译可能需要联网：

```powershell
Get-Location
Get-ComputerInfo | Select-Object OsArchitecture
flutter --version
flutter doctor -v
rustup --version
rustc -vV
cargo --version
```

使用 FVM 时对应检查 `fvm --version`、`fvm install`、`fvm flutter --version`、`fvm flutter doctor -v`。

`OsArchitecture` 只能辅助确认操作系统架构，并不能证明 Flutter 进程的架构；最终以构建产物的 PE 架构检查为准。`rustc -vV` 的 `host` 可用来检查 Rust 工具链架构。

### 2. 构建并打包

在仓库根目录按目标架构只选择一组命令。每条命令成功后再执行下一条；失败时保留完整错误输出并修复，不要继续打包旧产物。`flutter clean` 会清除 Flutter 构建产物，再重新获取依赖。

构建前必须先生成 `app/windows/localsend_msix_helper.msix`：`app/windows/CMakeLists.txt` 的 install 步骤会复制它，但该文件不在版本控制中（`git ls-files app/windows` 查不到，它由 `app/windows/.gitignore` 忽略），缺失时 `flutter build windows` 会在 INSTALL 阶段以 `error MSB3073` 失败，且日志不显示真实原因。在仓库根目录执行（与 `.github/workflows/build_windows_zip_x64.yml` 的 “Build MSIX helper” 步骤、`support/scripts/compile_windows_exe.ps1` 的第 1-3 行一致）：

```powershell
$makepri = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\10.*\x64\makepri.exe' | Select-Object -Last 1
& $makepri.FullName new /pr support\build\msix\content /cf support\build\msix\priconfig.xml /mn support\build\msix\content\AppxManifest.xml /of support\build\msix\content\resources.pri /o
& 'C:\Program Files (x86)\Windows Kits\10\App Certification Kit\makeappx.exe' pack /o /d support\build\msix\content /nv /p app\windows\localsend_msix_helper.msix
```

生成的 `resources.pri` 和 `localsend_msix_helper.msix` 都已被 `.gitignore` 忽略，`flutter clean` 也不会删除后者（它在 `app/windows/` 而非 `build/`），因此只需生成一次。仓库另有 `support/scripts/compile_windows_msix_helper.ps1` 做同一件事，但它调用裸命令 `MakePri.exe`/`MakeAppx.exe`，需要在 Visual Studio Developer PowerShell 中运行；普通 PowerShell 里两者都不在 PATH，会报“无法将...项识别为 cmdlet”，所以上面用绝对路径。

系统区域不是 UTF-8（例如中文的代码页 936）时，还需为 MSVC 指定源文件编码，否则插件源码触发 `warning C4819`，配合仓库的 `/WX` 升级成 `error C2220` 导致编译失败。`_CL_` 是 cl.exe 识别的环境变量，只影响当前会话，不修改仓库代码；英文区域（如 CI）不会触发该警告：

```powershell
$env:_CL_ = '/utf-8'
```

**x86_64 Windows：**

```powershell
rustup target add x86_64-pc-windows-msvc
$env:_CL_ = '/utf-8'
cd app
flutter clean
flutter pub get
flutter build windows --release

# 便携化处理，与 build_windows_zip_x64.yml 同序，三步都不能省
$rel = 'build/windows/x64/runner/Release'
Set-Content -Path "$rel/settings.json" -Value '{}' -NoNewline -Encoding Ascii
Copy-Item ../support/build/windows/x64/msvcp140.dll,../support/build/windows/x64/vcruntime140.dll,../support/build/windows/x64/vcruntime140_1.dll $rel
Remove-Item "$rel/localsend_msix_helper.msix","$rel/install_msix_helper.ps1","$rel/localsend_app.exe.manifest"

New-Item -ItemType Directory -Force -Path dist | Out-Null
Compress-Archive -Path $rel/* -DestinationPath dist/LocalSend-windows-x86_64.zip -Force
```

**ARM64 Windows：**

```powershell
rustup target add aarch64-pc-windows-msvc
$env:_CL_ = '/utf-8'
cd app
flutter clean
flutter pub get
flutter build windows --release

# 便携化处理；仓库只带 x64 的运行时 DLL，arm64 要从 Visual Studio redist 取（与 CI 一致）
$rel = 'build/windows/arm64/runner/Release'
Set-Content -Path "$rel/settings.json" -Value '{}' -NoNewline -Encoding Ascii
$crt = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\arm64\Microsoft.VC143.CRT' | Select-Object -Last 1
Copy-Item "$($crt.FullName)\msvcp140.dll","$($crt.FullName)\vcruntime140.dll","$($crt.FullName)\vcruntime140_1.dll" $rel
Remove-Item "$rel/localsend_msix_helper.msix","$rel/install_msix_helper.ps1","$rel/localsend_app.exe.manifest"

New-Item -ItemType Directory -Force -Path dist | Out-Null
Compress-Archive -Path $rel/* -DestinationPath dist/LocalSend-windows-arm64.zip -Force
```

`x64` 是 Flutter 实际生成的目录名，对应 x86_64。ZIP 位于 `app/dist/`（该目录已被 `app/.gitignore` 的 `/dist/` 规则忽略，不会误提交），分别名为 `LocalSend-windows-x86_64.zip` 和 `LocalSend-windows-arm64.zip`。必须打包 Release 目录中的全部文件和子目录，不能只复制 exe。

上面的便携化三步决定了包是不是真的便携版，缺一步就会退化：

1. **写入空的 `settings.json`**。它是便携模式的开关，而不是配置文件：`app/lib/provider/persistence_provider.dart` 检测到 exe 旁边存在 `settings.json` 时才使用 `SharedPreferencesPortable`，把设置写在 exe 同目录；否则 Windows 上会写入 `%APPDATA%\LocalSend\settings.json`，而且 `app/lib/config/init.dart` 在非便携模式首次启动时会调 `enableContextMenu()` 改注册表。内容必须是合法 JSON（`{}`）且不带 BOM，所以用 `Set-Content -Encoding Ascii` 或 `[System.IO.File]::WriteAllText`，不要用 PowerShell 的 `>` 重定向（PS 5.1 会写成 UTF-16）。另注意 .NET 的当前目录不跟随 `Set-Location`，给 `WriteAllText` 传相对路径会写到错误位置。
2. **复制 VC++ 运行时**（`msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll`）。`flutter build windows` 不会产出它们，不带的话在未安装 Visual C++ Redistributable 的干净机器上会因缺少 DLL 而无法启动。开发机通常已装 Redist，所以这个缺陷在本地不会暴露。
3. **删除 MSIX helper 三件套**（`localsend_msix_helper.msix`、`install_msix_helper.ps1`、`localsend_app.exe.manifest`）。它们是 CMake install 步骤从 `app/windows/` 复制过来的，只对安装程序有意义（CI 注释：“portable users should not register an MSIX package”）。只删 `build/` 里的副本，`app/windows/localsend_msix_helper.msix` 保留，下次构建仍可直接用。

本地产物是**未签名**的：CI 用 Azure Trusted Signing 在打包前签 `exe`/`dll`（先签名再复制 Microsoft 已签名的 CRT DLL，以免破坏它们的原签名），本地没有证书无法复制这一步，因此首次运行可能遇到 SmartScreen 拦截。

本节全部步骤（MSIX helper 生成、`_CL_` 设置、构建、PE 架构校验、便携化三步、打包）已封装为 `support/scripts/compile_windows_portable.ps1`，在仓库根目录执行即可，产物输出到 `app/dist/`：

```powershell
.\support\scripts\compile_windows_portable.ps1              # x86_64，默认先 flutter clean
.\support\scripts\compile_windows_portable.ps1 -NoClean     # 增量构建，跳过 clean
.\support\scripts\compile_windows_portable.ps1 -Arch arm64  # 仅在原生 ARM64 Windows 上有效
```

它与维护者的 `support/scripts/compile_windows_zip.ps1` 相互独立：后者面向发布流程，使用 `fvm`、把 ZIP 输出到 `app/`，且不做便携化三步（它们由 CI workflow 完成）。

仓库现有的 Windows 脚本（`compile_windows_zip.ps1`、`compile_windows_exe.ps1`、`compile_windows_msix_helper.ps1`、`compile_windows_msix_signed.ps1`、`compile_windows_msix_store.ps1`）本质上是维护者发布机上的脚本，在干净环境上通常无法直接运行：它们假定 `fvm` 已在 PATH（winget 没有 FVM 包）、`compile_windows_exe.ps1` 还假定 `D:\inno` 与 Inno Setup 的 `iscc`、MSIX 类脚本假定 Developer PowerShell 或签名证书。CI 也不调用这些脚本（只引用 `compile_windows_exe-inno.iss`），而是把 makepri/makeappx 与 flutter 命令内联写在 workflow 里。因此在新机器上按本节命令构建，而不是直接跑那些脚本；要做安装程序（`.exe`）或 MSIX 发布产物时，再参照对应脚本和 CI workflow 补齐依赖。

执行策略为默认的 `Restricted` 时，直接运行 `.ps1` 会报 `无法加载文件 ...，因为在此系统上禁止运行脚本`（`UnauthorizedAccess`）。两种解法：每次加 Bypass 调用 `powershell -NoProfile -ExecutionPolicy Bypass -File .\support\scripts\compile_windows_portable.ps1`，或一次性执行 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`（CurrentUser 作用域不需要管理员，且只要求下载的脚本带签名）。

也可以直接双击 `support\scripts\compile_windows_portable.cmd`：它内部带 `-ExecutionPolicy Bypass`，固定执行全量构建（含 `flutter clean`），结束时 `pause` 保留输出。注意双击无法传参，需要 `-NoClean` 或 `-Arch arm64` 时仍要在 PowerShell 中调用 `.ps1`；Windows 默认把 `.ps1` 关联到记事本（`HKCR\.ps1` → `notepad.exe %1`），双击 `.ps1` 只会打开文件而不会执行。

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

- 找不到 `flutter`、`fvm`、`rustup` 或 `cargo`：检查安装和 PATH，重新打开 PowerShell 后重试。
- `flutter doctor` 报 Visual Studio 或 Windows SDK 缺失：在 Visual Studio Installer 补装 C++ 工作负载和 SDK；ARM64 同时检查 ARM64 C++ 工具。注意该提示中的 `MSVC v142 ...` 与 `Windows 10 SDK` 两行是固定文案，真实缺失项以 `vswhere -latest -products * -requires <组件ID> -property installationPath` 的结果为准。
- 构建在 INSTALL 阶段报 `error MSB3073`：通常是 `app/windows/localsend_msix_helper.msix` 未生成，按本节开头的前置步骤补上。MSB3073 只是“安装步骤返回非 0”的外壳，需要检查 CMake install 引用的文件是否存在。
- 编译插件时报 `warning C4819` 并升级成 `error C2220`：系统代码页不是 UTF-8，构建前设置 `$env:_CL_ = '/utf-8'`。
- `flutter pub get` 报 `Building with plugins requires symlink support`：未启用 Windows 开发人员模式，见“准备环境”第 3 条。
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
