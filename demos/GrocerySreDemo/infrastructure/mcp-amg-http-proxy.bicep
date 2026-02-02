param location string = resourceGroup().location
param environmentId string
param acrName string
param grafanaName string
param grafanaEndpoint string
@description('Optional Loki base URL for direct query fallback (e.g., https://ca-loki.<stamp>.<region>.azurecontainerapps.io).')
param lokiEndpoint string = ''
@description('Optional Azure Monitor Workspace Prometheus query endpoint (e.g., https://<amw>.<region>.prometheus.monitor.azure.com). Used for Prometheus direct-query fallback.')
param amwQueryEndpoint string = ''
@description('Optional Grafana datasource UID for the AMW Prometheus datasource (e.g., efbya46rp2ltsc). Used to query Prometheus via Grafana datasource proxy without requiring AMW permissions on this proxy identity.')
param prometheusDatasourceUid string = ''
@description('Timeout in seconds for querying Prometheus via Grafana datasource proxy (server-side auth).')
param promGrafanaProxyTimeoutS int = 10
@description('Timeout in seconds for querying Prometheus directly from the Azure Monitor Workspace query endpoint.')
param amwPromqlTimeoutS int = 15
@description('Opt-in: allow using the amg-mcp stdio backend for Prometheus queries (disabled by default due to potential stalls/timeouts).')
param enableBackendPrometheus bool = false
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
              name: 'LOKI_ENDPOINT'
              value: lokiEndpoint
            }
            {
              name: 'AMW_QUERY_ENDPOINT'
              value: amwQueryEndpoint
            }
            {
              name: 'PROMETHEUS_DATASOURCE_UID'
              value: prometheusDatasourceUid
            }
            {
              name: 'PROM_GRAFANA_PROXY_TIMEOUT_S'
              value: string(promGrafanaProxyTimeoutS)
            }
            {
              name: 'AMW_PROMQL_TIMEOUT_S'
              value: string(amwPromqlTimeoutS)
            }
            {
              name: 'ENABLE_BACKEND_PROMETHEUS'
              value: string(enableBackendPrometheus)
            }
            {
              name: 'AMG_MCP_TOOL_TIMEOUT_S'
              value: '90'
            }
            {
              name: 'AMG_MCP_INIT_TIMEOUT_S'
              value: '60'
            }
            {
              name: 'AMG_MCP_TOOLS_LIST_TIMEOUT_S'
              value: '60'
            }
            {
              name: 'DISABLE_AMGMCP_AZURE_TOOLS'
              value: 'true'
            }
            {
              name: 'GRAFANA_RENDER_TIMEOUT_S'
              value: '20'
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
