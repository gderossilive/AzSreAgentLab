param location string = resourceGroup().location
param environmentId string
param jiraUrl string
param jiraUsername string
@secure()
param jiraApiToken string

resource mcpJiraApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-mcp-jira'
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
          name: 'jira-token'
          value: jiraApiToken
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'mcp-jira'
          image: 'ghcr.io/sooperset/mcp-atlassian:latest'
          args: ['--transport', 'streamable-http', '--host', '0.0.0.0', '--port', '8000']
          env: [
            {
              name: 'JIRA_URL'
              value: jiraUrl
            }
            {
              name: 'JIRA_USERNAME'
              value: jiraUsername
            }
            {
              name: 'JIRA_API_TOKEN'
              secretRef: 'jira-token'
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

output mcpJiraUrl string = 'https://${mcpJiraApp.properties.configuration.ingress.fqdn}/mcp'
