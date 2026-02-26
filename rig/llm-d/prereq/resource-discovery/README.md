# GPU and RDMA Resource Discovery

Shared resource discovery mechanism for all llm-d overlays. Dynamically discovers:

- GPU count per node
- Available RDMA resources (NVIDIA shared devices, SR-IOV NICs, rdma/ devices)
- Generates proper resource requests/limits
- Calculates optimal tensor-parallel-size

## Why This Exists

Different clusters have different GPU and RDMA configurations:
- GPU count varies (4, 8, 16 GPUs per node)
- RDMA resources differ (NVIDIA shared, SR-IOV, kernel RDMA)
- NIC names and counts vary by cluster

This shared discovery script eliminates hardcoded values and makes deployments truly portable.

## What It Discovers

### GPU Resources
- `nvidia.com/gpu` - Count per node
- Auto-sets `tensor-parallel-size` to match GPU count

### RDMA Resources
Discovers all available RDMA/IB resources:
- `rdma/rdma_shared_*` - Kernel RDMA shared devices
- `openshift.io/*rdma` - SR-IOV RDMA VFs
- `openshift.io/*ib` - SR-IOV InfiniBand VFs
- `openshift.io/*roce` - SR-IOV RoCE VFs
- `nvidia.com/*rdma` - NVIDIA device plugin RDMA
- `nvidia.com/*ib` - NVIDIA device plugin IB

Only includes resources with non-zero allocatable capacity.

## How It Works

### Discovery Process

1. **Find GPU nodes** - Queries all nodes with `nvidia.com/gpu > 0`
2. **Sample first node** - Analyzes resources on first GPU node
3. **Extract GPU count** - Reads `nvidia.com/gpu` allocatable
4. **Find RDMA resources** - Filters all RDMA/IB/RoCE resources with capacity > 0
5. **Generate config** - Creates YAML with resource requests and vLLM settings

### Output Format

```yaml
discovered:
  gpuCount: 8
  rdmaCount: 6
  tensorParallelSize: 8
  nodeCount: 3
  sampleNode: worker-node-1

resources:
  limits:
    cpu: "32"
    memory: "256Gi"
    nvidia.com/gpu: "8"
    rdma/rdma_shared_nic4: "1"
    rdma/rdma_shared_nic5: "1"
    rdma/rdma_shared_nic6: "1"
    rdma/rdma_shared_nic9: "1"
    rdma/rdma_shared_nic10: "1"
    rdma/rdma_shared_nic11: "1"
  requests:
    # ... same as limits

vllm:
  tensorParallelSize: 8

rdmaDevices:
  - nic4
  - nic5
  - nic6
  - nic9
  - nic10
  - nic11
```

## Usage in Overlays

All deployment jobs should run discovery as an init container:

```yaml
initContainers:
- name: discover-resources
  image: registry.access.redhat.com/ubi9/ubi:latest
  command: ["/bin/bash", "/scripts/discover-gpu-rdma.sh"]
  env:
    - name: OUTPUT_FILE
      value: "/data/discovered-resources.yaml"
  volumeMounts:
    - name: discovery-script
      mountPath: /scripts
    - name: shared-data
      mountPath: /data

containers:
- name: deploy
  # Use /data/discovered-resources.yaml to generate Helm values
  volumeMounts:
    - name: shared-data
      mountPath: /data

volumes:
- name: discovery-script
  configMap:
    name: gpu-rdma-discovery-script
    defaultMode: 0755
- name: shared-data
  emptyDir: {}
```

## Testing

Run discovery manually:

```bash
# Deploy the discovery ConfigMap
oc apply -k rig/llm-d/prereq/resource-discovery

# Run discovery from client pod
oc exec -it llm-d-client -n llm-d -- /bin/bash

# Inside pod:
export OUTPUT_FILE=/tmp/discovered.yaml
kubectl get configmap gpu-rdma-discovery-script -n llm-d -o jsonpath='{.data.discover-gpu-rdma\.sh}' | bash

# View results
cat /tmp/discovered.yaml
```

## Benefits

✅ **Portable** - Works across different cluster configurations
✅ **Accurate** - Always uses current cluster state
✅ **Complete** - Discovers all RDMA resource types
✅ **Shared** - Single source of truth for all overlays
✅ **Dynamic** - No hardcoded GPU counts or NIC names
✅ **Safe** - Only requests resources that exist

## Integration

This is used by llm-d overlays that need dynamic resource allocation:
- pd-disaggregation (single-node)
- pd-disaggregation-multinode
- wide-ep-multinode
- inference-scheduling (TODO)

Each overlay's deployment job runs this script to generate cluster-specific resource configurations.
