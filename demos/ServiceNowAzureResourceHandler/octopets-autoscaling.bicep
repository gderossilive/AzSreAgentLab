// Auto-scaling configuration for Octopets Container Apps
// INC0010041: Enable auto-scaling to handle memory pressure and traffic spikes
// Configures KEDA-based scaling rules for CPU and memory

@description('Azure subscription ID where resources are deployed')
param subscriptionId string

@description('Resource group name containing the Octopets Container Apps')
param resourceGroupName string

@description('Name of the backend Container App')
param backendAppName string = 'octopetsapi'

@description('Location for the container app')
param location string = 'swedencentral'

@description('Minimum number of replicas')
param minReplicas int = 1

@description('Maximum number of replicas')
param maxReplicas int = 3

@description('CPU threshold percentage for scaling (0-100)')
param cpuScaleThreshold int = 70

@description('Memory threshold percentage for scaling (0-100)')
param memoryScaleThreshold int = 70

@description('HTTP concurrent requests threshold for scaling')
param httpConcurrentRequestsThreshold int = 10

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Lab'
  Purpose: 'Octopets-AutoScaling'
  ManagedBy: 'Bicep'
  IncidentReference: 'INC0010041'
}

// Get reference to existing container app
resource containerApp 'Microsoft.App/containerApps@2023-05-01' existing = {
  name: backendAppName
  scope: resourceGroup(subscriptionId, resourceGroupName)
}

// Update container app with auto-scaling configuration
resource containerAppUpdate 'Microsoft.App/containerApps@2023-05-01' = {
  name: backendAppName
  location: location
  tags: tags
  properties: {
    environmentId: containerApp.properties.environmentId
    configuration: containerApp.properties.configuration
    template: {
      containers: containerApp.properties.template.containers
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'cpu-scaling-rule'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: string(cpuScaleThreshold)
              }
            }
          }
          {
            name: 'memory-scaling-rule'
            custom: {
              type: 'memory'
              metadata: {
                type: 'Utilization'
                value: string(memoryScaleThreshold)
              }
            }
          }
          {
            name: 'http-scaling-rule'
            http: {
              metadata: {
                concurrentRequests: string(httpConcurrentRequestsThreshold)
              }
            }
          }
        ]
      }
    }
  }
}

output containerAppName string = containerApp.name
output minReplicas int = minReplicas
output maxReplicas int = maxReplicas
output scalingRules array = [
  'cpu-scaling-rule'
  'memory-scaling-rule'
  'http-scaling-rule'
]
