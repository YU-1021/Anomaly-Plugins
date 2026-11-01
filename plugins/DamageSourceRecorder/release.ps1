# 伤害来源记录 —— 生成可发布的插件 ZIP
#
#   ./release.ps1                    用 -SdkDir / $env:AnomalySDK_DIR 指向的 SDK 构建、校验，产出 dist\<id>-<version>.zip
#   ./release.ps1 -SdkDir ... -ToolsDir ...   指定 SDK 与 Anomaly-tools（提供 anomaly-plugin / anomaly-test-host）
#
# 产物结构按第三方插件源要求：ZIP 第一层直接是 manifest.json、plugin.dll、package.sha256、locales\。
[CmdletBinding()]
param(
    [string]$SdkDir = $env:AnomalySDK_DIR,
    [string]$ToolsDir = $(if ($env:AnomalyToolsDir) { $env:AnomalyToolsDir } else { 'D:\project\Anomaly\Anomaly-tools' }),
    [string]$Configuration = 'RelWithDebInfo',
    [string]$Generator = 'Visual Studio 17 2022',
    [string]$OutputDir = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SdkDir)) {
    throw '未指定 Anomaly SDK：用 -SdkDir <sdk>/lib/cmake/AnomalySDK，或设置环境变量 AnomalySDK_DIR'
}
if (-not (Test-Path -LiteralPath (Join-Path $SdkDir 'AnomalySDKConfig.cmake'))) {
    throw "找不到 Anomaly SDK：$SdkDir"
}

$root = $PSScriptRoot
$buildDir = Join-Path $root 'build'
$manifest = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
$pluginId = $manifest.id
$version = $manifest.version
$packageName = 'DamageSourceRecorder'
$packageDir = Join-Path $buildDir "package\$packageName"

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$packedRoot = Join-Path $OutputDir 'packed'
if (Test-Path -LiteralPath $packedRoot) { Remove-Item -LiteralPath $packedRoot -Recurse -Force }

cmake -S $root -B $buildDir -G $Generator -A x64 "-DAnomalySDK_DIR=$SdkDir"
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed' }

cmake --build $buildDir --config $Configuration
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }

$pluginCli = Join-Path $ToolsDir 'anomaly-plugin.exe'
$packedDir = Join-Path $packedRoot $packageName
if (Test-Path -LiteralPath $pluginCli) {
    & $pluginCli validate $packageDir
    if ($LASTEXITCODE -ne 0) { throw 'Package validation failed' }

    # pack 按 Manifest ID 重新组织目录并写入 package.sha256。
    & $pluginCli pack $packageDir --output $packedRoot
    if ($LASTEXITCODE -ne 0) { throw 'anomaly-plugin pack failed' }
    $packedDir = Join-Path $packedRoot $pluginId

    # 单包路径在部分机器上会走临时目录 staging，所以用插件根目录跑离线夹具。
    $testHost = Join-Path $ToolsDir 'anomaly-test-host.exe'
    if (Test-Path -LiteralPath $testHost) {
        $testRoot = Join-Path $buildDir 'testroot'
        if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
        $testPackage = Join-Path $testRoot $packageName
        New-Item -ItemType Directory -Path $testPackage -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $packageDir 'plugin.dll'), (Join-Path $packageDir 'manifest.json') -Destination $testPackage -Force
        & $testHost --plugin $testRoot --reload 10 --ticks 60
        if ($LASTEXITCODE -ne 0) { throw 'Offline plugin test failed' }
    } else {
        Write-Warning "未找到 $testHost，跳过离线加载测试"
    }
} else {
    Write-Warning "未找到 $pluginCli，跳过 validate/pack，直接用包目录打 ZIP"
    $packedDir = $packageDir
}

$zipPath = Join-Path $OutputDir "$pluginId-$version.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

# 只发布运行期需要的文件：MSVC 的 .pdb/.lib/.exp/.ilk 留在 build 里，不进发布 ZIP。
$stageDir = Join-Path $OutputDir 'stage'
if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
$excluded = @('.pdb', '.lib', '.exp', '.ilk', '.obj')
Get-ChildItem -LiteralPath $packedDir -Force | Where-Object { $excluded -notcontains $_.Extension } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stageDir -Recurse -Force }

# 重新生成 package.sha256：pack 生成的那份包含被排除的 .pdb/.lib/.exp，与最终 ZIP 对不上。
$shaFile = Join-Path $stageDir 'package.sha256'
if (Test-Path -LiteralPath $shaFile) { Remove-Item -LiteralPath $shaFile -Force }
$lines = Get-ChildItem -LiteralPath $stageDir -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($stageDir.Length + 1).Replace('\', '/')
    "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $relative"
}
[System.IO.File]::WriteAllLines($shaFile, $lines, (New-Object System.Text.UTF8Encoding($false)))

# 压缩包内容而不是最外层目录：安装器要求 manifest.json 位于 ZIP 根。
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
if ($LASTEXITCODE -ne 0) { throw 'Compress-Archive failed' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $names = $archive.Entries | ForEach-Object { $_.FullName }
    if ($names -notcontains 'manifest.json') { throw 'ZIP 根目录缺少 manifest.json' }
    if ($names -notcontains $manifest.entry) { throw "ZIP 根目录缺少入口 DLL：$($manifest.entry)" }
} finally {
    $archive.Dispose()
}

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $zipPath).Length

Write-Host ''
Write-Host "插件包: $packedDir"
Write-Host "发布 ZIP: $zipPath"
Write-Host "大小: $size 字节"
Write-Host "SHA256: $hash"
Write-Host "条目: $pluginId $version"
