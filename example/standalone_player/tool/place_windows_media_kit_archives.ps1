<#
.SYNOPSIS
Place manually downloaded media_kit Windows archives into the Flutter CMake
build directory before running `flutter run -d windows`.

.DESCRIPTION
media_kit_libs_windows_video downloads libmpv and ANGLE from GitHub release
assets. In restricted networks that download may produce a 0-byte or corrupt
archive. Download the two archives in a browser/with a proxy, then run this
script to verify their MD5 hashes and place them where CMake expects them.

.PARAMETER MpvArchive
Path to mpv-dev-x86_64-20230924-git-652a1dd.7z

.PARAMETER AngleArchive
Path to ANGLE.7z

.EXAMPLE
.\tool\place_windows_media_kit_archives.ps1 `
  -MpvArchive C:\Downloads\mpv-dev-x86_64-20230924-git-652a1dd.7z `
  -AngleArchive C:\Downloads\ANGLE.7z
#>
param(
  [Parameter(Mandatory = $true)]
  [string] $MpvArchive,

  [Parameter(Mandatory = $true)]
  [string] $AngleArchive,

  [string] $BuildArchDir = (Join-Path $PSScriptRoot '..\build\windows\x64')
)

$ErrorActionPreference = 'Stop'

$expected = @{
  'mpv-dev-x86_64-20230924-git-652a1dd.7z' = 'a832ef24b3a6ff97cd2560b5b9d04cd8'
  'ANGLE.7z' = 'e866f13e8d552348058afaafe869b1ed'
}

function Install-VerifiedArchive {
  param(
    [Parameter(Mandatory = $true)][string] $Source,
    [Parameter(Mandatory = $true)][string] $FileName,
    [Parameter(Mandatory = $true)][string] $DestinationDirectory
  )

  if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    throw "Archive not found: $Source"
  }

  $actual = (Get-FileHash -LiteralPath $Source -Algorithm MD5).Hash.ToLowerInvariant()
  $wanted = $expected[$FileName]
  if ($actual -ne $wanted) {
    throw "MD5 mismatch for $FileName. Expected $wanted, got $actual."
  }

  New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
  Copy-Item -LiteralPath $Source -Destination (Join-Path $DestinationDirectory $FileName) -Force
  Write-Host "Installed $FileName -> $DestinationDirectory"
}

$resolvedBuildArchDir = [System.IO.Path]::GetFullPath($BuildArchDir)
Install-VerifiedArchive -Source $MpvArchive -FileName 'mpv-dev-x86_64-20230924-git-652a1dd.7z' -DestinationDirectory $resolvedBuildArchDir
Install-VerifiedArchive -Source $AngleArchive -FileName 'ANGLE.7z' -DestinationDirectory $resolvedBuildArchDir
Write-Host 'Now run: flutter run -d windows'
