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

# Deploy
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

Each environment directory should contain:

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

## Support

For issues or questions about specific environments:
- **Baremetal:** See [main README](../README.md)
- **Other platforms:** Coming soon
