# RoCE/InfiniBand Discovery and SR-IOV Resource Generator

Automatically discovers RDMA-capable network interfaces (RoCE and InfiniBand) and generates SR-IOV policies and networks.

## Table of Contents
- [Quick Start](#quick-start)
- [Link Type Auto-Detection](#link-type-auto-detection)
- [Subnet Configuration Modes](#subnet-configuration-modes)
- [Configuration Examples](#configuration-examples)
- [Routing Behavior](#routing-behavior)
- [How It Works](#how-it-works)
- [Verification](#verification)
- [Advanced Configuration](#advanced-configuration)
- [Troubleshooting](#troubleshooting)
- [Related Documentation](#related-documentation)

## Quick Start

The generator automatically discovers all Mellanox/NVIDIA NICs with RDMA capability (both RoCE and InfiniBand) and creates SR-IOV resources. **No manual configuration needed for basic deployment.**

## Link Type Auto-Detection

The discovery system **automatically detects** whether your NICs are configured for:
- **InfiniBand** native fabric (`linkType: ib`) - automatically sets `numVfs: 16`
- **RoCE** (RDMA over Converged Ethernet) (`linkType: eth`) - uses configured `NUM_VFS` (default: 1)

### Detection Methods

The discovery script uses multiple methods to determine the link type:

1. **Primary**: Reads `/sys/class/infiniband/<device>/ports/*/link_layer` from the hardware
   - "InfiniBand" → `linkType: ib`
   - "Ethernet" → `linkType: eth`

2. **Fallback**: Checks interface naming patterns
   - Interfaces starting with `ib*` → `linkType: ib`
   - Other interfaces → `linkType: eth` (default)

**No manual configuration required** - the correct `linkType` and `numVfs` will be set automatically in the generated `SriovNetworkNodePolicy` resources.

### Important Notes

1. **Link Type Detection**: The link type is determined by the **hardware firmware configuration**, not the interface name. An interface named `ens2f1np1` can have InfiniBand mode if the firmware is configured that way. The discovery script detects the actual link layer from sysfs.

2. **VF Count for InfiniBand**: InfiniBand interfaces automatically get `numVfs: 16` because:
   - InfiniBand requires more VFs for proper RDMA operation
   - Mellanox firmware for IB mode expects 16 VFs as the standard configuration
   - Using fewer VFs can cause firmware configuration issues and reboot loops

3. **VF Count for RoCE**: RoCE/Ethernet interfaces use the configured `NUM_VFS` value (default: 1) which is safe and sufficient for most workloads.

### Manual Override (Optional)

If auto-detection fails or you need to override the detected value:

```yaml
# manifests/35-roce-discovery/job-generator.yaml
env:
  - name: LINK_TYPE
    value: "ib"  # Force InfiniBand mode
    # or
    value: "eth" # Force RoCE/Ethernet mode
```

This fallback value is only used if hardware detection fails.

## Subnet Configuration Modes

You can configure how IP addresses are allocated to SR-IOV networks by setting `SUBNET_MODE` in `job-generator.yaml`.

### Mode 1: Separate Subnets (DEFAULT - Recommended)

**Each NIC gets its own isolated /24 subnet with unique route destination:**

```yaml
env:
  - name: SUBNET_MODE
    value: "separate"  # DEFAULT
  - name: IP_RANGE_BASE
    value: "10.0"
  - name: ROUTE_DEST
    value: "192.168.75.0/24"  # Base route (auto-incremented per NIC)
```

**Result:**
- `ens3f0np0` → `10.0.101.0/24` (254 IPs) → route to `192.168.75.0/24`
- `ens3f1np1` → `10.0.102.0/24` (254 IPs) → route to `192.168.76.0/24`
- `ens7f0np0` → `10.0.103.0/24` (254 IPs) → route to `192.168.77.0/24`

**Benefits:**
- ✅ Network isolation between NICs (Layer-3 separated subnets)
- ✅ **No routing ambiguity** - each NIC has unique route destination
- ✅ Optimal parallel performance (no kernel routing conflicts)
- ✅ Running multi-tenant workloads
- ✅ Segregating traffic types (storage vs compute)
- ✅ Maximum scalability (254 IPs × number of NICs)

### Mode 2: Shared Subnet

**All NICs share the same /24 subnet:**

```yaml
env:
  - name: SUBNET_MODE
    value: "shared"
  - name: IP_RANGE_BASE
    value: "10.0"
```

**Result:**
- `ens3f0np0` → `10.0.100.0/24` (shared pool)
- `ens3f1np1` → `10.0.100.0/24` (shared pool)
- `ens7f0np0` → `10.0.100.0/24` (shared pool)
- Total: **254 IPs shared across all NICs**

**Use when:**
- ✅ Pods on different NICs need layer-2 connectivity
- ✅ Legacy applications expect flat network
- ✅ High-availability pairs require same subnet

**Limitations:**
- ⚠️  Only 254 IPs total (shared by all pods on all NICs)
- ⚠️  No network isolation
- ⚠️  Risk of IP exhaustion with many pods

## Configuring VF Counts

Virtual Function (VF) counts are configured in `manifests/35-roce-discovery/job-generator.yaml`:

**Location to set defaults:**
```yaml
# manifests/35-roce-discovery/job-generator.yaml
env:
  - name: NUM_VFS
    value: "8"              # Default VFs for RoCE interfaces
```

**How VF counts are determined:**
- **InfiniBand interfaces**: Always get `numVfs: 16` (automatically detected, cannot be overridden)
- **RoCE interfaces**: Use the `NUM_VFS` value from job-generator.yaml (default: 8)

**Why these defaults?**
- InfiniBand requires exactly 16 VFs for proper firmware operation
- RoCE default of 8 provides good balance between resources and flexibility
- You can adjust NUM_VFS for RoCE (1-16), but InfiniBand always gets 16

## Configuration Examples

### Example 1: Default Configuration (Separate Subnets)

```yaml
# manifests/35-roce-discovery/job-generator.yaml
env:
  - name: NUM_VFS
    value: "8"              # 8 VFs per RoCE NIC (InfiniBand auto-detects as 16)
  - name: MTU
    value: "9000"           # Jumbo frames for RDMA
  - name: SUBNET_MODE
    value: "separate"       # Each NIC gets own subnet
  - name: IP_RANGE_BASE
    value: "10.0"           # Use 10.0.x.x addresses
  - name: NETWORK_NAMESPACE
    value: "default"
  - name: ROUTE_DEST
    value: "192.168.75.0/24"
```

**Generates:**
```yaml
# SriovNetworkNodePolicy for RoCE interface (ens3f0np0)
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: policy-ens3f0np0
spec:
  deviceType: netdevice
  isRdma: true
  linkType: eth          # Auto-detected as RoCE
  numVfs: 8              # Default for RoCE
  resourceName: ens3f0np0rdma

---
# SriovNetworkNodePolicy for InfiniBand interface (ibp24s0)
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: policy-ibp24s0
spec:
  deviceType: netdevice
  isRdma: true
  linkType: ib           # Auto-detected as InfiniBand
  numVfs: 16             # Automatically set to 16 for IB
  resourceName: ibp24s0rdma

---
# SriovNetwork for ens3f0np0
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetwork
metadata:
  name: ens3f0np0-network
spec:
  ipam: |
    {
      "type": "whereabouts",
      "range": "10.0.101.0/24",
      "routes": [{"dst": "192.168.75.0/24"}]  # First NIC uses base route
    }
  resourceName: ens3f0np0rdma

---
# SriovNetwork for ibp24s0
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetwork
metadata:
  name: ibp24s0-network
spec:
  ipam: |
    {
      "type": "whereabouts",
      "range": "10.0.102.0/24",
      "routes": [{"dst": "192.168.76.0/24"}]  # Second NIC auto-incremented to .76
    }
  resourceName: ibp24s0rdma
```

**Note:**
- InfiniBand interfaces automatically receive `numVfs: 16` regardless of `NUM_VFS` environment variable
- RoCE interfaces use the configured `NUM_VFS` value (default: 8)
- In "separate" mode, route destinations are automatically incremented per NIC (192.168.75.0/24 → 192.168.76.0/24 → 192.168.77.0/24, etc.) to avoid routing ambiguity and ensure optimal parallel performance

### Example 2: Shared Subnet with Custom IP Range

```yaml
# manifests/35-roce-discovery/job-generator.yaml
env:
  - name: SUBNET_MODE
    value: "shared"         # All NICs share subnet
  - name: IP_RANGE_BASE
    value: "192.168"        # Use 192.168.x.x addresses
```

**Generates:**
```yaml
# All SriovNetworks use same subnet
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetwork
metadata:
  name: ens3f0np0-network
spec:
  ipam: |
    {
      "type": "whereabouts",
      "range": "192.168.100.0/24",  # Shared with all NICs
      ...
    }
---
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetwork
metadata:
  name: ens3f1np1-network
spec:
  ipam: |
    {
      "type": "whereabouts",
      "range": "192.168.100.0/24",  # Same subnet
      ...
    }
```

### Example 3: Multiple VFs with 172.16.x.x Range

```yaml
env:
  - name: NUM_VFS
    value: "4"              # 4 VFs per RoCE NIC (InfiniBand still gets 16)
  - name: SUBNET_MODE
    value: "separate"
  - name: IP_RANGE_BASE
    value: "172.16"
```

**Result:**
- `ens3f0np0` (RoCE) → `172.16.101.0/24` with 4 VFs
- `ens3f1np1` (RoCE) → `172.16.102.0/24` with 4 VFs
- `ibp24s0` (InfiniBand) → `172.16.103.0/24` with 16 VFs (auto-detected)

## Routing Behavior

### Automatic Route Destination Assignment (Separate Mode)

When using `SUBNET_MODE="separate"`, the generator automatically assigns unique route destinations to each NIC:

| NIC | IP Range | Route Destination | Why |
|-----|----------|-------------------|-----|
| ens3f0np0 | 10.0.101.0/24 | 192.168.75.0/24 | Base route from ROUTE_DEST |
| ens3f1np1 | 10.0.102.0/24 | 192.168.76.0/24 | Third octet incremented |
| ens7f0np0 | 10.0.103.0/24 | 192.168.77.0/24 | Third octet incremented |

**Why this matters:**

Without unique routes, the kernel faces ambiguity when routing traffic to the same destination:
- ❌ **Before**: Both NICs route to 192.168.75.0/24 → kernel picks one NIC → other NIC unused
- ✅ **After**: Each NIC routes to different subnet → no ambiguity → both NICs used in parallel

**Performance impact:**
- Parallel RDMA tests with same route: **0.56 Gb/s** (failed)
- Parallel RDMA tests with unique routes: **96.20 Gb/s** (full line rate)

### Shared Mode Routing

When using `SUBNET_MODE="shared"`, all NICs share the same route destination since they're on the same subnet:

```yaml
All NICs: 10.0.100.0/24 → route to 192.168.75.0/24
```

This is appropriate for shared mode since pods can communicate across NICs at layer-2.

## How It Works

1. **Discovery Phase** (`job-discovery.yaml`)
   - DaemonSet runs on each worker node
   - Detects RoCE-capable NICs (Mellanox/NVIDIA)
   - Writes discovery results to hostPath volume

2. **Generator Phase** (`job-generator.yaml`)
   - Waits for all nodes to complete discovery
   - Collects results from all nodes
   - Deduplicates by (PF name, device ID)
   - Generates SriovNetworkNodePolicy and SriovNetwork for each unique NIC
   - Applies resources to cluster

3. **SR-IOV Operator** (automatic)
   - Creates Virtual Functions (VFs)
   - Configures device plugin
   - Makes resources available to pods

## Verification

```bash
# Check discovered NICs
oc get sriovnetworknodepolicy -n openshift-sriov-network-operator

# Check generated networks
oc get sriovnetwork -n openshift-sriov-network-operator

# Check allocatable resources per node
oc get nodes -o json | jq '.items[] | {
  node: .metadata.name,
  allocatable: .status.allocatable | with_entries(select(.key | test("rdma")))
}'

# View network IP ranges
oc get sriovnetwork -n openshift-sriov-network-operator \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.ipam}{"\n"}{end}' | \
  jq -r '. | "\(.metadata.name): \(.spec.ipam | fromjson | .range)"'
```

## Advanced Configuration

### Custom IP Ranges

Change the first two octets of IP addresses:

```yaml
- name: IP_RANGE_BASE
  value: "192.168"  # Use 192.168.x.x instead of 10.0.x.x
```

### Per-Namespace Networks

By default, SR-IOV networks are available in the `default` namespace. To make networks available in other namespaces, either:

**Option 1: Change default namespace**
```yaml
- name: NETWORK_NAMESPACE
  value: "my-workload-namespace"
```

**Option 2: Create additional SriovNetwork resources** for each namespace (recommended for multi-tenancy)

### Custom MTU

```yaml
- name: MTU
  value: "1500"  # Standard Ethernet (vs 9000 for jumbo frames)
```

## Troubleshooting

### No NICs discovered

```bash
# Check discovery pods
oc get pods -n openshift-sriov-network-operator -l app=roce-port-discovery

# View discovery logs
oc logs -n openshift-sriov-network-operator -l app=roce-port-discovery

# Check node labels
oc get nodes --show-labels | grep "pci-15b3.present"
```

### SR-IOV operator not discovering InfiniBand interfaces

**Symptom:** Some NICs are physically present (visible in `lspci`) but missing from `sriovnetworknodestate`.

**Check for "message too long" errors:**

```bash
# Find the config daemon pod for the affected node
oc get pods -n openshift-sriov-network-operator -l app=sriov-network-config-daemon -o wide

# Check logs for netlink errors
oc logs -n openshift-sriov-network-operator <config-daemon-pod> | grep "message too long"
```

**Example error:**
```
ERROR daemon/status.go:112 DiscoverSriovDevices(): unable to get Link for device, skipping
{"device": "0000:40:00.0", "error": "message too long"}
```

**Root cause:** The SR-IOV operator uses netlink to query interface information. When VFs already exist from a previous configuration, the netlink response can exceed the buffer size, causing discovery to fail and skip that interface.

**Solution:** Manually remove VFs from affected interfaces to allow clean discovery:

```bash
# 1. Find the config daemon pod on the affected node
NODE_NAME="ocp-poc26704-13780"  # Replace with your node name
CONFIG_POD=$(oc get pod -n openshift-sriov-network-operator \
  -l app=sriov-network-config-daemon -o json | \
  jq -r ".items[] | select(.spec.nodeName == \"$NODE_NAME\") | .metadata.name")

# 2. Identify affected PCI addresses from error logs
oc logs -n openshift-sriov-network-operator $CONFIG_POD | \
  grep "message too long" | \
  grep -oP '0000:[0-9a-f:]+\.[0-9]'

# 3. Clear VFs from each affected interface
for pci in 0000:40:00.0 0000:4f:00.0 0000:5e:00.0; do
  echo "Clearing VFs from $pci"
  oc exec -n openshift-sriov-network-operator $CONFIG_POD -- \
    bash -c "echo 0 > /sys/bus/pci/devices/$pci/sriov_numvfs"
done

# 4. Restart the config daemon to trigger rediscovery
oc delete pod -n openshift-sriov-network-operator $CONFIG_POD

# 5. Wait for new pod to be ready and verify interfaces are discovered
sleep 15
oc get sriovnetworknodestate $NODE_NAME -n openshift-sriov-network-operator \
  -o jsonpath='{.status.interfaces[*].name}' | tr ' ' '\n' | sort

# 6. Regenerate SR-IOV policies to include newly discovered interfaces
oc delete pod -n openshift-sriov-network-operator -l app=roce-port-discovery
oc delete job sriov-resource-generator -n openshift-sriov-network-operator
oc apply -f manifests/35-roce-discovery/job-generator.yaml
```

**When to use this fix:**
- After changing SR-IOV configuration or deleting policies
- When migrating from manual VF configuration to operator-managed
- After firmware updates that change VF capabilities
- When interfaces appear in `lspci` but not in `sriovnetworknodestate`

**Prevention:** Always delete SR-IOV policies and let VFs be removed cleanly before making configuration changes.

### IP address conflicts

If using `SUBNET_MODE="shared"` and seeing IP conflicts:
- Switch to `SUBNET_MODE="separate"`
- Or increase subnet size (requires manual editing of generated resources)

### Networks not available in namespace

Check `NETWORK_NAMESPACE` setting or create additional SriovNetwork resources with different `networkNamespace` values.

### Policies created but no VF resources available

Check SR-IOV node state sync status:

```bash
# Check if nodes are being reconfigured
oc get sriovnetworknodestate -n openshift-sriov-network-operator

# Watch for node reconfiguration progress (can take 30-60 minutes per node)
oc get sriovnetworknodestate -n openshift-sriov-network-operator -w
```

Nodes will show:
- `InProgress`: Node is being drained, reconfigured, and rebooted
- `Succeeded`: VF resources are available on the node
- `Failed`: Check config daemon logs for errors

## Related Documentation

- [SR-IOV Operator Configuration](../30-sriov-operator/README.md)
- [Baremetal Deployment Guide](../../rig/baremetal/README.md)
- [OpenShift SR-IOV Network Operator Docs](https://docs.openshift.com/container-platform/latest/networking/hardware_networks/configuring-sriov-operator.html)
