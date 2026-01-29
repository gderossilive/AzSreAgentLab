param location string = resourceGroup().location
param environmentId string
param grafanaUrl string
@secure()
param grafanaToken string

resource mcpServerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-mcp-grafana'
  location: location
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
      secrets: [
        {
          name: 'grafana-token'
          value: grafanaToken
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'mcp-grafana'
          image: 'grafana/mcp-grafana:latest'
          args: ['-t', 'streamable-http']
          env: [
            {
              name: 'GRAFANA_URL'
              value: grafanaUrl
            }
            {
              name: 'GRAFANA_SERVICE_ACCOUNT_TOKEN'
              secretRef: 'grafana-token'
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

output mcpServerUrl string = 'https://${mcpServerApp.properties.configuration.ingress.fqdn}/mcp'
