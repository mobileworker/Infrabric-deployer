# RDMA Interface Name Normalization

## Overview

This manifest normalizes RDMA interface names (InfiniBand & RoCE) across all nodes to enable consistent network configuration with RDMA shared devices.

**Wave: 25 (runs BEFORE NIC discovery)**

## Problem Solved

Different nodes may have different interface names for the same NIC position:
- Node 1: `ibp64s0` (InfiniBand, PCI `0000:40:00.0`)
- Node 2: `ibp64s0` (InfiniBand, PCI `0000:40:00.0`)
- Node 3: `ibp24s0` (InfiniBand, PCI `0000:18:00.0`)
- Node 4: `ens2f1np1` (RoCE, PCI `0000:29:00.1`)

CNI plugins require consistent interface names in NetworkAttachmentDefinitions, but we can't specify a single name that works across all nodes when names differ.

## Solution

Generate udev rules that rename RDMA interfaces based on PCI address to consistent names:
- Position 0 → `ib_nic0` (regardless of current name or link type)
- Position 1 → `ib_nic1`
- Position 2 → `ib_nic2`
- etc.

**Note**: The `ib_nic` prefix is used for all RDMA devices (both InfiniBand and RoCE) for backwards compatibility.

## How It Works

1. **Discovery Phase**
   - Job uses `oc debug node` to discover all RDMA-capable NICs on all worker nodes
   - Detects both InfiniBand (link_layer=InfiniBand) and RoCE (link_layer=Ethernet) devices
   - **Safety filters** - Excludes only interfaces actively in use by the cluster:
     - Interfaces with IP addresses assigned (management, pod network, etc.)
     - Virtual/bridge interfaces (br-*, veth*, ovn*, genev*, vlan*, bond*, team*)
   - **Physical RDMA NICs without IPs are renamed** - This includes RoCE devices on `ens*` or `eth*` ports that are RDMA-only (no IP configured)
   - Collects interface name + PCI address for each safe-to-rename RDMA NIC
   - Groups NICs by PCI address globally across all nodes

2. **Udev Rule Generation**
   - Maps each unique PCI address to a normalized name
   - Generates udev rules: `KERNELS=="PCI_ADDR" -> NAME="ib_nicX"`
   - Sorted by PCI address to ensure consistent numbering

3. **MachineConfig Application**
   - Creates MachineConfig `99-worker-normalize-ib-interfaces` with udev rules
   - Applies to all worker nodes
   - Triggers rolling reboot of worker nodes

4. **Result**
   - All nodes have consistent interface names: `ib_nic0`, `ib_nic1`, etc.
   - Works for both InfiniBand and RoCE devices
   - CNI plugins can use these names in NetworkAttachmentDefinitions

## Deployment Order

```
Wave 25  → This directory: Normalize RDMA interface names (IB + RoCE) → Nodes reboot
Wave 26a → NIC Discovery: Sees normalized names (ib_nic0, ib_nic1, etc.)
Wave 28  → NVIDIA Network Operator: Uses normalized names in network configurations
```

## Files

- `job-generate-ib-udev-rules.yaml`: Auto-discovery and udev rule generator
  - ServiceAccount, ClusterRole, ClusterRoleBinding
  - Job with embedded discovery and udev generation logic

## Verification

### Check if MachineConfig was created
```bash
oc get machineconfig 99-worker-normalize-ib-interfaces
```

### Monitor node reboot progress
```bash
oc get mcp worker -w
```

Wait for:
- `UPDATING=True` → Nodes are rebooting
- `UPDATED=True, DEGRADED=False` → All nodes updated successfully

### Verify new interface names (after reboot)
```bash
oc debug node/<node-name> -- chroot /host ip link show | grep ib_nic
```

Should see: `ib_nic0`, `ib_nic1`, `ib_nic2`, etc.

## Example Udev Rules Generated

```
# Auto-generated udev rules to normalize RDMA interface names (InfiniBand & RoCE)

# ib_nic0 <- PCI 0000:18:00.0 (InfiniBand)
SUBSYSTEM=="net", ACTION=="add", KERNELS=="0000:18:00.0", NAME="ib_nic0"

# ib_nic1 <- PCI 0000:29:00.0 (InfiniBand)
SUBSYSTEM=="net", ACTION=="add", KERNELS=="0000:29:00.0", NAME="ib_nic1"

# ib_nic2 <- PCI 0000:29:00.1 (RoCE)
SUBSYSTEM=="net", ACTION=="add", KERNELS=="0000:29:00.1", NAME="ib_nic2"

# ib_nic3 <- PCI 0000:40:00.0 (InfiniBand)
SUBSYSTEM=="net", ACTION=="add", KERNELS=="0000:40:00.0", NAME="ib_nic3"
```

## Benefits

✅ Consistent interface names across all nodes
✅ Works for both InfiniBand and RoCE devices
✅ CNI plugins can use single interface name in network configurations
✅ Fully automatic - no manual configuration needed
✅ Handles heterogeneous hardware configurations
✅ Works with any number of RDMA NICs
✅ Safe - excludes cluster-critical interfaces automatically

## Safety Mechanism

**The script will NEVER rename:**
- Interfaces with IP addresses assigned (these are in use by the cluster/management)
- Virtual/bridge interfaces (br-ex, ovn-k8s-mp0, veth*, etc.)

**The script WILL rename:**
- RDMA-capable physical NICs without IP addresses
- This includes both InfiniBand interfaces (ibp*, ib*)
- AND RoCE devices on standard names (ens*, eth*, enp*)

**Example:**
- `ens1f0` with IP address → **NOT renamed** (cluster network interface)
- `ens1f0` without IP but RDMA-capable → **Renamed to ib_nicX** (RoCE RDMA device)
- `ibp24s0` without IP → **Renamed to ib_nicX** (InfiniBand device)

## Notes

- Job runs in wave 25 (PreSync hook)
- Nodes will reboot after MachineConfig is applied
- This is a one-time operation per cluster
- If NICs are added/removed, re-run this job to update udev rules
- RoCE devices are treated identically to InfiniBand devices (both get `ib_nic` prefix)
