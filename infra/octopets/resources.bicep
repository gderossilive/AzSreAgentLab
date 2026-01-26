// Resources Bicep for Octopets infrastructure
// Creates Log Analytics, App Insights, ACR, Container App Environment, and Container Apps

@description('Environment name')
param environmentName string

@description('Azure region for resources')
param location string

@description('Tags for all resources')
param tags object

// Generate unique suffix for global resources
var uniqueSuffix = uniqueString(resourceGroup().id)

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${uniqueSuffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'octopets_appinsights-${uniqueSuffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
  }
}

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: 'acr${uniqueSuffix}'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

// Container Apps Environment
resource containerAppEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${environmentName}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    daprAIConnectionString: appInsights.properties.ConnectionString
  }
}

// Octopets API Container App
resource octopetsApi 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'octopetsapi'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: 'system'
        }
      ]
    }
    template: {
      // Use placeholder image - will be updated by deployment script
      containers: [
        {
          name: 'octopetsapi'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            {
              name: 'EnableSwagger'
              value: 'true'
            }
            {
              name: 'ASPNETCORE_URLS'
              value: 'http://+:8080'
            }
            {
              name: 'CPU_STRESS'
              value: 'false' // Disabled by default for reliability
            }
            {
              name: 'MEMORY_ERRORS'
              value: 'false' // Disabled by default for reliability
            }
            {
              name: 'OTEL_DOTNET_AUTO_HOME'
              value: '/otel-dotnet-auto'
            }
            {
              name: 'OTEL_SERVICE_NAME'
              value: 'octopetsapi'
            }
            {
              name: 'OTEL_TRACES_EXPORTER'
              value: 'otlp'
            }
            {
              name: 'OTEL_METRICS_EXPORTER'
              value: 'otlp' // Changed from 'none' to enable metrics
            }
            {
              name: 'OTEL_LOGS_EXPORTER'
              value: 'otlp' // Changed from 'none' to enable logs
            }
            {
              name: 'OTEL_EXPORTER_OTLP_PROTOCOL'
              value: 'grpc'
            }
            {
              name: 'OTEL_EXPORTER_OTLP_ENDPOINT'
              value: 'http://localhost:4317'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
          ]
          // Add health probes for better reliability
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              failureThreshold: 3
              successThreshold: 1
              timeoutSeconds: 5
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              failureThreshold: 3
              successThreshold: 1
              timeoutSeconds: 3
            }
          ]
        }
        // OpenTelemetry Collector sidecar
        {
          name: 'otelcol'
          image: 'otel/opentelemetry-collector-contrib:0.91.0'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
          ]
        }
      ]
      scale: {
        minReplicas: 2 // Increased from 1 for high availability
        maxReplicas: 10 // Increased from 1 for better scaling
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10' // Keep existing value
              }
            }
          }
        ]
      }
    }
  }
}

// Octopets Frontend Container App
resource octopetsFrontend 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'octopetsfe'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: 'system'
        }
      ]
    }
    template: {
      // Use placeholder image - will be updated by deployment script
      containers: [
        {
          name: 'octopetsfe'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'services__octopetsapi__https__0'
              value: 'https://${octopetsApi.properties.configuration.ingress.fqdn}'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

// Grant ACR pull permissions to Container Apps
resource apiAcrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, octopetsApi.id, 'acrpull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: octopetsApi.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource frontendAcrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, octopetsFrontend.id, 'acrpull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: octopetsFrontend.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output containerRegistryName string = acr.name
output containerAppEnvironmentName string = containerAppEnv.name
output logAnalyticsWorkspaceId string = logAnalytics.id
output applicationInsightsConnectionString string = appInsights.properties.ConnectionString
output octopetsApiAppName string = octopetsApi.name
output octopetsFrontendAppName string = octopetsFrontend.name
output octopetsApiUrl string = 'https://${octopetsApi.properties.configuration.ingress.fqdn}'
output octopetsFrontendUrl string = 'https://${octopetsFrontend.properties.configuration.ingress.fqdn}'
