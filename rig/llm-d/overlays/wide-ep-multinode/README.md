# Wide Expert Parallelism Multi-Node

## Overview

Wide Expert Parallelism (EP/DP) deployment for DeepSeek-R1-0528 across multiple nodes. Leverages vLLM's P/D disaggregation with NIXL for distributed expert parallelism.

**Model**: DeepSeek-R1-0528 (Mixture of Experts)

**Configuration**:
- Dynamically discovers available GPU nodes and GPUs per node
- Configures tensor parallelism based on discovered GPUs (power-of-2)
- Deploys prefill and decode workers with expert parallelism
- Automatically configures RDMA resources for multi-node communication

## Hardware Requirements

- **GPUs**: 8+ NVIDIA H100/H200/B200 GPUs across multiple nodes
- **Networking**: InfiniBand or RoCE RDMA (full mesh required)
- **Minimum**: 2 nodes with 4 GPUs each
- **Validated On**:
  - Multi-node H200 clusters with InfiniBand
  - Multi-node H200 clusters on GKE with RoCE
  - Multi-node B200 clusters on GKE with RoCE

## Prerequisites

All prerequisites are automatically deployed:

- ✅ Client tools pod (automatically removed after deployment completes)
- ✅ Gateway provider (Istio)
- ✅ HuggingFace token secret (empty by default, update for gated models like DeepSeek-R1)
- ⏳ LeaderWorkerSet controller (required for multi-host inference - manual installation)
- ⏳ Full mesh RDMA connectivity (verify with network-perf-tests)

**CRITICAL**: This deployment requires All-to-All RDMA connectivity. Every NIC on a host must communicate with every NIC on all other hosts. Rail-only connectivity will fail.

## LeaderWorkerSet Controller

Before deploying, install the LeaderWorkerSet controller:

```bash
# Install LeaderWorkerSet CRDs and controller
kubectl apply -f https://github.com/kubernetes-sigs/lws/releases/latest/download/manifests.yaml
```

## Quick Start

### 1. Verify Infrastructure

```bash
# Check RDMA connectivity
oc get nodes -o json | jq '.items[].status.allocatable' | grep rdma

# Verify LeaderWorkerSet CRD
oc get crd leaderworkersets.leaderworkerset.x-k8s.io

# Run network performance tests
oc apply -k manifests/99-network-perf-tests
```

### 2. Deploy

**Single command deployment**:

```bash
oc apply -k rig/llm-d/overlays/wide-ep-multinode
```

This automatically creates namespace, RBAC, and prerequisites.

**For gated models** (DeepSeek-R1 requires HuggingFace token):

```bash
# The HF_TOKEN secret is automatically created (empty by default)
# Update it with your token for DeepSeek-R1:
export HF_TOKEN=hf_your_token_here
oc create secret generic llm-d-hf-token \
  --from-literal="HF_TOKEN=${HF_TOKEN}" \
  --namespace llm-d \
  --dry-run=client -o yaml | oc apply -f -

# Restart pods to pick up the token
oc delete pods -n llm-d -l llm-d.ai/guide=wide-ep-multinode
```

## Customization

### Change the Model

You can use any MoE (Mixture of Experts) model compatible with vLLM by editing `ms-manifests-configmap.yaml`:

```bash
# Edit the ConfigMap
vi rig/llm-d/overlays/wide-ep-multinode/ms-manifests-configmap.yaml

# Update the MODEL environment variable
env:
  - name: MODEL
    value: "mistralai/Mixtral-8x22B-Instruct-v0.1"  # Your custom MoE model
```

**Supported MoE Models**:
- DeepSeek-R1-0528 (671B, 256 experts)
- DeepSeek-V2/V3 (MoE)
- Mixtral-8x7B, Mixtral-8x22B
- Qwen2-MoE models
- Other vLLM-compatible MoE architectures

See [vLLM supported models](https://docs.vllm.ai/en/latest/models/supported_models.html).

**Note**:
- Expert Parallelism requires MoE models (models with multiple experts)
- For gated models, update the HuggingFace token secret before deploying
- Adjust GPU count and parallelism settings based on model size

## Architecture

```
LeaderWorkerSet (Prefill)
  ├─ Leader Pod (DP=16, Worker 0)
  └─ Worker Pods (DP=16, Workers 1-15)
       ↓ RDMA (Expert Parallelism)
LeaderWorkerSet (Decode)
  ├─ Leader Pod (DP=16, Worker 0)
  └─ Worker Pods (DP=16, Workers 1-15)
       ↓
Response Stream
```

## Expert Parallelism (EP)

**How it works**:
- Model experts are distributed across 16 workers
- Each worker handles a subset of experts
- RDMA enables fast expert communication
- DeepEP backend coordinates expert routing

**Network Requirements**:
- Full mesh connectivity between all pods
- High-bandwidth RDMA (45+ GB/s per NIC)
- Low-latency inter-pod communication

## Performance Characteristics

### Expected Throughput
- **Prefill**: Optimized for compute-bound workloads
- **Decode**: Optimized for latency-bound workloads

### Network Performance
- **RDMA Bandwidth**: ~45 GB/s per NIC
- **Latency**: <100 μs (GPUDirect RDMA)
- **Aggregate**: ~1.4 TB/s (32 NICs @ 45 GB/s each)

## Troubleshooting

### Expert Parallelism Failures

```bash
# Check RDMA connectivity
oc exec <pod> -- ibstatus

# Verify GPU-NIC topology
oc exec <pod> -- nvidia-smi topo -m

# Check for network errors
oc logs <pod> | grep -i "rdma\|error"
```

### LeaderWorkerSet Issues

```bash
# Check LWS status
oc get leaderworkerset -n ${NAMESPACE}

# Describe LWS
oc describe leaderworkerset <name> -n ${NAMESPACE}

# Check pod distribution
oc get pods -n ${NAMESPACE} -o wide
```

## References

- [llm-d Wide-EP Guide](https://github.com/llm-d/llm-d/tree/main/guides/wide-ep-lws)
- [LeaderWorkerSet Documentation](https://github.com/kubernetes-sigs/lws)
- [DeepSeek-R1 Model](https://huggingface.co/deepseek-ai/DeepSeek-R1-0528)
