# ArcLab environment (Arc servers + Arc-connected k3s)

This environment describes the **ArcLab** resource group and the key resources that are relevant for Azure SRE Agent knowledge.

- Resource group: `rg-arclab-arclab-20260127-112946-u3y`
- Subscription: `06dbbc7b-2363-4dd4-9803-95d07f1a8d3e`
- Primary location: `northeurope`

> Scope note: this document intentionally filters to **Arc resources (VMs + Kubernetes)**, **Azure Monitor workspace**, **Log Analytics workspaces**, and **how to obtain kubeconfig**. The RG contains other resources (DCR/DCE, alert rule groups, extensions, etc.) that are not listed here.

## Arc-enabled servers (Azure Arc)

Azure Arc-enabled machines (providers `Microsoft.HybridCompute/machines`) in this RG:

- `win-arclab-01` (Windows) — status: Connected
- `sql-arclab-01` (Windows) — status: Connected
- `lin-arclab-01` (Linux) — status: Connected

These Arc resources are backed by Azure VMs in the same RG (useful when correlating guest logs/updates/networking):

- `win-arclab-01` (Windows) — `Standard_B2s` — Public IP: `40.112.74.93`
- `sql-arclab-01` (Windows) — `Standard_B2s` — Public IP: `20.238.102.144`
- `lin-arclab-01` (Linux) — `Standard_B2s` — Public IP: `20.234.83.55`

## Kubernetes (Arc-enabled cluster)

Arc-enabled Kubernetes connected cluster (provider `Microsoft.Kubernetes/connectedClusters`):

- Cluster: `k3s-arclab-01`
- Location: `northeurope`

Underlying VM (provider `Microsoft.Compute/virtualMachines`):

- `k3s-arclab-01` (Linux) — `Standard_B2ms` — Public IP: `74.234.112.79`

## Monitoring

### Azure Monitor workspace (AMW)

Azure Monitor workspace (provider `Microsoft.Monitor/accounts`):

- `arclab-amw` (northeurope)

This workspace is typically used for **Azure Monitor managed Prometheus** / metrics pipeline scenarios.

### Log Analytics workspaces (LAW)

Log Analytics workspaces (provider `Microsoft.OperationalInsights/workspaces`):

- `log-arclab-arclab-20260127-112946-u3y` (northeurope) — retention: 30 days
- `workspacewardxkswwslfy` (swedencentral) — retention: 30 days

If you need the workspace GUIDs (for certain API-based flows), query:

- `az resource show --ids <lawResourceId> --query properties.customerId -o tsv`

## Kubeconfig for the cluster (safe acquisition)

Do **not** paste kubeconfig contents into chats/logs and do **not** commit kubeconfig files to git.

### Preferred: generate a kubeconfig context via Azure Arc proxy

This uses your Azure identity to create/update a kubeconfig entry and proxy traffic to the Arc-connected cluster.

- Update your default kubeconfig (`~/.kube/config`):
  - `az connectedk8s proxy -g rg-arclab-arclab-20260127-112946-u3y -n k3s-arclab-01`

- Write to a dedicated file instead (recommended for demo isolation):
  - `az connectedk8s proxy -g rg-arclab-arclab-20260127-112946-u3y -n k3s-arclab-01 -f ./kubeconfig-arclab.yaml --kube-context arclab-k3s`
  - Then use it: `KUBECONFIG=./kubeconfig-arclab.yaml kubectl get nodes`

- Print kubeconfig YAML to stdout (use carefully):
  - `az connectedk8s proxy -g rg-arclab-arclab-20260127-112946-u3y -n k3s-arclab-01 -f -`

### Alternate: obtain the native k3s kubeconfig from the VM

Azure does not “store” the original cluster kubeconfig; for k3s it is usually on the node (commonly at `/etc/rancher/k3s/k3s.yaml`). A typical workflow is:

1) SSH to `k3s-arclab-01` (using your approved admin access path).
2) Copy the kubeconfig file to your workstation.
3) Edit the `clusters[].cluster.server` field to point at a reachable API server address (for example the VM’s public IP `74.234.112.79` if that’s how you access it, or a private IP/VPN endpoint if applicable).

## Quick inventory commands

- Arc machines:
  - `az connectedmachine list -g rg-arclab-arclab-20260127-112946-u3y --query "[].{name:name, os:osType, status:status}" -o table`

- Arc-connected k8s clusters:
  - `az connectedk8s list -g rg-arclab-arclab-20260127-112946-u3y --query "[].{name:name, location:location}" -o table`

- Monitor + Log Analytics workspaces (by type):
  - `az resource list -g rg-arclab-arclab-20260127-112946-u3y --resource-type Microsoft.Monitor/accounts --query "[].name" -o tsv`
  - `az resource list -g rg-arclab-arclab-20260127-112946-u3y --resource-type Microsoft.OperationalInsights/workspaces --query "[].name" -o tsv`
