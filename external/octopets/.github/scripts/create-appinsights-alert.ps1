# This script creates an Azure Monitor alert rule for a Container App
# Parameters (all optional with defaults):
# $ResourceGroup - Resource Group Name (defaults to "rg_octopets")
# $ContainerAppName - Container App Resource Name (defaults to "octopetsapi")
# $AppInsightsName - App Insights Resource Name (defaults to "octopets_appinsights-abc123xyz456")
# $SubscriptionId - Subscription ID (defaults to "12345678-abcd-9e8f-7g6h-5i4j3k2l1m0n")
# $Location - Location (defaults to "eastus")
#
# Usage examples:
# ./create-appinsights-alert.ps1                                        # Use all defaults
# ./create-appinsights-alert.ps1 -ResourceGroup "my-resource-group"     # Custom resource group, defaults for the rest
# ./create-appinsights-alert.ps1 -AppInsightsName "myinsights"          # Custom App Insights name, defaults for the rest

param(
    [string]$ResourceGroup = "rg-octopets",
    [string]$ContainerAppName = "octopetsapi",
    [string]$AppInsightsName = "octopets_appinsights-abc123xyz456",
    [string]$SubscriptionId = "12345678-abcd-9e8f-7g6h-5i4j3k2l1m0n",
    [string]$Location = "eastus"
)

# Display parameter info
Write-Host "Using the following parameters:"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Container App: $ContainerAppName"
Write-Host "App Insights: $AppInsightsName"
Write-Host "Subscription: $SubscriptionId"
Write-Host "Location: $Location"

# Generate a unique suffix for the alert name
$Suffix = -join ((97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
$AlertName = "octopets-failed-requests-alert-$Suffix"
$ActionGroupName = "octopets-action-group-$Suffix"

# If subscription ID is provided, set it
if ($SubscriptionId) {
    Write-Host "Setting subscription to $SubscriptionId"
    az account set --subscription $SubscriptionId
}

# Get the resource IDs
Write-Host "Getting Container App resource ID..."
$ContainerAppId = az containerapp show `
    --resource-group $ResourceGroup `
    --name $ContainerAppName `
    --query id -o tsv

if (-not $ContainerAppId) {
    Write-Error "Error: Container App '$ContainerAppName' not found in resource group '$ResourceGroup'"
    exit 1
}

Write-Host "Getting App Insights resource ID..."
$AppInsightsId = az monitor app-insights component show `
    --app $AppInsightsName `
    --resource-group $ResourceGroup `
    --query id -o tsv

if (-not $AppInsightsId) {
    Write-Error "Error: App Insights '$AppInsightsName' not found in resource group '$ResourceGroup'"
    exit 1
}

# Create action group for the alert (where notifications will be sent)
Write-Host "Creating action group: $ActionGroupName"
az monitor action-group create `
    --resource-group $ResourceGroup `
    --name $ActionGroupName `
    --short-name "OctopetsAG" `
    --location $Location

# Get the action group ID
$ActionGroupId = az monitor action-group show `
    --resource-group $ResourceGroup `
    --name $ActionGroupName `
    --query id -o tsv

# Get current script directory to find the prompt file
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$PromptFilePath = Join-Path -Path $RootDir -ChildPath ".github/prompts/sreagent.prompt.md"
$AlertDescription = Get-Content -Path $PromptFilePath -Raw

# Create the alert rule
Write-Host "Creating alert rule: $AlertName"
az monitor metrics alert create `
    --resource-group $ResourceGroup `
    --name $AlertName `
    --scopes $AppInsightsId `
    --condition "count requests/failed > 0" `
    --window-size 5m `
    --evaluation-frequency 1m `
    --action $ActionGroupId `
    --description $AlertDescription `
    --severity 0

Write-Host "Alert rule creation completed."
Write-Host "Alert Name: $AlertName"
Write-Host "Container App: $ContainerAppName"
Write-Host "Action Group: $ActionGroupName"
Write-Host "Resource Group: $ResourceGroup"
