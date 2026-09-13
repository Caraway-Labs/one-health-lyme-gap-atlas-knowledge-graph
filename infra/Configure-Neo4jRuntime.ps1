param(
  [ValidateSet('dev', 'prod')][string]$Environment,
  [Parameter(Mandatory = $true)][string]$SshHost,
  [Parameter(Mandatory = $true)][string]$PrivateIp,
  [Parameter(Mandatory = $true)][string]$RuntimeEnvFile,
  [string]$Neo4jImage = 'neo4j:2026.07.1'
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command ssh -ErrorAction SilentlyContinue) -or -not (Get-Command scp -ErrorAction SilentlyContinue)) {
  throw 'OpenSSH client tools are required to configure Neo4j.'
}
if (-not (Test-Path -LiteralPath $RuntimeEnvFile)) {
  throw "Protected environment file $RuntimeEnvFile does not exist."
}

$values = @{}
Get-Content -LiteralPath $RuntimeEnvFile | ForEach-Object {
  if ($_ -match '^\s*(NEO4J_(?:ADMIN|RUNTIME)_PASSWORD)=(.*)$') {
    $values[$matches[1]] = $matches[2].Trim()
  }
}
if ([string]::IsNullOrWhiteSpace($values['NEO4J_RUNTIME_PASSWORD'])) {
  throw 'NEO4J_RUNTIME_PASSWORD is required in the protected environment file.'
}
if ($Environment -eq 'prod' -and [string]::IsNullOrWhiteSpace($values['NEO4J_ADMIN_PASSWORD'])) {
  throw 'NEO4J_ADMIN_PASSWORD is required to initialize a new PROD Neo4j host.'
}

$inputFile = New-TemporaryFile
try {
  $runtimeLines = @($values['NEO4J_RUNTIME_PASSWORD'])
  if ($values.ContainsKey('NEO4J_ADMIN_PASSWORD')) {
    $runtimeLines += $values['NEO4J_ADMIN_PASSWORD']
  }
  Set-Content -LiteralPath $inputFile.FullName -Value ($runtimeLines -join "`n") -Encoding utf8 -NoNewline
  & scp (Join-Path $PSScriptRoot 'configure-neo4j.sh') "root@${SshHost}:/tmp/configure-neo4j.sh"
  & scp (Join-Path $PSScriptRoot 'configure-neo4j-runtime.sh') "root@${SshHost}:/tmp/configure-neo4j-runtime.sh"
  & scp $inputFile.FullName "root@${SshHost}:/tmp/neo4j-runtime-input"
  if ($LASTEXITCODE -ne 0) { throw 'Failed to transfer protected Neo4j configuration inputs.' }

  $remoteCommand = "set -e; chmod 0700 /tmp/configure-neo4j.sh /tmp/configure-neo4j-runtime.sh; chmod 0600 /tmp/neo4j-runtime-input; ATLAS_ENV='$Environment' PRIVATE_IP='$PrivateIp' NEO4J_IMAGE='$Neo4jImage' /tmp/configure-neo4j-runtime.sh; rm -f /tmp/configure-neo4j.sh /tmp/configure-neo4j-runtime.sh /tmp/neo4j-runtime-input"
  & ssh "root@$SshHost" $remoteCommand
  if ($LASTEXITCODE -ne 0) { throw "Neo4j $Environment runtime configuration failed." }
} finally {
  Remove-Item -LiteralPath $inputFile.FullName -Force -ErrorAction SilentlyContinue
}
