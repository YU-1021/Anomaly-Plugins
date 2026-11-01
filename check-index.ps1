# 检查第三方插件源索引（pluginmaster.json）
#
#   ./check-index.ps1                                  检查线上索引：JSON 结构、必填字段、ID / SemVer 格式、下载地址可访问
#   ./check-index.ps1 -Validate                         再下载每个 ZIP，核对 manifest 并跑 anomaly-plugin validate
#   ./check-index.ps1 -IndexPath .\pluginmaster.json    改索引前先在本地过一遍（不联网检查下载地址时加 -SkipDownloadCheck）
#
# Runtime 的解析规则（src/repository/plugin_list.cpp）：
#   * 根不是数组或 JSON 非法 -> 整个源刷新失败，该源下的插件全部消失；
#   * 单个条目缺 Name / InternalName / Version / DownloadLinkInstall、ID 不合法、Version 不是 SemVer -> 只跳过该条目；
#   * 同一个 InternalName 出现多次（含跨源）-> 只保留版本最高的一条。
[CmdletBinding()]
param(
    [string]$IndexUrl = 'https://raw.githubusercontent.com/YU-1021/Anomaly-Plugin-DamageSourceRecorder/main/pluginmaster.json',
    [string]$IndexPath,
    [switch]$Validate,
    [switch]$SkipDownloadCheck,
    [string]$ToolsDir = $(if ($env:AnomalyToolsDir) { $env:AnomalyToolsDir } else { 'D:\project\Anomaly\Anomaly-tools' })
)

$ErrorActionPreference = 'Stop'

# 与 Runtime 的 QualifiedId 一致：小写点分 ID，段内可用 - 与数字，段不超过 63 字符，总长 3..255。
$idPattern = '^[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+(-[a-z0-9]+)*)+$'
$semVerPattern = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

$problems = [System.Collections.Generic.List[string]]::new()
$notes = [System.Collections.Generic.List[string]]::new()

if ($IndexPath) {
    $source = (Resolve-Path -LiteralPath $IndexPath).Path
    $text = Get-Content -LiteralPath $source -Raw
} else {
    $source = $IndexUrl
    $text = (Invoke-WebRequest -Uri $IndexUrl -UseBasicParsing).Content
}
Write-Host "索引: $source"

try {
    $document = $text | ConvertFrom-Json -NoEnumerate
} catch {
    Write-Host "FAIL 不是合法 JSON：$($_.Exception.Message)"
    exit 1
}

if ($document -isnot [System.Array]) {
    Write-Host 'FAIL 根节点必须是 JSON 数组（对象或其他类型会让整个插件源刷新失败）'
    exit 1
}
Write-Host "条目数: $($document.Count)"
Write-Host ''

$seen = @{}
foreach ($entry in $document) {
    $label = if ($entry.InternalName) { $entry.InternalName } else { '<缺少 InternalName>' }
    $entryProblems = [System.Collections.Generic.List[string]]::new()

    foreach ($field in 'Name', 'InternalName', 'Version', 'DownloadLinkInstall') {
        if ([string]::IsNullOrWhiteSpace([string]$entry.$field)) {
            $entryProblems.Add("缺少 $field")
        }
    }
    if ($entry.InternalName) {
        if ($entry.InternalName.Length -lt 3 -or $entry.InternalName.Length -gt 255 -or
            $entry.InternalName -notmatch $idPattern) {
            $entryProblems.Add("InternalName 不是合法插件 ID：$($entry.InternalName)")
        }
        if ($seen.ContainsKey($entry.InternalName)) {
            $notes.Add("$($entry.InternalName) 在索引里出现多次，Runtime 只保留版本最高的一条")
        }
        $seen[$entry.InternalName] = $true
    }
    if ($entry.Version -and $entry.Version -notmatch $semVerPattern) {
        $entryProblems.Add("Version 不是合法 SemVer：$($entry.Version)")
    }
    if ($null -ne $entry.PSObject.Properties['ApiMajor']) {
        $apiMajor = $entry.ApiMajor
        if ($apiMajor -isnot [int] -and $apiMajor -isnot [long] -and $apiMajor -isnot [int64]) {
            $entryProblems.Add("ApiMajor 必须是正整数：$apiMajor")
        } elseif ([int64]$apiMajor -le 0) {
            $entryProblems.Add("ApiMajor 必须是正整数：$apiMajor")
        }
    } else {
        $notes.Add("$($entry.InternalName) 没有 ApiMajor，Runtime 无法在下载前判断 API 兼容性")
    }

    if (-not $SkipDownloadCheck -and $entry.DownloadLinkInstall) {
        try {
            $head = Invoke-WebRequest -Uri $entry.DownloadLinkInstall -Method Head -UseBasicParsing -TimeoutSec 60
            if ($head.StatusCode -ne 200) {
                $entryProblems.Add("下载地址返回 $($head.StatusCode)：$($entry.DownloadLinkInstall)")
            }
        } catch {
            $entryProblems.Add("下载地址不可访问：$($entry.DownloadLinkInstall)（$($_.Exception.Message)）")
        }
    }

    if ($Validate -and $entry.DownloadLinkInstall) {
        $pluginCli = Join-Path $ToolsDir 'anomaly-plugin.exe'
        if (-not (Test-Path -LiteralPath $pluginCli)) {
            $notes.Add('未找到 anomaly-plugin.exe，跳过解包校验（用 -ToolsDir 指定）')
        } else {
            $work = Join-Path ([System.IO.Path]::GetTempPath()) ("anomaly-index-" + [guid]::NewGuid().ToString('N'))
            try {
                $zip = Join-Path $work 'package.zip'
                New-Item -ItemType Directory -Path $work -Force | Out-Null
                Invoke-WebRequest -Uri $entry.DownloadLinkInstall -OutFile $zip -UseBasicParsing
                Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $work 'pkg') -Force
                $package = Join-Path $work 'pkg'
                & $pluginCli validate $package
                if ($LASTEXITCODE -ne 0) {
                    $entryProblems.Add('anomaly-plugin validate 未通过')
                } else {
                    $manifest = Get-Content -LiteralPath (Join-Path $package 'manifest.json') -Raw | ConvertFrom-Json
                    if ($manifest.id -ne $entry.InternalName) {
                        $entryProblems.Add("manifest.id=$($manifest.id) 与 InternalName=$($entry.InternalName) 不一致")
                    }
                    if ($manifest.version -ne $entry.Version) {
                        $entryProblems.Add("manifest.version=$($manifest.version) 与 Version=$($entry.Version) 不一致")
                    }
                }
            } finally {
                if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
            }
        }
    }

    if ($entryProblems.Count -eq 0) {
        Write-Host "OK   $label $($entry.Version)"
    } else {
        Write-Host "FAIL $label $($entry.Version)"
        foreach ($problem in $entryProblems) {
            Write-Host "     - $problem"
            $problems.Add("${label}: $problem")
        }
    }
}

if ($notes.Count -gt 0) {
    Write-Host ''
    foreach ($note in ($notes | Sort-Object -Unique)) { Write-Host "注意 $note" }
}

Write-Host ''
if ($problems.Count -gt 0) {
    Write-Host "结果: $($problems.Count) 个问题"
    exit 1
}
Write-Host "结果: 通过（$($document.Count) 个条目）"
