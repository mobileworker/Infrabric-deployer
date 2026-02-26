# P/D Disaggregation Deployment (Multi-Node)

## Overview

Multi-node Prefill/Decode disaggregation deployment for efficient LLM inference. Separates prefill and decode workloads across **different nodes** with full GPU utilization and RDMA-based communication.

**Model**: RedHatAI/Meta-Llama-3.1-8B-FP8

**Configuration**:
- Multi-node deployment (prefill and decode on **different** GPU nodes)
- **Dynamic GPU Allocation**: Uses all available GPUs per node (power-of-2)
- **RDMA Communication**: Cross-node KV cache transfer via RDMA resources
- Pod anti-affinity ensures prefill and decode are on separate nodes

## Key Differences from Single-Node

| Aspect | Single-Node | Multi-Node |
|--------|-------------|------------|
| **Pod Placement** | Same node (pod affinity) | Different nodes (pod anti-affinity) |
| **GPU Allocation** | Split GPUs between prefill/decode | All GPUs per node for tensor parallelism |
| **RDMA** | Shared via hostPath | Requested as Kubernetes resources |
| **Communication** | Local (same node) | Cross-node via RDMA network |
| **Use Case** | Testing, single GPU node | Production, multi-node clusters |

## GPU Allocation Logic

Uses all available GPUs per node for tensor parallelism (largest power of 2 ≤ GPU count).

### Examples

| GPUs per Node | Tensor Parallel Size | Unused per Node |
|---------------|---------------------|-----------------|
| 8             | 8                   | 0               |
| 7             | 4                   | 3               |
| 4             | 4                   | 0               |
| 2             | 2                   | 0               |

## Quick Start

```bash
# Deploy
oc apply -k rig/llm-d/overlays/pd-disaggregation-multinode

# Verify pods are on DIFFERENT nodes
oc get pods -n llm-d -l llm-d.ai/guide=pd-disaggregation-multinode -o wide
```

## Native Kubernetes Manifests

This deployment uses **pure Kubernetes Deployments** (not Helm charts) with dynamic resource patching.

## Customization

### Change the Model

You can use any vLLM-compatible model by editing `ms-manifests-configmap.yaml`:

```bash
# Edit the ConfigMap
vi rig/llm-d/overlays/pd-disaggregation-multinode/ms-manifests-configmap.yaml

# Update the MODEL environment variable in both prefill and decode sections
env:
  - name: MODEL
    value: "mistralai/Mistral-7B-Instruct-v0.3"  # Your custom model
```

**Important**: Update the model in both prefill and decode pod specifications to ensure they use the same model.

Supported models: Llama, Mistral, Mixtral, Qwen, Phi, DeepSeek, and more. See [vLLM supported models](https://docs.vllm.ai/en/latest/models/supported_models.html).

**Note**: For gated models, update the HuggingFace token secret before deploying.
