# Infrastructure Cleanup

This directory contains utilities for cleaning up the deployed infrastructure.

## Quick Start

### Run Infrastructure Cleanup

```bash
# Run the cleanup job
oc apply -f manifests/99-cleanup/infrastructure-cleanup.yaml

# Monitor the cleanup job
oc logs -f job/infrastructure-cleanup -n nvidia-network-operator

# Wait for MachineConfigPools to be ready
oc get mcp -w
```

The cleanup job will:
1. **Delete all fab-rig ArgoCD applications** (removes all deployed infrastructure)
2. **Wait for namespaces to terminate**
3. **Reset VFs to 0** on all worker-dgx nodes
4. **Display summary** of deleted applications and final VF status

### Redeploy After Cleanup

```bash
# Redeploy all infrastructure
oc apply -k rig/baremetal/bootstrap

# Monitor deployment progress
oc get applications -n openshift-gitops -w

# Wait for MachineConfigPools to update and nodes to reboot
oc get mcp -w

# Monitor NVIDIA Network Operator deployment
oc get pods -n nvidia-network-operator -w

# Verify NicClusterPolicy was created
oc get nicclusterpolicy nic-cluster-policy -n nvidia-network-operator -o yaml
```

## What This Job Does

### infrastructure-cleanup.yaml

**Purpose**: Completely remove all deployed infrastructure for fresh redeployment.

**What it does**:
1. **Deletes all fab-rig ArgoCD applications** - Removes all infrastructure managed by ArgoCD
2. **Waits for namespace termination** - Ensures all resources are fully cleaned up
3. **Resets VFs to 0** - Clears SR-IOV Virtual Functions on all worker-dgx nodes
4. **Provides summary** - Shows count of deleted applications and final VF status

**When to use**:
- Before redeploying with configuration changes
- When testing new infrastructure changes
- When recovering from failed deployments
- When you need a clean slate

## Cleanup After Running

The cleanup job is self-contained and cleans up after itself. To manually remove it:

```bash
# Delete the cleanup job
oc delete job infrastructure-cleanup -n nvidia-network-operator
```

## Troubleshooting

### MachineConfigPools stuck updating

Check which nodes are updating:
```bash
oc get mcp -o wide
oc get nodes -l node-role.kubernetes.io/worker-dgx
```

### MOFED driver pods stuck terminating

Force delete the daemonset:
```bash
oc delete daemonset -n nvidia-network-operator -l app=mofed-driver --grace-period=0 --force
```

### ArgoCD keeps recreating resources

Verify root-app auto-sync is disabled:
```bash
kubectl get app root-app -n openshift-gitops -o jsonpath='{.spec.syncPolicy}' | jq .
```

Should show no `automated` field. If it exists, manually remove it:
```bash
kubectl patch app root-app -n openshift-gitops --type=json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'
```

### VFs not resetting to 0

Make sure MOFED drivers are fully unloaded first:
```bash
oc get pods -n nvidia-network-operator -l app=mofed-driver
# Should show: No resources found

# Then manually reset on each node
oc debug node/<node> -- chroot /host /bin/bash -c \
  'echo 0 > /sys/class/infiniband/mlx5_0/device/sriov_numvfs'
```
