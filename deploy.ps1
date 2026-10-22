# Package, upload, assign to the development channel and install an Edge driver in one go.
# Usage: .\deploy.ps1 zigbee-power-meter            (home hub)
#        .\deploy.ps1 zigbee-power-meter -Hub office
param(
  [Parameter(Mandatory = $true)][string]$Driver,
  [ValidateSet("home", "office")][string]$Hub = "home"
)

$channel = "2a0dce29-0ee2-4ada-b08a-9d225cb47565"
$hubs = @{
  home   = "4caf3278-1091-42e6-a7d8-54c3bba85729"
  office = "96b889e6-b406-47a5-b8ac-3e12112e2989"
}

smartthings edge:drivers:package (Join-Path $PSScriptRoot $Driver) --channel $channel --hub $hubs[$Hub]
