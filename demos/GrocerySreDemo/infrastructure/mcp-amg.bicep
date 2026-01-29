param location string = resourceGroup().location
param environmentId string
param acrName string
param grafanaName string
param grafanaEndpoint string
@description('Name of the Container App to deploy (use a different name like ca-mcp-amg-debug for diagnostics without impacting the primary app).')
param appName string = 'ca-mcp-amg'
@description('When false, deploy without ingress (avoids port-based startup checks so you can inspect runtime behavior even if nothing is listening on 8000).')
param ingressEnabled bool = true
@description('When true, run amg-mcp under a shell wrapper and keep the container alive for debugging (prints logs then sleeps).')
param debugHold bool = false

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' existing = {
  name: grafanaName
}

resource mcpAmgIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'uami-mcp-amg'
  location: location
}

resource mcpAmgApp 'Microsoft.App/containerApps@2023-05-01' = {
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
      // Important: we omit the ingress property entirely when ingressEnabled=false.
      // Using `ingress: null` may be ignored by ARM during updates, leaving ingress enabled.
      ...union(
        {
          registries: [
            {
              server: '${acrName}.azurecr.io'
              identity: mcpAmgIdentity.id
            }
          ]
        },
        ingressEnabled
          ? {
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
            }
          : {}
      )
    }
    template: {
      containers: [
        debugHold
          ? {
              name: 'amg-mcp'
              image: '${acrName}.azurecr.io/amg-mcp:latest'
              command: [
                '/bin/sh'
              ]
              args: [
                '-lc'
                // Keep PID 1 alive even if amg-mcp exits, so we can inspect logs/exec.
                'set -eux; echo "[amg-mcp] wrapper starting"; uname -a; id; ls -la /usr/local/bin/amg-mcp; echo "[amg-mcp] env snapshot"; env | sort | sed -n "1,120p"; dump_ports(){ echo "[amg-mcp] /proc/net/tcp* (first 60 lines)"; (cat /proc/net/tcp /proc/net/tcp6 2>/dev/null || true) | sed -n "1,60p"; echo "[amg-mcp] matches for :8000 (hex :1F40)"; (cat /proc/net/tcp /proc/net/tcp6 2>/dev/null || true) | grep -E ":1F40" | head -n 20 || true; }; dump_ports; echo "[amg-mcp] starting amg-mcp (background)"; /usr/local/bin/amg-mcp --AmgMcpOptions:Transport=Sse --AmgMcpOptions:SseListenAddress=http://0.0.0.0:8000 --AmgMcpOptions:AzureManagedGrafanaEndpoint="${grafanaEndpoint}" 2>&1 & pid=$!; sleep 2; echo "[amg-mcp] after 2s (pid=$pid)"; dump_ports; echo "[amg-mcp] monitoring ports for 60s"; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do sleep 5; echo "[amg-mcp] t=$((i*5))s"; dump_ports; done; echo "[amg-mcp] waiting for amg-mcp pid=$pid"; wait "$pid"; ec=$?; echo "[amg-mcp] exited code=$ec"; sleep 3600'
              ]
              env: [
                {
                  name: 'AmgMcpOptions__AzureManagedGrafanaEndpoint'
                  value: grafanaEndpoint
                }
                {
                  name: 'AZURE_CLIENT_ID'
                  value: mcpAmgIdentity.properties.clientId
                }
                {
                  name: 'ASPNETCORE_URLS'
                  value: 'http://+:8000'
                }
              ]
              resources: {
                cpu: json('0.25')
                memory: '0.5Gi'
              }
            }
          : {
              name: 'amg-mcp'
              image: '${acrName}.azurecr.io/amg-mcp:latest'
              // Stdio pivot: run as a stdio MCP server (no HTTP listener). We keep stdin open via a pipe.
              // The process may exit when no client is attached; restart in a simple loop to keep it available.
              command: [
                '/bin/sh'
              ]
              args: [
                '-lc'
                'set -eu; while true; do echo "[amg-mcp] starting (stdio transport)"; tail -f /dev/null | /usr/local/bin/amg-mcp --AmgMcpOptions:Transport=Stdio --AmgMcpOptions:AzureManagedGrafanaEndpoint="${grafanaEndpoint}" 2>&1; ec=$?; echo "[amg-mcp] exited code=$ec"; sleep 1; done'
              ]
              env: [
                {
                  name: 'AmgMcpOptions__AzureManagedGrafanaEndpoint'
                  value: grafanaEndpoint
                }
                {
                  name: 'AZURE_CLIENT_ID'
                  value: mcpAmgIdentity.properties.clientId
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

output mcpAmgSseUrl string = ingressEnabled ? 'https://${mcpAmgApp.properties.configuration.ingress.fqdn}/sse' : ''
output mcpAmgPrincipalId string = mcpAmgIdentity.properties.principalId
