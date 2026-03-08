# DeepEP Multi-Node Test

This overlay deploys the DeepEP low-latency microbenchmark test across multiple nodes to validate RDMA/NVSHMEM functionality.

## Purpose

The DeepEP test validates that:
- NVSHMEM IBGDA works correctly across Kubernetes pods
- InfiniBand RDMA devices are properly exposed and configured
- GPU-to-GPU communication works across nodes
- Expert parallelism communication primitives function correctly

This test should be run **before** deploying production workloads to ensure the infrastructure is properly configured.

## Expected Results

When working correctly, you should see:
- All 3 nodes (24 GPUs total) successfully communicate
- Dispatch + Combine bandwidth: ~17-18 GB/s per rank
- Dispatch bandwidth: ~15-20 GB/s
- Combine bandwidth: ~17-19 GB/s
- Test completes successfully on all ranks

## Prerequisites

1. **RDMA Shared Devices**: Cluster must have RDMA resources available
   ```bash
   oc get nodes -o json | jq -r '.items[] | .status.allocatable | keys[] | select(startswith("rdma/"))'
   ```

2. **GPU/RDMA Discovery ConfigMap**: Must exist in namespace
   ```bash
   oc get configmap -n llm-d gpu-rdma-discovery-script
   ```

3. **Service Account**: llm-d-modelserver must exist
   ```bash
   oc get sa -n llm-d llm-d-modelserver
   ```

## Deployment

```bash
# Deploy the test
oc apply -k rig/llm-d/overlays/deepep-test

# Watch pods start
oc get pods -n llm-d -l app=deepep-test-multinode -w

# Check test results (wait ~2-3 minutes for test to complete)
oc logs -n llm-d deepep-test-0 -c test | grep "bandwidth"
oc logs -n llm-d deepep-test-1 -c test | grep "bandwidth"
oc logs -n llm-d deepep-test-2 -c test | grep "bandwidth"

# Look for "Test Complete" message
oc logs -n llm-d deepep-test-0 -c test | tail -20
```

## Cleanup

```bash
# Delete the test deployment
oc delete -k rig/llm-d/overlays/deepep-test
```

## Configuration

### Default Configuration

The test defaults to:
- **3 nodes** (WORLD_SIZE auto-detected)
- **8 GPUs per node** (24 GPUs total by default)
- **288 experts** (36 experts per GPU)
- **Top-8 routing** (each token goes to 8 experts)
- **NVSHMEM IBGDA** transport for low-latency communication

### Adjusting for Different Node Counts

**Option 1: Edit the LWS directly**
```bash
# Edit deepep-test-lws.yaml
vi rig/llm-d/overlays/deepep-test/deepep-test-lws.yaml

# Change spec.replicas to match your node count
spec:
  replicas: 2  # Change to 2, 3, 4, etc.
```

**Option 2: Use Kustomize patch (recommended)**
```bash
# Copy the example patch
cp rig/llm-d/overlays/deepep-test/replicas-patch.yaml.example \
   rig/llm-d/overlays/deepep-test/replicas-patch.yaml

# Edit replicas value
vi rig/llm-d/overlays/deepep-test/replicas-patch.yaml

# Add to kustomization.yaml
cat >> rig/llm-d/overlays/deepep-test/kustomization.yaml << EOF

patches:
  - path: replicas-patch.yaml
EOF

# Deploy with custom replicas
oc apply -k rig/llm-d/overlays/deepep-test
```

**Option 3: Using environment variable**
```bash
# Set WORLD_SIZE before deployment
export WORLD_SIZE=2  # For 2 nodes
oc apply -k rig/llm-d/overlays/deepep-test
```

The test automatically detects `WORLD_SIZE` based on the number of replicas in the LeaderWorkerSet.

### RDMA Resources Used

The test requests the following RDMA shared devices per pod:
- `rdma/rdma_shared_nic4`
- `rdma/rdma_shared_nic5`
- `rdma/rdma_shared_nic6`
- `rdma/rdma_shared_nic9`
- `rdma/rdma_shared_nic10`
- `rdma/rdma_shared_nic11`

If your cluster has different RDMA device names, update `deepep-test-lws.yaml` accordingly.

## Cleanup

To remove the DeepEP test deployment:

```bash
# Use the cleanup overlay (removes all llm-d deployments)
oc apply -k rig/llm-d/overlays/cleanup

# Monitor cleanup progress
oc logs -n llm-d job/llm-d-cleanup -f

# Or manually delete just the DeepEP test
oc delete leaderworkerset deepep-test -n llm-d
oc delete job deploy-deepep-test -n llm-d
```

The cleanup overlay removes:
- LeaderWorkerSets (deepep-test pods)
- Deployment jobs
- ConfigMaps
- All other llm-d resources

See **[overlays/cleanup/README.md](../cleanup/README.md)** for details.

## Troubleshooting

### Test hangs or times out
- Check if all pods are running: `oc get pods -n llm-d -l app=deepep-test-multinode`
- Verify RDMA devices are visible: `oc exec -n llm-d deepep-test-0 -- ls -la /dev/infiniband/`
- Check RDMA discovery logs: `oc logs -n llm-d deepep-test-0 -c rdma-discovery`

### "Peer GPU not accessible" errors
- Ensure RDMA shared device resources are properly allocated
- Verify network connectivity between pods
- Check that InfiniBand HCAs are active: `oc exec -n llm-d deepep-test-0 -- cat /data/vllm_env.sh`

### Low bandwidth results
- Expected: ~17-18 GB/s per rank
- If much lower, check for network contention or misconfiguration
- Verify GPUs are using correct InfiniBand NICs (check NVSHMEM logs)

## Based On

This test is based on the upstream WideEP well-lit path:
- DeepEP fork: https://github.com/smarterclayton/DeepEP
- Branch: `nic_pe_alignment`
- Test: `tests/test_low_latency.py`
