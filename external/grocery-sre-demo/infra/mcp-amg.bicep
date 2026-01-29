param location string = resourceGroup().location
param environmentId string
param acrName string
param grafanaEndpoint string

// Reference existing ACR
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// Reference existing Managed Grafana
resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' existing = {
  name: 'amg-3syj3i2fat5dm'
}

resource mcpAmgApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-mcp-amg'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        transport: 'http'
        corsPolicy: {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'OPTIONS']
          allowedHeaders: ['*']
        }
      }
      registries: [
        {
          server: '${acrName}.azurecr.io'
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'amg-mcp'
          image: '${acrName}.azurecr.io/amg-mcp:latest'
          env: [
            {
              name: 'AmgMcpOptions__GrafanaEndpoint'
              value: grafanaEndpoint
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

// Grant Container App managed identity access to ACR
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, mcpAmgApp.id, 'acrpull')
  scope: acr
  properties: {
    principalId: mcpAmgApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
  }
}

// Grant Container App managed identity Grafana Viewer role on Managed Grafana
resource grafanaViewerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(grafana.id, mcpAmgApp.id, 'grafanaviewer')
  scope: grafana
  properties: {
    principalId: mcpAmgApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '60921a7e-fef1-4a43-9b16-a26c52ad4769') // Grafana Viewer
  }
}

output mcpAmgUrl string = 'https://${mcpAmgApp.properties.configuration.ingress.fqdn}/sse'
output mcpAmgPrincipalId string = mcpAmgApp.identity.principalId
