param([ValidateRange(0, 10000)][int]$PlatformFeeBps = 1200,
      [string[]]$OnlyFunctions = @())

$ErrorActionPreference = 'Stop'
$workspaceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$stage = [IO.Path]::GetFullPath((Join-Path $workspaceRoot '.dart_tool/platform-deploy'))
if (-not $stage.StartsWith($workspaceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Deployment source must stay inside this workspace.'
}
$priorDebug = $env:DEBUG
$priorDiscoveryTimeout = $env:FUNCTIONS_DISCOVERY_TIMEOUT
Push-Location $workspaceRoot
try {
  $env:DEBUG = $null
  $env:FIREBASE_CLI_DISABLE_UPDATE_CHECK = 'true'
  $env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
  & npm run build --prefix functions
  if ($LASTEXITCODE -ne 0) { throw 'Function compilation failed.' }

  New-Item -ItemType Directory -Force -Path "$stage/functions" | Out-Null
  Copy-Item -LiteralPath 'functions/lib', 'functions/src' -Destination "$stage/functions" -Recurse -Force
  Copy-Item -LiteralPath 'functions/package.json', 'functions/package-lock.json', 'functions/tsconfig.json' -Destination "$stage/functions" -Force
  Copy-Item -LiteralPath 'firestore.rules', 'firestore.indexes.json', 'storage.rules' -Destination $stage -Force
  if (-not (Test-Path -LiteralPath "$stage/functions/node_modules")) {
    New-Item -ItemType Junction -Path "$stage/functions/node_modules" -Target (Join-Path $workspaceRoot 'functions/node_modules') | Out-Null
  }
  $encoding = New-Object System.Text.UTF8Encoding($false)
  $packagePath = Join-Path $stage 'functions/package.json'
  $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
  $package.main = 'lib/src/platform_index.js'
  [IO.File]::WriteAllText($packagePath, ($package | ConvertTo-Json -Depth 30), $encoding)
  [IO.File]::WriteAllText((Join-Path $stage 'functions/.env.onlyonepoint-lesson'), "PLATFORM_FEE_BPS=$PlatformFeeBps`n", $encoding)
  $configuration = @{
    firestore = @{ rules = 'firestore.rules'; indexes='firestore.indexes.json' }
    storage = @{ rules = 'storage.rules' }
    functions = @{ source = 'functions'; codebase = 'default'; ignore = @('node_modules', '.git', '*.log') }
  }
  [IO.File]::WriteAllText((Join-Path $stage 'firebase.json'), ($configuration | ConvertTo-Json -Depth 10), $encoding)
  $functionTargets = & node -e "process.stdout.write(Object.keys(require('./functions/lib/src/platform_index.js')).map(n=>'functions:'+n).join(','))"
  if ($LASTEXITCODE -ne 0 -or -not $functionTargets) { throw 'Could not determine platform functions.' }
  if ($OnlyFunctions.Count -gt 0) {
    $availableTargets = $functionTargets.Split(',')
    $selectedTargets = foreach ($functionName in $OnlyFunctions) {
      $target = "functions:$functionName"
      if ($availableTargets -notcontains $target) { throw "Not an exported platform function: $functionName" }
      $target
    }
    $functionTargets = $selectedTargets -join ','
  }
  # Explicit targets retain unrelated functions. --force acknowledges retries
  # for idempotent push/report delivery and resumable account-cleanup handlers.
  & './security-tests/node_modules/.bin/firebase.cmd' deploy --config "$stage/firebase.json" --project onlyonepoint-lesson --only "firestore:rules,firestore:indexes,storage,$functionTargets" --non-interactive --force
  if ($LASTEXITCODE -ne 0) { throw 'Platform deployment failed.' }
} finally {
  $env:DEBUG = $priorDebug
  $env:FUNCTIONS_DISCOVERY_TIMEOUT = $priorDiscoveryTimeout
  Pop-Location
}
