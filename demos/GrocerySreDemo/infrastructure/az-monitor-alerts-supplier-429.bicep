targetScope = 'resourceGroup'

@description('Location for the Scheduled Query Rule resource (must be a supported Azure region; cannot be global).')
param location string = resourceGroup().location

@description('Name of the Grocery API Container App (e.g., ca-api-xxxx).')
param apiContainerAppName string

@description('Resource ID of the Log Analytics workspace where Container Apps logs are stored.')
param logAnalyticsWorkspaceResourceId string

@description('Optional: existing Action Group resource ID to notify (leave empty for no notifications).')
param actionGroupResourceId string = ''

@description('Optional: email address for a new Action Group receiver (leave empty to skip creating an Action Group).')
param alertEmailAddress string = ''

@description('Alert evaluation frequency (ISO 8601 duration).')
param evaluationFrequency string = 'PT1M'

@description('Alert window size (ISO 8601 duration).')
param windowSize string = 'PT5M'

@description('Threshold for number of matching log entries in the window.')
param threshold int = 1

@description('Severity (0-4). 0 is most severe.')
param severity int = 2

@description('Tags to apply to alert resources.')
param tags object = {
  demo: 'grocery-sre-demo'
  managedBy: 'bicep'
}

var shouldCreateActionGroup = !empty(alertEmailAddress)

resource createdActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (shouldCreateActionGroup) {
  name: 'ag-grocery-sre-demo'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'grocerySRE'
    enabled: true
    emailReceivers: [
      {
        name: 'primary-email'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

var actionGroupIds = !empty(actionGroupResourceId)
  ? [actionGroupResourceId]
  : (shouldCreateActionGroup ? [createdActionGroup.id] : [])

// Count log entries that include the supplier rate limit signal emitted by the API.
// The upstream app uses pino JSON logs with an errorCode field (SUPPLIER_RATE_LIMIT_429).
var kqlQuery = '''
ContainerAppConsoleLogs
| extend caName = coalesce(tostring(column_ifexists("ContainerAppName", "")), tostring(column_ifexists("ContainerAppName_s", "")))
| where caName == "${apiContainerAppName}"
| extend msg = coalesce(tostring(column_ifexists("Log_s", "")), tostring(column_ifexists("Log", "")), tostring(column_ifexists("Message", "")))
| where msg has "SUPPLIER_RATE_LIMIT_429"
'''

resource supplierRateLimitAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'Grocery API - Supplier rate limit (SUPPLIER_RATE_LIMIT_429)'
  location: location
  kind: 'LogAlert'
  tags: tags
  properties: {
    displayName: 'Grocery API - Supplier rate limit (SUPPLIER_RATE_LIMIT_429)'
    description: 'Fires when the Grocery API logs supplier rate limit events (SUPPLIER_RATE_LIMIT_429).'
    enabled: true
    severity: severity
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize

    // Scope to the workspace containing Container Apps logs.
    scopes: [
      logAnalyticsWorkspaceResourceId
    ]

    // Avoid deploy-time failures if the workspace tables aren't populated yet.
    skipQueryValidation: true

    criteria: {
      allOf: [
        {
          query: kqlQuery
          timeAggregation: 'Count'
          operator: 'GreaterThanOrEqual'
          threshold: threshold
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }

    actions: {
      actionGroups: actionGroupIds
      customProperties: {
        demo: 'grocery-sre-demo'
        signal: 'SUPPLIER_RATE_LIMIT_429'
        apiContainerAppName: apiContainerAppName
      }
    }

    autoMitigate: true
  }
}

output scheduledQueryRuleId string = supplierRateLimitAlert.id
output actionGroupId string = shouldCreateActionGroup ? createdActionGroup.id : actionGroupResourceId
