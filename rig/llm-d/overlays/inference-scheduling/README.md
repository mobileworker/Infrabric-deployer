# Inference Scheduling Deployment

## Overview

This deployment demonstrates intelligent inference scheduling with load-aware and prefix-cache aware balancing for vLLM deployments. It reduces tail latency and increases throughput through smart request routing.

**Model**: Qwen/Qwen3-32B (default)

**Features**:
- Approximate prefix cache aware scoring
- Load-aware balancing
- Reduces tail latency
- Increases throughput

## Hardware Requirements

- **Default**: 16 GPUs (8 replicas × 2 GPUs each)
- **Minimum**: 2 GPUs
- **Supported Accelerators**:
  - NVIDIA GPUs
  - AMD GPUs
  - Intel XPU/GPUs
  - Intel Gaudi (HPU)
  - Google Cloud TPUs

## Prerequisites

All prerequisites are automatically deployed:

- ✅ Namespace creation
- ✅ Client tools pod (kubectl, helm, helmfile, yq) - automatically removed after deployment
- ✅ Gateway provider (Istio with Inference Extension)
- ✅ HuggingFace token secret (empty by default, update for gated models)

## Quick Start

### 1. Deploy Inference Scheduling

**Single command deployment**:

```bash
oc apply -k rig/llm-d/overlays/inference-scheduling
```

This automatically:
1. Creates namespace and RBAC
2. Deploys client tools pod
3. Deploys Istio gateway provider
4. Waits for gateway to be ready
5. Deploys inference scheduling workload (12 replicas dynamically calculated)
6. Removes client tools pod after deployment completes

**No manual steps required!**

### 2. (Optional) Add HuggingFace Token

An empty HuggingFace token secret is automatically created. For the gated Qwen3-32B model, add your token:

```bash
export HF_TOKEN=hf_your_token_here
oc create secret generic llm-d-hf-token \
  --from-literal="HF_TOKEN=${HF_TOKEN}" \
  --namespace llm-d \
  --dry-run=client -o yaml | oc apply -f -

# Restart pods to pick up the token
oc rollout restart deployment -n llm-d
```

### 3. Verify Installation

```bash
# Check Gateway API
oc api-resources --api-group=inference.networking.k8s.io

# Check Istio
oc get pods -n istio-system

# Check GatewayClass
oc get gatewayclass
```

## Deployment Details

### Default Configuration

- **Replicas**: 8
- **GPUs per replica**: 2
- **Total GPUs**: 16
- **Model**: Qwen/Qwen3-32B
- **Tensor Parallelism**: 2

### Customization

#### Change the Model

You can use any vLLM-compatible model by editing `ms-manifests-configmap.yaml`:

```bash
# Edit the ConfigMap
vi rig/llm-d/overlays/inference-scheduling/ms-manifests-configmap.yaml

# Update the MODEL environment variable
env:
  - name: MODEL
    value: "mistralai/Mixtral-8x7B-Instruct-v0.1"  # Your custom model
```

Supported models: Llama, Mistral, Mixtral, Qwen, Phi, DeepSeek, and more. See [vLLM supported models](https://docs.vllm.ai/en/latest/models/supported_models.html).

**Note**: For gated models, update the HuggingFace token secret before deploying.

#### Adjust GPU Count

To use fewer GPUs, modify `replicas` in the deployment configuration:

```yaml
# For 2 GPUs total
replicas: 1

# For 4 GPUs total
replicas: 2
```

### CPU-Only Deployment

For CPU-only deployment (no GPUs):
- **Requirements**: 64 cores, 64GB RAM per replica
- See deployment configuration for CPU-specific settings

## Architecture

```
User Request
     ↓
HTTPRoute (Gateway API)
     ↓
InferencePool (Inference Scheduler)
     ↓
vLLM Model Server Replicas (8x)
     ↓
Qwen3-32B Model
```

## Monitoring

TODO: Add monitoring configuration

## Troubleshooting

### Prerequisites Not Ready

```bash
# Check client tools
oc get pod llm-d-client -n llm-d

# Check Gateway CRDs
oc get crd | grep inference.networking

# Check Istio
oc get pods -n istio-system
```

### Model Server Issues

TODO: Add troubleshooting steps once deployment is implemented

## References

- [llm-d Inference Scheduling Guide](https://github.com/llm-d/llm-d/tree/main/guides/inference-scheduling)
- [Inference Scheduler Architecture](https://github.com/llm-d/llm-d-inference-scheduler/blob/main/docs/architecture.md)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
