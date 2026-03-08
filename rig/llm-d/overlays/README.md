# LLM-d Deployment Overlays

## Overview

This directory contains 4 deployment scenarios (overlays) for llm-d workloads, plus utility overlays for testing and cleanup. Each deployment overlay is a **complete, self-contained deployment** that includes all prerequisites.

## Single Command Deployment

Each overlay deploys **everything automatically** with a single command:

```bash
oc apply -k rig/llm-d/overlays/<scenario-name>
```

No manual prerequisite steps required!

## Available Scenarios

### Deployment Overlays

| Directory | Scenario | Min GPUs | Description | Status |
|-----------|----------|----------|-------------|--------|
| `inference-scheduling/` | Inference Scheduling | Model dependent | Load-aware and prefix cache routing | ✅ Implemented |
| `pd-disaggregation/` | P/D Disaggregation | Model dependent | Separate prefill/decode on single node | ✅ Implemented |
| `pd-disaggregation-multinode/` | P/D Multi-Node | Model dependent | Multi-node prefill/decode disaggregation | ✅ Implemented |
| `ep-multinode/` | Wide Expert Parallelism | Model dependent | MoE models, Expert parallelism | ✅ Implemented |

### Utility Overlays

| Directory | Purpose | Description | Status |
|-----------|---------|-------------|--------|
| `deepep-test/` | RDMA/NVSHMEM Validation | DeepEP low-latency microbenchmark across 3 nodes | ✅ Implemented |
| `guidellm-inference-test/` | Testing | Automated inference tests with guidellm | ✅ Implemented |
| `cleanup/` | Cleanup | Removes all llm-d deployments while preserving namespace and RBAC | ✅ Implemented |

## How Overlays Work

### Structure

Each overlay contains:

```
<scenario-name>/
├── kustomization.yaml              # Kustomize overlay configuration
├── deployment-placeholder.yaml     # Placeholder (TODO: actual deployment)
└── README.md                       # Scenario-specific documentation
```

### Kustomize Resources

Each `kustomization.yaml` references:

```yaml
resources:
  # Prerequisites (deployed via sync waves)
  - ../../prereq/client-tools       # Wave -1 to 0
  - ../../prereq/gateway-provider   # Wave 5 to 15

  # Workload (deployed after prerequisites ready)
  - deployment-placeholder.yaml     # Wave 20 (TODO)
```

### Gateway Provider Configuration

Each overlay can specify which gateway provider to use via Kustomize patches:

```yaml
patches:
  - target:
      kind: Job
      name: deploy-gateway-provider
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: "istio"  # or "kgateway" or "gke"
```

## Deployment Flow (Automatic)

When you run `oc apply -k rig/llm-d/overlays/<scenario>`:

```
Wave -1: Create namespace + RBAC
    ↓ (instant)
Wave 0: Deploy client tools pod
    ↓ (wait for pod ready, ~30s)
Wave 5: Create gateway namespace
    ↓ (instant)
Wave 10: Job: Deploy gateway provider
    ↓ (wait for job complete, ~5-10 min)
Wave 15: Job: Wait for gateway ready
    ↓ (wait for job complete, ~1-2 min)
Wave 20: Deploy workload
    ↓ (wait for model servers ready)
Step 4: Cleanup - Remove llm-d-client pod
    ↓
✅ Deployment Complete
```

Total time: ~10-15 minutes (prerequisites) + workload deployment time

**Note:** The `llm-d-client` pod is automatically removed after deployment completes (Step 4: Cleanup in deployment jobs).

See [SYNC-WAVES.md](SYNC-WAVES.md) for detailed flow.

## Examples

### Deploy P/D Disaggregation (Single-Node)

```bash
# Requires RDMA networking and sufficient GPUs for the model
oc apply -k rig/llm-d/overlays/pd-disaggregation

# Monitor deployment
oc get jobs -n llm-d -w
oc get pods -n llm-d -w

# Check deployment logs
oc logs -f job/deploy-pd-singlenode -n llm-d
```

### Deploy P/D Disaggregation (Multi-Node)

```bash
# Requires RDMA networking and sufficient GPUs across multiple nodes
oc apply -k rig/llm-d/overlays/pd-disaggregation-multinode

# Monitor deployment
oc get jobs -n llm-d -w
oc get pods -n llm-d -w -o wide

# Check deployment logs
oc logs -f job/deploy-pd-multinode -n llm-d
```

### Deploy Wide-EP (MoE Models, Multi-Node)

```bash
# Requires RDMA networking and sufficient GPUs across multiple nodes
oc apply -k rig/llm-d/overlays/ep-multinode

# Monitor LeaderWorkerSets
oc get leaderworkerset -n llm-d -w

# Check deployment logs
oc logs -f job/deploy-ep-multinode -n llm-d
```

### Validate RDMA/NVSHMEM (Before Production Deployment)

```bash
# Run DeepEP multi-node test to validate infrastructure
oc apply -k rig/llm-d/overlays/deepep-test

# Watch test pods (test completes in ~2-3 minutes)
oc get pods -n llm-d -l app=deepep-test-multinode -w

# Check bandwidth results (expect ~17-18 GB/s per rank)
oc logs -n llm-d deepep-test-0 -c test | grep "bandwidth"
oc logs -n llm-d deepep-test-1 -c test | grep "bandwidth"
oc logs -n llm-d deepep-test-2 -c test | grep "bandwidth"

# Cleanup test
oc delete -k rig/llm-d/overlays/deepep-test
```

See [deepep-test/README.md](deepep-test/README.md) for detailed validation documentation.

### Cleanup Deployment

```bash
# Remove all llm-d deployment resources
oc apply -k rig/llm-d/overlays/cleanup

# Monitor cleanup progress
oc logs -n llm-d job/llm-d-cleanup -f

# After cleanup completes, delete the cleanup job
oc delete job llm-d-cleanup -n llm-d

# Verify cleanup
oc get all -n llm-d
```

See [cleanup/README.md](cleanup/README.md) for detailed cleanup documentation.

## Developer Tools

### `generate-overlays.sh`

**IMPORTANT**: This script is a **development tool only** and is **NOT executed during deployment**.

```bash
# Run manually during development to regenerate overlay structure
./generate-overlays.sh
```

This script:
- ✅ Used by developers to create consistent overlay files
- ✅ Kept in repo for documentation
- ❌ NOT part of GitOps deployment
- ❌ NOT executed on cluster

All actual deployment logic runs in Kubernetes Jobs/Pods.

## Customization

### Change Gateway Provider

Edit `kustomization.yaml` patches:

```yaml
patches:
  - target:
      kind: Job
      name: deploy-gateway-provider
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: "kgateway"  # Changed from "istio"
```

### Add Custom Labels

```yaml
commonLabels:
  custom-label: "my-value"
  team: "ml-platform"
```

### Override Resources

Create a new patch file:

```yaml
# custom-patch.yaml
apiVersion: v1
kind: Pod
metadata:
  name: llm-d-client
spec:
  containers:
    - name: client
      resources:
        limits:
          cpu: 1000m
```

Reference in `kustomization.yaml`:

```yaml
patches:
  - path: custom-patch.yaml
```

## Troubleshooting

### Deployment Stuck

```bash
# Check which wave is stuck
oc get jobs -n llm-d

# Check job logs
oc logs -f job/<job-name> -n llm-d

# Check pod status
oc get pods -n llm-d
oc describe pod <pod-name> -n llm-d
```

### Gateway Not Ready

```bash
# Check Istio
oc get pods -n istio-system

# Check GatewayClass
oc get gatewayclass

# Check CRDs
oc api-resources --api-group=inference.networking.k8s.io
```

### Prerequisites Failed

```bash
# View all events
oc get events -n llm-d --sort-by='.lastTimestamp'

# Check Jobs
oc get jobs -n llm-d
oc describe job deploy-gateway-provider -n llm-d
oc describe job wait-for-gateway-ready -n llm-d
```

## References

- [Sync Waves Documentation](SYNC-WAVES.md)
- [llm-d GitHub](https://github.com/llm-d/llm-d)
