# Yu の Anomaly 插件源 —— 生成发布 ZIP / 发布到 Release
#
#   ./release.ps1 -Plugin damage-source-recorder                 构建、校验并产出 dist\<id>-<version>.zip
#   ./release.ps1                                                处理 plugins.json 里的全部插件
#   ./release.ps1 -Plugin damage-source-recorder -Publish        再创建 Release 并上传 ZIP
#
# 发布后记得同步 pluginmaster.json 的 Version 与 DownloadLinkInstall（见 README「发布新版本」）。
[CmdletBinding()]
param(
    [string[]]$Plugin,
    [switch]$Publish,
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
$allPlugins = Get-Content -LiteralPath (Join-Path $root 'plugins.json') -Raw | ConvertFrom-Json
$selected = if ($Plugin) {
    $Plugin | ForEach-Object {
        $wanted = $_
        $match = $allPlugins | Where-Object { $_.short -eq $wanted }
        if (-not $match) { throw "plugins.json 里没有插件：$wanted（可用：$(($allPlugins.short) -join ', ')）" }
        $match
    }
} else {
    $allPlugins
}

$pluginCli = Join-Path $ToolsDir 'anomaly-plugin.exe'
$testHost = Join-Path $ToolsDir 'anomaly-test-host.exe'
$repository = 'YU-1021/Anomaly-Plugins'

foreach ($entry in $selected) {
    $pluginDir = Join-Path $root $entry.dir
    $buildDir = Join-Path $root "build/$($entry.short)"
    $manifest = Get-Content -LiteralPath (Join-Path $pluginDir 'manifest.json') -Raw | ConvertFrom-Json
    $pluginId = $manifest.id
    $version = $manifest.version
    $packageDir = Join-Path $buildDir "package/$($entry.package)"

    Write-Host ''
    Write-Host "===== $($entry.name) $version（$($entry.short)）====="

    cmake -S $pluginDir -B $buildDir -G $Generator -A x64 "-DAnomalySDK_DIR=$SdkDir"
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed: $($entry.short)" }

    cmake --build $buildDir --config $Configuration
    if ($LASTEXITCODE -ne 0) { throw "Build failed: $($entry.short)" }

    $packedRoot = Join-Path $buildDir 'packed'
    if (Test-Path -LiteralPath $packedRoot) { Remove-Item -LiteralPath $packedRoot -Recurse -Force }
    $packedDir = $packageDir

    if (Test-Path -LiteralPath $pluginCli) {
        & $pluginCli validate $packageDir
        if ($LASTEXITCODE -ne 0) { throw "Package validation failed: $($entry.short)" }

        & $pluginCli pack $packageDir --output $packedRoot
        if ($LASTEXITCODE -ne 0) { throw "anomaly-plugin pack failed: $($entry.short)" }
        $packedDir = Join-Path $packedRoot $pluginId

        if (Test-Path -LiteralPath $testHost) {
            $testRoot = Join-Path $buildDir 'testroot'
            if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
            $testPackage = Join-Path $testRoot $entry.package
            New-Item -ItemType Directory -Path $testPackage -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $packageDir 'plugin.dll'), (Join-Path $packageDir 'manifest.json') -Destination $testPackage -Force
            & $testHost --plugin $testRoot --reload 10 --ticks 60
            if ($LASTEXITCODE -ne 0) { throw "Offline plugin test failed: $($entry.short)" }
        }
    } else {
        Write-Warning "未找到 $pluginCli，跳过 validate/pack，直接用包目录打 ZIP"
    }

    # 只发布运行期需要的文件：MSVC 的 .pdb/.lib/.exp/.ilk 留在 build 里。
    $stageDir = Join-Path $OutputDir "stage/$($entry.short)"
    if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
    $excluded = @('.pdb', '.lib', '.exp', '.ilk', '.obj')
    Get-ChildItem -LiteralPath $packedDir -Force | Where-Object { $excluded -notcontains $_.Extension } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stageDir -Recurse -Force }

    # 重新生成 package.sha256：pack 生成的那份包含被排除的 .pdb/.lib/.exp。
    $shaFile = Join-Path $stageDir 'package.sha256'
    if (Test-Path -LiteralPath $shaFile) { Remove-Item -LiteralPath $shaFile -Force }
    $lines = Get-ChildItem -LiteralPath $stageDir -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($stageDir.Length + 1).Replace('\', '/')
        "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $relative"
    }
    [System.IO.File]::WriteAllLines($shaFile, $lines, (New-Object System.Text.UTF8Encoding($false)))

    $zipPath = Join-Path $OutputDir "$pluginId-$version.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
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
    Write-Host "发布 ZIP: $zipPath"
    Write-Host "大小: $size 字节"
    Write-Host "SHA256: $hash"
    Write-Host "条目: $pluginId $version"

    if ($Publish) {
        $tag = "$($entry.short)-v$version"
        $zipName = Split-Path $zipPath -Leaf
        gh release view $tag --repo $repository *> $null
        if ($LASTEXITCODE -eq 0) {
            $existing = gh release view $tag --repo $repository --json assets --jq '.assets[].name'
            if ($existing -contains $zipName) {
                Write-Host "Release $tag 已有 $zipName，跳过上传"
            } else {
                gh release upload $tag $zipPath --repo $repository
            }
        } else {
            gh release create $tag $zipPath --repo $repository --title "$($entry.name) v$version" `
                --notes "$($manifest.description)`n`nSHA256: $hash"
        }
        Write-Host "Release: https://github.com/$repository/releases/tag/$tag"
    }
}
