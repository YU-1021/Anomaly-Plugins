# Yu の Anomaly 插件源 —— 构建 / 校验 / 离线测试 / 部署
#
#   ./build.ps1                                     构建并校验全部插件
#   ./build.ps1 -Plugin damage-source-recorder      只处理其中一个（短名见 plugins.json）
#   ./build.ps1 -Plugin damage-source-recorder -Deploy          复制到 Runtime 插件目录
#   ./build.ps1 -Plugin damage-source-recorder -Deploy -Enable   并在 plugin-enablement.json 里启用
#
# 需要 Visual Studio 2022（C++20）、CMake ≥ 3.22、Anomaly SDK（-SdkDir 或 $env:AnomalySDK_DIR）。
[CmdletBinding()]
param(
    [string[]]$Plugin,
    [switch]$Deploy,
    [switch]$Enable,
    [string]$SdkDir = $env:AnomalySDK_DIR,
    [string]$ToolsDir = $(if ($env:AnomalyToolsDir) { $env:AnomalyToolsDir } else { 'D:\project\Anomaly\Anomaly-tools' }),
    [string]$RuntimePlugins = $(if ($env:AnomalyRuntimePlugins) { $env:AnomalyRuntimePlugins } else { 'D:\project\Anomaly\Anomaly-2.4.3-runtime\Anomaly\plugins' }),
    [string]$Configuration = 'RelWithDebInfo',
    [string]$Generator = 'Visual Studio 17 2022'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SdkDir)) {
    throw '未指定 Anomaly SDK：用 -SdkDir <sdk>/lib/cmake/AnomalySDK，或设置环境变量 AnomalySDK_DIR'
}
if (-not (Test-Path -LiteralPath (Join-Path $SdkDir 'AnomalySDKConfig.cmake'))) {
    throw "找不到 Anomaly SDK：$SdkDir"
}

$root = $PSScriptRoot
$allPlugins = Get-Content -LiteralPath (Join-Path $root 'plugins.json') -Raw | ConvertFrom-Json
$selected = if ($Plugin) {
    $Plugin | ForEach-Object {
        $wanted = $_
        $match = $allPlugins | Where-Object { $_.short -eq $wanted }
        if (-not $match) {
            throw "plugins.json 里没有插件：$wanted（可用：$(($allPlugins.short) -join ', ')）"
        }
        $match
    }
} else {
    $allPlugins
}

$pluginCli = Join-Path $ToolsDir 'anomaly-plugin.exe'
$testHost = Join-Path $ToolsDir 'anomaly-test-host.exe'

foreach ($entry in $selected) {
    $pluginDir = Join-Path $root $entry.dir
    $buildDir = Join-Path $root "build/$($entry.short)"
    $packageDir = Join-Path $buildDir "package/$($entry.package)"

    Write-Host ''
    Write-Host "===== $($entry.name)（$($entry.short)）====="

    cmake -S $pluginDir -B $buildDir -G $Generator -A x64 "-DAnomalySDK_DIR=$SdkDir"
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed: $($entry.short)" }

    cmake --build $buildDir --config $Configuration
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $($entry.short)" }

    if (Test-Path -LiteralPath $pluginCli) {
        & $pluginCli validate $packageDir
        if ($LASTEXITCODE -ne 0) { throw "Package validation failed: $($entry.short)" }
    } else {
        Write-Warning "未找到 $pluginCli，跳过包校验"
    }

    if (Test-Path -LiteralPath $testHost) {
        # 单包路径在部分机器上会走临时目录 staging，所以用插件根目录跑离线夹具。
        $testRoot = Join-Path $buildDir 'testroot'
        if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
        $testPackage = Join-Path $testRoot $entry.package
        New-Item -ItemType Directory -Path $testPackage -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $packageDir 'plugin.dll'), (Join-Path $packageDir 'manifest.json') -Destination $testPackage -Force
        & $testHost --plugin $testRoot --reload 10 --ticks 60
        if ($LASTEXITCODE -ne 0) { throw "Offline plugin test failed: $($entry.short)" }
    } else {
        Write-Warning "未找到 $testHost，跳过离线加载测试"
    }

    if ($Deploy) {
        if ($selected.Count -ne 1) { throw '-Deploy 需要 -Plugin 指定单个插件' }
        $target = Join-Path $RuntimePlugins $entry.package
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $packageDir 'plugin.dll'), (Join-Path $packageDir 'manifest.json') -Destination $target -Force
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
            $manifest = Get-Content -LiteralPath (Join-Path $packageDir 'manifest.json') -Raw | ConvertFrom-Json
            $document.plugins | Add-Member -NotePropertyName $manifest.id -NotePropertyValue $true -Force
            $json = $document | ConvertTo-Json -Depth 6
            [System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "已启用: $($manifest.id) ($configPath)"
        }
    }

    Write-Host "插件包: $packageDir"
}
