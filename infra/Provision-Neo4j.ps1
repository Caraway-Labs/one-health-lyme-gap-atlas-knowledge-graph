param(
  [ValidateSet('dev','prod')][string]$Environment,
  [string]$VpcUuid,
  [string]$SshKeyFingerprint,
  [string]$SshAllowedCidr,
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
if (-not $VpcUuid -or -not $SshKeyFingerprint -or -not $SshAllowedCidr) {
  throw 'VpcUuid, SshKeyFingerprint, and SshAllowedCidr are required for confirmed provisioning.'
}
if (-not (Get-Command doctl -ErrorAction SilentlyContinue)) {
  throw 'doctl is required.'
}
$name = "oh-lyme-$Environment-neo4j"
$firewallName = "$name-private"
$existingDroplet = & doctl compute droplet list --tag-name $name --output json | ConvertFrom-Json
if ($existingDroplet.Count -gt 0) {
  throw "A tagged $name Droplet already exists; refusing duplicate compute."
}
$existingVolume = & doctl compute volume list --region $spec.region --output json | ConvertFrom-Json |
  Where-Object { $_.name -eq "$name-data" }
if ($existingVolume.Count -gt 1) { throw "Multiple $name-data volumes exist." }
if ($existingVolume.Count -eq 0) {
  $volumeJson = & doctl compute volume create "$name-data" --region $spec.region --size "$($spec.volume_gib)GiB" --desc "Retained Neo4j $Environment data" --output json
  if ($LASTEXITCODE -ne 0) { throw "Failed to create retained $Environment Neo4j volume." }
  $volume = $volumeJson | ConvertFrom-Json
  if (-not $volume -or -not $volume[0].id) { throw "DigitalOcean did not return a retained $Environment Neo4j volume ID." }
  $volumeId = $volume[0].id
} else {
  $volumeId = $existingVolume[0].id
}
$dropletJson = & doctl compute droplet create $name --region $spec.region --size $spec.droplet_size `
  --image ubuntu-24-04-x64 --vpc-uuid $VpcUuid --ssh-keys $SshKeyFingerprint `
  --volumes $volumeId --tag-names $name --user-data-file (Join-Path $PSScriptRoot 'neo4j-cloud-init.yml') `
  --wait --output json
if ($LASTEXITCODE -ne 0) { throw "Failed to create $Environment Neo4j Droplet." }
$droplet = $dropletJson | ConvertFrom-Json
if (-not $droplet -or -not $droplet[0].id) { throw "DigitalOcean did not return a $Environment Neo4j Droplet ID." }
$vpc = & doctl vpcs get $VpcUuid --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $vpc -or -not $vpc[0].ip_range) {
  throw "Failed to resolve VPC $VpcUuid address range for the $Environment Neo4j firewall."
}
$inboundRules = "protocol:tcp,ports:22,address:$SshAllowedCidr protocol:tcp,ports:7687,address:$($vpc[0].ip_range)"
$outboundRules = 'protocol:icmp,ports:0,address:0.0.0.0/0 protocol:tcp,ports:1-65535,address:0.0.0.0/0 protocol:udp,ports:1-65535,address:0.0.0.0/0'
$existingFirewall = @(& doctl compute firewall list --output json | ConvertFrom-Json | Where-Object { $_.name -eq $firewallName })
if ($existingFirewall.Count -gt 1) { throw "Multiple $firewallName firewalls exist." }
if ($existingFirewall.Count -eq 0) {
  & doctl compute firewall create --name $firewallName --inbound-rules $inboundRules --outbound-rules $outboundRules --tag-names $name | Out-Null
} else {
  & doctl compute firewall update $existingFirewall[0].id --name $firewallName --inbound-rules $inboundRules --outbound-rules $outboundRules --tag-names $name | Out-Null
}
if ($LASTEXITCODE -ne 0) { throw "Failed to configure the $Environment Neo4j firewall." }
[pscustomobject]@{ environment = $Environment; droplet_id = $droplet[0].id; volume_id = $volumeId; firewall_name = $firewallName } | ConvertTo-Json
