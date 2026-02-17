# Baremetal Deployment - Prerequisites and Installation

This directory contains the GitOps configuration for deploying the baremetal AI/ML suite.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation Steps](#installation-steps)
  - [Step 1: Install Prerequisites (GitOps Operator + Health Monitor)](#step-1-install-prerequisites-gitops-operator--health-monitor)
  - [Step 2: Deploy the Application Suite](#step-2-deploy-the-application-suite)
  - [Step 3: Monitor Deployment](#step-3-monitor-deployment)
- [Deployment Order (Sync Waves)](#deployment-order-sync-waves)
- [Expected Timeline](#expected-timeline)
- [What Gets Deployed](#what-gets-deployed)
- [NIC Discovery and SR-IOV Network Configuration](#nic-discovery-and-sr-iov-network-configuration)
- [Automated Self-Healing (Health Monitor)](#automated-self-healing-health-monitor)
- [Troubleshooting](#troubleshooting)
  - [GitOps operator not installing](#gitops-operator-not-installing)
  - [ArgoCD applications stuck](#argocd-applications-stuck)
  - [SR-IOV configuration issues](#sr-iov-configuration-issues)
  - [MOFED Pods CrashLoopBackOff - irdma Module Conflict](#mofed-pods-crashloopbackoff---irdma-module-conflict)
- [Cleanup](#cleanup)
- [Security Notes](#security-notes)

## Prerequisites

Before deploying the main application suite, you must install the OpenShift GitOps operator.

## Installation Steps

### Step 1: Install Prerequisites (GitOps Operator + Health Monitor)

```bash
# Install GitOps operator and health monitor
oc apply -f rig/baremetal/bootstrap/00-prerequisites.yaml
```

This installs:
- OpenShift GitOps operator (ArgoCD)
- Auto-approval Job for InstallPlans
- **Health Monitor CronJob** (runs every 2 minutes to auto-fix stuck operations)

**Why health monitor is in prerequisites:**
- Deployed BEFORE root-app to avoid chicken-and-egg issues
- If root-app gets stuck, health monitor is already running to fix it
- Prevents need for manual intervention during deployment

**Wait for the operator to be ready** (~2-3 minutes):

```bash
# Watch for the operator to become available
watch -n 5 'oc get csv -n openshift-operators | grep gitops'

# Wait for the openshift-gitops namespace to be created
watch -n 5 'oc get namespace openshift-gitops'

# Check GitOps pods are running
oc get pods -n openshift-gitops
```

You should see output like:
```
NAME                                                         READY   STATUS      RESTARTS   AGE
cluster-67f5c4874b-gglzl                                     1/1     Running     0          38s
gitops-plugin-598cff7645-tktcz                               1/1     Running     0          38s
openshift-gitops-application-controller-0                    1/1     Running     0          36s
openshift-gitops-applicationset-controller-69964ffd4-qb9hc   1/1     Running     0          36s
openshift-gitops-dex-server-64659464d5-9rnzc                 1/1     Running     0          36s
openshift-gitops-redis-68469975f8-h8vb4                      1/1     Running     0          37s
openshift-gitops-repo-server-75db857f8-plzgq                 1/1     Running     0          37s
openshift-gitops-server-674758b98b-8dnct                     1/1     Running     0          37s
```

### Step 2: Deploy the Application Suite

Once the GitOps operator is ready, deploy the full suite:

```bash
oc apply -k rig/baremetal/bootstrap/
```

This will:
- Grant ArgoCD cluster-admin permissions (gitops-cluster-admin.yaml)
- Create necessary namespaces
- Deploy the root ArgoCD Application
- Bootstrap all applications in the suite with proper sequencing

**Note:** The kustomization automatically applies cluster-admin permissions to ArgoCD - no manual step needed.

## Deployment Order (Sync Waves)

ArgoCD deploys applications in the following order to ensure correct dependencies:

```
Wave -1: Node Preparation (AUTOMATED)
  └─ node-preparation
      ├─ Labels all worker nodes with fab-rig-deployer=true
      └─ Taints all master/control-plane nodes with fab-rig=control-plane:NoSchedule
      └─ PREVENTS GPU and MOFED deployment on master nodes

Wave 15: Node Feature Discovery
  └─ nfd-config
      └─ Discovers hardware features (NICs, GPUs, kernel version)

Wave 26: SR-IOV VF Configuration (MachineConfigs)
  └─ sriov-vf-config
      ├─ Creates systemd service on worker nodes
      ├─ Configures 16 VFs per RDMA-capable NIC at boot time
      └─ Triggers node reboots (rolling update, one node at a time)

Wave 28: NVIDIA Network Operator Namespace
  └─ nvidia-network-operator
      └─ Creates namespace for Network Operator resources

Wave 29: MOFED Readiness Check
  └─ nvidia-mofed-ready
      └─ Waits for MOFED DaemonSet pods to be Running and Ready

Wave 35: NIC Discovery (PreSync: Wait for MCPs)
  └─ nic-discovery
      ├─ PreSync hook: Waits for all MachineConfigPools to complete updates
      ├─ Discovers InfiniBand and RoCE-capable network ports
      ├─ Generates NicClusterPolicy with dynamic MOFED timeout
      └─ Creates NetworkAttachmentDefinitions for each NIC

Wave 40: GPU Operator (PreSync: Wait for MOFED)
  └─ gpu-operator-nfd
      ├─ PreSync hook: Waits for MOFED pods to be fully ready
      ├─ Blocked by master taint (fab-rig=control-plane:NoSchedule)
      └─ Deploys NVIDIA GPU drivers (uses MOFED for GPUDirect RDMA) on workers only
```

**Critical:**
- Wave -1 automatically prepares nodes on ANY cluster - no manual intervention needed
- GPU and MOFED operators NEVER deploy on master/control-plane nodes (protected by taint + nodeAffinity)
- GPU Operator (Wave 4) requires NVIDIA Network Operator's OFED drivers (Wave 2) to be fully ready
- Wave 3 ensures MOFED pods are Running before GPU deployment begins

### Step 3: Monitor Deployment

```bash
# Watch ArgoCD applications
watch -n 5 'oc get applications -n openshift-gitops'

# Check for any issues
oc get applications -n openshift-gitops | grep -v "Healthy.*Synced"

# Monitor SR-IOV node configuration (takes ~60 min per node)
# The sriov-node-monitor job is automatically created by ArgoCD
oc logs -n openshift-sriov-network-operator job/sriov-node-monitor -f
```

## Expected Timeline

| Time | Event |
|------|-------|
| 0min | Prerequisites installed (GitOps operator) |
| 3min | GitOps operator ready |
| 5min | Root app deployed, all operators deploying |
| 10min | NFD discovers hardware features |
| 15min | Worker nodes auto-labeled |
| 20min | MachineConfig (wave 26) applied - VF configuration starts |
| 20min + (N × 10-15min) | All N workers configured with 16 VFs (nodes rebooted sequentially) |
| +2min | Wait for MCPs ready (wave 35 PreSync hook) |
| +1min | NIC discovery runs, creates NicClusterPolicy |
| +10min | MOFED driver compilation on all nodes |
| +5min | GPU Operator deployment |
| +10min | Full deployment complete |

**MachineConfig VF Configuration Time:**
- **~10-15 minutes per worker node** (requires node drain + reboot)
- **Default:** Nodes configured **sequentially** (1 at a time via `maxUnavailable: 1` in MachineConfigPool)
- **Configurable:** Adjust `maxUnavailable` in worker MachineConfigPool to configure multiple nodes in parallel
  - See [MachineConfig Operator Documentation](https://docs.openshift.com/container-platform/latest/post_installation_configuration/machine-configuration-tasks.html)
- **Example timelines (sequential, maxUnavailable: 1):**
  - 2 workers: ~30 minutes total
  - 10 workers: ~150 minutes (~2.5 hours)
  - 50 workers: ~750 minutes (~12.5 hours)
- **With parallel configuration (maxUnavailable: 5):**
  - 50 workers: ~150 minutes (~2.5 hours)

**Note:** Master/control-plane nodes are excluded from SR-IOV configuration (protected from reboots).

## What Gets Deployed

The baremetal suite includes:

- **Infrastructure**: Node Feature Discovery, GitOps, Operators
- **Networking**: SR-IOV, RoCE/RDMA, NVIDIA Network Operator (OFED drivers)
- **GPU**: NVIDIA GPU Operator
- **Monitoring**: NetObserv, User Workload Monitoring
- **Platform**: Cert Manager, Gateway API, Pipelines
- **AI/ML**: LLM deployment prerequisites

## NIC Discovery and SR-IOV Network Configuration

The deployment includes **automated RDMA NIC discovery** that finds all Mellanox/NVIDIA NICs with InfiniBand and RoCE capability and automatically generates NicClusterPolicy and NetworkAttachmentDefinitions.

### How It Works

1. **VF Creation (Wave 26)**: MachineConfig systemd service creates 16 VFs per RDMA NIC at boot time
2. **Discovery Phase (Wave 35)**: DaemonSet runs on each worker node and detects InfiniBand and RoCE-capable NICs
3. **Generator Phase**: Collects results from all nodes and generates:
   - **NicClusterPolicy**: MOFED driver config with dynamic startup probe timeout
   - **NetworkAttachmentDefinitions**: One per unique NIC (using host-device CNI + whereabouts IPAM)
4. **MOFED Deployment**: Network Operator deploys MOFED drivers based on NicClusterPolicy
5. **SR-IOV Device Plugin**: Exposes VF resources (e.g., `nvidia.com/ibp24s0_ib`, `nvidia.com/ens2f1np1_roce`)

### Subnet Configuration Modes

You can configure how IP addresses are allocated to SR-IOV networks:

**Mode 1: Separate Subnets (DEFAULT - Recommended)**
- Each NIC gets its own isolated /24 subnet
- Example: `ens3f0np0` → `10.0.101.0/24`, `ens3f1np1` → `10.0.102.0/24`
- ✅ Best for: Network isolation, multi-tenant workloads, traffic segregation
- ✅ Maximum scalability: 254 IPs per NIC

**Mode 2: Shared Subnet**
- All NICs share the same /24 subnet
- Example: All NICs → `10.0.100.0/24` (254 IPs total)
- ✅ Best for: Layer-2 connectivity between NICs, legacy flat networks
- ⚠️  Limitation: Only 254 IPs total shared across all pods

### Configuration

The NIC discovery generator is configured in `manifests/35-nic-discovery/job-generator.yaml`:

```yaml
env:
  - name: SUBNET_MODE
    value: "separate"       # "separate" or "shared"
  - name: IP_RANGE_BASE
    value: "10.0"           # First two octets (10.0, 192.168, 172.16, etc.)
  - name: NUM_VFS
    value: "1"              # Number of VF resources advertised per NIC (not hardware VF count)
  - name: MTU
    value: "9000"           # Jumbo frames for RDMA performance
  - name: NETWORK_NAMESPACE
    value: "default"        # Namespace where networks are available
  - name: ROUTE_DEST
    value: "192.168.75.0/24"  # Default route for SR-IOV traffic
```

**Note:** `NUM_VFS=1` controls resource advertisement (1 allocatable resource per NIC), not hardware VF creation. The MachineConfig (wave 26) creates 16 VFs per NIC at boot time.

### Detailed Documentation

For comprehensive documentation including:
- Dynamic MOFED startup probe timeout calculation
- Detailed subnet mode comparison
- Configuration examples (custom IP ranges, multiple VFs, etc.)
- Mixed topology support (same PCI, different link types)
- Automatic cleanup of discovery resources
- Troubleshooting guide
- Verification commands

See **[NIC Discovery and Configuration Documentation](../../manifests/35-nic-discovery/README.md)**

## Automated Self-Healing (Health Monitor)

The deployment includes an **automated health monitor** that runs every 2 minutes to detect and fix common issues.

**Location:** Deployed in `rig/baremetal/bootstrap/00-prerequisites.yaml` (also available in `manifests/27-gitops/argocd-health-monitor.yaml`)

**Why it's in prerequisites:** The health monitor is deployed BEFORE the root-app to prevent chicken-and-egg issues where the root-app gets stuck but the health monitor hasn't been deployed yet to fix it.

**What it fixes automatically:**

1. **Stuck ArgoCD Sync Operations** (>3 minutes)
   - Clears stuck operations to allow automated retry
   - Prevents deployments from hanging indefinitely

2. **Stuck ArgoCD Hook Jobs** (>3 minutes)
   - Removes finalizers from terminating/completed hook Jobs
   - Allows PreSync/PostSync hooks to complete

3. **Failed PreSync Hooks**
   - Retriggers sync for Applications with failed PreSync hooks
   - Automatically retries failed operations

4. **OLM Operator Issues** (>5 minutes)
   - **Stuck CSVs in Pending:** Deletes CSVs stuck in Pending state (OLM recreates from Subscription)
   - **Broken Subscriptions:** Deletes Subscriptions referencing deleted InstallPlans (ArgoCD recreates from Application)

5. **Pods Stuck in Pending** (>3 minutes)
   - Reports pods that can't be scheduled (informational only, requires manual intervention)

**How to monitor:**

```bash
# Check health monitor CronJob status
oc get cronjob argocd-health-monitor -n openshift-gitops

# View recent health monitor runs
oc get jobs -n openshift-gitops | grep health-monitor | tail -5

# Check latest health monitor logs
oc logs -n openshift-gitops job/$(oc get jobs -n openshift-gitops --sort-by=.metadata.creationTimestamp | grep health-monitor | tail -1 | awk '{print $1}')

# Follow logs from next health monitor run (waits for next CronJob execution)
oc logs -n openshift-gitops -l job-name --selector=job-name -f --since=10s | grep -A 100 "ArgoCD Health Monitor"
```

**Reading the logs:**

The health monitor logs are organized into sections:

```
========================================
ArgoCD Health Monitor
Checking for stuck sync operations...
========================================

✓ OK: app-name - Running for 45s (< 180s)
⚠️  STUCK: another-app - Running for 245s (> 180s)
   → Clearing stuck operation...
   ✓ Cleared successfully

========================================
Checking for stuck OLM operators (CSVs)...
========================================

⚠️  STUCK CSV: namespace/csv-name
   Age: 420s (> 300s)
   Phase: Pending
   Reason: RequirementsNotMet
   → Deleting CSV to force OLM to retry...
   ✓ CSV deleted. OLM will recreate from Subscription.

========================================
Summary:
  Stuck operations found: 1
  Operations cleared: 1
  CSVs stuck in Pending: 1
  CSVs deleted: 1
  Broken Subscriptions: 0
  Subscriptions fixed: 0
========================================

✓ Self-healing completed. ArgoCD automated sync will retry.
```

**What to look for:**

- **✓ OK:** Everything is healthy (no action needed)
- **⚠️ STUCK:** Issue detected and being fixed automatically
- **✓ Cleared/Deleted:** Issue was successfully resolved
- **✗ Failed:** Automatic fix failed (may need manual intervention)
- **Summary section:** Overall count of issues found and fixed

**When to investigate:**

- If the same issue appears in multiple consecutive runs (health monitor can't fix it)
- If you see **✗ Failed** messages (automatic fix didn't work)
- If "Pods stuck in Pending" are reported (these require manual investigation)

**Result:** The cluster self-heals from most common deployment issues with **ZERO manual intervention**.

### Does the health monitor stay running after deployment?

**Yes - it runs continuously** (every 2 minutes, permanently). This is by design.

**Why it should keep running:**

- **Future deployments:** Auto-fixes issues when you update/redeploy Applications
- **Operator upgrades:** OLM operator updates can get stuck in Pending state
- **Configuration changes:** Any ArgoCD Application modifications might need self-healing
- **Cluster maintenance:** Operations can get stuck during normal cluster lifecycle events

**Resource usage:**
- Runs every 2 minutes (very lightweight)
- Each run takes ~20-30 seconds
- Only acts when issues are detected
- Minimal resource impact: 10m CPU, 32Mi RAM requests

**Think of it as:** A cluster "watchdog" for continuous monitoring and self-healing.

**To disable (not recommended):**

```bash
# Suspend the CronJob (stops future runs)
oc patch cronjob argocd-health-monitor -n openshift-gitops -p '{"spec":{"suspend":true}}'

# Or delete it entirely
oc delete cronjob argocd-health-monitor -n openshift-gitops
```

**Recommendation:** Keep it running - it provides continuous self-healing for production clusters.

## Troubleshooting

### GitOps operator not installing

```bash
# Check subscription status
oc get subscription openshift-gitops-operator -n openshift-operators -o yaml

# Check install plan
oc get installplan -n openshift-operators

# Check operator pod logs
oc logs -n openshift-operators -l name=openshift-gitops-operator
```

### ArgoCD applications stuck

```bash
# Check application details
oc describe application <app-name> -n openshift-gitops

# Check ArgoCD controller logs
oc logs -n openshift-gitops openshift-gitops-application-controller-0
```

### SR-IOV configuration issues

See `manifests/35-nic-discovery/README.md` for NIC discovery troubleshooting and `manifests/26-sriov-vf-config/README.md` for VF creation troubleshooting.

### MOFED Pods CrashLoopBackOff - irdma Module Conflict

**Symptom:** MOFED driver pods crash with error:
```
rmmod: ERROR: Module ib_uverbs is in use by: irdma
Command "/etc/init.d/openibd restart" failed with exit code: 1
```

**Cause:** Intel RDMA (irdma) driver conflicts with NVIDIA MOFED driver. This typically occurs on hardware with Intel network adapters that have RDMA support.

**Check if you have this issue:**
```bash
# Check if irdma module is loaded on worker nodes
oc debug node/<worker-node-name> -- chroot /host lsmod | grep irdma
```

If `irdma` module is loaded, apply the workaround below.

**Workaround:** Blacklist the irdma driver using a Tuned performance profile:

```yaml
apiVersion: tuned.openshift.io/v1
kind: Tuned
metadata:
  name: openshift-node-custom
  namespace: openshift-cluster-node-tuning-operator
spec:
  profile:
  - data: |
      [main]
      summary=Custom OpenShift node profile with irdma module blacklist
      include=openshift-node
      [bootloader]
      cmdline_openshift_node_custom=module_blacklist=irdma
    name: openshift-node-custom

  recommend:
  - machineConfigLabels:
      machineconfiguration.openshift.io/role: "worker"
    priority: 20
    profile: openshift-node-custom
```

**Apply the fix:**
```bash
# Save the above YAML to a file and apply
oc apply -f tuned-blacklist-irdma.yaml

# Wait for nodes to apply the tuned profile (~1-2 minutes)
# Nodes will NOT reboot, but kernel cmdline will update on next boot

# Verify the profile is applied
oc get tuned -n openshift-cluster-node-tuning-operator openshift-node-custom

# Reboot nodes to apply kernel cmdline change
# OR restart MOFED pods if nodes were already rebooted
oc delete pods -n nvidia-network-operator -l app=mofed
```

**Note:** This issue is hardware-specific and not commonly encountered. Only apply this workaround if you confirm the irdma module is loaded and causing MOFED pod crashes.

## Cleanup

To completely remove the deployment, **delete ClusterPolicy resources FIRST** to avoid orphaning CRs:

```bash
# Step 1: Delete ClusterPolicy resources BEFORE deleting operators
oc delete nicclusterpolicy --all 2>/dev/null || true
oc delete clusterpolicy --all 2>/dev/null || true

# Step 2: Delete the root application (cascade delete will remove operators and applications)
oc delete -k rig/baremetal/bootstrap/

# Step 3: Wait for cascade deletion to complete (~1-2 minutes)
watch oc get applications -n openshift-gitops
```

**Why this order matters:**
- ClusterPolicy resources depend on operator CRDs
- Deleting operators first would leave orphaned CRs that can't be managed
- Always delete ClusterPolicy → then operators/applications

**What gets deleted:**
- ClusterPolicy resources (NicClusterPolicy, ClusterPolicy)
- ArgoCD root application and all child Applications (via cascade delete)
- All operators and their managed resources
- Application namespaces

**What persists:**
- `gitops-cluster-admin` ClusterRoleBinding (intentionally kept so ArgoCD retains permissions)
- `openshift-gitops` namespace and GitOps operator
- Prerequisites (00-prerequisites.yaml)

## Security Notes

- Master/control-plane nodes are NOT configured with SR-IOV (protected from reboots)
- Worker nodes are automatically labeled and configured
- All operators run with minimal required permissions
- GitOps service account has cluster-admin (required for full deployment)
