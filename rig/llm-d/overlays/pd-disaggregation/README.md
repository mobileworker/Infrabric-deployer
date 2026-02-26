# P/D Disaggregation Deployment (Single-Node)

## Overview

Single-node Prefill/Decode disaggregation deployment for efficient LLM inference. Separates prefill and decode workloads on the same node with dynamic GPU splitting.

**Model**: RedHatAI/Meta-Llama-3.1-8B-FP8

**Configuration**:
- Single GPU node deployment
- **Dynamic GPU Split**: Automatically divides GPUs between prefill and decode
- Even power-of-2 split for tensor parallelism
- RDMA-based KV cache transfer

## GPU Split Logic

The deployment **automatically** divides available GPUs between prefill and decode with these constraints:

### Power of 2 Requirement
- Tensor parallelism requires GPU counts that are powers of 2: **1, 2, 4, 8, 16, 32...**
- Model weights cannot be divided by 3, 5, 6, 7, etc.
- This is a fundamental requirement of distributed model loading

### Even Split Algorithm
1. Get total GPU count on the node
2. Divide by 2 to get half
3. Find largest power of 2 that is ≤ half
4. Use that number for **both** prefill and decode

### GPU Split Examples

| Total GPUs | Half | Largest Power of 2 ≤ Half | Prefill | Decode | Total Used | Unused |
|------------|------|---------------------------|---------|--------|------------|--------|
| 8          | 4    | 4                         | 4       | 4      | 8          | 0      |
| 7          | 3.5  | 2                         | 2       | 2      | 4          | **3**  |
| 6          | 3    | 2                         | 2       | 2      | 4          | **2**  |
| 5          | 2.5  | 2                         | 2       | 2      | 4          | **1**  |
| 4          | 2    | 2                         | 2       | 2      | 4          | 0      |
| 3          | 1.5  | 1                         | 1       | 1      | 2          | **1**  |
| 2          | 1    | 1                         | 1       | 1      | 2          | 0      |
| 1          | 0.5  | -                         | 0       | 0      | 0          | **1**  |

**Why unused GPUs?**
- With 7 GPUs, we can't use 3 GPUs for each (3 is not a power of 2)
- With 6 GPUs, we can't do 3/3 split (model weights can't divide by 3)
- The deployment uses the largest safe split and leaves GPUs idle

## Hardware Requirements

- **GPUs**: 2+ NVIDIA GPUs on a single node (4+ recommended)
- **Networking**: InfiniBand or RoCE RDMA for KV cache transfer
- **Memory**: Sufficient for model + KV cache on each pod

## Prerequisites

All prerequisites are automatically deployed:

- ✅ Client tools pod (deployed automatically, removed after deployment completes)
- ✅ Gateway provider (Istio, deployed via Helmfile)
- ✅ InferencePool controller (GAIE, deployed via Helm)
- ✅ GPU/RDMA resource discovery (automatic)
- ✅ GPU SecurityContextConstraints (llm-d-gpu-scc)
- ✅ HuggingFace token secret (empty by default, update for gated models)

## Quick Start

### 1. Verify GPU and RDMA Resources

```bash
# Check GPU count and RDMA resources
oc get nodes -o json | jq '.items[] | select(.status.allocatable["nvidia.com/gpu"]) | {node: .metadata.name, gpus: .status.allocatable["nvidia.com/gpu"], rdma: (.status.allocatable | to_entries | map(select(.key | startswith("rdma/"))) | from_entries)}'
```

### 2. Deploy

Single command GitOps deployment:

```bash
oc apply -k rig/llm-d/overlays/pd-disaggregation
```

The deployment automatically:
- Creates llm-d namespace and RBAC
- Deploys Istio gateway provider
- Deploys InferencePool controller (GAIE)
- **Discovers GPU count and calculates P/D split**
- **Discovers all RDMA resources dynamically**
- Deploys model server (prefill + decode pods on same node)
- Configures HTTP routing

**Optional**: For gated HuggingFace models (not needed for RedHatAI/Meta-Llama-3.1-8B-FP8):

```bash
# The HF_TOKEN secret is automatically created (empty by default)
# For gated models, update it with your token:
export HF_TOKEN=hf_your_token_here
oc create secret generic llm-d-hf-token \
  --from-literal="HF_TOKEN=${HF_TOKEN}" \
  --namespace llm-d \
  --dry-run=client -o yaml | oc apply -f -

# Restart pods to pick up the token
oc rollout restart deployment -n llm-d
```

### 3. Verify Deployment

```bash
# Check GPU split
oc logs -n llm-d job/deploy-pd-singlenode -c deploy-pd | grep "Single-Node P/D Configuration"

# Check pods
oc get pods -n llm-d -l llm-d.ai/guide=pd-disaggregation

# Example output with 8 GPUs:
# ms-pd-llm-d-modelservice-prefill-0   (4 GPUs)
# ms-pd-llm-d-modelservice-decode-0    (4 GPUs)
```

### 4. Test Inference

Use the automated inference test overlay:

```bash
# Deploy inference test job
oc apply -k rig/llm-d/overlays/inference-test

# Watch test progress
oc logs -n llm-d job/llm-d-inference-test -f

# The test automatically discovers the gateway and model, then runs guidellm benchmarks
```

Or test manually:

```bash
# Test inference request from a test pod
oc run -it --rm test-inference --image=curlimages/curl --restart=Never -- \
  curl -X POST http://infra-pd-inference-gateway-istio.llm-d.svc.cluster.local/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "RedHatAI/Meta-Llama-3.1-8B-FP8",
    "prompt": "What is Kubernetes?",
    "max_tokens": 50
  }' | jq .

# Check available models
curl http://infra-pd-inference-gateway-istio.llm-d.svc.cluster.local/v1/models | jq .
```

### 5. Cleanup

```bash
# Run cleanup (keeps RBAC for redeployment)
oc apply -f rig/llm-d/overlays/pd-disaggregation-multinode/llm-d-cleanup-job.yaml

# Monitor cleanup
oc logs -f job/llm-d-cleanup -n llm-d
```

## Customization

### Change the Model

You can use any vLLM-compatible model by editing `ms-manifests-configmap.yaml`:

```bash
# Edit the ConfigMap
vi rig/llm-d/overlays/pd-disaggregation/ms-manifests-configmap.yaml

# Update the MODEL environment variable in both prefill and decode sections
env:
  - name: MODEL
    value: "mistralai/Mistral-7B-Instruct-v0.3"  # Your custom model
```

**Important**: Update the model in both prefill and decode pod specifications to ensure they use the same model.

Supported models: Llama, Mistral, Mixtral, Qwen, Phi, DeepSeek, and more. See [vLLM supported models](https://docs.vllm.ai/en/latest/models/supported_models.html).

**Note**: For gated models, update the HuggingFace token secret before deploying.

## Architecture

```
Single GPU Node
│
├─ Prefill Pod (X GPUs, TP=X)
│  └─ vLLM serving RedHatAI/Meta-Llama-3.1-8B-FP8
│     └─ Handles prompt processing
│
└─ Decode Pod (X GPUs, TP=X)
   └─ vLLM serving same model
      └─ Handles token generation
      └─ Receives KV cache from Prefill via RDMA

User Request → Gateway → InferencePool → Prefill → (KV transfer) → Decode → Response
```

Where X is automatically calculated based on available GPUs.

## Dynamic Configuration

The deployment automatically configures:

1. **GPU Discovery**: Scans node for available GPUs
2. **P/D Split Calculation**: Determines prefill/decode GPU allocation
3. **Tensor Parallelism**: Sets `--tensor-parallel-size` for both pods
4. **RDMA Discovery**: Finds all available RDMA/IB/RoCE resources
5. **Resource Injection**: Applies discovered resources to pod specs

Example discovery output (8 GPU node):
```yaml
vllm:
  singlenode:
    prefillTensorParallelSize: 4
    decodeTensorParallelSize: 4
    totalUsedGpus: 8
    unusedGpus: 0
```

## When to Use Single-Node P/D

✅ **Good for**:
- Testing P/D disaggregation on single node
- 4-8 GPU nodes
- Models that fit split across available GPUs
- RDMA-enabled nodes

❌ **Not ideal for**:
- Very large models requiring >8 GPUs
- Nodes with only 1-2 GPUs (use standard deployment)
- Multi-node clusters (use pd-disaggregation-multinode instead)

## Troubleshooting

### Unused GPUs Warning

If you see "Unused GPUs" in the deployment logs:
```
⚠️  WARNING: 3 GPU(s) will remain unused due to power-of-2 constraint
```

This is **expected** when total GPU count doesn't allow even power-of-2 split:
- 7 GPUs → uses 4 (2+2), leaves 3 unused
- 6 GPUs → uses 4 (2+2), leaves 2 unused
- This ensures model weights can be properly sharded

### Check GPU Split

```bash
# View actual configuration used
oc logs -n llm-d job/deploy-pd-singlenode -c discover-resources

# Check pod resource allocation
oc get pod -n llm-d -l llm-d.ai/guide=pd-disaggregation -o json | \
  jq '.items[] | {name: .metadata.name, gpus: .spec.containers[0].resources.limits["nvidia.com/gpu"]}'
```

## References

- [llm-d P/D Disaggregation Guide](https://github.com/llm-d/llm-d/tree/main/guides/pd-disaggregation)
- [Resource Discovery Documentation](../../prereq/resource-discovery/README.md)
