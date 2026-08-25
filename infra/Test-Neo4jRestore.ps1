param(
  [string]$BackupPrefix,
  [switch]$Confirm
)
$ErrorActionPreference = 'Stop'
if (-not $Confirm) {
  [pscustomobject]@{
    mode = 'preview'
    cadence = 'quarterly'
    backup_prefix = $BackupPrefix
    checks = @('dump checksums','constraints','node and edge counts','representative retrieval')
    teardown = 'destroy ephemeral compute after record upload'
  } | ConvertTo-Json -Depth 3
  exit 0
}
throw 'Quarterly live restore creates paid ephemeral infrastructure and must run in the owner-approved protected workflow.'
