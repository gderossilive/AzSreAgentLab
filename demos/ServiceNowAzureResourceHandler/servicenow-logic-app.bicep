// Azure Logic App for ServiceNow Integration
// Receives webhooks from Azure Monitor and forwards to ServiceNow with authentication

@description('Azure subscription ID where resources are deployed')
param subscriptionId string

@description('Resource group name for Logic App deployment')
param resourceGroupName string

@description('ServiceNow instance name (without .service-now.com)')
param serviceNowInstance string

@description('ServiceNow username for Basic Authentication')
@secure()
param serviceNowUsername string

@description('ServiceNow password for Basic Authentication')
@secure()
param serviceNowPassword string

@description('Location for Logic App')
param location string = 'swedencentral'

@description('Tags to apply to resources')
param tags object = {
  Environment: 'Lab'
  Purpose: 'SRE-Agent-Demo'
  ManagedBy: 'Bicep'
}

// Logic App workflow
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'ServiceNow-Incident-Creator'
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                schemaId: { type: 'string' }
                data: { type: 'object' }
              }
            }
          }
        }
      }
      actions: {
        Parse_Alert_Data: {
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()'
            schema: {
              type: 'object'
              properties: {
                schemaId: { type: 'string' }
                data: {
                  type: 'object'
                  properties: {
                    essentials: {
                      type: 'object'
                      properties: {
                        alertRule: { type: 'string' }
                        severity: { type: 'string' }
                        monitorCondition: { type: 'string' }
                        description: { type: 'string' }
                        firedDateTime: { type: 'string' }
                      }
                    }
                    alertContext: { type: 'object' }
                  }
                }
              }
            }
          }
          runAfter: {}
        }
        Create_ServiceNow_Incident: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://${serviceNowInstance}.service-now.com/api/now/table/incident'
            headers: {
              'Content-Type': 'application/json'
              'Accept': 'application/json'
              'Authorization': 'Basic @{base64(concat(\'${serviceNowUsername}\', \':\', \'${serviceNowPassword}\'))}'
            }
            body: {
              short_description: '@{body(\'Parse_Alert_Data\')?[\'data\']?[\'essentials\']?[\'alertRule\']}'
              description: 'Azure Monitor Alert\n\nAlert Rule: @{body(\'Parse_Alert_Data\')?[\'data\']?[\'essentials\']?[\'alertRule\']}\nSeverity: @{body(\'Parse_Alert_Data\')?[\'data\']?[\'essentials\']?[\'severity\']}\nCondition: @{body(\'Parse_Alert_Data\')?[\'data\']?[\'essentials\']?[\'monitorCondition\']}\nFired: @{body(\'Parse_Alert_Data\')?[\'data\']?[\'essentials\']?[\'firedDateTime\']}\n\nFull Alert Data:\n@{body(\'Parse_Alert_Data\')}'
              priority: 2
              state: 1
              caller_id: 'Azure Monitor'
              category: 'inquiry'
              subcategory: 'azure'
              impact: 2
              urgency: 2
            }
          }
          runAfter: {
            Parse_Alert_Data: [
              'Succeeded'
            ]
          }
        }
        Response: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: {
              status: 'Incident created'
              incident: '@{if(startsWith(trim(string(body(\'Create_ServiceNow_Incident\'))), \'{\'), json(body(\'Create_ServiceNow_Incident\'))?[\'result\']?[\'number\'], null)}'
              sys_id: '@{if(startsWith(trim(string(body(\'Create_ServiceNow_Incident\'))), \'{\'), json(body(\'Create_ServiceNow_Incident\'))?[\'result\']?[\'sys_id\'], null)}'
              raw_response: '@{string(body(\'Create_ServiceNow_Incident\'))}'
            }
          }
          runAfter: {
            Create_ServiceNow_Incident: [
              'Succeeded'
            ]
          }
        }
      }
      outputs: {}
    }
  }
}

// Output the Logic App callback URL
output logicAppCallbackUrl string = listCallbackUrl('${logicApp.id}/triggers/manual', '2019-05-01').value
output logicAppName string = logicApp.name
output logicAppResourceId string = logicApp.id
