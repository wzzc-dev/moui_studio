[CmdletBinding()]
param(
  [string]$Arch = "x64",
  [string]$VcpkgRoot = "",
  [string]$WgpuNativeRoot = "",
  [switch]$SkipZlibCheck
)

# Thin shim: dot-source the published MSVC helper that ships inside the
# wzzc-dev/moui module. The MoUI parent repo keeps moui as a workspace member
# at <repoRoot>\moui; a standalone moui_studio checkout gets it as a
# mooncakes dependency, which is only extracted from the registry cache on
# the first build — so as a last resort this shim extracts the helper from
# the cached module zip into a temp dir.

$ErrorActionPreference = "Stop"

$scriptDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
  $PSScriptRoot
} else {
  Split-Path -Parent $MyInvocation.MyCommand.Path
}
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path

$candidates = @(
  (Join-Path $repoRoot "moui\scripts\windows\msvc_env.ps1"),
  (Join-Path $repoRoot ".mooncakes\wzzc-dev\moui\scripts\windows\msvc_env.ps1")
)
foreach ($candidate in $candidates) {
  if (Test-Path -LiteralPath $candidate) {
    . $candidate @PSBoundParameters
    return
  }
}

# Resolve the pinned wzzc-dev/moui version from moon.mod.
$moduleManifest = Join-Path $repoRoot "moon.mod"
$versionLine = Select-String -LiteralPath $moduleManifest -Pattern '"wzzc-dev/moui@([^"]+)"' |
  Select-Object -First 1
if ($null -eq $versionLine) {
  throw "Cannot resolve wzzc-dev/moui version from $moduleManifest"
}
$mouiVersion = $versionLine.Matches[0].Groups[1].Value

$registryZip = Join-Path $HOME ".moon\registry\cache\wzzc-dev\moui\$mouiVersion.zip"
if (-not (Test-Path -LiteralPath $registryZip)) {
  throw "Published MSVC helper not found in candidates and registry cache zip is missing: $registryZip"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "moui-msvc-helper-$mouiVersion"
if (Test-Path -LiteralPath $tempRoot) {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force
}
Expand-Archive -LiteralPath $registryZip -DestinationPath $tempRoot -Force

$helper = Join-Path $tempRoot "scripts\windows\msvc_env.ps1"
if (-not (Test-Path -LiteralPath $helper)) {
  throw "Published MSVC helper is missing inside $registryZip"
}
. $helper @PSBoundParameters
