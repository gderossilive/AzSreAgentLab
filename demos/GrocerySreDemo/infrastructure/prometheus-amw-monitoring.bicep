param location string = resourceGroup().location
param environmentId string
param acrName string
@description('Name of the Container App to deploy.')
param appName string = 'ca-prom-amw-monitoring'
@description('ACR image tag for the monitoring images.')
param imageTag string = 'latest'
@description('Full Azure Monitor Workspace Prometheus remote_write ingestion URL (DCE endpoint + DCR immutableId).')
param ingestionUrl string
@description('Unique value to force a new Container Apps revision (for example, a deployment timestamp).')
param deploymentStamp string = utcNow('yyyyMMddHHmmss')

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

resource promIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uami-prom-amw-monitoring'
  location: location
}

resource promApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${promIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      registries: [
        {
          server: '${acrName}.azurecr.io'
          identity: promIdentity.id
        }
      ]
      ingress: null
    }
    template: {
      containers: [
        {
          name: 'prometheus'
          image: '${acrName}.azurecr.io/grocery-prometheus:${imageTag}'
          resources: {
            cpu: json('0.5')
            memory: '1.5Gi'
          }
          env: [
            {
              name: 'DEPLOYMENT_STAMP'
              value: deploymentStamp
            }
          ]
        }
        {
          name: 'blackbox'
          image: '${acrName}.azurecr.io/grocery-blackbox-exporter:${imageTag}'
          resources: {
            cpu: json('0.25')
            memory: '0.25Gi'
          }
        }
        {
          name: 'remote-write-proxy'
          image: '${acrName}.azurecr.io/prom-remote-write-proxy:${imageTag}'
          resources: {
            cpu: json('0.25')
            memory: '0.25Gi'
          }
          env: [
            {
              name: 'INGESTION_URL'
              value: ingestionUrl
            }
            {
              name: 'TOKEN_RESOURCE'
              value: 'https://monitor.azure.com/'
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: promIdentity.properties.clientId
            }
            {
              name: 'DEPLOYMENT_STAMP'
              value: deploymentStamp
            }
          ]
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
  name: guid(acr.id, promIdentity.id, 'acrpull')
  scope: acr
  properties: {
    principalId: promIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

output principalId string = promIdentity.properties.principalId
output identityClientId string = promIdentity.properties.clientId
output appName string = promApp.name
