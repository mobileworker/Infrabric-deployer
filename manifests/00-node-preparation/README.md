# Node Preparation - Automated Labeling and Tainting

This directory contains the automated node preparation Job that runs before any other deployment (sync wave -1).

## Table of Contents
- [Purpose](#purpose)
- [Why This Is Needed](#why-this-is-needed)
- [How It Works](#how-it-works)
- [Integration with Operators](#integration-with-operators)
- [Deployment Order](#deployment-order)
- [Verification](#verification)
- [Cleanup](#cleanup)
- [Idempotency](#idempotency)

## Purpose

Ensures consistent node configuration across all clusters by automatically:
1. **Labeling worker nodes** with `fab-rig-deployer=true`
2. **Tainting master/control-plane nodes** with `fab-rig=control-plane:NoSchedule`

## Why This Is Needed

NVIDIA GPU Operator and Network Operator (MOFED) should NEVER deploy on master/control-plane nodes because:
- Driver compilation/installation can destabilize control plane
- RDMA drivers (irdma, MOFED) can conflict and cause kernel panics
- Master nodes don't typically have GPUs or high-speed network adapters
- Reboots during driver installation disrupt cluster control plane

## How It Works

The Job automatically detects node roles using standard Kubernetes labels:
- **Workers**: Nodes with `node-role.kubernetes.io/worker` label
- **Masters**: Nodes with `node-role.kubernetes.io/master` OR `node-role.kubernetes.io/control-plane` label

### What Gets Applied

**Worker Nodes:**
```yaml
labels:
  fab-rig-deployer: "true"  # Added by this Job
```

**Master/Control-Plane Nodes:**
```yaml
taints:
  - key: fab-rig
    value: control-plane
    effect: NoSchedule  # Prevents GPU/MOFED pods from scheduling
```

## Integration with Operators

### NVIDIA Network Operator (MOFED)
The NicClusterPolicy uses `nodeAffinity` to explicitly require worker nodes:
```yaml
spec:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/worker
          operator: Exists
        - key: node-role.kubernetes.io/master
          operator: DoesNotExist
```

**Defense-in-depth:** Both nodeAffinity AND master taint prevent MOFED deployment on control plane.

### NVIDIA GPU Operator
The ClusterPolicy CRD doesn't support `nodeAffinity`, so we rely on:
- **Master taint** (`fab-rig=control-plane:NoSchedule`) - prevents scheduling
- **GPU taint tolerations** - allow GPU pods on tainted GPU nodes, but NOT on master taint

The ClusterPolicy tolerations:
```yaml
spec:
  daemonsets:
    tolerations:
      - key: "benchmark.llm-d.ai/test-gpu-amd64"
        operator: "Exists"
        effect: "NoSchedule"
```

**Note:** GPU pods tolerate `benchmark.llm-d.ai/test-gpu-amd64` but NOT `fab-rig`, so they won't schedule on master.

## Deployment Order

```
Wave -1: Node Preparation (this Job)
  └─ Labels workers, taints masters

Wave 0: Node Feature Discovery
  └─ Discovers hardware features

Wave 1: SR-IOV Operator
  └─ Configures SR-IOV (workers only via NFD labels)

Wave 2: NVIDIA Network Operator
  └─ Deploys MOFED drivers (workers only via nodeAffinity + taint)

Wave 3: MOFED Readiness Check
  └─ Waits for MOFED drivers ready

Wave 4: GPU Operator
  └─ Deploys GPU drivers (workers only via taint)
```

## Verification

After deployment, verify node configuration:

```bash
# Check worker labels
oc get nodes -l fab-rig-deployer=true

# Check master taints
oc get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints | grep fab-rig

# Verify MOFED pods only on workers
oc get pods -n nvidia-network-operator -l nvidia.com/ofed-driver -o wide

# Verify GPU driver pods only on workers
oc get pods -n nvidia-gpu-operator -l app=nvidia-driver-daemonset -o wide
```

## Cleanup

The Job is managed by ArgoCD and will be deleted when the root application is removed. The labels and taints persist on nodes until:
- Nodes are removed/replaced
- Manual cleanup: `oc label node <node> fab-rig-deployer-` and `oc adm taint node <node> fab-rig-`

## Idempotency

The Job is idempotent - it can run multiple times safely:
- Uses `--overwrite` for labels (updates existing)
- Checks for existing taints before applying
- Safe to re-run after cluster upgrades or node additions
