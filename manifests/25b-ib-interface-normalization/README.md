# InfiniBand Interface Name Normalization

## Overview

This manifest normalizes InfiniBand interface names across all nodes to enable IPoIB CNI with RDMA shared devices.

**Wave: 25 (runs BEFORE NIC discovery)**

## Problem Solved

Different nodes may have different interface names for the same NIC position:
- Node 1: `ibp64s0` (PCI `0000:40:00.0`)
- Node 2: `ibp64s0` (PCI `0000:40:00.0`)
- Node 3: `ibp24s0` (PCI `0000:18:00.0`)

IPoIB CNI requires a `master` interface name in NetworkAttachmentDefinitions, but we can't specify a single name that works across all nodes when names differ.

## Solution

Generate udev rules that rename interfaces based on PCI address to consistent names:
- Position 0 → `ib_nic0` (regardless of current name)
- Position 1 → `ib_nic1`
- Position 2 → `ib_nic2`
- etc.

## How It Works

1. **Discovery Phase**
   - Job uses `oc debug node` to discover InfiniBand NICs on all worker nodes
   - Collects interface name + PCI address for each NIC
   - Groups NICs by position (sorted by interface name for consistency)

2. **Udev Rule Generation**
   - Maps each NIC position to all PCI addresses across nodes
   - Generates udev rules: `KERNELS=="PCI_ADDR" -> NAME="ib_nicX"`
   - Multiple PCI addresses can map to same normalized name (for different nodes)

3. **MachineConfig Application**
   - Creates MachineConfig with udev rules
   - Applies to all worker nodes
   - Triggers rolling reboot of worker nodes

4. **Result**
   - All nodes have consistent interface names: `ib_nic0`, `ib_nic1`, etc.
   - IPoIB CNI can use these names in NetworkAttachmentDefinitions

## Deployment Order

```
Wave 25  → This directory: Normalize IB interface names → Nodes reboot
Wave 26a → NIC Discovery: Sees normalized names (ib_nic0, ib_nic1, etc.)
Wave 28  → NVIDIA Network Operator: Uses normalized names in IPoIB networks
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
# Position 0 -> ib_nic0
SUBSYSTEM=="net", ACTION=="add", KERNELS=="0000:9a:00.0", NAME="ib_nic0"

# Position 4 -> ib_nic4 (handles different PCI addresses across nodes)
SUBSYSTEM=="net", ACTION=="add", KERNELS=="0000:40:00.0", NAME="ib_nic4"
SUBSYSTEM=="net", ACTION=="add", KERNELS=="0000:18:00.0", NAME="ib_nic4"
```

## Benefits

✅ Consistent interface names across all nodes
✅ IPoIB CNI can use single master interface name
✅ Fully automatic - no manual configuration needed
✅ Handles heterogeneous hardware configurations
✅ Works with any number of NICs

## Notes

- Job runs in wave 25 (PreSync hook)
- Nodes will reboot after MachineConfig is applied
- This is a one-time operation per cluster
- If NICs are added/removed, re-run this job to update udev rules
