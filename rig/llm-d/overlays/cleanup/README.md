# llm-d Cleanup Overlay

This overlay provides a Kubernetes Job to cleanup all llm-d deployment resources.

## Purpose

Removes all resources created by llm-d deployments while preserving:
- The `llm-d` namespace
- The `llm-d-client` serviceaccount and RBAC
- Prerequisites like `llm-d-hf-token` secret

**Note:** The `llm-d-client` pod is now removed during cleanup as it has fulfilled its deployment role. Use the `inference-test` overlay to verify deployments instead.

## What Gets Deleted

The cleanup job removes the following resources in order:

1. **HTTPRoutes** - Gateway routing rules
2. **InferencePools** - GAIE inference pool CRs
3. **Gateways** - Gateway API gateway instances
4. **Deployments** - All application deployments
5. **StatefulSets** - Any stateful workloads
6. **LeaderWorkerSets** - LeaderWorkerSet CRs (for wide-EP)
7. **Services** - All services
8. **ConfigMaps** - Configuration data
9. **Jobs** - Deployment and installation jobs (except this cleanup job)
10. **EnvoyFilters** - Istio Envoy filters
11. **DestinationRules** - Istio traffic rules
12. **llm-d-client pod** - Client tools pod (deployment complete)
13. **Pods** - Force delete any remaining pods

## Usage

### Deploy the cleanup job

```bash
oc apply -k rig/llm-d/overlays/cleanup
```

### Monitor cleanup progress

```bash
# Watch the cleanup job
oc get jobs -n llm-d -w

# Follow cleanup logs
oc logs -n llm-d job/llm-d-cleanup -f
```

### Verify cleanup

```bash
# Check remaining resources
oc get all -n llm-d

# Check custom resources
oc get gateway,httproute,inferencepool,envoyfilter,destinationrule -n llm-d
```

### Delete the cleanup job after completion

```bash
oc delete job llm-d-cleanup -n llm-d
```

## Complete Cleanup

To remove **everything** including the namespace:

```bash
# Run cleanup first
oc apply -k rig/llm-d/overlays/cleanup

# Wait for cleanup to complete
oc wait --for=condition=complete --timeout=300s job/llm-d-cleanup -n llm-d

# Remove the entire namespace
oc delete namespace llm-d
```

## After Cleanup

After running cleanup, you can redeploy any llm-d overlay:

```bash
# Deploy pd-disaggregation
oc apply -k rig/llm-d/overlays/pd-disaggregation

# Or deploy pd-disaggregation-multinode
oc apply -k rig/llm-d/overlays/pd-disaggregation-multinode

# Or any other overlay...
```

### Verify Deployment

Use the `inference-test` job to verify your deployment is working:

```bash
# Deploy inference test job
oc apply -k rig/llm-d/overlays/inference-test

# Watch test progress
oc logs -n llm-d job/llm-d-inference-test -f
```

See **[overlays/inference-test/README.md](../inference-test/README.md)** for details.

## Troubleshooting

### Resources stuck in terminating state

Some resources may take time to fully terminate (especially with finalizers):

```bash
# Check for stuck resources
oc get all -n llm-d

# Force delete specific resources if needed
oc delete pod <pod-name> -n llm-d --force --grace-period=0
```

### Cleanup job fails

Check the job logs:

```bash
oc logs -n llm-d job/llm-d-cleanup
```

If the job fails, you can manually delete resources:

```bash
# Delete all resources in llm-d namespace
oc delete httproute,inferencepool,gateway,deployment,service,configmap,job,envoyfilter,destinationrule,pod -n llm-d --all
```

## Integration with ArgoCD

If using ArgoCD, the cleanup job has sync wave 100 to ensure it runs after all other resources.

To trigger cleanup via ArgoCD:
1. Deploy the cleanup overlay as an ArgoCD application
2. Monitor the job through ArgoCD UI
3. Delete the ArgoCD application after cleanup completes
