[CmdletBinding()]
param(
  [string]$Ref = "main",
  [string]$Environment = "dev",
  [string]$Service = "hermes-railway-template",
  [string]$Project = "",
  [string]$CacheBust = ""
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command railway -ErrorAction SilentlyContinue)) {
  throw "Railway CLI is not installed or is not on PATH."
}

if ([string]::IsNullOrWhiteSpace($CacheBust)) {
  $CacheBust = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
}

function Invoke-Railway {
  param([string[]]$Arguments)

  Write-Host "railway $($Arguments -join ' ')"
  & railway @Arguments
  $code = $LASTEXITCODE
  if ($code -ne 0) {
    throw "Railway CLI exited with code $code."
  }
}

$setArgs = @(
  "variable",
  "set",
  "HERMES_GIT_REF=$Ref",
  "HERMES_SOURCE_CACHE_BUST=$CacheBust",
  "--service",
  $Service,
  "--environment",
  $Environment,
  "--skip-deploys"
)

$redeployArgs = @(
  "deployment",
  "redeploy",
  "--from-source",
  "--yes",
  "--service",
  $Service,
  "--environment",
  $Environment
)

if (-not [string]::IsNullOrWhiteSpace($Project)) {
  $setArgs += @("--project", $Project)
  $redeployArgs += @("--project", $Project)
}

Invoke-Railway -Arguments $setArgs
Invoke-Railway -Arguments $redeployArgs

Write-Host "Requested Railway rebuild for Hermes ref '$Ref' with cache bust '$CacheBust'."
