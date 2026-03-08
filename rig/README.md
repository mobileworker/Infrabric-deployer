# Deployment Environments

This directory contains environment-specific configurations for deploying InfraBrig Deployer across different platforms.

## Available Environments

### Baremetal (OpenShift)
**Status:** ✅ Production Ready

Automated deployment for baremetal OpenShift clusters with NVIDIA GPUs and RDMA/InfiniBand networking.

**Quick Start:**
```bash
# Customize your environment
vi rig/baremetal/infra-operators-values.yaml

# Deploy infrastructure
oc apply -k rig/baremetal/bootstrap
```

**Features:**
- Fully automated deployment with self-healing
- Universal GPU support (V100, A100, H100, H200)
- RoCE/RDMA auto-discovery and SR-IOV automation
- Network performance testing
- Cluster cleanup utilities

**Documentation:** See main [README.md](../README.md) and [rig/baremetal/bootstrap/README.md](baremetal/bootstrap/README.md)

---

### LLM-d (Distributed LLM Inference)
**Status:** ✅ Production Ready

Automated deployment of distributed LLM inference workloads on GPU clusters with RDMA support.

**Quick Start:**
```bash
# Deploy P/D disaggregation (single-node)
oc apply -k rig/llm-d/overlays/pd-disaggregation

# Deploy P/D disaggregation (multi-node)
oc apply -k rig/llm-d/overlays/pd-disaggregation-multinode

# Deploy inference scheduling
oc apply -k rig/llm-d/overlays/inference-scheduling

# Deploy EP for MoE models
oc apply -k rig/llm-d/overlays/ep-multinode
```

**Features:**
- 5 deployment scenarios (inference scheduling, P/D disaggregation, EP for MoE models, DeepEP testing)
- Configurable models - use any vLLM-compatible model
- Gateway API integration with intelligent request routing
- Dynamic GPU and RDMA resource discovery
- Automated inference testing with guidellm
- Single-command cleanup overlay

**Documentation:** See [rig/llm-d/README.md](llm-d/README.md) and [rig/llm-d/QUICK-START.md](llm-d/QUICK-START.md)

---

### AWS
**Status:** 🚧 Coming Soon

GPU cluster deployment for AWS EKS with NVIDIA GPUs.

---

### IBM Cloud
**Status:** 🚧 Coming Soon

GPU cluster deployment for IBM Cloud with NVIDIA GPUs.

---

## Creating a New Environment

To add a new deployment environment:

1. Create a new directory: `rig/<environment>/`
2. Copy the baremetal structure as a template
3. Customize for your platform:
   - Update `bootstrap/root-app.yaml` to point to `rig/<environment>`
   - Modify `infra-operators-values.yaml` for platform-specific operators
   - Adjust app manifests in `apps/` as needed
4. Add platform-specific documentation

## Structure

### Infrastructure Environments

Each infrastructure environment directory contains:

```
rig/<environment>/
├── bootstrap/                 # ArgoCD bootstrap resources
│   ├── root-app.yaml         # Root ArgoCD Application
│   ├── namespace.yaml        # Target namespace
│   └── README.md             # Environment-specific docs
├── infra-operators-values.yaml # Operator configuration
├── kustomization.yaml        # Kustomize overlay
└── namespace.yaml            # Namespace definition
```

### Workload Environments

Workload deployments (like llm-d) contain:

```
rig/<workload>/
├── prereq/                    # Prerequisites (client-tools, gateway-provider, etc.)
├── overlays/                  # Deployment scenarios
│   ├── <scenario-1>/          # Scenario-specific overlay
│   ├── <scenario-2>/          # Another scenario
│   ├── cleanup/               # Cleanup overlay
│   └── guidellm-inference-test/  # Testing overlay
├── README.md                  # Main documentation
└── QUICK-START.md            # Quick start guide
```

## Support

For issues or questions about specific environments:
- **Baremetal:** See [main README](../README.md)
- **Other platforms:** Coming soon
