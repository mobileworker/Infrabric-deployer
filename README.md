# InfraBric Deployer

**Automated Baremetal NVIDIA GPU + RDMA/RoCE Infrastructure Deployment**

InfraBrig Deployer provides a complete, production-ready ArgoCD-based GitOps deployment for baremetal clusters with NVIDIA GPUs and RDMA/InfiniBand networking.

## Features

### 🚀 Core Capabilities

- **Fully Automated Deployment**: Zero-touch deployment of GPU and RDMA infrastructure
- **Self-Healing**: Automated detection and repair of stuck operators and resources
- **Universal GPU Support**: Pre-compiled images supporting V100, A100, H100, H200, and all NVIDIA architectures
- **RoCE/RDMA Auto-Discovery**: Automatic detection and configuration of RDMA-capable NICs
- **SR-IOV Automation**: Dynamic SR-IOV policy and network generation

### 🧩 Components

1. **[Node Preparation](manifests/00-node-preparation/README.md)** - Automated node labeling and GPU/MOFED exclusion from master nodes
2. **[NFD (Node Feature Discovery)](manifests/15-nfd/README.md)** - Hardware feature detection
3. **[Infrastructure Operators](manifests/20-operators/README.md)** - Core operators (Sealed Secrets, GPU, Network Operator)
4. **[Operator Readiness](manifests/25-operator-readiness/README.md)** - Readiness gates ensuring operators are fully deployed
5. **[SR-IOV VF Configuration](manifests/26-sriov-vf-config/README.md)** - MachineConfigs creating 16 VFs per RDMA NIC at boot
6. **[NVIDIA Network Operator](manifests/28-nvidia-network-operator/README.md)** - MOFED driver namespace
7. **[MOFED Readiness](manifests/29-nvidia-mofed-ready/README.md)** - Wait for MOFED drivers before GPU operator
8. **[NIC Discovery](manifests/35-nic-discovery/README.md)** - Automatic RDMA NIC detection and configuration (InfiniBand & RoCE)
9. **[NVIDIA GPU Operator](manifests/30-gpu-operator-nfd/README.md)** - GPU driver and device plugin
10. **[Network Performance Testing](manifests/99-network-perf-tests/README.md)** - IB bandwidth and NCCL validation tools

### 🧹 Utilities

- **[Cluster Cleanup](manifests/99-cleanup/README.md)** - Complete infrastructure cleanup for fresh deployments
- **[Network Performance Tests](manifests/99-network-perf-tests/README.md)** - RDMA bandwidth and NCCL testing

### 📖 Guides

- **[Running Individual Jobs](#running-individual-jobs)** - Manual execution of specific components for testing and debugging

---

## Quick Start

### Prerequisites

- OpenShift cluster (baremetal)
- NVIDIA GPUs installed
- InfiniBand/RoCE-capable NICs
- Cluster-admin permissions
- **BIOS Configuration for GPUDirect RDMA** (see requirements below)

### Deployment

See the **[Baremetal Deployment Guide](rig/baremetal/bootstrap/README.md)** for detailed installation steps.

**Quick version:**

1. **Fork this repository** and update the Git URLs:

   > **Why fork?** ArgoCD continuously monitors the Git repository and **automatically applies every change** to your cluster. If you use the upstream repository directly, any changes pushed by others will be immediately deployed to your production cluster without your review or approval. Forking gives you full control over what gets deployed and when.

   ```bash
   # Set your repository URL
   export REPO_URL="https://github.com/YOUR_USERNAME/Infrabric-deployer.git"

   # Update all ArgoCD manifests and documentation
   for file in $(find apps/ rig/baremetal/bootstrap/ manifests/01-private-repo-config/ \
     \( -name "app.yaml" -o -name "root-app.yaml" -o -name "README.md" \)); do
     sed "s|https://github.com/bbenshab/Infrabric-deployer.git|${REPO_URL}|g" "$file" > "$file.tmp"
     mv "$file.tmp" "$file"
   done
   ```

2. **Deploy prerequisites** (GitOps operator + health monitor):
   ```bash
   oc apply -f rig/baremetal/bootstrap/00-prerequisites.yaml

   # Wait for GitOps operator to be ready (~2-3 minutes)
   oc wait --for=condition=ready pod -l control-plane=gitops-operator -n openshift-operators --timeout=300s

   # Wait for ArgoCD instance to be ready (~1 minute)
   oc wait --for=condition=ready pod -l app.kubernetes.io/name=openshift-gitops-server -n openshift-gitops --timeout=180s
   ```

   **Expected output** - ArgoCD pods should be running:
   ```
   $ oc get pods -n openshift-gitops
   NAME                                                         READY   STATUS    RESTARTS   AGE
   cluster-67f5c4874b-9crvc                                     1/1     Running   0          8m35s
   gitops-plugin-598cff7645-h67nt                               1/1     Running   0          8m35s
   openshift-gitops-application-controller-0                    1/1     Running   0          8m34s
   openshift-gitops-applicationset-controller-69964ffd4-6v7fj   1/1     Running   0          8m34s
   openshift-gitops-dex-server-6dc958b54-tsqwd                  1/1     Running   0          8m33s
   openshift-gitops-redis-68469975f8-ndwnz                      1/1     Running   0          8m34s
   openshift-gitops-repo-server-75db857f8-5fqzb                 1/1     Running   0          8m34s
   openshift-gitops-server-674758b98b-nlg5c                     1/1     Running   0          8m34s
   ```

   > **Note:** You might also see `argocd-health-monitor-*` pods with `Status: Completed`. This is completely normal - they run as a CronJob every 2 minutes to monitor ArgoCD health.

3. **Configure private repository access** (ONLY if your fork is private):

   > **Public repository?** Skip this step - ArgoCD can access public repositories without credentials.

   If your forked repository is private, configure Git credentials by following the guide:

   **[Private Repository Configuration Guide](manifests/01-private-repo-config/README.md)**

4. **Deploy the bootstrap**:
   ```bash
   oc apply -k rig/baremetal/bootstrap
   ```

5. **Monitor deployment**:

   > **Important:** ArgoCD applications showing "Healthy" status does NOT mean all pods and drivers are fully deployed. The NVIDIA GPU Operator is the last component to deploy and takes the longest time. Always verify the actual pod status in the `nvidia-gpu-operator` namespace before considering the cluster ready.

   ```bash
   # Watch ArgoCD applications status
   watch oc get applications -n openshift-gitops

   # Monitor GPU operator pods (last component to deploy)
   watch oc get pods -n nvidia-gpu-operator

   # Cluster is ready when all GPU operator pods are Running:
   # - nvidia-driver-daemonset pods (one per GPU node)
   # - nvidia-dcgm-exporter pods
   # - nvidia-device-plugin-daemonset pods
   # - gpu-feature-discovery pods
   # - nvidia-operator-validator pods

   # Monitor self-healing health monitor
   oc logs -n openshift-gitops -l job-name=argocd-health-monitor --tail=100
   ```

---

## BIOS Requirements for GPUDirect RDMA

### Critical: IOMMU and ACS Configuration

GPUDirect RDMA requires specific BIOS settings to enable direct memory access between GPUs and RDMA NICs. **These settings must be configured before deployment**, as they require a node reboot.

**Why this is required:**
- GPUDirect RDMA needs PCIe peer-to-peer (P2P) communication between GPUs and NICs
- IOMMU (I/O Memory Management Unit) blocks direct GPU memory access from RDMA devices
- Without these settings, RDMA tests will fail with "local protection error" and IOMMU page faults

### Dell Server Configuration

For Dell PowerEdge servers (tested on R7525, R750xa), disable the following BIOS settings:

**System BIOS → Integrated Devices:**
```
n9: Secured-Core.IOMMU: Enabled → Disabled
n9: DevicesandIOPorts.IOMMU: Enabled → Disabled
```

**Additional PCIe Settings (if available):**
- **ACS (Access Control Services):** Disabled
- **PCIe Relaxed Ordering:** Enabled (recommended for performance)

### Other Server Vendors

**HPE ProLiant:**
- Navigate to: System Configuration → BIOS/Platform Configuration → System Options
- Set: **Intel VT-d** → Disabled (or **AMD IOMMU** → Disabled for AMD systems)

**Supermicro:**
- Navigate to: Advanced → Chipset Configuration
- Set: **Intel VT-d** → Disabled (or **IOMMU** → Disabled for AMD systems)

**Lenovo ThinkSystem:**
- Navigate to: System Settings → Devices and I/O Ports
- Set: **Intel VT-d** → Disabled (or **AMD IOMMU** → Disabled for AMD systems)

### Verification

After BIOS changes and node reboot, verify IOMMU is disabled:

```bash
# Check if IOMMU is disabled in kernel parameters
oc debug node/<node-name> -- chroot /host cat /proc/cmdline

# Should NOT see: amd_iommu=on or intel_iommu=on
# Expected: No IOMMU parameters (disabled by BIOS)
```

### Alternative: Kernel Parameter Override (Not Recommended)

If BIOS access is not available, you can configure IOMMU passthrough mode via OpenShift MachineConfig. **However, BIOS-level disabling is preferred** for production deployments:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-iommu-passthrough
spec:
  kernelArguments:
    - amd_iommu=on
    - iommu=pt
```

**Note:** This requires node reboot and takes 10-15 minutes per node as OpenShift performs rolling updates.

### References

- [NVIDIA GPUDirect RDMA Documentation](https://docs.nvidia.com/cuda/gpudirect-rdma/)
- [GPUDirect Storage Troubleshooting Guide](https://docs.nvidia.com/gpudirect-storage/troubleshooting-guide/)
- [NVIDIA GPU Operator RDMA Configuration](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-rdma.html)

---

## Directory Structure

```
Infrabric-deployer/
├── manifests/                     # Kubernetes resource manifests
│   ├── 00-cleanup/                # Infrastructure cleanup (DEPRECATED - use 99-cleanup)
│   ├── 00-node-preparation/       # Node prep job and scripts (wave -1)
│   ├── 01-private-repo-config/    # Private Git repository credentials
│   ├── 15-nfd/                    # NFD configuration (wave 15)
│   ├── 20-operators/              # Helm charts for operators (wave 20)
│   ├── 25-operator-readiness/     # Operator readiness gates (wave 25)
│   ├── 26-sriov-vf-config/        # MachineConfigs for SR-IOV VF setup (wave 26)
│   ├── 27-gitops/                 # Self-healing monitor CronJob (wave 27)
│   ├── 28-nvidia-network-operator/ # Network operator namespace (wave 28)
│   ├── 29-nvidia-mofed-ready/     # MOFED readiness gate (wave 29)
│   ├── 30-gpu-operator-nfd/       # GPU ClusterPolicy and MOFED wait hook (wave 30-40)
│   ├── 35-nic-discovery/          # NIC discovery DaemonSet and generator job (wave 35)
│   ├── 99-cleanup/                # Infrastructure cleanup jobs
│   └── 99-network-perf-tests/     # Network performance validation
└── rig/                           # Environment configurations
    ├── baremetal/                 # Baremetal deployment (OpenShift)
    │   ├── bootstrap/             # Initial deployment resources
    │   │   ├── 00-prerequisites.yaml    # GitOps operator + health monitor
    │   │   ├── root-app.yaml            # Root ArgoCD Application
    │   │   ├── gitops-cluster-admin.yaml # Cluster-admin for ArgoCD
    │   │   ├── namespace.yaml           # Target namespace
    │   │   └── README.md                # Deployment guide
    │   ├── infra-operators-values.yaml # Operator configuration values
    │   ├── kustomization.yaml     # Kustomize overlay
    │   └── namespace.yaml         # Target namespace
    ├── aws/                       # AWS deployment (coming soon)
    └── ibm-cloud/                 # IBM Cloud deployment (coming soon)

```

---

## Deployment Workflow

### ArgoCD Sync Waves

The deployment uses ArgoCD sync waves for proper ordering:

- **Wave -1**: Node preparation (labels worker nodes, disables GPU/MOFED on masters)
- **Wave 15**: NFD configuration
- **Wave 20**: Infrastructure operators (Sealed Secrets, GPU, Network operators via Helm)
- **Wave 25**: Operator readiness gates (wait for Network Operator to be ready)
- **Wave 26**: SR-IOV VF configuration (MachineConfigs - creates systemd service, sets 16 VFs per NIC, triggers node reboots)
- **Wave 28**: GitOps configuration (ArgoCD settings)
- **Wave 29**: NVIDIA Network Operator namespace
- **Wave 30**: MOFED readiness check
- **Wave 35**: **PreSync: Wait for MCPs** → NIC discovery → Creates NicClusterPolicy with dynamic timeout (triggers MOFED deployment) → Auto-cleanup discovery resources
- **Wave 40**: **PreSync: Wait for MOFED** → GPU Operator ClusterPolicy

**Key Dependencies:**
- Wave 26 creates 16 VFs per RDMA NIC via boot-time systemd service
- Wave 35 blocks until all MachineConfigPools complete node updates (PreSync hook)
- Wave 35 calculates dynamic MOFED startup probe timeout based on total VF count (prevents pod termination during VF restoration)
- Wave 40 blocks until MOFED pods are ready (PreSync hook)
- This ensures NICs and drivers are fully configured before GPU operator deploys

**Recent Improvements:**
- **Dynamic MOFED timeout**: Automatically calculated from VF count (e.g., 576 VFs = ~65 min timeout)
- **Mixed topology support**: Same PCI address with different link types (IB vs RoCE) across nodes
- **Automatic cleanup**: Discovery DaemonSet and Job auto-deleted after NicClusterPolicy creation
- **NUM_VFS=1**: One allocatable resource per NIC (hardware VFs created by MachineConfig)

---

## Running Individual Jobs

For testing, debugging, or re-running specific components without triggering a full ArgoCD deployment, you can apply individual job manifests directly using `oc apply`.

### Common Use Cases

**1. Re-run Interface Normalization (Wave 25b)**

Normalizes InfiniBand interface names across all nodes using udev rules:

```bash
# Apply the job
oc apply -f manifests/25b-ib-interface-normalization/job-generate-ib-udev-rules.yaml

# Monitor progress
POD=$(oc get pods -l app=ib-udev-generator -n default -o jsonpath='{.items[0].metadata.name}')
oc logs -f $POD -n default

# Check MachineConfig was created
oc get machineconfig 99-worker-normalize-ib-interfaces

# Monitor node rollout (nodes will reboot)
oc get mcp worker -w
```

**2. Re-run NIC Discovery and Resource Generation (Wave 26a)**

Discovers RDMA NICs and generates SR-IOV policies or NVIDIA Network Operator configs:

```bash
# Delete existing discovery resources
oc delete daemonset nic-port-discovery -n default --ignore-not-found
oc delete configmap generated-sriov-resources -n default --ignore-not-found

# Apply discovery manifests
oc apply -k manifests/26a-sriov-discovery/

# Monitor discovery
oc logs daemonset/nic-port-discovery -n default -f

# Wait for generator job to complete
oc wait --for=condition=complete job/nic-resource-generator -n default --timeout=300s

# Check generated resources
oc get configmap generated-sriov-resources -n default -o yaml
```

**3. Re-run RDMA Configuration Generator (Wave 28)**

Generates RDMA shared device resources from discovered InfiniBand devices:

```bash
# Delete existing job if it exists
oc delete job generate-rdma-config -n default --ignore-not-found

# Apply the generator job
oc apply -f manifests/28-nvidia-network-operator/job-generate-rdma-config.yaml

# Monitor progress
oc logs job/generate-rdma-config -n default -f

# Verify RDMA resources were created
oc get nicclusterpolicy nic-cluster-policy -n nvidia-network-operator -o yaml | grep rdmaSharedDevicePlugin
oc get net-attach-def -n default | grep rdma
```

### Manual Job Execution Pattern

Most jobs in this repository follow a standard pattern:

```bash
# 1. Apply the job manifest
oc apply -f manifests/<wave-directory>/<job-file>.yaml

# 2. Get the pod name
POD=$(oc get pods -l <label-selector> -n <namespace> -o jsonpath='{.items[0].metadata.name}')

# 3. Monitor logs
oc logs -f $POD -n <namespace>

# 4. Check job status
oc get job <job-name> -n <namespace>

# 5. Cleanup (if needed)
oc delete job <job-name> -n <namespace>
```

### Pre-Sync Jobs and Hooks

Some jobs use ArgoCD hooks and won't run when applied directly:

```yaml
annotations:
  argocd.argoproj.io/hook: PreSync  # Runs before sync
  argocd.argoproj.io/hook-delete-policy: BeforeHookCreation  # Auto-cleanup
```

To run these manually, **remove the ArgoCD annotations** before applying:

```bash
# Example: Run NIC discovery PreSync job manually
oc apply -f manifests/26a-sriov-discovery/job-generator.yaml
# Note: Remove hook annotations first, or they won't execute outside ArgoCD
```

### Important Notes

- **Jobs with MachineConfigs**: Jobs that create MachineConfigs (like interface normalization) will trigger node reboots. Monitor with `oc get mcp worker -w`
- **Cleanup**: Most jobs include `ttlSecondsAfterFinished` to auto-delete after completion
- **Dependencies**: Some jobs depend on resources from earlier waves (check README files)
- **State**: Re-running jobs may create duplicate resources - cleanup existing resources first
- **ArgoCD Sync**: Manual changes may be reverted when ArgoCD syncs. Use `argocd app set <app> --sync-policy none` to disable auto-sync

### Debugging Failed Jobs

```bash
# Get pod status
oc get pods -l job-name=<job-name> -n <namespace>

# Check pod events
oc describe pod <pod-name> -n <namespace>

# View logs
oc logs <pod-name> -n <namespace>

# Check job conditions
oc describe job <job-name> -n <namespace>
```

---

## Testing & Validation

### Network Performance Tests

Test RDMA bandwidth, TCP performance, and NCCL collective operations. See **[Network Performance Tests README](manifests/99-network-perf-tests/README.md)** for details.

```bash
# Run performance tests
oc apply -k manifests/99-network-perf-tests

# View results
oc logs -n default job/network-perf-test -f

# Expected results:
# - RoCE (Host Memory): ~90-100 Gb/s (100G InfiniBand)
# - RoCE with CUDA: ~85-95 Gb/s (GPUDirect RDMA)
# - TCP Baseline: ~10-40 Gb/s (standard TCP/IP)
# - NCCL all_reduce: ~400 GB/s (GPU memory bandwidth)

# Cleanup after testing
oc delete -k manifests/99-network-perf-tests
oc delete daemonset network-perf-test-worker -n default
```

**Note:** The test coordinator Job dynamically creates a DaemonSet at runtime (not managed by kustomize). You must manually delete the DaemonSet after testing, as `oc delete -k` only removes the Job and ConfigMap template.

---

## 🧹 Cluster Cleanup

Before redeploying or when you need to start fresh, use the automated cleanup job to remove all infrastructure resources. See **[Cleanup README](manifests/99-cleanup/README.md)** for full documentation.

### Quick Cleanup

```bash
# Apply the cleanup Job directly
oc apply -f manifests/99-cleanup/infrastructure-cleanup.yaml

# Watch the cleanup process
oc logs -n default job/infrastructure-cleanup -f

# The job will automatically delete itself after 10 minutes
```

### What Gets Cleaned Up

**IMPORTANT:** ArgoCD/GitOps is **NOT** cleaned up automatically since it manages the cleanup job itself. See "Manual ArgoCD Cleanup" below for final steps.

The cleanup job removes:
- **ArgoCD Applications:** All operator Applications (preserves gitops and root-app)
- **Operators:** GPU Operator, NVIDIA Network Operator, NFD, SR-IOV
- **CSVs:** From ALL namespaces (solves stuck CSV issues)
- **Resources:** Subscriptions, InstallPlans, ClusterPolicies, NicClusterPolicies
- **Network Performance Testing:** Jobs, DaemonSets, ConfigMaps, and RBAC
- **Namespaces:** nvidia-gpu-operator, nvidia-network-operator, openshift-nfd, openshift-sriov-network-operator, helm-charts
- **Stuck Resources:** Automatically removes finalizers from stuck namespaces and resources
- **CRDs:** Operator-related custom resource definitions (GPU, Network, NFD, SR-IOV)
- **RBAC:** Operator ClusterRoles and ClusterRoleBindings

### Verify Cleanup

```bash
# Check no operator CSVs remain
oc get csv -A | grep -E "(gpu|nvidia|nfd|sriov)" || echo "Clean ✓"

# Check no operator namespaces remain (GitOps should still exist)
oc get ns | grep -E "(nvidia|nfd|sriov|helm-charts)" || echo "Clean ✓"

# Check no operator CRDs remain (ArgoCD CRDs should still exist)
oc get crd | grep -E "(nvidia|mellanox|nfd|sriov)" || echo "Clean ✓"
```

### Manual ArgoCD Cleanup

After all operator resources are cleaned up, ArgoCD can be removed manually as the final step:

```bash
# Delete the ArgoCD namespace
oc delete namespace openshift-gitops

# Delete ArgoCD CRDs
oc delete crd -l app.kubernetes.io/part-of=argocd

# Delete ArgoCD operator subscription (if installed via OLM)
oc delete subscription openshift-gitops-operator -n openshift-operators --ignore-not-found

# Verify ArgoCD is fully removed
oc get ns openshift-gitops 2>/dev/null && echo "Still exists" || echo "Removed ✓"
oc get crd | grep argoproj || echo "CRDs removed ✓"
```

**Why manual cleanup?**
- ArgoCD manages the cleanup job itself
- Deleting ArgoCD while it's running would terminate the cleanup job prematurely
- This ensures all operator resources are fully cleaned before removing the orchestrator

**Note:** The cleanup job is safe to run multiple times (idempotent) and auto-deletes after 10 minutes.

---

## Custom Images

### Network Performance Testing Image

Pre-built universal image supporting all NVIDIA GPUs:

```
quay.io/bbenshab/perf-test:universal
```

**Includes:**
- NCCL tests (all_reduce, all_gather, etc.) pre-compiled for all GPU architectures
- perftest (ib_write_bw, ib_read_bw)
- All analysis tools (jq, bc, numactl, lspci, nvidia-smi)

**Build your own:**
```bash
cd manifests/99-network-perf-tests
podman build -t your-registry/perf-test:latest -f Dockerfile .
podman push your-registry/perf-test:latest
```

See **[Network Performance Tests README](manifests/99-network-perf-tests/README.md)** for details.

---

## Configuration

### NIC Discovery (InfiniBand & RoCE) Subnet Modes

Configure subnet allocation in `manifests/35-nic-discovery/job-generator.yaml`:

- **Separate subnets** (default): Each NIC gets its own subnet (10.0.101.0/24, 10.0.102.0/24)
- **Shared subnet**: All NICs share one subnet (10.0.100.0/24)

See **[NIC Discovery README](manifests/35-nic-discovery/README.md)** for details.

### RDMA Resource Connectivity Requirements

**IMPORTANT:** RDMA shared device resources are only created for NICs that have **active carrier on ALL nodes** in the cluster.

**Why this requirement?**

RDMA resources are cluster-wide and pods can be scheduled to any node. If a NIC has carrier on some nodes but not others:
- Pods requesting that RDMA resource might be scheduled to a node where the physical link is disconnected
- This causes application failures and unpredictable behavior
- Resource allocation appears successful but RDMA operations fail at runtime

**How it works:**

During NIC discovery and RDMA configuration (waves 26a and 28):

1. **Discovery phase** - The discovery DaemonSet detects all InfiniBand/RoCE NICs and their carrier status on each node
2. **Carrier validation** - The RDMA generator groups NICs by interface name and checks carrier status:
   - ✓ **Fully connected**: All nodes have carrier=1 → Resource created
   - ⚠ **Partially connected**: Some nodes have carrier=1, others carrier=0 → Resource skipped
   - ✗ **Disconnected**: No nodes have carrier=1 → Resource skipped
3. **Resource creation** - Only fully connected NICs become available as `rdma/rdma_shared_nicX` resources

**Example output from RDMA generator:**

```
Checking carrier status consistency across nodes...
Note: RDMA resources are only created for NICs with carrier on ALL nodes

  ✓ ib_nic4: 3/3 nodes connected - INCLUDED
    Nodes: ocp-poc26704-13779, ocp-poc26704-13780, ocp-poc26704-13781

  ⚠ ib_nic0: 2/3 nodes connected - SKIPPED (partial)
    Connected: ocp-poc26704-13779, ocp-poc26704-13781
    Disconnected: ocp-poc26704-13780

  ✗ ib_nic1: 0/3 nodes connected - SKIPPED (down)
    Nodes: ocp-poc26704-13779, ocp-poc26704-13780, ocp-poc26704-13781

Summary:
  Fully connected NICs (all nodes): 6
  Partially connected NICs (some nodes): 2
  Disconnected NICs (no nodes): 4
```

**Verification:**

Check which RDMA resources are available on your nodes:

```bash
# View RDMA resources on a node
oc get node <node-name> -o json | jq '.status.allocatable' | grep rdma_shared_nic

# Expected output - only fully connected NICs show capacity:
#   "rdma/rdma_shared_nic4": "1k"   ← All 3 nodes connected
#   "rdma/rdma_shared_nic0": "0"    ← Only 2/3 nodes connected (skipped)
```

**Troubleshooting partial connectivity:**

If NICs are being skipped due to partial connectivity:

1. **Check physical cabling**: Verify InfiniBand/Ethernet cables are connected to all nodes
2. **Check switch configuration**: Ensure switch ports are enabled and properly configured
3. **Check link status**: Run discovery manually to see detailed carrier status:
   ```bash
   oc get configmap generated-sriov-resources -n default -o jsonpath='{.data.ib-devices\.json}' | \
     jq -r '.[] | "\(.pfName) on \(._node_name): carrier=\(.carrier), linkStatus=\(.linkStatus)"' | sort
   ```
4. **Re-run discovery**: After fixing connectivity issues, re-run NIC discovery:
   ```bash
   oc delete daemonset nic-port-discovery -n default
   oc delete job nic-resource-generator generate-rdma-config -n default
   oc apply -k manifests/26a-sriov-discovery/
   oc apply -f manifests/28-nvidia-network-operator/job-generate-rdma-config.yaml
   ```

### RDMA Communication Modes

The deployment configures RDMA shared device plugin which supports two modes of communication:

#### 1. Pure RDMA (Verbs) - Default and Recommended

**Status:** ✓ Working out of the box

Applications communicate directly using RDMA verbs via exposed `/dev/infiniband/uverbsX` devices:

- **Performance:** 45+ GB/s per NIC (~360 Gb/s)
- **No IP required:** Direct device access, no networking layer
- **Use cases:** NCCL, GPUDirect RDMA, MPI, HPC applications
- **Test:** Use `ib_write_bw`, `ib_read_bw`, or NCCL tests

**Verification:**
```bash
# Deploy test pods
oc apply -f manifests/99-network-perf-tests/rdma-bandwidth-test.yaml

# Run bandwidth test between pods
oc exec <server-pod> -- ib_write_bw -d mlx5_4 -a
oc exec <client-pod> -- ib_write_bw -d mlx5_4 <server-ip> -a

# Expected: 45+ GB/s bandwidth
```

#### 2. IP over InfiniBand (IPoIB) - Optional

**Status:** ✗ Dormant (IPoIB CNI configured but requires host IP configuration)

IPoIB CNI is pre-configured but dormant because host InfiniBand interfaces don't have IP addresses. This allows applications to use standard TCP/IP over InfiniBand fabric.

**Why it's dormant:**
- NetworkAttachmentDefinitions are created during deployment
- IPoIB CNI plugin is enabled in NicClusterPolicy
- Host IPoIB interfaces (ib_nic4-11) exist but have no IPs configured
- Without host IPs, pod IPoIB interfaces can't communicate

**Use cases for enabling IPoIB:**
- Legacy applications requiring IP connectivity over InfiniBand
- TCP/IP workloads that benefit from low-latency IB fabric
- Applications that don't support RDMA verbs

### Enabling IP Connectivity with NMState

To enable IP connectivity over IPoIB, use **NMState** to configure persistent IPs on host InfiniBand interfaces. NMState provides declarative network configuration that survives reboots and node updates.

**Prerequisites:**
1. Install NMState operator (if not already installed):
   ```bash
   oc apply -f - <<EOF
   apiVersion: v1
   kind: Namespace
   metadata:
     name: openshift-nmstate
   ---
   apiVersion: operators.coreos.com/v1
   kind: OperatorGroup
   metadata:
     name: nmstate
     namespace: openshift-nmstate
   spec:
     targetNamespaces:
       - openshift-nmstate
   ---
   apiVersion: operators.coreos.com/v1alpha1
   kind: Subscription
   metadata:
     name: kubernetes-nmstate-operator
     namespace: openshift-nmstate
   spec:
     channel: stable
     name: kubernetes-nmstate-operator
     source: redhat-operators
     sourceNamespace: openshift-marketplace
   EOF
   ```

2. Wait for NMState to be ready:
   ```bash
   oc wait --for=condition=ready pod -l app=nmstate-operator -n openshift-nmstate --timeout=300s
   ```

**NMState Configuration Example:**

Create a `NodeNetworkConfigurationPolicy` to assign IPs to IPoIB interfaces:

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: ipoib-host-config
spec:
  # Apply to nodes with Mellanox NICs
  nodeSelector:
    feature.node.kubernetes.io/pci-15b3.present: "true"

  desiredState:
    interfaces:
      # Configure ib_nic4 (mlx5_4)
      - name: ib_nic4
        type: infiniband
        state: up
        ipv4:
          enabled: true
          dhcp: false
          address:
            # Use node-specific suffix (e.g., .254 for first node, .253 for second)
            - ip: 10.0.105.254
              prefix-length: 24
        mtu: 2044

      # Configure ib_nic5 (mlx5_5)
      - name: ib_nic5
        type: infiniband
        state: up
        ipv4:
          enabled: true
          dhcp: false
          address:
            - ip: 10.0.106.254
              prefix-length: 24
        mtu: 2044

      # Configure ib_nic6 (mlx5_6)
      - name: ib_nic6
        type: infiniband
        state: up
        ipv4:
          enabled: true
          dhcp: false
          address:
            - ip: 10.0.107.254
              prefix-length: 24
        mtu: 2044

      # Configure ib_nic9 (mlx5_9)
      - name: ib_nic9
        type: infiniband
        state: up
        ipv4:
          enabled: true
          dhcp: false
          address:
            - ip: 10.0.110.254
              prefix-length: 24
        mtu: 2044

      # Configure ib_nic10 (mlx5_10)
      - name: ib_nic10
        type: infiniband
        state: up
        ipv4:
          enabled: true
          dhcp: false
          address:
            - ip: 10.0.111.254
              prefix-length: 24
        mtu: 2044

      # Configure ib_nic11 (mlx5_11)
      - name: ib_nic11
        type: infiniband
        state: up
        ipv4:
          enabled: true
          dhcp: false
          address:
            - ip: 10.0.112.254
              prefix-length: 24
        mtu: 2044
```

**Per-Node IP Assignment:**

For different IPs on each node, create separate policies with node-specific selectors:

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: ipoib-node1-config
spec:
  nodeSelector:
    kubernetes.io/hostname: "ocp-poc26704-13779"
  desiredState:
    interfaces:
      - name: ib_nic4
        type: infiniband
        state: up
        ipv4:
          enabled: true
          dhcp: false
          address:
            - ip: 10.0.105.1
              prefix-length: 24
        mtu: 2044
      # ... repeat for other NICs with .1 suffix
---
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: ipoib-node2-config
spec:
  nodeSelector:
    kubernetes.io/hostname: "ocp-poc26704-13780"
  desiredState:
    interfaces:
      - name: ib_nic4
        type: infiniband
        state: up
        ipv4:
          enabled: true
          dhcp: false
          address:
            - ip: 10.0.105.2
              prefix-length: 24
        mtu: 2044
      # ... repeat for other NICs with .2 suffix
# ... repeat for remaining nodes
```

**Apply the configuration:**

```bash
oc apply -f ipoib-nmstate-config.yaml

# Check status
oc get nncp

# Verify on a node
oc debug node/<node-name> -- chroot /host ip addr show | grep "ib_nic"
```

**Expected output after NMState applies:**
```
ib_nic4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 2044 qdisc mq state UP
    inet 10.0.105.254/24 brd 10.0.105.255 scope global ib_nic4
ib_nic5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 2044 qdisc mq state UP
    inet 10.0.106.254/24 brd 10.0.106.255 scope global ib_nic5
...
```

**Testing IP connectivity after NMState configuration:**

```bash
# Deploy test pods (IPoIB CNI will now work)
oc apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ipoib-test
  namespace: default
spec:
  selector:
    matchLabels:
      app: ipoib-test
  template:
    metadata:
      labels:
        app: ipoib-test
      annotations:
        k8s.v1.cni.cncf.io/networks: |
          [
            {"name": "rdma-nic4", "namespace": "default"}
          ]
    spec:
      nodeSelector:
        feature.node.kubernetes.io/pci-15b3.present: "true"
      containers:
        - name: test
          image: nicolaka/netshoot:latest
          command: ["sleep", "infinity"]
EOF

# Wait for pods to start
sleep 10

# Test ping between pods over IPoIB
POD1=$(oc get pods -l app=ipoib-test -o jsonpath='{.items[0].metadata.name}')
POD2=$(oc get pods -l app=ipoib-test -o jsonpath='{.items[1].metadata.name}')
POD2_IP=$(oc exec $POD2 -- ip -4 addr show net1 | grep inet | awk '{print $2}' | cut -d/ -f1)

# Ping from POD1 to POD2
oc exec $POD1 -- ping -c 3 $POD2_IP
# Expected: 0% packet loss
```

**Important Notes:**

1. **IP Ranges:** The example uses the same IP ranges (10.0.105.0/24, etc.) configured in the NetworkAttachmentDefinitions. Host IPs should be outside the IPAM range to avoid conflicts.

2. **MTU:** InfiniBand datagram mode supports MTU up to 2044 bytes. The example uses 2044 to match the IPoIB interfaces.

3. **Persistence:** NMState configuration survives reboots and MachineConfig updates.

4. **Rollback:** To remove IPs, delete the NodeNetworkConfigurationPolicy:
   ```bash
   oc delete nncp ipoib-host-config
   ```

5. **Performance:** IPoIB provides IP connectivity but with lower performance than pure RDMA verbs. For maximum performance, use RDMA verbs directly (Option 1).

### GPU ClusterPolicy

Customize GPU operator settings in `manifests/30-gpu-operator-nfd/clusterpolicy.yaml`:
- Driver version (auto-detected by default)
- Device plugin configuration
- GPU Feature Discovery settings

See **[GPU Operator README](manifests/30-gpu-operator-nfd/README.md)** for details.

### Network Operator

Customize MOFED/RDMA settings in `manifests/28-nvidia-network-operator/nicclusterpolicy.yaml`:
- OFED version (auto-detected by default)
- Secondary network configuration
- RDMA shared device plugin

See **[NVIDIA Network Operator README](manifests/28-nvidia-network-operator/README.md)** for details.

---

## Troubleshooting

### Check Deployment Status

```bash
# View all ArgoCD applications
watch oc get applications -n openshift-gitops

# Check health monitor logs
oc logs -n openshift-gitops -l job-name=argocd-health-monitor --tail=100

# Verify operators are running
oc get csv -A | grep -E "(gpu|nvidia|nfd|sriov)"
```

### OLM CSV Stuck in Pending State

**Symptom:** After cleanup or fresh deployment, operator ClusterServiceVersion (CSV) remains in `Pending` phase for several minutes with status `RequirementsNotMet`.

**Example:**
```bash
oc get csv -n openshift-operators
# NAME                                DISPLAY                  VERSION   REPLACES   PHASE
# openshift-gitops-operator.v1.19.0   Red Hat OpenShift GitOps 1.19.0              Pending
```

**Root Cause:** This occurs when OLM recreates a CSV before its required CRDs are fully deleted from the cluster. The timing issue typically happens during cleanup when:
1. Cleanup Job deletes operator Subscription → OLM starts CSV cleanup
2. OLM has already recreated the CSV
3. Cleanup Job deletes CRDs 10 seconds later
4. CSV is now stuck waiting for CRDs that won't be created because InstallPlan already shows "Complete"

**Diagnostic Commands:**

```bash
# 1. Check CSV status
oc get csv <csv-name> -n <namespace> -o jsonpath='{.status.phase}'
# Output: Pending

# 2. Check detailed CSV conditions
oc describe csv <csv-name> -n <namespace>
# Look for:
#   Message: one or more requirements couldn't be found
#   Reason: RequirementsNotMet

# 3. Check InstallPlan status
oc get installplan -n <namespace>
# If InstallPlan shows "Complete" but CRDs are missing, CSV is stuck
```

**Resolution:**

The **self-healing health monitor** automatically detects and fixes this issue by deleting stuck CSVs after 5 minutes. If you need immediate resolution:

```bash
# Delete the stuck CSV
oc delete csv <csv-name> -n <namespace>

# Wait 30-60 seconds, then verify:
oc get csv -n <namespace>
# Phase should progress: Installing → Succeeded
```

**Prevention:** The health monitor runs every 2 minutes and automatically handles this scenario. During initial deployment, the auto-approval Job includes retry logic to minimize this issue.

### Subscription with Missing CSV

**Symptom:** Subscription shows `UpgradePending` state, InstallPlan is `Complete`, but the CSV doesn't exist.

**Example:**
```bash
oc get subscription.operators.coreos.com openshift-gitops-operator -n openshift-operators -o yaml
# status:
#   currentCSV: openshift-gitops-operator.v1.19.0
#   state: UpgradePending
#   installPlanRef:
#     name: install-xxxxx

oc get installplan install-xxxxx -n openshift-operators -o jsonpath='{.status.phase}'
# Complete

oc get csv openshift-gitops-operator.v1.19.0 -n openshift-operators
# Error from server (NotFound): clusterserviceversions.operators.coreos.com "openshift-gitops-operator.v1.19.0" not found
```

**Root Cause:** OLM completed the InstallPlan and set the Subscription's currentCSV, but the CSV resource was never actually created. This can happen when:
1. Previous CSV cleanup occurs while new InstallPlan is running
2. CRD timing issues prevent CSV creation
3. OLM controller race conditions

**Resolution:**

The **self-healing health monitor** automatically detects this scenario in multiple ways:
- **Immediate fix:** If Subscription is `UpgradePending` + InstallPlan is `Complete` + CSV missing → deletes Subscription immediately
- **Timeout fix:** If Subscription is `UpgradePending` for >3 minutes with missing CSV → deletes Subscription
- **General fix:** Any Subscription missing its currentCSV for >5 minutes → deletes Subscription

Manual fix if needed:
```bash
# Delete the stuck Subscription
oc delete subscription.operators.coreos.com <subscription-name> -n <namespace>

# ArgoCD will recreate the Subscription, triggering a fresh InstallPlan
# Wait 30-60 seconds, then verify CSV exists:
oc get csv -n <namespace>
# Phase should be: Installing → Succeeded
```

**Additional Checks:** The health monitor also detects and cleans up:
- **Orphaned CSVs**: CSVs with no corresponding Subscription (older than 5 minutes)
- **Broken Subscriptions**: Subscriptions referencing deleted InstallPlans

### Common Issues

- **Stuck namespaces**: Use the [cleanup job](manifests/99-cleanup/README.md) to remove finalizers
- **Failed InstallPlans**: Health monitor auto-approves and retries
- **GPU pods on master nodes**: [Node preparation job](manifests/00-node-preparation/README.md) adds exclusion labels
- **MOFED not ready**: [MOFED readiness gate](manifests/30-nvidia-mofed-ready/README.md) waits for driver pods
- **MCPs stuck updating**: [NIC Discovery PreSync hook](manifests/35-nic-discovery/README.md) waits for MachineConfigPools
- **MOFED CrashLoopBackOff**: See [NVIDIA Network Operator troubleshooting](manifests/28-nvidia-network-operator/README.md#troubleshooting)

See individual manifest READMEs for detailed troubleshooting.

---

## Contributing

This is a specialized deployment for NVIDIA GPU + RDMA infrastructure. Contributions welcome for:
- Additional GPU architectures
- Network performance optimizations
- Enhanced monitoring and observability
- Bug fixes and improvements

---

## License

This project is provided as-is for baremetal GPU cluster deployments.
