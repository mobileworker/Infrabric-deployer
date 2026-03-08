# EP Model Cache Setup

This guide explains the shared model cache system for the EP deployment. The model cache is **automatically set up** during deployment, but you may need to customize the storage class.

## Overview

The deployment automatically:
1. **Wave 10**: Creates a 1TB ReadWriteMany PVC
2. **Wave 15**: Downloads the ~200GB model to the PVC
3. **Wave 25**: Deploys prefill/decode pods (waits for model download)

All pods mount the same cached model, avoiding redundant downloads.

## Prerequisites

- A ReadWriteMany (RWX) storage class (typically NFS or similar)
- At least 1TB of available storage
- HuggingFace token configured in the `llm-d-hf-token` secret (for gated models)

## Automatic Deployment

**The model cache is set up automatically** when you deploy:

```bash
oc apply -k rig/llm-d/overlays/ep-multinode
```

### What Happens Automatically

**Wave 10** - PVC Creation:
```
✅ Creates wide-ep-model-cache PVC (1TB)
```

**Wave 15** - Model Download:
```
✅ Starts wide-ep-model-download job
⏳ Downloads Qwen3-235B-A22B-FP8 (~200GB)
⏳ Takes 20-30 minutes depending on network speed
```

**Wave 25** - Model Server Deployment:
```
⏳ Waits for model download to complete
✅ Deploys prefill and decode LeaderWorkerSets
✅ Pods mount the cached model (read-only)
```

### Monitor the Deployment

Watch the deployment progress:
```bash
# Watch all pods
kubectl get pods -n llm-d -w

# Monitor model download
kubectl logs -n llm-d -l job=model-download --follow

# Check PVC status
kubectl get pvc wide-ep-model-cache -n llm-d
```

Expected output:
```
NAME                    STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS    AGE
wide-ep-model-cache     Bound    pvc-xxxxx    1Ti        RWX            nfs-disk-1-sc   5m
```

## Customizing Storage Class

**BEFORE deploying**, update the storage class if you don't have `nfs-disk-1-sc`:

### Step 1: Identify Your Storage Class

```bash
kubectl get storageclass
```

Look for a storage class that supports `ReadWriteMany` access mode (usually NFS-based).

### Step 2: Update the PVC Configuration

Edit `model-cache-pvc.yaml` and replace the storage class name:

```bash
vi rig/llm-d/overlays/ep-multinode/model-cache-pvc.yaml
```

Change:
```yaml
spec:
  storageClassName: nfs-disk-1-sc  # REPLACE with your storage class
```

### Step 3: Deploy

Now run the deployment:
```bash
oc apply -k rig/llm-d/overlays/ep-multinode
```

## Verify Model Cache

```bash
# Watch pods come up
kubectl get pods -n llm-d -l llm-d.ai/guide=ep-multinode -w

# Check logs
kubectl logs -n llm-d wide-ep-prefill-0 -c vllm --follow
```

## Troubleshooting

### PVC stuck in Pending
- Verify your storage class supports ReadWriteMany
- Check if PV provisioner is running: `kubectl get pods -n kube-system | grep nfs`
- Check storage class: `kubectl describe storageclass <your-sc-name>`

### Download job fails
- Check HuggingFace token: `kubectl get secret llm-d-hf-token -n llm-d -o yaml`
- View job logs: `kubectl logs -n llm-d -l job=model-download`
- Check disk space on NFS server

### Pods fail to mount PVC
- Verify PVC is bound: `kubectl get pvc -n llm-d`
- Check pod events: `kubectl describe pod <pod-name> -n llm-d`
- Ensure NFS mount is accessible from worker nodes

## Cleanup

### Normal Deployment Cleanup

**The model cache PVC is preserved during normal cleanup**:
```bash
# This removes the deployment but KEEPS the cached model
kubectl delete -k rig/llm-d/overlays/ep-multinode
```

The `wide-ep-model-cache` PVC is **not** included in `kustomization.yaml`, so it persists across deployments. This is intentional - the 200GB model download is expensive and time-consuming.

### Full Cleanup (Including Model Cache)

Only delete the PVC if you want to completely remove the cached model:
```bash
# Delete the download job (optional)
kubectl delete job wide-ep-model-download -n llm-d

# Delete the PVC (WARNING: deletes the ~200GB cached model)
kubectl delete pvc wide-ep-model-cache -n llm-d
```

**When to delete the PVC**:
- Switching to a different model
- Reclaiming storage space
- Troubleshooting corrupted model files

**When NOT to delete the PVC**:
- Normal deployment cleanup/redeployment
- Updating configuration (ConfigMaps, env vars)
- Debugging pod issues

## Notes

- The PVC is mounted as **read-only** in the model server pods to prevent accidental modifications
- The model download job uses 4 parallel workers for faster downloads
- The job has a backoff limit of 3 retries in case of transient failures
- JIT compilation cache (`/var/cache/vllm`) remains pod-local as it contains compiled kernels specific to each GPU
