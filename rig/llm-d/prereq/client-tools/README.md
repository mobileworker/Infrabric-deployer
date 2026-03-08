# LLM-d Client Tools Pod

This directory contains manifests for deploying a client tools pod with all necessary tools for managing llm-d deployments.

## Overview

The client tools pod is a temporary deployment pod that provides tools needed for llm-d deployments:

- **kubectl** - Kubernetes CLI (uses OpenShift `oc` if available)
- **helm** v3.19.0 - Kubernetes package manager
- **helm diff** plugin v3.13.0 - Helm diff plugin for comparing releases
- **helmfile** v1.2.1 - Declarative Helm chart deployment tool
- **yq** v4+ - YAML processor

**Note:** This pod is automatically removed after deployment completes. Use the `guidellm-inference-test` overlay to verify deployments.

## Quick Start

### Deploy the Client Tools Pod

```bash
# Deploy all resources
oc apply -k rig/llm-d/prereq/client-tools

# Wait for pod to be ready
oc wait --for=condition=ready pod/llm-d-client -n llm-d --timeout=300s
```

### Use the Client Tools Pod

```bash
# Access the pod
oc exec -it llm-d-client -n llm-d -- /bin/bash

# Inside the pod, verify tools are available
kubectl version --client
helm version
helmfile version
yq --version
```

## What Gets Created

- **Namespace**: `llm-d` - Dedicated namespace for llm-d resources
- **ServiceAccount**: `llm-d-client` - With cluster-wide permissions for Gateway API and llm-d resources
- **ClusterRole**: `llm-d-client` - Permissions for managing Gateway API, InferencePools, and Kubernetes resources
- **ClusterRoleBinding**: Binds the ServiceAccount to the ClusterRole
- **ConfigMap**: `llm-d-install-tools` - Script to install client tools
- **Pod**: `llm-d-client` - Long-running pod with all tools pre-installed

## Permissions

The `llm-d-client` ServiceAccount has the following permissions:

- Full access to Gateway API resources (`gateway.networking.k8s.io`)
- Full access to Inference Extension resources (`inference.networking.k8s.io`)
- CRUD operations on core Kubernetes resources (pods, services, configmaps, secrets)
- CRUD operations on apps resources (deployments, statefulsets, daemonsets)
- CRUD operations on batch resources (jobs, cronjobs)
- Read-only access to CRDs

## Tool Versions

| Tool       | Version   | Location          |
|------------|-----------|-------------------|
| yq         | latest    | /tools/bin/yq     |
| kubectl    | latest    | /tools/bin/kubectl|
| helm       | v3.19.0   | /tools/bin/helm   |
| helm-diff  | v3.13.0   | /tools/helm/plugins |
| helmfile   | v1.2.1    | /tools/bin/helmfile |

## Cleanup

```bash
# Delete all resources
oc delete -k rig/llm-d/prereq/client-tools

# Or manually
oc delete pod llm-d-client -n llm-d
oc delete clusterrolebinding llm-d-client
oc delete clusterrole llm-d-client
oc delete namespace llm-d
```

## Usage Examples

### Deploy Gateway Provider from Client Pod

```bash
# Access the pod
oc exec -it llm-d-client -n llm-d -- /bin/bash

# Inside the pod
cd /workspace
# Copy or mount the gateway-provider manifests, then:
helmfile apply -f istio.helmfile.yaml
```

### Verify Gateway API Installation

```bash
oc exec -it llm-d-client -n llm-d -- kubectl api-resources --api-group=inference.networking.k8s.io
```

## Configuration

### KEEP_RUNNING Mode

The client pod behavior can be configured via the `KEEP_RUNNING` environment variable:

- **`KEEP_RUNNING=true`** (default): Pod runs indefinitely for interactive debugging and testing
- **`KEEP_RUNNING=false`**: Pod completes after tool installation (production mode)

#### Development Mode (Default)
Keep the pod running for interactive debugging:

```yaml
env:
  - name: KEEP_RUNNING
    value: "true"  # Default
```

Use the pod interactively:
```bash
oc exec -it llm-d-client -n llm-d -- /bin/bash
```

#### Production Mode
Make the pod complete after initialization:

```yaml
# In your overlay's kustomization.yaml
patches:
  - target:
      kind: Pod
      name: llm-d-client
    patch: |-
      - op: replace
        path: /spec/containers/0/env/3/value
        value: "false"
```

Or set via environment variable directly:
```bash
oc set env pod/llm-d-client -n llm-d KEEP_RUNNING=false
```

When `KEEP_RUNNING=false`:
- Pod status will change to `Completed` after tools are installed
- No resources consumed after initialization
- Perfect for production deployments where interactive access isn't needed

## Automatic Cleanup

The `llm-d-client` pod is automatically removed after deployment jobs complete. This happens in two ways:

1. **After successful deployment**: Each deployment job (Step 4: Cleanup) deletes the client pod once model servers are ready
2. **During cleanup overlay**: The cleanup job removes the client pod along with other resources

To verify deployments, use the guidellm-inference-test overlay instead:
```bash
oc apply -k rig/llm-d/overlays/guidellm-inference-test
oc logs -n llm-d job/llm-d-guidellm-inference-test -f
```

## Notes

- Tools are installed in `/tools/bin` and added to PATH
- Helm data is stored in `/tools/helm`
- Workspace directory `/workspace` is available for mounting configs
- By default, the pod runs indefinitely (`sleep infinity`) but is removed after deployment
- Set `KEEP_RUNNING=false` if the pod should complete immediately after tool installation
- Init container installs all tools before the main container starts
