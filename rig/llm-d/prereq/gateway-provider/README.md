# Gateway Provider (Istio) Installation

This directory contains manifests for deploying Istio as the Gateway provider with Gateway API Inference Extension support for llm-d.

## Overview

The Gateway Provider provides:

- **Gateway API CRDs** (v1.4.0) - Kubernetes Gateway API resources
- **Gateway API Inference Extension CRDs** (v1.3.0) - InferencePool and InferenceObjective support
- **Istio** (v1.28.1) - Service mesh and Gateway implementation
  - `istio-base` - Base Istio CRDs
  - `istiod` - Istio control plane with Inference Extension enabled

## Prerequisites

- OpenShift cluster with cluster-admin permissions
- `llm-d` namespace created (automatically created by client-tools)
- `llm-d-client` ServiceAccount with cluster permissions

## Quick Start

### Deploy Gateway Provider

```bash
# Deploy all resources (CRDs + Istio)
oc apply -k rig/llm-d/prereq/gateway-provider

# Monitor CRD installation
oc logs -f job/install-gateway-crds -n llm-d

# Monitor Istio installation
oc logs -f job/install-istio -n llm-d
```

### Verification

```bash
# Verify Gateway API CRDs
oc api-resources --api-group=gateway.networking.k8s.io

# Verify Inference Extension CRDs
oc api-resources --api-group=inference.networking.k8s.io

# Expected output includes:
#   inferencepools   infpool   inference.networking.k8s.io/v1   true   InferencePool

# Verify Istio pods
oc get pods -n istio-system

# Expected output:
#   NAME                      READY   STATUS    RESTARTS   AGE
#   istiod-86cc5d77df-xxxxx   1/1     Running   0          <time>

# Verify GatewayClasses
oc get gatewayclass

# Expected output:
#   NAME           CONTROLLER                    ACCEPTED   AGE
#   istio          istio.io/gateway-controller   True       <time>
#   istio-remote   istio.io/unmanaged-gateway    True       <time>

# Verify Helm releases (requires helm client)
helm list -n istio-system --kubeconfig /path/to/kubeconfig

# Expected output:
#   NAME      	NAMESPACE   	REVISION	STATUS  	CHART        	APP VERSION
#   istio-base	istio-system	1       	deployed	base-1.28.1  	1.28.1
#   istiod    	istio-system	1       	deployed	istiod-1.28.1	1.28.1

# Note: The llm-d-client pod is automatically removed after deployments complete
```

## What Gets Deployed

### Job 1: Install Gateway CRDs (Wave 10, PreSync)

- **Gateway API CRDs** v1.4.0
  - GatewayClass, Gateway, HTTPRoute, etc.
  - May already be managed by OpenShift (warnings are OK)
- **Gateway API Inference Extension CRDs** v1.3.0
  - InferencePool, InferenceObjective

### Job 2: Install Istio (Wave 20, Sync)

- **Istio Base** - Installs Istio base CRDs
- **Istiod** - Instio control plane with:
  - `ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true` - Enables InferencePool support
  - Gateway controller for managing Gateway resources

## ArgoCD Sync Waves

The deployment uses sync waves for proper ordering:

- **Wave 10 (PreSync)**: Install Gateway API CRDs
- **Wave 20 (Sync)**: Install Istio

This ensures CRDs are available before Istio is installed.

## Configuration

### Istio Version

Default: `1.28.1`

To change the version, edit `install-istio-job.yaml`:

```yaml
env:
  - name: ISTIO_VERSION
    value: "1.28.1"
```

### Istio Configuration

The following Istio settings are configured:

- **Inference Extension**: Enabled via environment variables
- **Gateway Controller**: Automatically installed
- **Hub**: `docker.io/istio`
- **Tag**: Matches Istio version

### IPv4 Enforcement

The installation uses `curl -4` to force IPv4 connections when downloading Istio charts. This avoids IPv6 connectivity issues with Google Storage.

## Troubleshooting

### Job Fails to Install CRDs

Check job logs:
```bash
oc logs job/install-gateway-crds -n llm-d
oc describe job/install-gateway-crds -n llm-d
```

If Gateway API CRDs fail (managed by OpenShift):
```
⚠️ Gateway API CRDs may already be managed by OpenShift (this is OK)
```
This is expected - OpenShift's Ingress Operator manages base Gateway API CRDs.

### Istio Installation Fails

Check job logs:
```bash
oc logs job/install-istio -n llm-d
```

Common issues:
- **Namespace not found**: Ensure `istio-system` namespace is created
- **Helm timeout**: Increase `--timeout` in the job
- **Image pull errors**: Check network connectivity to `docker.io/istio`

### GatewayClass Not Accepted

Check GatewayClass status:
```bash
oc describe gatewayclass istio
```

Look for conditions indicating why it's not accepted.

### InferencePool CRD Not Found

Verify CRDs were installed:
```bash
oc get crd | grep inference.networking
```

Expected output:
```
inferencepools.inference.networking.k8s.io
```

If missing, re-run CRD installation:
```bash
oc delete job install-gateway-crds -n llm-d
oc apply -k rig/llm-d/prereq/gateway-provider
```

## Cleanup

```bash
# Delete Istio
oc exec -it llm-d-client -n llm-d -- helm uninstall istiod -n istio-system
oc exec -it llm-d-client -n llm-d -- helm uninstall istio-base -n istio-system

# Delete namespace
oc delete namespace istio-system

# Delete jobs
oc delete -k rig/llm-d/prereq/gateway-provider
```

## Manual Installation (Alternative)

If the automated jobs fail, you can install manually using the client tools pod:

```bash
# Access client pod
oc exec -it llm-d-client -n llm-d -- /bin/bash

# Inside the pod, follow the manual installation guide
# See: /Users/bbenshab/workspace/llm-d/guides/prereq/gateway-provider/ISTIO_MANUAL_INSTALL.md
```

## References

- [Istio Helm Installation Guide](https://istio.io/latest/docs/setup/install/helm/)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/)
- [llm-d Gateway Provider Guide](https://github.com/llm-d/llm-d/tree/main/guides/prereq/gateway-provider)

## Notes

- Jobs have `ttlSecondsAfterFinished: 600` - auto-deleted after 10 minutes
- Jobs use `backoffLimit: 3` - retry up to 3 times on failure
- ServiceAccount `llm-d-client` must exist (created by client-tools deployment)
- OpenShift Gateway API CRDs (v1.2.1) are managed by Ingress Operator - this is expected
- Istio v1.28.1 is compatible with Gateway API v1.2.1
