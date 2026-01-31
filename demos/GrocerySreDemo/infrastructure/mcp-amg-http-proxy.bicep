param location string = resourceGroup().location
param environmentId string
param acrName string
param grafanaName string
param grafanaEndpoint string
@description('Name of the Container App to deploy (you can change this to run multiple variants).')
param appName string = 'ca-mcp-amg-proxy'
@description('ACR image tag for the amg-mcp-http-proxy container image.')
param imageTag string = 'latest'
@description('Unique value to force a new Container Apps revision (for example, a deployment timestamp).')
param deploymentStamp string = utcNow('yyyyMMddHHmmss')

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' existing = {
  name: grafanaName
}

// Reuse (or create) the same identity name as the stdio-based AMG MCP.
resource mcpAmgIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uami-mcp-amg'
  location: location
}

resource mcpAmgProxyApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${mcpAmgIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      registries: [
        {
          server: '${acrName}.azurecr.io'
          identity: mcpAmgIdentity.id
        }
      ]
      ingress: {
        external: true
        targetPort: 8000
        transport: 'http'
        corsPolicy: {
          allowedOrigins: [
            '*'
          ]
          allowedMethods: [
            'GET'
            'POST'
            'OPTIONS'
          ]
          allowedHeaders: [
            '*'
          ]
        }
      }
    }
    template: {
      containers: [
        {
          name: 'amg-mcp-proxy'
          image: '${acrName}.azurecr.io/amg-mcp-http-proxy:${imageTag}'
          env: [
            {
              name: 'GRAFANA_ENDPOINT'
              value: grafanaEndpoint
            }
            {
              name: 'AMG_MCP_TOOL_TIMEOUT_S'
              value: '90'
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: mcpAmgIdentity.properties.clientId
            }
            {
              name: 'DEPLOYMENT_STAMP'
              value: deploymentStamp
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, mcpAmgIdentity.id, 'acrpull')
  scope: acr
  properties: {
    principalId: mcpAmgIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

resource grafanaViewerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(grafana.id, mcpAmgIdentity.id, 'grafanaviewer')
  scope: grafana
  properties: {
    principalId: mcpAmgIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '60921a7e-fef1-4a43-9b16-a26c52ad4769')
  }
}

output mcpUrl string = 'https://${mcpAmgProxyApp.properties.configuration.ingress.fqdn}/mcp'
output principalId string = mcpAmgIdentity.properties.principalId
