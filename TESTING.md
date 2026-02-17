# Testing Guide

## Quick Start (Recommended)

Use the automated test jobs for the easiest testing experience:

```bash
# 1. Clean and prepare for testing
oc apply -f manifests/99-cleanup/infrastructure-cleanup.yaml
oc logs -f job/infrastructure-cleanup -n nvidia-network-operator

# 2. Run your manual tests (see Full Test Cycle below)

# 3. Restore auto-deployment (if you disabled it manually - see Manual Approach section)
```

See `manifests/99-cleanup/README.md` for detailed documentation.

## Why Disable Auto-Deployment for Testing?

When testing the full deployment cycle, you need to prevent ArgoCD from automatically recreating resources. This is especially important because:

1. **Hook Annotations**: The `discover-ofed-version` Job has ArgoCD hook annotations (`argocd.argoproj.io/hook: Sync`) that cause it to run on every sync
2. **Self-Healing**: ArgoCD's `selfHeal` feature automatically recreates deleted resources (including NicClusterPolicy)
3. **Root App**: The `root-app` manages child applications and will recreate them if deleted

## Manual Approach (Alternative)

If you need more control, you can manually disable/enable auto-deployment:

### Disable Auto-Deployment

```bash
# 1. Disable root-app auto-sync (prevents child app recreation)
kubectl patch app root-app -n openshift-gitops --type=json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'

# 2. Delete the child applications you want to test
kubectl delete app nvidia-network-operator sriov-vf-config -n openshift-gitops

# 3. Verify apps are deleted and won't be recreated
kubectl get app nvidia-network-operator sriov-vf-config -n openshift-gitops 2>&1
# Should show: Error from server (NotFound)
```

### Re-Enable Auto-Deployment

After testing is complete, restore ArgoCD automation:

```bash
# 1. Re-enable root-app auto-sync
kubectl patch app root-app -n openshift-gitops --type=merge \
  -p='{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'

# 2. The root-app will automatically recreate child applications
# Wait a few seconds, then verify:
kubectl get app nvidia-network-operator sriov-vf-config -n openshift-gitops

# 3. Trigger a sync if needed
kubectl patch app root-app -n openshift-gitops --type=merge \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}'
```

## Full Test Cycle

### Prerequisites

1. Disable auto-deployment (see above)
2. Clean existing resources:

```bash
# Delete NVIDIA resources
oc delete nicclusterpolicy --all --all-namespaces
oc delete job discover-ofed-version wait-for-mofed-ready -n nvidia-network-operator --ignore-not-found=true
oc delete serviceaccount nic-policy-updater -n nvidia-network-operator --ignore-not-found=true
oc delete clusterrole nic-policy-updater --ignore-not-found=true
oc delete clusterrolebinding nic-policy-updater --ignore-not-found=true

# Delete MachineConfigs
oc delete machineconfig 99-worker-sriov-max-vfs 99-worker-dgx-sriov-max-vfs --ignore-not-found=true

# Wait for MOFED driver pods to terminate
oc get pods -n nvidia-network-operator -w

# Reset VFs to 0 (after MOFED drivers are unloaded)
for node in $(oc get nodes -l node-role.kubernetes.io/worker-dgx -o name | cut -d/ -f2); do
  oc debug node/$node -- chroot /host /bin/bash -c '
    for nic in mlx5_0 mlx5_1; do
      numvfs_path="/sys/class/infiniband/$nic/device/sriov_numvfs"
      if [ -f "$numvfs_path" ]; then
        echo 0 > "$numvfs_path" 2>/dev/null
      fi
    done
  '
done
```

### Manual Deployment Test

```bash
# 1. Apply SR-IOV VF configuration
kubectl apply -k manifests/26-sriov-vf-config/

# 2. Monitor MachineConfigPool updates
watch oc get mcp

# Wait for all worker pools to show:
#   UPDATED=True, UPDATING=False, DEGRADED=False

# 3. Verify VF configuration on nodes
for node in $(oc get nodes -l node-role.kubernetes.io/worker-dgx -o name | cut -d/ -f2); do
  echo "=== $node ==="
  oc debug node/$node -- chroot /host /bin/bash -c '
    for nic in mlx5_0 mlx5_1; do
      numvfs_path="/sys/class/infiniband/$nic/device/sriov_numvfs"
      if [ -f "$numvfs_path" ]; then
        vfs=$(cat $numvfs_path)
        echo "$nic: $vfs VFs"
      fi
    done
  '
done

# 4. Apply NVIDIA Network Operator configuration
kubectl apply -k manifests/28-nvidia-network-operator/

# 5. Monitor MOFED driver deployment
watch oc get pods -n nvidia-network-operator

# 6. Verify NicClusterPolicy was created with correct version
oc get nicclusterpolicy nic-cluster-policy -n nvidia-network-operator -o yaml

# 7. Check MOFED driver daemonset
oc get daemonset -n nvidia-network-operator -l app=mofed-driver
```

## Why Hook Annotations Are Needed (Production)

The hook annotations on `discover-ofed-version` Job are **essential for production** because:

1. **Self-Healing**: If NicClusterPolicy is deleted, ArgoCD detects drift and triggers a sync
2. **Hook Execution**: The sync runs the hook Job, which discovers the OFED version and recreates the policy
3. **Automatic Recovery**: No manual intervention needed - fully automated

**For Testing Only**: The hook behavior makes testing harder because resources get recreated automatically. This is why we temporarily disable the root-app auto-sync during testing.

## Forcing MachineConfig Updates

To trigger a MachineConfig update without changing the actual script:

```bash
# Update the DEPLOY_VERSION timestamp in manifests/26-sriov-vf-config/kustomization.yaml
# Change the timestamp on line 27:
#   Environment="DEPLOY_VERSION=2026-02-02T19:00:00Z"
# to a new timestamp, then commit and push:

git add manifests/26-sriov-vf-config/kustomization.yaml
git commit -m "Trigger MachineConfig update with new DEPLOY_VERSION"
git push

# ArgoCD will detect the change and update the MachineConfigs
# This causes MCO to create new rendered configs → node reboots → VF configuration runs
```
