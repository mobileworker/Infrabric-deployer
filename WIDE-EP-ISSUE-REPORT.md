# Wide-EP Multi-Node Deployment Issue Report

**Date:** 2026-03-03
**Environment:** OpenShift 4.x with 3 nodes, 8x H200 GPUs per node
**Model:** DeepSeek-R1-0528 (671B parameters, 256 experts)
**Issue:** Pods crash in a loop during vLLM initialization

---

## Problem Summary

Wide-EP (Expert Parallelism) deployment for DeepSeek-R1-0528 crashes during initialization. The pods start, vLLM begins loading, but crashes before completing startup and listening on port 8000/8200.

**Symptoms:**
- Pods enter Running state
- vLLM logs show initial startup messages
- Pods crash before health check succeeds (startup probe fails)
- LeaderWorkerSet recreates pods in a loop
- No clear error messages in logs - appears to hang/crash silently during initialization

---

## Current Configuration

### Cluster Setup
- **Nodes:** 3 nodes
- **GPUs per node:** 8x NVIDIA H200
- **Networking:** InfiniBand with RDMA (6 RDMA resources per node)
- **Kubernetes:** OpenShift 4.x
- **Istio:** 1.28.1

### Deployment Architecture
- **Prefill:** 1 LeaderWorkerSet with size=1 (1 pod on 1 node, 8 GPUs)
- **Decode:** 1 LeaderWorkerSet with size=2 (2 pods on 2 nodes, 8 GPUs each)
- **Total:** 3 pods using 24 GPUs total

### Key Parameters
- `TP_SIZE=1` (Tensor Parallelism disabled)
- `DP_SIZE_LOCAL=8` (8-way Data Parallelism per pod)
- `VLLM_ALL2ALL_BACKEND=naive`
- `NVSHMEM_REMOTE_TRANSPORT=none`
- `--enforce-eager` (CUDA graphs disabled)
- `--enable-expert-parallel` (Expert Parallelism enabled)
- `--max-model-len=32000`

---

## Generated YAML Files

See full YAMLs in: `rig/llm-d/overlays/wide-ep-multinode/ms-manifests-configmap.yaml`

### Prefill vLLM Command
```bash
vllm serve deepseek-ai/DeepSeek-R1-0528 \
  --port 8000 \
  --disable-log-requests \
  --disable-uvicorn-access-log \
  --enable-expert-parallel \
  --tensor-parallel-size 1 \
  --data-parallel-size 8 \
  --data-parallel-size-local 8 \
  --data-parallel-address wide-ep-prefill-0.wide-ep-prefill.llm-d \
  --data-parallel-rpc-port 5555 \
  --data-parallel-start-rank 0 \
  --trust-remote-code \
  --enforce-eager \
  --max-model-len 32000 \
  --data-parallel-hybrid-lb \
  --kv_transfer_config '{"kv_connector":"NixlConnector","kv_role":"kv_both"}'
```

### Decode vLLM Command
```bash
vllm serve deepseek-ai/DeepSeek-R1-0528 \
  --port 8200 \
  --disable-log-requests \
  --disable-uvicorn-access-log \
  --enable-expert-parallel \
  --tensor-parallel-size 1 \
  --data-parallel-size 16 \
  --data-parallel-size-local 8 \
  --data-parallel-address wide-ep-decode-0.wide-ep-decode.llm-d \
  --data-parallel-rpc-port 5555 \
  --data-parallel-start-rank 0 \
  --trust-remote-code \
  --enforce-eager \
  --max-model-len 32000 \
  --data-parallel-hybrid-lb \
  --kv_transfer_config '{"kv_connector":"NixlConnector","kv_role":"kv_both"}'
```

### Key Environment Variables
```yaml
HF_TOKEN: <from secret>
DP_SIZE_LOCAL: "8"
TP_SIZE: "1"
VLLM_ALL2ALL_BACKEND: "naive"
NVSHMEM_REMOTE_TRANSPORT: "none"
VLLM_USE_DEEP_GEMM: "1"
NVIDIA_GDRCOPY: "enabled"
```

### Resources per Pod
```yaml
requests:
  cpu: 32
  memory: 512Gi
  nvidia.com/gpu: "8"
  rdma/rdma_shared_nic10: "1"
  rdma/rdma_shared_nic11: "1"
  rdma/rdma_shared_nic4: "1"
  rdma/rdma_shared_nic5: "1"
  rdma/rdma_shared_nic6: "1"
  rdma/rdma_shared_nic9: "1"
  ephemeral-storage: 1Ti

volumes:
  dshm: 2Gi (in-memory)
```

---

## What We've Tried

### Configuration Changes Made
1. ✅ Fixed `TP_SIZE` from 8 to 1 (Wide-EP uses DP/EP, not TP)
2. ✅ Changed `VLLM_ALL2ALL_BACKEND` from `deepep_high_throughput` to `naive`
3. ✅ Changed `NVSHMEM_REMOTE_TRANSPORT` from `ibgda` to `none`
4. ✅ Added `--enforce-eager` to disable CUDA graphs
5. ✅ Added `--max-model-len 32000`
6. ✅ Removed advanced features: `--async-scheduling`, `--enable-dbo`, `--enable-eplb`
7. ✅ Fixed `dshm` size from 256Gi to 2Gi
8. ✅ Added HuggingFace token for gated model access
9. ✅ Simplified KV transfer config

### Earlier Bugs Fixed
- **CUDA Error 803**: Fixed by using `TP_SIZE=1` and `--enforce-eager`
- **dshm OOM**: Fixed by reducing from 256Gi to 2Gi
- **Missing logging**: Alignment with working example

---

## Working Reference

We have a working example on `n42-h01-b05-mx750c.rdu3.labs.perfscale.redhat.com` at:
`/mnt/data/David/llm-d/guides/wide-ep-lws/manifests/modelserver/base/`

**Key differences from working example:**
- Working example: **Qwen3-Coder-30B** (30B parameters, smaller model)
- Our deployment: **DeepSeek-R1-0528** (671B parameters, 22x larger)
- Working example: **4 GPUs per node** with `DP_SIZE_LOCAL=4`
- Our deployment: **8 GPUs per node** with `DP_SIZE_LOCAL=8`

The configuration is now aligned with the working example, scaled for 8 GPUs instead of 4.

---

## Observable Behavior

**Pod Lifecycle:**
1. Pod starts (Status: Running)
2. vLLM initialization begins
3. Logs show:
   ```
   INFO vLLM API server version 0.14.1
   INFO non-default args: {...}
   INFO Replacing legacy 'type' key with 'rope_type'
   ```
4. Logs stop (no error messages)
5. After ~30-45 seconds, startup probe fails
6. Pod terminates with exit code 1
7. LeaderWorkerSet recreates pod (crash loop)

**No visible errors** - vLLM appears to hang/crash silently during model initialization.

**No OOM killer** - Exit is not due to memory exhaustion.

---

## Questions for Expert

1. **Is DeepSeek-R1-0528 (671B) too large for this configuration?**
   - With `DP_SIZE_LOCAL=8` across 8 H200 GPUs?
   - Should we reduce `DP_SIZE_LOCAL` to 4 (use only half the GPUs)?

2. **Are there missing vLLM flags for very large MoE models?**
   - DeepSeek-R1 has 256 experts vs typical 8-16 experts
   - Any special configuration needed for 671B models?

3. **Memory allocation issues?**
   - 512Gi RAM per pod sufficient?
   - `dshm` size of 2Gi appropriate for this model size?
   - `--max-model-len 32000` too large?

4. **RDMA/Networking issues?**
   - Are RDMA resources properly allocated?
   - Should `NVSHMEM_REMOTE_TRANSPORT` be `ibgda` instead of `none`?
   - Does `VLLM_ALL2ALL_BACKEND=naive` work for 671B models?

5. **Initialization timeout?**
   - Does DeepSeek-R1-0528 need more time to initialize?
   - Is 2700 seconds (45 minutes) startup probe timeout insufficient?

6. **Missing environment variables or flags?**
   - Any DeepSeek-R1 specific requirements?
   - vLLM version 0.14.1 compatible with this model?

---

## Additional Context

- **vLLM version:** 0.14.1 (ghcr.io/llm-d/llm-d-cuda:v0.5.0)
- **Model source:** HuggingFace `deepseek-ai/DeepSeek-R1-0528`
- **HuggingFace token:** Configured and accessible
- **All 8 GPUs visible:** Verified with `nvidia-smi -L`
- **RDMA resources available:** 6 RDMA interfaces per node

---

## Files for Reference

Configuration files are in branch `test-wide-ep-fix`:
- `rig/llm-d/overlays/wide-ep-multinode/ms-manifests-configmap.yaml`
- `rig/llm-d/overlays/wide-ep-multinode/gaie-values-configmap.yaml`
- `rig/llm-d/overlays/wide-ep-multinode/deploy-ep-job.yaml`

Full YAML manifests with all details included in `ms-manifests-configmap.yaml`.
