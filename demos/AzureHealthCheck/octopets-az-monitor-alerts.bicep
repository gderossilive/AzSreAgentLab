// Azure Monitor Metric Alerts for Octopets Container Apps
// Creates simple, reversible alerts for CPU, response time, and 5xx errors on:
// - octopetsapi (backend)
// - octopetsfe (frontend)

@description('Azure subscription ID where resources are deployed')
param subscriptionId string

@description('Resource group name containing the Octopets Container Apps')
param resourceGroupName string

@description('Name of the backend Container App')
param backendAppName string = 'octopetsapi'

@description('Name of the frontend Container App')
param frontendAppName string = 'octopetsfe'

@description('Optional Action Group resource ID to notify (leave empty for no notifications).')
param actionGroupResourceId string = ''

@description('Alert evaluation frequency (ISO 8601 duration).')
param evaluationFrequency string = 'PT1M'

@description('Alert window size (ISO 8601 duration).')
param windowSize string = 'PT5M'

@description('CPU threshold in NanoCores (0.5 core = 500,000,000; 70% = 350,000,000).')
param cpuUsageNanoCoresThreshold int = 350000000

@description('Backend average response time threshold in milliseconds.')
param backendResponseTimeMsThreshold int = 700

@description('Frontend average response time threshold in milliseconds.')
param frontendResponseTimeMsThreshold int = 400

@description('5xx requests threshold over the alert window.')
param http5xxRequestsThreshold int = 10

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Lab'
  Purpose: 'Octopets-Metric-Alerts'
  ManagedBy: 'Bicep'
}

var metricNamespace = 'Microsoft.App/containerApps'

// Construct Container App resource IDs
var backendAppResourceId = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.App/containerApps/${backendAppName}'
var frontendAppResourceId = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.App/containerApps/${frontendAppName}'

var actionsArray = empty(actionGroupResourceId)
  ? []
  : [
      {
        actionGroupId: actionGroupResourceId
      }
    ]

// ----------------------------
// Backend (octopetsapi)
// ----------------------------
resource apiHighCpu 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'High CPU Usage - Octopets API'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when Octopets API CPU usage exceeds threshold for the window.'
    severity: 2
    enabled: true
    scopes: [
      backendAppResourceId
    ]
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CpuHigh'
          metricName: 'UsageNanoCores'
          metricNamespace: metricNamespace
          operator: 'GreaterThan'
          threshold: cpuUsageNanoCoresThreshold
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: actionsArray
  }
}

resource apiHighLatency 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'High Response Time - Octopets API'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when Octopets API average response time exceeds threshold for 2xx responses only.'
    severity: 2
    enabled: true
    scopes: [
      backendAppResourceId
    ]
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ResponseTimeHigh'
          metricName: 'ResponseTime'
          metricNamespace: metricNamespace
          operator: 'GreaterThan'
          threshold: backendResponseTimeMsThreshold
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'statusCodeCategory'
              operator: 'Include'
              values: [
                '2xx'
              ]
            }
          ]
        }
      ]
    }
    autoMitigate: true
    actions: actionsArray
  }
}

resource apiHttp5xx 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'HTTP 5xx - Octopets API'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when Octopets API returns too many 5xx responses in the window.'
    severity: 1
    enabled: true
    scopes: [
      backendAppResourceId
    ]
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xx'
          metricName: 'Requests'
          metricNamespace: metricNamespace
          operator: 'GreaterThan'
          threshold: http5xxRequestsThreshold
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'statusCodeCategory'
              operator: 'Include'
              values: [
                '5xx'
              ]
            }
          ]
        }
      ]
    }
    autoMitigate: true
    actions: actionsArray
  }
}

// ----------------------------
// Frontend (octopetsfe)
// ----------------------------
resource feHighCpu 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'High CPU Usage - Octopets FE'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when Octopets FE CPU usage exceeds threshold for the window.'
    severity: 2
    enabled: true
    scopes: [
      frontendAppResourceId
    ]
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CpuHigh'
          metricName: 'UsageNanoCores'
          metricNamespace: metricNamespace
          operator: 'GreaterThan'
          threshold: cpuUsageNanoCoresThreshold
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: actionsArray
  }
}

resource feHighLatency 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'High Response Time - Octopets FE'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when Octopets FE average response time exceeds threshold for 2xx responses only.'
    severity: 2
    enabled: true
    scopes: [
      frontendAppResourceId
    ]
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ResponseTimeHigh'
          metricName: 'ResponseTime'
          metricNamespace: metricNamespace
          operator: 'GreaterThan'
          threshold: frontendResponseTimeMsThreshold
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'statusCodeCategory'
              operator: 'Include'
              values: [
                '2xx'
              ]
            }
          ]
        }
      ]
    }
    autoMitigate: true
    actions: actionsArray
  }
}

resource feHttp5xx 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'HTTP 5xx - Octopets FE'
  location: 'global'
  tags: tags
  properties: {
    description: 'Triggers when Octopets FE returns too many 5xx responses in the window.'
    severity: 1
    enabled: true
    scopes: [
      frontendAppResourceId
    ]
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xx'
          metricName: 'Requests'
          metricNamespace: metricNamespace
          operator: 'GreaterThan'
          threshold: http5xxRequestsThreshold
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'statusCodeCategory'
              operator: 'Include'
              values: [
                '5xx'
              ]
            }
          ]
        }
      ]
    }
    autoMitigate: true
    actions: actionsArray
  }
}

output alertRuleNames array = [
  apiHighCpu.name
  apiHighLatency.name
  apiHttp5xx.name
  feHighCpu.name
  feHighLatency.name
  feHttp5xx.name
]
