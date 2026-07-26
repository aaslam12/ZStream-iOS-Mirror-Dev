#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Archive,

    [Parameter(Position = 1)]
    [string]$OutputName
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

if (-not (Test-Path -LiteralPath $Archive)) {
    throw "error: $Archive does not exist"
}

$item = Get-Item -LiteralPath $Archive -Force
$inFull = $item.FullName
$inDir = Split-Path -Parent $inFull

$work = Join-Path ([IO.Path]::GetTempPath()) ("xcarchive-to-ipa." + [Guid]::NewGuid().ToString('N').Substring(0, 8))

try {
    if ($item.PSIsContainer) {
        $archiveRoot = $inFull
    } else {
        $archiveRoot = Join-Path $work 'extracted'
        New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
        Write-Host "==> extracting $($item.Name)..." -ForegroundColor Cyan
        [System.IO.Compression.ZipFile]::ExtractToDirectory($inFull, $archiveRoot)
    }

    $appDir = Get-ChildItem -LiteralPath $archiveRoot -Recurse -Directory -Depth 3 -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*\Products\Applications' } |
        Select-Object -First 1
    if (-not $appDir) {
        throw "error: could not find Products/Applications under $inFull"
    }

    $app = Get-ChildItem -LiteralPath $appDir.FullName -Directory -Filter '*.app' -Force |
        Select-Object -First 1
    if (-not $app) {
        throw "error: no .app found under $($appDir.FullName)"
    }

    $appName = $app.Name
    $bundleName = [IO.Path]::GetFileNameWithoutExtension($appName)

    if ($OutputName) {
        if ($OutputName -notlike '*.ipa') { $OutputName = "$OutputName.ipa" }
    } else {
        $OutputName = "$bundleName.ipa"
    }
    $out = Join-Path $inDir $OutputName

    $links = Get-ChildItem -LiteralPath $app.FullName -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }
    if ($links) {
        Write-Warning "bundle contains symlinks; Windows zipping will flatten them:"
        $links | ForEach-Object { Write-Warning "  $($_.FullName.Replace($app.FullName + '\', ''))" }
    }

    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

    Write-Host "==> packing Payload/$appName -> $OutputName..." -ForegroundColor Cyan

    $appRootLen = $app.FullName.Length + 1
    $files = Get-ChildItem -LiteralPath $app.FullName -Recurse -File -Force
    $zip = [System.IO.Compression.ZipFile]::Open($out, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($appRootLen).Replace('\', '/')
            $entryName = "Payload/$appName/$rel"

            $entry = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = [DateTimeOffset]::new($f.LastWriteTimeUtc, [TimeSpan]::Zero)

            $isExec = ($f.Name -eq $bundleName) -or ($f.Extension -eq '' -and $f.Name -ne 'PkgInfo')
            $mode = if ($isExec) { 0x1ED } else { 0x1A4 }
            $entry.ExternalAttributes = $mode -shl 16

            $dst = $entry.Open()
            try {
                $src = [IO.File]::OpenRead($f.FullName)
                try { $src.CopyTo($dst) } finally { $src.Dispose() }
            } finally { $dst.Dispose() }
        }
    } finally {
        $zip.Dispose()
    }

    $sizeMB = [math]::Round((Get-Item -LiteralPath $out).Length / 1MB, 2)
    Write-Host "wrote $out ($sizeMB MB, $($files.Count) files)" -ForegroundColor Green
    Write-Host ""
    Write-Host "NOTE for whoever signs this: the app's entitlements are NOT embedded"
    Write-Host "since the archive was built with CODE_SIGNING_ALLOWED=NO. They must"
    Write-Host "pass --entitlements pointing at that file when re-signing."
}
finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
