param(
  [ValidateSet('dev','prod')][string]$Environment,
  [string]$VpcUuid,
  [string]$SshKeyFingerprint,
  [switch]$Confirm
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$specPath = Join-Path $PSScriptRoot "neo4j-$Environment.json"
$spec = Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json
if (-not $Confirm) {
  [pscustomobject]@{
    mode = 'preview'
    environment = $Environment
    region = $spec.region
    droplet_size = $spec.droplet_size
    volume_gib = $spec.volume_gib
    image = $spec.neo4j_image
    public_bolt = $false
    public_browser = $false
  } | ConvertTo-Json
  exit 0
}
if (-not $VpcUuid -or -not $SshKeyFingerprint) {
  throw 'VpcUuid and SshKeyFingerprint are required for confirmed provisioning.'
}
if (-not (Get-Command doctl -ErrorAction SilentlyContinue)) {
  throw 'doctl is required.'
}
$name = "oh-lyme-$Environment-neo4j"
$existingDroplet = & doctl compute droplet list --tag-name $name --output json | ConvertFrom-Json
if ($existingDroplet.Count -gt 0) {
  throw "A tagged $name Droplet already exists; refusing duplicate compute."
}
$existingVolume = & doctl compute volume list --region $spec.region --output json | ConvertFrom-Json |
  Where-Object { $_.name -eq "$name-data" }
if ($existingVolume.Count -gt 1) { throw "Multiple $name-data volumes exist." }
if ($existingVolume.Count -eq 0) {
  $volume = & doctl compute volume create "$name-data" --region $spec.region --size $spec.volume_gib --desc "Retained Neo4j $Environment data" --output json | ConvertFrom-Json
  $volumeId = $volume[0].id
} else {
  $volumeId = $existingVolume[0].id
}
$droplet = & doctl compute droplet create $name --region $spec.region --size $spec.droplet_size `
  --image ubuntu-24-04-x64 --vpc-uuid $VpcUuid --ssh-keys $SshKeyFingerprint `
  --volumes $volumeId --tag-names $name --user-data-file (Join-Path $PSScriptRoot 'neo4j-cloud-init.yml') `
  --wait --output json | ConvertFrom-Json
[pscustomobject]@{ environment = $Environment; droplet_id = $droplet[0].id; volume_id = $volumeId } | ConvertTo-Json
