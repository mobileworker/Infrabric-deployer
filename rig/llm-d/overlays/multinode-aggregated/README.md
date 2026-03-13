# Wide Expert Parallelism Multi-Node

## Overview

Wide Expert Parallelism (EP/DP) deployment for DeepSeek-R1-0528 across multiple nodes. Leverages vLLM's P/D disaggregation with NIXL for distributed expert parallelism.

**Model**: Qwen3-235B-A22B-FP8 (Mixture of Experts with FP8 quantization)

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
- ✅ HuggingFace token secret (empty by default, update for gated models)
- ⏳ LeaderWorkerSet controller (required for multi-host inference - manual installation)
- ⏳ Full mesh RDMA connectivity (verify with network-perf-tests)
- ⏳ **Shared model cache PVC** (required - see Model Cache Setup below)

**Storage Requirements**:
- ReadWriteMany (RWX) storage class (NFS or similar)
- 1TB available storage for model cache
- The model (~200GB) is downloaded once and shared across all pods

**CRITICAL**: This deployment requires All-to-All RDMA connectivity. Every NIC on a host must communicate with every NIC on all other hosts. Rail-only connectivity will fail.

## LeaderWorkerSet Controller

Before deploying, install the LeaderWorkerSet controller:

```bash
# Install LeaderWorkerSet CRDs and controller
kubectl apply -f https://github.com/kubernetes-sigs/lws/releases/latest/download/manifests.yaml
```

## Quick Start

### 1. Configure Storage Class (if needed)

**IMPORTANT**: If your cluster doesn't have `nfs-disk-1-sc` storage class, update it **before deploying**:

```bash
# 1. Find your RWX storage class
kubectl get storageclass | grep -i nfs

# 2. Edit the PVC to use your storage class
vi rig/llm-d/overlays/ep-multinode/model-cache-pvc.yaml
# Update: storageClassName: your-nfs-sc  # REPLACE with your RWX storage class
```

See **[SETUP-MODEL-CACHE.md](SETUP-MODEL-CACHE.md)** for details.

**Note**: The deployment will automatically:
- Create a 1TB PVC for model cache (Wave 10)
- Download the model to the PVC (Wave 15, ~20-30 min)
- Wait for download to complete before deploying pods (Wave 25)

### 2. Verify Infrastructure

```bash
# Check RDMA connectivity
oc get nodes -o json | jq '.items[].status.allocatable' | grep rdma

# Verify LeaderWorkerSet CRD
oc get crd leaderworkersets.leaderworkerset.x-k8s.io

# Run network performance tests
oc apply -k manifests/99-network-perf-tests
```

### 3. Deploy

**Single command deployment** - everything is automatic:

```bash
oc apply -k rig/llm-d/overlays/ep-multinode
```

This automatically:
- Creates namespace, RBAC, and prerequisites
- **Wave 10**: Creates 1TB PVC for model cache
- **Wave 15**: Downloads Qwen3-235B-A22B-FP8 model (~200GB, 20-30 min)
- **Wave 25**: Deploys prefill/decode pods (waits for model download)

**Monitor deployment**:
```bash
# Watch model download
kubectl logs -n llm-d -l job=model-download --follow

# Watch pod startup (after model download completes)
kubectl get pods -n llm-d -l llm-d.ai/guide=ep-multinode -w
```

**For gated models** (e.g., DeepSeek-R1, Llama models):

```bash
# Some models require a HuggingFace token
# The HF_TOKEN secret is automatically created (empty by default)
# Update it with your token if using gated models:
export HF_TOKEN=hf_your_token_here
oc create secret generic llm-d-hf-token \
  --from-literal="HF_TOKEN=${HF_TOKEN}" \
  --namespace llm-d \
  --dry-run=client -o yaml | oc apply -f -

# Re-run model download job with the token
kubectl delete job wide-ep-model-download -n llm-d
kubectl apply -f rig/llm-d/overlays/ep-multinode/model-download-job.yaml
```

**Note**: The current model (Qwen3-235B-A22B-FP8) does not require a HuggingFace token.

## Customization

### Change the Model

You can use any MoE (Mixture of Experts) model compatible with vLLM:

**Step 1**: Update the model in the download job:
```bash
# Edit the download job
vi rig/llm-d/overlays/ep-multinode/model-download-job.yaml

# Update the model_id
model_id = 'mistralai/Mixtral-8x22B-Instruct-v0.1'  # Your custom MoE model
```

**Step 2**: Update the model in the ConfigMap:
```bash
# Edit the ConfigMap
vi rig/llm-d/overlays/ep-multinode/ms-manifests-configmap.yaml

# Update the vllm serve command (appears in both prefill and decode sections)
exec vllm serve \
  mistralai/Mixtral-8x22B-Instruct-v0.1 \  # Your custom MoE model
  --port 8000 \
  ...
```

**Step 3**: Update the model cache PVC size if needed:
```bash
# Larger models may require more storage (default is 1TB)
vi rig/llm-d/overlays/ep-multinode/model-cache-pvc.yaml

# Adjust storage size
storage: 2Ti  # For very large models
```

**Step 4**: Redeploy:
```bash
# Delete existing deployment (keeps PVC by default)
oc delete -k rig/llm-d/overlays/ep-multinode

# If changing models, also delete the PVC to clear old cache
kubectl delete pvc wide-ep-model-cache -n llm-d

# Redeploy (automatically downloads new model)
oc apply -k rig/llm-d/overlays/ep-multinode
```

**Supported MoE Models**:
- Qwen3-235B-A22B-FP8 (235B, 128 experts, FP8 quantized) - **Default**
- DeepSeek-R1-0528 (671B, 256 experts)
- DeepSeek-V2/V3 (MoE)
- Mixtral-8x7B, Mixtral-8x22B
- Qwen2-MoE models
- Other vLLM-compatible MoE architectures

See [vLLM supported models](https://docs.vllm.ai/en/latest/models/supported_models.html).

**Note**:
- Expert Parallelism requires MoE models (models with multiple experts)
- For gated models, update the HuggingFace token secret before downloading
- Adjust GPU count and parallelism settings based on model size
- Model size directly impacts PVC storage requirements

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

## Cleanup

To remove the Wide-EP deployment:

```bash
# Remove the deployment (keeps the model cache PVC)
oc delete -k rig/llm-d/overlays/ep-multinode
```

**Important**: The model cache PVC (`wide-ep-model-cache`) is **NOT** deleted during cleanup. This is intentional - the cached model (~200GB) is preserved to avoid re-downloading on future deployments.

To completely remove everything including the cached model:
```bash
# First remove the deployment
oc delete -k rig/llm-d/overlays/ep-multinode

# Then manually delete the PVC (WARNING: deletes cached model)
kubectl delete pvc wide-ep-model-cache -n llm-d
```

See [SETUP-MODEL-CACHE.md](SETUP-MODEL-CACHE.md#cleanup) for more details.

## References

- [llm-d Wide-EP Guide](https://github.com/llm-d/llm-d/tree/main/guides/wide-ep-lws)
- [LeaderWorkerSet Documentation](https://github.com/kubernetes-sigs/lws)
- [Model Cache Setup Guide](SETUP-MODEL-CACHE.md)
