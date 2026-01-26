// Main Bicep template for Octopets deployment on Azure Container Apps
// Deploys Container Apps Environment, ACR, Log Analytics, App Insights, and Container Apps

targetScope = 'subscription'

@description('Environment name (e.g., octopets-demo-lab)')
param environmentName string

@description('Azure region for resources')
param location string = 'swedencentral'

@description('Tags for all resources')
param tags object = {
  Environment: 'Lab'
  ManagedBy: 'Bicep'
  Purpose: 'Octopets-Demo'
}

// Create resource group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

// Deploy infrastructure modules
module infrastructure 'resources.bicep' = {
  name: 'octopets-infrastructure'
  scope: rg
  params: {
    environmentName: environmentName
    location: location
    tags: tags
  }
}

// Outputs
output resourceGroupName string = rg.name
output containerRegistryName string = infrastructure.outputs.containerRegistryName
output containerAppEnvironmentName string = infrastructure.outputs.containerAppEnvironmentName
output logAnalyticsWorkspaceId string = infrastructure.outputs.logAnalyticsWorkspaceId
output applicationInsightsConnectionString string = infrastructure.outputs.applicationInsightsConnectionString
output octopetsApiAppName string = infrastructure.outputs.octopetsApiAppName
output octopetsFrontendAppName string = infrastructure.outputs.octopetsFrontendAppName
