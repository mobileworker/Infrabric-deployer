# LLM-d on Infrabric Deployer

Automated deployment of llm-d (LLM Distributed) workloads on baremetal OpenShift clusters with NVIDIA GPU and RDMA infrastructure.

## Overview

This directory provides **100% GitOps-compliant** Kubernetes manifests for deploying llm-d with various parallelism strategies on GPU clusters provisioned by Infrabric Deployer.

**Key Features:**
- 🎯 **Single Command Deployment**: `oc apply -k` deploys everything automatically
- 🔄 **Pure GitOps**: All deployment logic in declarative YAML (no host scripts)
- 📦 **4 Deployment Scenarios**: Inference scheduling, P/D disaggregation, wide-EP multinode
- 🧹 **Automated Cleanup**: Single-command resource cleanup overlay
- 🚪 **Gateway API Integration**: Intelligent LLM request routing via Inference Extension
- ⚡ **RDMA Support**: High-speed GPU-to-GPU communication via InfiniBand
- 🎭 **ArgoCD Sync Waves**: Automatic dependency ordering and readiness checks

## Directory Structure

```
rig/llm-d/
├── prereq/                        # Prerequisites
│   ├── client-tools/              # Client tools pod (kubectl, helm, helmfile)
│   ├── gateway-provider/          # Istio Gateway with Inference Extension
│   ├── istio-gateway/             # Istio installation with Gateway API support
│   ├── inferencepool-controller/  # GAIE InferencePool controller
│   ├── leaderworkerset-controller/ # LeaderWorkerSet CRD and controller
│   └── resource-discovery/        # GPU and RDMA resource discovery
└── overlays/                      # Deployment scenarios
    ├── inference-scheduling/      # Intelligent inference scheduling
    ├── pd-disaggregation/         # P/D disaggregation single-node
    ├── pd-disaggregation-multinode/ # P/D disaggregation multi-node
    ├── ep-multinode/              # Expert Parallelism (MoE models)
    ├── deepep-test/               # DeepEP RDMA/NVSHMEM validation
    ├── guidellm-inference-test/   # Automated inference testing with guidellm
    └── cleanup/                   # Cleanup overlay (removes deployments)
```

## Quick Start

### Single Command Deployment

Choose a deployment scenario and run `oc apply -k` to deploy everything automatically (prerequisites + workload):

```bash
# P/D Disaggregation Single-Node
oc apply -k rig/llm-d/overlays/pd-disaggregation

# P/D Disaggregation Multi-Node
oc apply -k rig/llm-d/overlays/pd-disaggregation-multinode

# Expert Parallelism (MoE models)
oc apply -k rig/llm-d/overlays/ep-multinode

# Inference Scheduling
oc apply -k rig/llm-d/overlays/inference-scheduling

# Monitor deployment
oc get pods -n llm-d -w
```

Each overlay automatically deploys all required prerequisites via Kustomize, including:
- Client tools pod
- Gateway provider (Istio + Gateway API)
- LeaderWorkerSet controller
- Resource discovery scripts

### Manual Step-by-Step Deployment (Optional)

If you prefer to deploy prerequisites separately, you can run each step manually:

#### Step 1: Deploy Client Tools Pod

```bash
oc apply -k rig/llm-d/prereq/client-tools
oc wait --for=condition=ready pod/llm-d-client -n llm-d --timeout=300s
```

#### Step 2: Deploy Gateway Provider (Istio)

```bash
oc apply -k rig/llm-d/prereq/gateway-provider
oc logs -f job/install-gateway-crds -n llm-d
oc logs -f job/install-istio -n llm-d
```

#### Step 3: Deploy LeaderWorkerSet Controller

```bash
oc apply -k rig/llm-d/prereq/leaderworkerset-controller
oc logs -f job/install-leaderworkerset -n llm-d
```

#### Step 4: Deploy LLM Workload

```bash
oc apply -k rig/llm-d/overlays/pd-disaggregation
oc get pods -n llm-d -w
```

### Test Deployment (Optional)

Run automated inference tests to validate the deployment:

```bash
# Deploy inference test job
oc apply -k rig/llm-d/overlays/guidellm-inference-test

# Watch test progress
oc logs -n llm-d job/llm-d-guidellm-inference-test -f

# Check test results
oc get job llm-d-guidellm-inference-test -n llm-d
```

The test automatically discovers the gateway, detects the model, and runs guidellm benchmarks. It passes if 80%+ of requests succeed.

See **[overlays/guidellm-inference-test/README.md](overlays/guidellm-inference-test/README.md)** for detailed testing documentation.

### 4. Cleanup Deployment

To remove all llm-d deployment resources:

```bash
# Deploy cleanup job
oc apply -k rig/llm-d/overlays/cleanup

# Monitor cleanup progress
oc logs -n llm-d job/llm-d-cleanup -f

# Verify cleanup
oc get all -n llm-d

# Delete the cleanup job
oc delete job llm-d-cleanup -n llm-d
```

The cleanup overlay removes all deployments (including the `llm-d-client` pod) while preserving:
- The `llm-d` namespace
- RBAC and service accounts
- Prerequisites like `llm-d-hf-token` secret

**Note:** Use the `guidellm-inference-test` overlay to verify deployments instead of the client pod.

See **[overlays/cleanup/README.md](overlays/cleanup/README.md)** for detailed cleanup documentation.

## Prerequisites

Before deploying llm-d, ensure the Infrabric infrastructure is ready:

- ✅ **GPU Operator**: NVIDIA GPU operator deployed and healthy
- ✅ **MOFED Drivers**: NVIDIA Network Operator with MOFED drivers installed
- ✅ **RDMA Devices**: RDMA shared devices available (`rdma/rdma_shared_nicX`)
- ✅ **InfiniBand**: InfiniBand interfaces active and connected
- ✅ **GPUDirect RDMA**: BIOS configured (IOMMU disabled, ACS settings)

Verify prerequisites:

```bash
# Check GPU operator
oc get pods -n nvidia-gpu-operator

# Check RDMA resources
oc get nodes -o json | jq '.items[].status.allocatable' | grep rdma

# Check InfiniBand status (from any GPU node)
oc debug node/<gpu-node> -- chroot /host ibstat
```

## Components

### Prerequisites (`prereq/`)

#### Client Tools (`client-tools/`)

Provides a pod with all necessary tools for managing llm-d:

- **kubectl** - Kubernetes CLI
- **helm** v3.19.0 - Package manager
- **helmfile** v1.2.1 - Declarative Helm deployment
- **yq** v4+ - YAML processor

**Usage:**
```bash
oc exec -it llm-d-client -n llm-d -- /bin/bash
```

See [Client Tools README](prereq/client-tools/README.md) for details.

#### Gateway Provider (`gateway-provider/`)

Deploys Istio as the Gateway implementation with:

- **Gateway API CRDs** v1.4.0
- **Gateway API Inference Extension** v1.3.0 (InferencePool support)
- **Istio** v1.28.1 with inference extension enabled

The Gateway Provider enables:
- Smart LLM request routing (prompt-aware load balancing)
- Traffic splitting for model A/B testing
- TLS encryption for inference requests

See [Gateway Provider README](prereq/gateway-provider/README.md) for details.

### Deployment Scenarios (`overlays/`)

Different deployment scenarios for LLM inference workloads. Each scenario uses a default model but **can be configured to use any compatible model** by editing the ConfigMap.

#### 1. **Inference Scheduling** (`inference-scheduling/`)
Intelligent inference scheduling with load-aware and prefix-cache aware balancing.
- **Default Model**: Qwen/Qwen3-32B (configurable)
- **GPUs**: 2-16 GPUs
- **Features**: Load balancing, approximate prefix cache awareness
- **Status**: ✅ Implemented

#### 2. **P/D Disaggregation Single-Node** (`pd-disaggregation/`)
Prefill/Decode disaggregation for improved throughput and lower latency on a single node.
- **Default Model**: RedHatAI/Meta-Llama-3.1-8B-FP8 (configurable)
- **GPUs**: 8+ GPUs (dynamically discovered, power-of-2 split)
- **Networking**: InfiniBand/RoCE RDMA required
- **Status**: ✅ Implemented

#### 3. **P/D Disaggregation Multi-Node** (`pd-disaggregation-multinode/`)
Multi-node P/D disaggregation for large-scale deployments.
- **Default Model**: RedHatAI/Meta-Llama-3.1-8B-FP8 (configurable)
- **GPUs**: 8+ GPUs across multiple nodes (dynamically discovered)
- **Networking**: Full mesh RDMA connectivity required
- **Status**: ✅ Implemented

#### 4. **Expert Parallelism** (`ep-multinode/`)
Multi-node EP deployment for Mixture of Experts models.
- **Default Model**: DeepSeek-R1-0528 (671B MoE, configurable)
- **GPUs**: 8+ H100/H200/B200 (dynamically discovered)
- **Networking**: Full mesh RDMA required
- **Status**: ✅ Implemented

#### 5. **DeepEP Testing** (`deepep-test/`)
RDMA/NVSHMEM validation using DeepEP low-latency microbenchmark.
- **Test**: DeepEP all-to-all communication patterns
- **GPUs**: Fully dynamic (adapts to cluster size)
- **Networking**: RDMA required
- **Status**: ✅ Implemented

**Note**: To change the model, edit the `ms-manifests-configmap.yaml` in each overlay and update the `MODEL` environment variable.

Each overlay includes:
- Prerequisites (client-tools, gateway-provider, resource-discovery)
- Kustomization configuration
- Dynamic resource discovery
- Comprehensive README with deployment instructions

## Configuration

### Common Resources

Common resources shared across all deployment scenarios are in the `prereq/` directory:

- **Namespace** - `llm-d` namespace created by client-tools
- **RBAC** - Service accounts and cluster roles (llm-d-client, llm-d-modelserver)
- **Gateway Provider** - Istio with Gateway API Inference Extension
- **InferencePool Controller** - GAIE controller for intelligent routing

Each overlay includes the necessary prereqs via Kustomize resources.

### Overlay Customization (TODO)

Each parallelism strategy can be customized via Kustomize patches:

```yaml
# Example: Increase GPU allocation
patchesStrategicMerge:
  - |-
    apiVersion: v1
    kind: Pod
    metadata:
      name: llm-d-worker
    spec:
      containers:
      - name: worker
        resources:
          limits:
            nvidia.com/gpu: 8
```

## Network Performance

llm-d leverages the high-performance RDMA network for:

- **GPU-to-GPU Communication**: GPUDirect RDMA for zero-copy transfers
- **Multi-Node Training**: InfiniBand for fast collective operations (NCCL)
- **Disaggregated Inference**: Low-latency prefill/decode communication

Expected performance (from network-perf-tests):
- **RDMA Bandwidth**: ~45 GB/s per NIC (~360 Gb/s)
- **RDMA Latency**: ~87-92 μs (CUDA GPUDirect)
- **NCCL All-Reduce**: ~400 GB/s aggregate

See [Network Performance Tests](../../manifests/99-network-perf-tests/README.md).

## HuggingFace Token

An empty HuggingFace token secret is created automatically by the deployment. This works for **public models** like:
- RedHatAI/Meta-Llama-3.1-8B-FP8 (used in P/D disaggregation)

For **gated or private models**, you must update the secret with your token:
- Qwen/Qwen3-32B (used in inference-scheduling)
- DeepSeek-R1-0528 (used in ep-multinode)
- Other gated models on HuggingFace

**To add your HuggingFace token:**

```bash
# 1. Get your token from https://huggingface.co/settings/tokens

# 2. Update the secret
export HF_TOKEN=<your-token>
oc create secret generic llm-d-hf-token \
  --from-literal="HF_TOKEN=${HF_TOKEN}" \
  --namespace llm-d \
  --dry-run=client -o yaml | oc apply -f -

# 3. Restart the pods to pick up the new token
oc rollout restart deployment -n llm-d
```

**Note:** The deployment will not fail without a token - pods will start but fail to download gated models.

## Troubleshooting

### Gateway API Not Available

```bash
# Verify CRDs installed
oc api-resources --api-group=inference.networking.k8s.io

# Re-run CRD installation
oc delete job install-gateway-crds -n llm-d
oc apply -k rig/llm-d/prereq/gateway-provider
```

### Istio Not Running

```bash
# Check Istio pods
oc get pods -n istio-system

# View logs
oc logs -n istio-system deployment/istiod

# Re-install Istio
oc delete job install-istio -n llm-d
oc apply -k rig/llm-d/prereq/gateway-provider
```

### Client Tools Pod Not Starting

```bash
# Check pod status
oc describe pod llm-d-client -n llm-d

# View init container logs
oc logs llm-d-client -n llm-d -c install-tools

# Delete and recreate
oc delete pod llm-d-client -n llm-d
oc apply -k rig/llm-d/prereq/client-tools
```

## References

- [llm-d GitHub Repository](https://github.com/llm-d/llm-d)
- [llm-d Prerequisites Guide](https://github.com/llm-d/llm-d/tree/main/guides/prereq)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/)
- [Istio Documentation](https://istio.io/latest/docs/)

## Documentation
- **[prereq/client-tools/README.md](prereq/client-tools/README.md)** - Client tools pod
- **[prereq/gateway-provider/README.md](prereq/gateway-provider/README.md)** - Gateway provider
- **[prereq/istio-gateway/README.md](prereq/istio-gateway/)** - Istio installation
- **[prereq/inferencepool-controller/README.md](prereq/inferencepool-controller/)** - GAIE controller
- **[overlays/*/README.md](overlays/)** - Scenario-specific guides (9 scenarios)
- **[overlays/guidellm-inference-test/README.md](overlays/guidellm-inference-test/README.md)** - Automated inference testing
- **[overlays/cleanup/README.md](overlays/cleanup/README.md)** - Cleanup overlay

## License

See [LICENSE](../../LICENSE) in the root of the repository.
