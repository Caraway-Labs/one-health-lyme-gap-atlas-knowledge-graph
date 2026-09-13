param(
  [string]$SshHost = '164.92.92.127',
  [string]$PrivateIp = '10.116.0.2',
  [ValidateRange(1024, 65535)][int]$LocalPort = 7687
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  throw 'OpenSSH is required to create the private Neo4j tunnel.'
}
if (Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue) {
  throw "Local port $LocalPort is already listening; refusing to replace an existing tunnel or service."
}

Write-Host "Opening DEV Neo4j tunnel on bolt://localhost:$LocalPort. Press Ctrl+C to close it."
& ssh -N -L "${LocalPort}:${PrivateIp}:7687" "root@$SshHost"
if ($LASTEXITCODE -ne 0) {
  throw 'DEV Neo4j tunnel ended unsuccessfully.'
}
