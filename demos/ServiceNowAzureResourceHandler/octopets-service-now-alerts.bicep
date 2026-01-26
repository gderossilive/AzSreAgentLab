// Azure Monitor Alert Rules for Octopets Container Apps
// Deploys metric alerts and ServiceNow action group for automated incident creation

@description('Azure subscription ID where resources are deployed')
param subscriptionId string

@description('Resource group name containing the Octopets Container Apps')
param resourceGroupName string

@description('Name of the backend Container App')
param backendAppName string = 'octopetsapi'

@description('Name of the frontend Container App')
param frontendAppName string = 'octopetsfe'

@description('ServiceNow instance URL (without https://)')
param serviceNowInstanceUrl string

@description('ServiceNow webhook URL for incident creation')
param serviceNowWebhookUrl string

@description('Location for alert rules and action group')
param location string = 'swedencentral'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Lab'
  Purpose: 'SRE-Agent-Demo'
  ManagedBy: 'Bicep'
}

// Construct Container App resource IDs
var backendAppResourceId = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.App/containerApps/${backendAppName}'
var frontendAppResourceId = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.App/containerApps/${frontendAppName}'

// Action Group for ServiceNow webhook
resource serviceNowActionGroup 'microsoft.insights/actionGroups@2023-01-01' = {
  name: 'ServiceNow-ActionGroup'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'SNow-AG'
    enabled: true
    webhookReceivers: [
      {
        name: 'ServiceNow-Webhook'
        serviceUri: serviceNowWebhookUrl
        useCommonAlertSchema: true
      }
    ]
  }
}

// Alert Rule 1: High Memory Usage (80% threshold)
resource highMemoryAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'High Memory Usage - Octopets API'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when backend container app memory usage exceeds 80% for 5 minutes'
    severity: 2  // Warning
    enabled: true
    scopes: [
      backendAppResourceId
    ]
    evaluationFrequency: 'PT1M'  // Every 1 minute
    windowSize: 'PT5M'  // 5 minute window
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'MemoryUsageHigh'
          metricName: 'WorkingSetBytes'
          metricNamespace: 'Microsoft.App/containerApps'
          operator: 'GreaterThan'
          threshold: 858993459  // 80% of 1GB (1073741824 bytes)
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: serviceNowActionGroup.id
        webHookProperties: {
          alertName: 'High Memory Usage - Octopets API'
          resourceName: backendAppName
          resourceGroup: resourceGroupName
          severity: 'Warning'
        }
      }
    ]
  }
}

// Alert Rule 2: Very High Memory Usage (90% threshold)
resource veryHighMemoryAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Very High Memory Usage - Octopets API'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when backend container app memory usage exceeds 90% for 5 minutes'
    severity: 1  // Error
    enabled: true
    scopes: [
      backendAppResourceId
    ]
    evaluationFrequency: 'PT1M'  // Every 1 minute
    windowSize: 'PT5M'  // 5 minute window
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'MemoryUsageVeryHigh'
          metricName: 'WorkingSetBytes'
          metricNamespace: 'Microsoft.App/containerApps'
          operator: 'GreaterThan'
          threshold: 966367641  // 90% of 1GB (1073741824 bytes)
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: serviceNowActionGroup.id
        webHookProperties: {
          alertName: 'Very High Memory Usage - Octopets API'
          resourceName: backendAppName
          resourceGroup: resourceGroupName
          severity: 'Error'
        }
      }
    ]
  }
}

// Alert Rule 3: High Error Rate (>10 errors/minute)
resource highErrorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'High Error Rate - Octopets API'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when backend API has more than 10 failed requests per minute for 5 minutes'
    severity: 2  // Warning
    enabled: true
    scopes: [
      backendAppResourceId
    ]
    evaluationFrequency: 'PT1M'  // Every 1 minute
    windowSize: 'PT5M'  // 5 minute window
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ErrorRateHigh'
          metricName: 'Requests'
          metricNamespace: 'Microsoft.App/containerApps'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'statusCodeCategory'
              operator: 'Include'
              values: [
                '5xx'  // Server errors (5xx)
              ]
            }
          ]
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: serviceNowActionGroup.id
        webHookProperties: {
          alertName: 'High Error Rate - Octopets API'
          resourceName: backendAppName
          resourceGroup: resourceGroupName
          severity: 'Warning'
        }
      }
    ]
  }
}

// Alert Rule 4: Critical Error Rate (>50 errors/minute)
resource criticalErrorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Critical Error Rate - Octopets API'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when backend API has more than 50 failed requests per minute for 5 minutes'
    severity: 0  // Critical
    enabled: true
    scopes: [
      backendAppResourceId
    ]
    evaluationFrequency: 'PT1M'  // Every 1 minute
    windowSize: 'PT5M'  // 5 minute window
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ErrorRateCritical'
          metricName: 'Requests'
          metricNamespace: 'Microsoft.App/containerApps'
          operator: 'GreaterThan'
          threshold: 50
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'statusCodeCategory'
              operator: 'Include'
              values: [
                '5xx'  // Server errors (5xx)
              ]
            }
          ]
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: serviceNowActionGroup.id
        webHookProperties: {
          alertName: 'Critical Error Rate - Octopets API'
          resourceName: backendAppName
          resourceGroup: resourceGroupName
          severity: 'Critical'
        }
      }
    ]
  }
}

// Outputs
output actionGroupId string = serviceNowActionGroup.id
output actionGroupName string = serviceNowActionGroup.name
output highMemoryAlertId string = highMemoryAlert.id
output veryHighMemoryAlertId string = veryHighMemoryAlert.id
output highErrorRateAlertId string = highErrorRateAlert.id
output criticalErrorRateAlertId string = criticalErrorRateAlert.id

output alertRuleNames array = [
  highMemoryAlert.name
  veryHighMemoryAlert.name
  highErrorRateAlert.name
  criticalErrorRateAlert.name
]
