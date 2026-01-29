param location string = resourceGroup().location
param environmentId string
param acrName string
param grafanaName string
param grafanaEndpoint string

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' existing = {
  name: grafanaName
}

resource mcpAmgIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uami-mcp-amg'
  location: location
}

resource mcpAmgApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-mcp-amg'
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
          identity: mcpAmgIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'amg-mcp'
          image: '${acrName}.azurecr.io/amg-mcp:latest'
          args: [
            '--AmgMcpOptions:Transport=Sse'
            '--AmgMcpOptions:SseListenAddress=http://0.0.0.0:8000'
            '--AmgMcpOptions:AzureManagedGrafanaEndpoint=${grafanaEndpoint}'
          ]
          env: [
            {
              name: 'AmgMcpOptions__AzureManagedGrafanaEndpoint'
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

output mcpAmgSseUrl string = 'https://${mcpAmgApp.properties.configuration.ingress.fqdn}/sse'
output mcpAmgPrincipalId string = mcpAmgIdentity.properties.principalId
