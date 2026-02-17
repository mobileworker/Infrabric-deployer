# NVIDIA Network Operator (InfiniBand Only)

## Overview

This manifest configures the **NVIDIA Network Operator** to handle **InfiniBand devices only** using RDMA shared devices.

**IMPORTANT**: This is part of a hybrid RDMA architecture:
- **SR-IOV Network Operator** (manifest 25a): Handles RoCE/Ethernet devices with dedicated VFs
- **NVIDIA Network Operator** (this directory): Handles InfiniBand devices with RDMA shared devices

## Why Hybrid Approach?

InfiniBand NICs with many VFs (16+) cause "message too long" errors when SR-IOV operator queries VF state via netlink. The kernel's ~4KB netlink response limit is exceeded.

**Solution:**
- **RoCE devices**: Use SR-IOV (no InfiniBand-specific large responses)
- **InfiniBand devices**: Use RDMA shared devices to avoid netlink queries entirely

## Architecture

### RDMA Shared Devices

Instead of creating VFs, RDMA shared devices allow multiple pods to share the Physical Function (PF):
- No VF creation required
- No netlink PAGE_SIZE limitation
- Separate resource per unique interface name for granular control
- Global resource naming for multi-node deployments

### Per-NIC Resources

**IMPORTANT**: After wave 25b interface normalization, the generator creates one RDMA resource per **unique interface name**:
- `rdma/rdma_shared_nic0` = all `ib_nic0` interfaces (same PCI address across all nodes)
- `rdma/rdma_shared_nic1` = all `ib_nic1` interfaces (same PCI address across all nodes)
- `rdma/rdma_shared_nic2` = all `ib_nic2` interfaces (same PCI address across all nodes)
- ... etc

**Why Interface-Name-Based (not position-based)?**
- Wave 25b normalizes interface names: same PCI address → same interface name (`ib_nicX`)
- Different nodes may have different NICs online (carrier status)
- Interface-name grouping ensures: **same interface name = same physical NIC (PCI address)**
- Position-based grouping would fail: Node A position 0 ≠ Node B position 0 if different NICs are online

**Example:**
- Node A online: `ib_nic0` (0000:18:00.0), `ib_nic3` (0000:40:00.0), `ib_nic5` (0000:5e:00.0)
- Node B online: `ib_nic0` (0000:18:00.0), `ib_nic1` (0000:29:00.0), `ib_nic3` (0000:40:00.0)
- Resource `rdma_shared_nic3` → both nodes' `ib_nic3` (PCI 0000:40:00.0) ✓ Correct!

This allows:
- Pods to request the same resource name regardless of which node they run on
- Scheduler automatically places pods on nodes that have the requested NIC
- Handles heterogeneous configurations (different NICs online per node)

## Components

### 1. RDMA Configuration Generator (job-generate-rdma-config.yaml)

Auto-generates RDMA configuration from discovered InfiniBand devices:

**Input:**
- IB devices from SR-IOV discovery configmap (`generated-sriov-resources`)
- Only devices with carrier=1 (online, cable connected) are included

**Output:**
- NicClusterPolicy patch with:
  - RDMA shared device plugin config (one resource per unique interface name)
  - IPoIB CNI (only if IB devices detected)
- NetworkAttachmentDefinitions for IPoIB networking

**Behavior:**
- Only runs if InfiniBand devices are detected
- If no IB devices found: Only deploys MOFED drivers (no RDMA plugin, no IPoIB)
- Groups by interface name (ib_nicX) after wave 25b normalization
- Handles heterogeneous configurations (different NICs online per node)
- Only creates resources for NICs that have carrier=1 on at least one node

### 2. Base NicClusterPolicy (nicclusterpolicy.yaml)

Empty base policy - actual configuration is generated dynamically by:
1. NIC discovery (manifest 26a): Creates base policy with MOFED drivers
2. RDMA generator (this manifest): Patches in RDMA shared device plugin + IPoIB CNI

## Configuration

### Environment Variables (job-generate-rdma-config.yaml)

```yaml
env:
  # Subnet mode: "separate" (one network per NIC) or "shared" (one network for all NICs)
  - name: SUBNET_MODE
    value: "separate"  # Default: separate subnets per NIC

  # IP address management
  - name: IP_RANGE_BASE
    value: "10.0"  # First two octets of IP addresses

  # Route destination (auto-incremented in separate mode)
  - name: ROUTE_DEST
    value: "192.168.75.0/24"

  # MTU for InfiniBand networks (default: 9000 for jumbo frames)
  - name: MTU
    value: "9000"

  # Namespace where NetworkAttachmentDefinitions are created
  - name: NETWORK_NAMESPACE
    value: "default"
```

### SUBNET_MODE Options

#### Option 1: Separate (Default)
One NetworkAttachmentDefinition per NIC position, each with its own subnet.

**Created Networks:**
- `rdma-nic0`: 10.0.101.0/24 → route to 192.168.75.0/24
- `rdma-nic1`: 10.0.102.0/24 → route to 192.168.76.0/24
- `rdma-nic2`: 10.0.103.0/24 → route to 192.168.77.0/24
- ... (one per NIC position)

**Use Case:** Network isolation between different NICs

#### Option 2: Shared
One NetworkAttachmentDefinition for all NICs, shared subnet.

**Created Network:**
- `rdma-ib-shared`: 10.0.100.0/24 → route to 192.168.75.0/24

**Use Case:** All NICs can reach each other, single subnet for entire cluster

## Deployment Order

1. **Wave 25a**: SR-IOV Network Operator installation
2. **Wave 26a**: NIC discovery
   - Discovers all Mellanox/NVIDIA NICs
   - Separates RoCE and InfiniBand devices
   - Creates base NicClusterPolicy with MOFED drivers
   - Exports IB devices to configmap
3. **Wave 28**: NVIDIA Network Operator (this directory)
   - Reads IB devices from configmap
   - Patches NicClusterPolicy with RDMA shared device plugin + IPoIB CNI
   - Creates NetworkAttachmentDefinitions

## Using RDMA Resources in Pods

### Example: Separate Subnet Mode

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rdma-test
  annotations:
    k8s.v1.cni.cncf.io/networks: rdma-nic0
spec:
  containers:
  - name: app
    image: your-rdma-app
    resources:
      requests:
        rdma/rdma_shared_nic0: 1
      limits:
        rdma/rdma_shared_nic0: 1
    securityContext:
      capabilities:
        add: ["IPC_LOCK"]
```

**Result:**
- Pod gets scheduled on a node that has NIC position 0
- Pod gets an IP from 10.0.101.0/24 subnet
- Pod has access to the InfiniBand NIC via RDMA shared device

### Example: Multi-Node Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rdma-workload
spec:
  replicas: 5
  template:
    metadata:
      annotations:
        k8s.v1.cni.cncf.io/networks: rdma-nic0
    spec:
      containers:
      - name: app
        image: your-rdma-app
        resources:
          requests:
            rdma/rdma_shared_nic0: 1
          limits:
            rdma/rdma_shared_nic0: 1
```

**Result:**
- All 5 pods request `rdma_shared_nic0`
- Scheduler places pods across available nodes
- Each pod gets the 1st NIC on its assigned node
- All pods have consistent resource naming

## Heterogeneous Configurations

The generator handles nodes with different NIC counts:

**Example Cluster:**
- Node A: 2 NICs connected
- Node B: 8 NICs connected

**Created Resources:**
- `rdma_shared_nic0`: Available on both nodes (both have 1st NIC)
- `rdma_shared_nic1`: Available on both nodes (both have 2nd NIC)
- `rdma_shared_nic2-7`: Only available on Node B

**Scheduler Behavior:**
- Pods requesting `rdma_shared_nic0` or `nic1`: Can schedule on any node
- Pods requesting `rdma_shared_nic2-7`: Only schedule on Node B

## Connectivity Check

Only NICs with physical connectivity (carrier=1) are included in the configuration.

**Discovery checks:**
- `/sys/class/net/<interface>/carrier` must be "1"
- `/sys/class/net/<interface>/operstate` must be "up"

Disconnected or down NICs are automatically excluded.

## Files

- `job-generate-rdma-config.yaml`: RDMA configuration generator
  - ServiceAccount, ClusterRole, ClusterRoleBinding
  - ConfigMap with Python generator script
  - Job to run generator
- `nicclusterpolicy.yaml`: Base NicClusterPolicy (empty, filled by generators)
- `kustomization.yaml`: Kustomize configuration
- `presync-wait-for-sriov-mcp.yaml`: PreSync hook to wait for MachineConfigs

## Verification

### Check RDMA Resources

```bash
# Check NicClusterPolicy status
oc get nicclusterpolicy nic-cluster-policy -n nvidia-network-operator -o yaml

# Check RDMA resources on nodes
oc get nodes -o json | jq -r '.items[] | .metadata.name as $node | .status.capacity | to_entries[] | select(.key | contains("rdma_shared_nic")) | "\($node): \(.key)=\(.value)"'

# Check RDMA device plugin pods
oc get pods -n nvidia-network-operator -l app=rdma-shared-dp

# Check IPoIB CNI pods
oc get pods -n nvidia-network-operator -l app=ipoib-cni
```

### Check NetworkAttachmentDefinitions

```bash
# List networks
oc get network-attachment-definitions -n default | grep rdma

# View specific network
oc get network-attachment-definition rdma-nic0 -n default -o yaml
```

### Check MOFED Drivers

```bash
# Check OFED driver pods
oc get pods -n nvidia-network-operator -l app=mofed-driver

# Check driver version
oc logs -n nvidia-network-operator -l app=mofed-driver -c mofed-container | grep "MOFED version"
```

## Related Manifests

- `25a-sriov-operator`: SR-IOV Network Operator (handles RoCE devices)
- `26a-sriov-discovery`: NIC discovery and base NicClusterPolicy generation
- `26-sriov-vf-config`: VF creation for RoCE devices (MachineConfig)

## References

- [NVIDIA Network Operator Documentation](https://docs.nvidia.com/networking/display/cokan10/network+operator)
- [RDMA Shared Device Plugin](https://github.com/Mellanox/k8s-rdma-shared-dev-plugin)
- [IPoIB CNI](https://github.com/Mellanox/ipoib-cni)
- [Netlink PAGE_SIZE Issue](https://github.com/k8snetworkplumbingwg/sriov-network-operator/pull/1026)
