targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name used as part of the naming convention.')
param environmentName string

@minLength(1)
@description('Primary location for all resources.')
param location string = 'swedencentral'

@description('Name of the resource group for this demo.')
param resourceGroupName string = 'rg-grocery-sre-demo'

@description('Name of the dedicated SRE Agent resource for this demo.')
param sreAgentName string = 'sre-agent-grocery-demo'

@description('SRE Agent access level (High or Low).')
@allowed([
  'High'
  'Low'
])
param sreAgentAccessLevel string = 'High'

@description('Optional: resourceId of an existing user-assigned managed identity to use for the agent.')
param sreAgentExistingManagedIdentityId string = ''

var groceryAbbrs = loadJsonContent('../../../external/grocery-sre-demo/infra/abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  demo: 'grocery-sre-demo'
  'azd-env-name': environmentName
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module groceryResources '../../../external/grocery-sre-demo/infra/resources.bicep' = {
  scope: rg
  params: {
    location: location
    tags: tags
    resourceToken: resourceToken
  }
}

module sreAgent '../../../external/sre-agent/samples/bicep-deployment/bicep/sre-agent-resources.bicep' = {
  scope: rg
  params: {
    agentName: sreAgentName
    location: location
    existingManagedIdentityId: sreAgentExistingManagedIdentityId
    accessLevel: sreAgentAccessLevel
    targetResourceGroups: [resourceGroupName]
    targetSubscriptions: [subscription().subscriptionId]
    subscriptionId: subscription().subscriptionId
    uniqueSuffix: resourceToken
  }
}

output resourceGroupName string = rg.name
output environmentName string = environmentName
output location string = location

output containerRegistryName string = groceryResources.outputs.containerRegistryName
output containerRegistryLoginServer string = groceryResources.outputs.containerRegistryLoginServer
output containerAppsEnvironmentName string = groceryResources.outputs.containerAppsEnvironmentName
output grafanaName string = groceryResources.outputs.grafanaName
output grafanaEndpoint string = groceryResources.outputs.grafanaEndpoint
output apiUrl string = groceryResources.outputs.apiUrl
output webUrl string = groceryResources.outputs.webUrl

output apiContainerAppName string = '${groceryAbbrs.containerApps}api-${resourceToken}'
output webContainerAppName string = '${groceryAbbrs.containerApps}web-${resourceToken}'

output sreAgentName string = sreAgent.outputs.agentName
output sreAgentId string = sreAgent.outputs.agentId
output sreAgentPortalUrl string = sreAgent.outputs.agentPortalUrl
