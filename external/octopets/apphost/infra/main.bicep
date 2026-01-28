// Octopets Infrastructure - Azure Container Apps
// Deploys Container Apps Environment, Container Registry, Log Analytics, and Application Insights
// Modified to address INC0010064: OutOfMemoryException in GET /api/listings/{id:int}

targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment which is used to generate a short unique hash suffix for resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

// Tags applied to all resources
var tags = {
  'azd-env-name': environmentName
  Purpose: 'SRE-Agent-Lab'
  ManagedBy: 'Bicep'
}

// Resource group name  
var resourceGroupName = 'rg-${environmentName}'

// Generate unique suffix for globally unique names
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Log Analytics Workspace
module logAnalytics './resources/log-analytics.bicep' = {
  name: 'log-analytics'
  scope: rg
  params: {
    name: 'logs-${resourceToken}'
    location: location
    tags: tags
  }
}

// Application Insights
module appInsights './resources/app-insights.bicep' = {
  name: 'app-insights'
  scope: rg
  params: {
    name: 'octopets-appinsights-${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
  }
}

// Container Registry
module containerRegistry './resources/container-registry.bicep' = {
  name: 'container-registry'
  scope: rg
  params: {
    name: 'cr${resourceToken}'
    location: location
    tags: tags
  }
}

// Container Apps Environment
module containerAppsEnvironment './resources/container-apps-environment.bicep' = {
  name: 'container-apps-environment'
  scope: rg
  params: {
    name: 'cae-${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    appInsightsConnectionString: appInsights.outputs.connectionString
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.name
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = containerAppsEnvironment.outputs.name
output APPLICATIONINSIGHTS_CONNECTION_STRING string = appInsights.outputs.connectionString
output RESOURCE_GROUP_NAME string = resourceGroupName
