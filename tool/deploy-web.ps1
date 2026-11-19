param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$workspaceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$priorDebug = $env:DEBUG
Push-Location $workspaceRoot
try {
  $env:DEBUG = $null
  $env:FIREBASE_CLI_DISABLE_UPDATE_CHECK = 'true'
  if (-not $SkipBuild) {
    & flutter build web
    if ($LASTEXITCODE -ne 0) { throw 'Web build failed.' }
  }
  foreach ($required in @('build/web/index.html', 'build/web/main.dart.js', 'build/web/flutter_bootstrap.js')) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing web output: $required" }
  }
  & './security-tests/node_modules/.bin/firebase.cmd' deploy --config firebase.json --project onlyonepoint-lesson --only hosting --non-interactive
  if ($LASTEXITCODE -ne 0) { throw 'Web hosting deployment failed.' }
} finally {
  $env:DEBUG = $priorDebug
  Pop-Location
}
