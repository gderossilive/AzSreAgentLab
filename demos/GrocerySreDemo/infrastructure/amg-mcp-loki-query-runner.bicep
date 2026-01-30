param location string = resourceGroup().location
param environmentId string
param acrName string
param grafanaEndpoint string

@description('Existing user-assigned managed identity name that already has Grafana Viewer on the Managed Grafana resource and AcrPull on the ACR.')
param uamiName string = 'uami-mcp-amg'

@description('Name of the ephemeral Container App that will run a one-shot query via the amg-mcp stdio server and then exit (logs-only runner).')
param appName string = 'ca-amg-mcp-loki-query'

@description('How far back to query (minutes).')
param lookbackMinutes int = 15

@description('LogQL expression to run against the Loki datasource.')
param lokiLogQl string = '{app="grocery-api"}'

@description('How many log entries to request (best-effort; depends on datasource/tool behavior).')
param limit int = 20

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: uamiName
}

resource runnerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      registries: [
        {
          server: '${acrName}.azurecr.io'
          identity: uami.id
        }
      ]
      // No ingress; logs-only utility.
    }
    template: {
      containers: [
        {
          name: 'runner'
          image: '${acrName}.azurecr.io/amg-mcp-loki-query-runner:latest'
          env: [
            {
              name: 'AmgMcpOptions__AzureManagedGrafanaEndpoint'
              value: grafanaEndpoint
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: uami.properties.clientId
            }
            {
              name: 'GRAFANA_ENDPOINT'
              value: grafanaEndpoint
            }
            {
              name: 'LOOKBACK_MINUTES'
              value: string(lookbackMinutes)
            }
            {
              name: 'LOKI_LOGQL'
              value: lokiLogQl
            }
            {
              name: 'LIMIT'
              value: string(limit)
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

output runnerAppName string = runnerApp.name
