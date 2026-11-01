# 伤害来源记录 —— 构建 / 校验 / 离线测试 / 部署
#
#   ./build.ps1                 构建 + 校验 + 离线加载测试
#   ./build.ps1 -Deploy         再复制到 Runtime 插件目录
#   ./build.ps1 -Deploy -Enable 并在 plugin-enablement.json 里启用
#
# 需要 Visual Studio 2022（C++20）、CMake ≥ 3.22、Anomaly SDK。
[CmdletBinding()]
param(
    [switch]$Deploy,
    [switch]$Enable,
    [string]$RuntimePlugins = $(if ($env:AnomalyRuntimePlugins) { $env:AnomalyRuntimePlugins } else { 'D:\project\Anomaly\Anomaly-2.4.3-runtime\Anomaly\plugins' }),
    [string]$ToolsDir = $(if ($env:AnomalyToolsDir) { $env:AnomalyToolsDir } else { 'D:\project\Anomaly\Anomaly-tools' }),
    [string]$SdkDir = $(if ($env:AnomalySDK_DIR) { $env:AnomalySDK_DIR } else { 'D:\project\Anomaly\Anomaly-sdk\lib\cmake\AnomalySDK' }),
    [string]$Configuration = 'RelWithDebInfo'
)

$ErrorActionPreference = 'Stop'

# AnomalySDK_DIR 指向 <sdk>/lib/cmake/AnomalySDK（SDK 发布包里就是 lib/cmake/AnomalySDK）。
if (-not (Test-Path -LiteralPath (Join-Path $SdkDir 'AnomalySDKConfig.cmake'))) {
    throw "找不到 Anomaly SDK：$SdkDir（用 -SdkDir 指定，或设置环境变量 AnomalySDK_DIR）"
}

$root = $PSScriptRoot
$buildDir = Join-Path $root 'build'
$packageDir = Join-Path $buildDir 'package\DamageSourceRecorder'
$pluginId = 'com.yu.damage-source-recorder'
$packageName = 'DamageSourceRecorder'

cmake -S $root -B $buildDir -G 'Visual Studio 17 2022' -A x64 "-DAnomalySDK_DIR=$SdkDir"
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed' }

cmake --build $buildDir --config $Configuration
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }

$validator = Join-Path $ToolsDir 'anomaly-plugin.exe'
if (Test-Path -LiteralPath $validator) {
    & $validator validate $packageDir
    if ($LASTEXITCODE -ne 0) { throw 'Package validation failed' }
} else {
    Write-Warning "未找到 $validator，跳过包校验"
}

# 单包路径会先复制到临时目录（本机可能受权限限制），所以用插件根目录跑离线夹具。
$testHost = Join-Path $ToolsDir 'anomaly-test-host.exe'
if (Test-Path -LiteralPath $testHost) {
    $testRoot = Join-Path $buildDir 'testroot'
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    $testPackage = Join-Path $testRoot $packageName
    New-Item -ItemType Directory -Path $testPackage -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $packageDir 'plugin.dll'), (Join-Path $packageDir 'manifest.json') -Destination $testPackage -Force
    & $testHost --plugin $testRoot --reload 10 --ticks 60
    if ($LASTEXITCODE -ne 0) { throw 'Offline plugin test failed' }
} else {
    Write-Warning "未找到 $testHost，跳过离线加载测试"
}

if (-not $Deploy) {
    Write-Host "插件包: $packageDir"
    return
}

$target = Join-Path $RuntimePlugins $packageName
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $packageDir 'plugin.dll') -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $packageDir 'manifest.json') -Destination $target -Force
# locales / assets 由 SDK 打包规则一并复制，这里按需同步到运行目录。
foreach ($directory in @('locales', 'assets')) {
    $source = Join-Path $packageDir $directory
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    }
}
Write-Host "已部署: $target"

if ($Enable) {
    $configPath = Join-Path (Split-Path -Parent $RuntimePlugins) 'config\plugin-enablement.json'
    if (Test-Path -LiteralPath $configPath) {
        $document = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    } else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
        $document = [pscustomobject]@{ schemaVersion = 1; defaultEnabled = $false; plugins = [pscustomobject]@{} }
    }
    if ($null -eq $document.plugins) {
        $document | Add-Member -NotePropertyName plugins -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $document.plugins | Add-Member -NotePropertyName $pluginId -NotePropertyValue $true -Force
    $json = $document | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "已启用: $pluginId ($configPath)"
}
