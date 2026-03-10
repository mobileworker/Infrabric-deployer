# NIC Discovery and Configuration (InfiniBand & RoCE)

Automatically discovers RDMA-capable network interfaces (InfiniBand and RoCE) and configures them using NVIDIA Network Operator.

## Overview

This discovers RDMA-capable network interfaces and configures NVIDIA Network Operator, providing:

- **PCI address-based resource allocation** - Stable device identification across reboots
- **Mixed topology support** - Handles nodes with different link types (InfiniBand vs RoCE) for the same PCI address
- **InfiniBand and RoCE** - Unified discovery for both link types
- **NetworkAttachmentDefinitions** - Standard Kubernetes networking instead of SR-IOV operator CRDs
- **Dynamic MOFED timeout** - Automatically calculates startup probe timeout based on VF count
- **Automatic cleanup** - Discovery DaemonSet auto-deleted after policy generation

## How It Works

### 1. NIC Discovery (DaemonSet: `nic-port-discovery`)

Scans each node for RDMA-capable NICs and collects:

- PCI addresses
- Device IDs
- Interface names
- Link type (InfiniBand vs RoCE/Ethernet)
- Maximum VF support
- **Physical link status (carrier)** - Detects if cable is connected and link is up

**Important**: Only ports with active physical connectivity (carrier=1) will be used to generate SR-IOV resources. Disconnected ports are automatically filtered out to prevent creating unusable networks.

### 2. Resource Generation (Job: `nic-resource-generator`)

Collects discovery results from all nodes and generates:

#### NicClusterPolicy

Configures NVIDIA Network Operator with:

- **MOFED Driver**: OFED version auto-detected from operator CSV
  - `RESTORE_DRIVER_ON_POD_TERMINATION=false` - Prevents VF state corruption
  - **Dynamic startup probe timeout** - Calculated based on total VF count across all nodes
    - Formula: `failureThreshold = max(60, ((total_vfs × 5s × 1.3) / 20s) + 10)`
    - Example: 576 VFs (36 ports × 16) = ~65 minute timeout (failureThreshold: 197)
    - Prevents pod termination during VF restoration
- **SR-IOV Device Plugin**: PCI-based resource allocation (`nvidia.com/ibp24s0_ib`, `nvidia.com/ens2f1np1_roce`, etc.)
  - Resources created based on discovered NICs (1 VF = 1 allocatable resource per NIC)
  - Supports mixed topologies: same PCI address with different link types across nodes

Example generated resource:

```yaml
sriovDevicePlugin:
  config: |
    {
      "resourceList": [
        {
          "resourcePrefix": "nvidia.com",
          "resourceName": "ibp24s0_ib",
          "selectors": {
            "vendors": ["15b3"],
            "devices": ["101e"],
            "drivers": ["mlx5_core"],
            "rootDevices": ["0000:18:00.0"],
            "isRdma": true,
            "linkTypes": ["infiniband"]
          }
        }
      ]
    }
```

#### NetworkAttachmentDefinitions

Creates network attachments using `host-device` CNI plugin:

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ibp24s0-network
  namespace: default
  annotations:
    k8s.v1.cni.cncf.io/resourceName: nvidia.com/ibp24s0_ib
spec:
  config: |-
    {
      "cniVersion": "0.4.0",
      "type": "host-device",
      "name": "ibp24s0-network",
      "ipam": {
        "type": "whereabouts",
        "range": "10.0.101.0/24",
        "routes": [{"dst": "192.168.75.0/24"}]
      }
    }
```

## Configuration

All configuration is in `job-generator.yaml`:

```yaml
env:
  # Virtual Functions per NIC (resource allocation)
  # Set to 1 to expose 1 allocatable resource per NIC
  # IMPORTANT: MachineConfig (wave 26) creates 16 VFs per NIC at boot
  # This value controls SR-IOV device plugin resource advertisement (1 VF = 1 resource)
  - name: NUM_VFS
    value: "1"

  # IP address management
  - name: IP_RANGE_BASE
    value: "10.0"  # First two octets of IP addresses

  # Subnet mode: "separate" (each NIC gets own subnet) or "shared"
  - name: SUBNET_MODE
    value: "separate"

  # Route destination (auto-incremented in separate mode)
  - name: ROUTE_DEST
    value: "192.168.75.0/24"

  # MTU for SR-IOV networks (default: 9000 for jumbo frames)
  - name: MTU
    value: "9000"

  # Namespace where NetworkAttachmentDefinitions are created
  - name: NETWORK_NAMESPACE
    value: "default"
```

## Deployment Order (ArgoCD Sync Waves)

- Wave 28: NVIDIA Network Operator namespace
- Wave 29: Wait for MOFED ready
- Wave 35: **PreSync Hook** → Wait for MCPs ready → NIC Discovery → Creates NicClusterPolicy (triggers MOFED deployment)
- Wave 40: Wait for MOFED pods → GPU Operator deployment

## Automatic Cleanup

After NicClusterPolicy is successfully created and applied:

- **Discovery DaemonSet**: Automatically deleted by generator script (no longer needed)
- **Generator Job**: Auto-deleted 2 minutes after completion (ttlSecondsAfterFinished: 120)
- **Discovery pods**: Removed via DaemonSet deletion

This ensures discovery resources don't persist after their purpose is fulfilled.

### PreSync Hook: MachineConfigPool Wait

**Why it's needed:**

Wave 26 deploys MachineConfigs that configure SR-IOV VFs on nodes. The MachineConfig Operator (MCO) needs time to:
1. Detect the new MachineConfigs
2. Render updated configurations
3. Update nodes (drain, reboot, reconfigure)
4. Bring nodes back online

If NicClusterPolicy is created before nodes are ready, MOFED pods will fail to deploy or configure NICs incorrectly.

**How it works:**

The PreSync hook (Job: `wait-for-mcp-ready`) blocks wave 35 deployment until all MachineConfigPools show UPDATING=False:

1. Sleeps 2 minutes for MCO to detect changes
2. Checks all MCPs for UPDATING status
3. Waits in a loop (checking every 5 seconds) until UPDATING=False
4. Times out after 90 minutes if MCPs don't complete

**Tracking MachineConfig progress:**

```bash
# Check MachineConfigPool status (UPDATING column shows progress)
oc get mcp

# Expected output during updates:
# NAME         UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT
# master       True      False      False      3              3                   3
# worker       False     True       False      2              0                   1    ← Updating
# worker-dgx   False     True       False      3              1                   2    ← Updating

# Follow the PreSync hook job logs
oc logs -n default job/wait-for-mcp-ready -f

# Example log output:
# ==========================================
# Waiting for MachineConfigPools to be Ready
# ==========================================
#
# Waiting 2 minutes for MCO to detect changes and start updating...
# Checking MachineConfigPools... (120s elapsed)
# MachineConfigPool Status:
#   master: Ready
#   worker: UPDATING
#   worker-dgx: UPDATING
# Waiting for MCPs to complete updates... (120s/5400s elapsed)

# Check when the PreSync hook completes
oc get job wait-for-mcp-ready -n default

# Check ArgoCD application status (will show "waiting for hook" until MCP job completes)
oc get application nic-discovery -n openshift-gitops
```

**What happens when MCPs are ready:**

1. PreSync hook job completes successfully
2. Wave 35 proceeds → NIC discovery runs
3. NicClusterPolicy is created with complete VF configuration
4. MOFED DaemonSet deploys to all nodes
5. MOFED pods compile drivers and configure NICs

## Using RDMA NICs in Pods

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rdma-test
  annotations:
    k8s.v1.cni.cncf.io/networks: ibp24s0-network
spec:
  containers:
  - name: app
    image: your-image
    resources:
      requests:
        nvidia.com/ibp24s0_ib: '1'
      limits:
        nvidia.com/ibp24s0_ib: '1'
    securityContext:
      capabilities:
        add: ["IPC_LOCK"]
```

## Resource Naming Convention

Resources are named by PF interface name + link type:

- `nvidia.com/ibp24s0_ib` - InfiniBand interface ibp24s0
- `nvidia.com/ens2f1np1_roce` - RoCE interface ens2f1np1
- `nvidia.com/ibs2f0_ib` - InfiniBand interface ibs2f0

This provides:
- Human-readable resource names
- Clear indication of link type (IB vs RoCE)
- Easy to match with interface names
- PCI addresses are used in selectors for stability

## Subnet Modes

### Separate Mode (Default, Recommended)

Each NIC gets its own subnet with unique route destination:

```
ens3f0np0  → 10.0.101.0/24 → route to 192.168.75.0/24
ens3f1np1  → 10.0.102.0/24 → route to 192.168.76.0/24
ibp24s0    → 10.0.103.0/24 → route to 192.168.77.0/24
```

Benefits:
- Network isolation between NICs
- No routing ambiguity
- Maximum parallel performance
- 254 IPs per NIC

### Shared Mode

All NICs share the same subnet:

```
All NICs → 10.0.100.0/24 → route to 192.168.75.0/24
```

Benefits:
- Layer-2 connectivity between pods on different NICs
- Simple flat network

Limitations:
- Only 254 IPs total (shared by all pods)
- No network isolation

## Verification

```bash
# Check discovery
oc get pods -n default -l app=nic-port-discovery -o wide

# Check resource generation
oc get job -n default nic-resource-generator

# View generated NicClusterPolicy
oc get nicclusterpolicy nic-cluster-policy -n nvidia-network-operator -o yaml

# View NetworkAttachmentDefinitions
oc get network-attachment-definitions -n default

# Check node resources
oc get nodes -o json | jq '.items[] | {
  name: .metadata.name,
  nic_resources: (.status.allocatable | to_entries | map(select(.key | contains("_ib") or .key | contains("_roce"))))
}'
```

## MOFED Driver and SR-IOV Device Plugin Deployment

**IMPORTANT: MOFED compilation takes time (5-10 minutes per node). The SR-IOV device plugin deploys per-node only after MOFED is ready on that node.**

### Deployment Timeline

After NicClusterPolicy is created (wave 35):

1. **MOFED DaemonSet deploys** to all nodes with Mellanox NICs
2. **Each MOFED pod compiles drivers** from source (5-10 minutes per node)
3. **SR-IOV device plugin deploys per-node** as each MOFED pod becomes ready
4. **RDMA resources appear** on each node after SR-IOV device plugin starts

**Do not expect all components to deploy simultaneously.** This is normal phased deployment behavior.

### Tracking MOFED Driver Compilation

```bash
# Watch MOFED pods across all nodes (should see 1 pod per worker-dgx node)
watch oc get pods -n nvidia-network-operator -l nvidia.com/ofed-driver

# Expected output during compilation:
# NAME                                READY   STATUS    RESTARTS   AGE
# mofed-rhel9.6-xxx-ds-abc123         1/2     Running   0          3m   ← Compiling drivers
# mofed-rhel9.6-xxx-ds-def456         2/2     Running   0          8m   ← Ready
# mofed-rhel9.6-xxx-ds-ghi789         1/2     Running   0          5m   ← Compiling drivers

# Follow MOFED compilation logs on a specific node
oc logs -n nvidia-network-operator -l nvidia.com/ofed-driver --tail=20 -f

# Check which nodes have MOFED ready
oc get nodes -l network.nvidia.com/operator.mofed.wait=false
# Only nodes with label "mofed.wait=false" will have SR-IOV device plugin
```

**MOFED Pod States:**
- `1/2 Running` - Driver compilation in progress (takes 5-10 minutes)
- `2/2 Running` - Drivers compiled and loaded, node is ready

### Tracking SR-IOV Device Plugin Deployment

The SR-IOV device plugin uses this node selector:
```yaml
nodeSelector:
  feature.node.kubernetes.io/pci-15b3.present: "true"    # Has Mellanox NICs
  network.nvidia.com/operator.mofed.wait: "false"        # MOFED is ready
```

**This means:**
- SR-IOV device plugin will NOT deploy until MOFED is ready on a node
- You'll see pods deploy gradually as MOFED completes on each node
- Final count should match number of nodes with Mellanox NICs

```bash
# Watch SR-IOV device plugin deployment (should eventually see 1 pod per worker-dgx node)
watch oc get pods -n nvidia-network-operator -l app=sriovdp

# Check DaemonSet status
oc get daemonset network-operator-sriov-device-plugin -n nvidia-network-operator
# DESIRED = number of nodes with Mellanox NICs AND MOFED ready
# CURRENT = number of SR-IOV device plugin pods deployed
# READY   = number of SR-IOV device plugin pods ready

# Example during phased deployment:
# NAME                                   DESIRED   CURRENT   READY
# network-operator-sriov-device-plugin   2         2         2     ← 2 nodes have MOFED ready
# (Will become 3/3/3 when third node's MOFED finishes compiling)
```

### Tracking RDMA Resource Advertisement

After SR-IOV device plugin deploys on a node, RDMA resources appear in node capacity:

```bash
# Check RDMA resources on all nodes
oc get nodes -o json | jq -r '.items[] |
  "\(.metadata.name):\n" +
  ((.status.allocatable // {}) |
   to_entries |
   map(select(.key | contains("_ib") or contains("_roce"))) |
   map("  \(.key): \(.value)") |
   join("\n"))'

# Expected output (increases as SR-IOV device plugin deploys per-node):
# ocp-poc26704-13779:
#   nvidia.com/ibp24s0_ib: 16
#   nvidia.com/ens3f0np0_roce: 8
# ocp-poc26704-13780:
#   (empty - MOFED still compiling)
# ocp-poc26704-13781:
#   nvidia.com/ibp24s0_ib: 16
```

### Complete Status Check

Monitor all components together:

```bash
# Single command to check everything
watch 'echo "=== MOFED Pods ===" && \
oc get pods -n nvidia-network-operator -l nvidia.com/ofed-driver && \
echo -e "\n=== SR-IOV Device Plugin Pods ===" && \
oc get pods -n nvidia-network-operator -l app=sriovdp && \
echo -e "\n=== Nodes with MOFED Ready ===" && \
oc get nodes -l network.nvidia.com/operator.mofed.wait=false'
```

**Deployment is complete when:**
- All MOFED pods show `2/2 Running`
- SR-IOV device plugin pod count matches number of worker-dgx nodes
- All nodes advertise RDMA resources (check with `oc get nodes -o json | jq` command above)

## Differences from SR-IOV Operator Approach

| Feature | SR-IOV Operator (REMOVED) | NVIDIA Network Operator (CURRENT) |
|---------|----------------|------------------------|
| Device Plugin | OpenShift SR-IOV operator | NVIDIA SR-IOV device plugin |
| Resource CRDs | SriovNetworkNodePolicy | NicClusterPolicy |
| Network CRDs | SriovNetwork, SriovIBNetwork | NetworkAttachmentDefinition |
| VF Creation | Operator-managed via daemon | **MachineConfig systemd service (boot-time)** |
| Resource Naming | Interface-based | PCI address-based (pfName + link type) |
| Node Drain | Required for VF changes | Not needed (VFs created at boot) |
| InfiniBand Support | Limited (netlink bugs) | Full support |
| Mixed Topology | Not supported | Same PCI address, different link types per node |
| MOFED Timeout | Static | Dynamic (calculated from VF count) |

## Troubleshooting

### No Resources Advertised

```bash
# Check SR-IOV device plugin logs
oc logs -n nvidia-network-operator -l app=sriovdp

# Verify VFs were created
oc debug node/<node-name> -- chroot /host bash -c "lspci | grep 'Virtual Function'"
```

### VF Creation Failed

VFs are created by MachineConfig systemd service at boot, not by NVIDIA Network Operator.

```bash
# Check systemd service status on node
oc debug node/<node-name> -- chroot /host systemctl status sriov-configure-max-vfs.service

# Check systemd service logs
oc debug node/<node-name> -- chroot /host journalctl -u sriov-configure-max-vfs.service

# Manually check VFs were created
oc debug node/<node-name> -- chroot /host bash -c "cat /sys/bus/pci/devices/0000:18:00.0/sriov_numvfs"

# Expected output: 16 (not 0)
```

See [SR-IOV VF Configuration README](../26-sriov-vf-config/README.md) for MachineConfig troubleshooting.

### NetworkAttachmentDefinition Not Working

```bash
# Check Multus logs
oc logs -n openshift-multus -l app=multus

# Verify network definition
oc get network-attachment-definitions -n default -o yaml
```

## Migration from SR-IOV Operator

If migrating from SR-IOV operator:

1. Remove existing SR-IOV policies and networks
2. Remove SR-IOV operator
3. Deploy NVIDIA Network Operator
4. Deploy NIC discovery
5. VFs will be recreated automatically

## Related Documentation

- [NVIDIA Network Operator](../28-nvidia-network-operator/README.md)
- [Baremetal Deployment Guide](../../rig/baremetal/README.md)
- [NVIDIA Network Operator Docs](https://docs.nvidia.com/networking/display/cokan10/network+operator)
