# Operator Cleanup Job

This directory contains a Kubernetes Job that performs comprehensive cleanup of all operators and their resources.

## Table of Contents
- [Purpose](#purpose)
- [Usage](#usage)
- [What Gets Cleaned Up](#what-gets-cleaned-up)
- [Verification](#verification)
- [Automatic ArgoCD Cleanup](#automatic-argocd-cleanup)
- [Notes](#notes)

## Purpose

Run this Job **BEFORE** a fresh deployment to prevent conflicts from previous installations:
- Removes all operator CSVs from ALL namespaces (solves the 91-namespace CSV issue)
- Deletes operator subscriptions and install plans
- Removes operator namespaces
- Deletes CRDs and webhook configurations

## Usage
```bash
# Apply the cleanup Job directly
oc apply -k manifests/00-cleanup

# Watch the cleanup process
oc logs -n openshift-operators job/cleanup-operators -f

# Wait for completion
oc wait --for=condition=complete job/cleanup-operators -n openshift-operators --timeout=600s

# Delete the Job (auto-deletes after 5 minutes anyway)
oc delete -k manifests/00-cleanup
```

## What Gets Cleaned Up

**IMPORTANT**: ArgoCD/GitOps is **preserved** and NOT deleted by this cleanup job. This allows you to keep using ArgoCD for other applications while cleaning up the GPU/RDMA infrastructure.

1. **ArgoCD Applications**
   - Deletes infrastructure operator Applications (gpu-operator, nvidia-network-operator, nfd, sriov-operator, etc.)
   - Removes finalizers to prevent stuck deletions
   - **Preserves**: ArgoCD/GitOps operator, openshift-gitops namespace, and root-app Application

2. **GPU Operator**
   - Subscription, ClusterPolicy, CSVs
   - Removes finalizers from ArgoCD hook jobs and serviceaccounts
   - Prevents stuck namespaces due to hook finalizers

3. **Network Operator**
   - Subscription, NicClusterPolicy, CSVs

4. **NFD Operator**
   - Subscription, CSVs
   - Removes finalizers from NodeFeatureDiscovery instances
   - Prevents stuck namespaces due to NFD finalizers

5. **SR-IOV Operator**
   - Subscription, CSVs, custom resources
   - Removes finalizers from SriovNetworks and SriovOperatorConfigs
   - Prevents stuck namespaces due to SR-IOV finalizers

6. **Network Performance Testing**
   - Job, ServiceAccount, ConfigMap in default namespace
   - Dynamically created DaemonSet (network-perf-test-worker)
   - ClusterRole and ClusterRoleBinding

7. **Namespaces**
   - nvidia-gpu-operator
   - nvidia-network-operator
   - openshift-nfd
   - openshift-sriov-network-operator
   - helm-charts
   - **PRESERVED**: `openshift-gitops` namespace and ArgoCD operator (for redeployment and other apps)
   - Waits up to 2 minutes for namespaces to be fully deleted
   - **Auto-recovery**: If namespaces remain stuck, force-finalizes them using:
     - Removes any remaining custom resources (NFD instances, helm jobs)
     - Force-deletes remaining serviceaccounts, jobs, and pods
     - Force-finalizes namespace using Kubernetes raw API
     - Ensures 100% cleanup even with stubborn resources

8. **CRDs and Webhooks**
   - Operator-related CRDs (GPU, Network, NFD, SR-IOV)
   - Webhook configurations
   - **PRESERVED**: ArgoCD CRDs and GitOps operator

## Verification

After cleanup completes, verify:

```bash
# No operator CSVs remain
oc get csv -A | grep -E "(gpu|nvidia|nfd|sriov)" || echo "Clean ✓"

# No operator namespaces remain
oc get ns | grep -E "(nvidia-gpu-operator|nvidia-network-operator|openshift-nfd|openshift-sriov|helm-charts)" || echo "Clean ✓"

# No operator CRDs remain
oc get crd | grep -E "(nvidia|mellanox|nfd|sriov)" || echo "Clean ✓"

# GitOps should still exist
oc get ns openshift-gitops && echo "✓ GitOps preserved"
oc get csv -n openshift-operators | grep gitops && echo "✓ GitOps operator preserved"
```

## Redeploying After Cleanup

Since GitOps/ArgoCD is preserved, you can immediately redeploy:

```bash
# Redeploy the infrastructure
oc apply -k rig/baremetal/bootstrap
```

ArgoCD will automatically sync and recreate all the infrastructure operator Applications.

## Notes

- The Job runs in the `openshift-operators` namespace
- Auto-deletes after 10 minutes (`ttlSecondsAfterFinished: 600`)
- Safe to run multiple times (idempotent)
- Uses cluster-scoped RBAC with minimal required permissions
- Automatically removes finalizers to prevent stuck namespaces
- Waits for namespaces to be fully deleted before completing
- **Force-finalization**: If namespaces remain stuck after 2 minutes, automatically force-finalizes them
- Handles edge cases like ArgoCD hook finalizers and SR-IOV network finalizers
- No manual intervention required - fully automated stuck namespace recovery
