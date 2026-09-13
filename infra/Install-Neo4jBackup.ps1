param(
  [Parameter(Mandatory = $true)][string]$SshHost,
  [Parameter(Mandatory = $true)][string]$RuntimeEnvFile,
  [string]$Neo4jImage = 'neo4j:2026.07.1'
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command ssh -ErrorAction SilentlyContinue) -or -not (Get-Command scp -ErrorAction SilentlyContinue)) {
  throw 'OpenSSH client tools are required to install the Neo4j backup timer.'
}
if (-not (Test-Path -LiteralPath $RuntimeEnvFile)) {
  throw "Protected environment file $RuntimeEnvFile does not exist."
}

$required = 'SPACES_BUCKET', 'SPACES_ENDPOINT', 'SPACES_ACCESS_KEY_ID', 'SPACES_SECRET_ACCESS_KEY'
$values = @{}
Get-Content -LiteralPath $RuntimeEnvFile | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)=(.*)$' -and $required -contains $matches[1]) {
    $values[$matches[1]] = $matches[2].Trim()
  }
}
foreach ($key in $required) {
  if ([string]::IsNullOrWhiteSpace($values[$key])) {
    throw "$key is required in the protected environment file."
  }
}

$inputFile = New-TemporaryFile
try {
  Set-Content -LiteralPath $inputFile.FullName -Value ($required | ForEach-Object { $values[$_] }) -Encoding utf8
  & scp (Join-Path $PSScriptRoot 'backup-neo4j.sh') "root@${SshHost}:/tmp/backup-neo4j.sh"
  & scp (Join-Path $PSScriptRoot 'install-neo4j-backup.sh') "root@${SshHost}:/tmp/install-neo4j-backup.sh"
  & scp (Join-Path $PSScriptRoot 'install-neo4j-backup-runtime.sh') "root@${SshHost}:/tmp/install-neo4j-backup-runtime.sh"
  & scp $inputFile.FullName "root@${SshHost}:/tmp/neo4j-backup-input"
  if ($LASTEXITCODE -ne 0) { throw 'Failed to transfer protected Neo4j backup configuration inputs.' }

  $remoteCommand = "set -e; cleanup() { rm -f /tmp/backup-neo4j.sh /tmp/install-neo4j-backup.sh /tmp/install-neo4j-backup-runtime.sh /tmp/neo4j-backup-input; }; trap cleanup EXIT; chmod 0700 /tmp/backup-neo4j.sh /tmp/install-neo4j-backup.sh /tmp/install-neo4j-backup-runtime.sh; chmod 0600 /tmp/neo4j-backup-input; NEO4J_IMAGE='$Neo4jImage' /tmp/install-neo4j-backup-runtime.sh"
  & ssh "root@$SshHost" $remoteCommand
  if ($LASTEXITCODE -ne 0) { throw 'Neo4j backup timer installation failed.' }
} finally {
  Remove-Item -LiteralPath $inputFile.FullName -Force -ErrorAction SilentlyContinue
}
