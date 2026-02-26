# LeaderWorkerSet Controller

This prerequisite installs the LeaderWorkerSet Custom Resource Definition (CRD) and controller.

## Overview

**LeaderWorkerSet** is a Kubernetes API for deploying coordinated groups of pods with a designated leader pod. It's essential for multi-pod vLLM deployments that require:
- Coordinated startup and shutdown
- Leader-worker communication patterns
- Multi-node Expert Parallelism (EP)
- Data Parallel configurations

## Installation

```bash
# Deploy LeaderWorkerSet controller
oc apply -k rig/llm-d/prereq/leaderworkerset-controller

# Monitor installation
oc logs -f job/install-leaderworkerset -n llm-d

# Verify CRD installation
oc get crd leaderworkersets.leaderworkerset.x-k8s.io

# Verify controller is running
oc get pods -n lws-system
```

## What Gets Installed

- **LeaderWorkerSet CRD** (`leaderworkersets.leaderworkerset.x-k8s.io`)
- **LeaderWorkerSet Controller** (deployed in `lws-system` namespace)
- **RBAC resources** for the controller

## Version

- **LeaderWorkerSet**: v0.3.1

## Dependencies

None - this can be installed independently.

## Used By

All llm-d deployment scenarios use LeaderWorkerSet:
- `inference-scheduling` - Single-pod LeaderWorkerSets for replica management
- `pd-disaggregation` - Coordinated prefill and decode pods
- `pd-disaggregation-multinode` - Multi-node P/D with RDMA communication
- `wide-ep-multinode` - Expert Parallelism with leader-worker coordination

## Cleanup

The LeaderWorkerSet controller is cluster-scoped and should be left installed for all llm-d deployments.

To remove (if needed):
```bash
# Delete the LeaderWorkerSet installation
LWS_VERSION="v0.3.1"
kubectl delete -f "https://github.com/kubernetes-sigs/lws/releases/download/${LWS_VERSION}/manifests.yaml"
```

## References

- [LeaderWorkerSet GitHub](https://github.com/kubernetes-sigs/lws)
- [LeaderWorkerSet Documentation](https://github.com/kubernetes-sigs/lws/tree/main/docs)
