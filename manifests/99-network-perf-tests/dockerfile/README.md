# Network Performance Test Container Image

This directory contains the Dockerfile for building the network performance test container image with CUDA-enabled perftest tools.

## Image Contents

The container image includes:

- **perftest** (RDMA performance testing tools) compiled with CUDA support
  - Enables GPUDirect RDMA testing with `--use_cuda` flag
  - Tests GPU-to-GPU memory transfers over InfiniBand

- **NCCL tests** compiled for all NVIDIA GPU architectures (sm_70-sm_90)
  - Volta (V100, Titan V)
  - Turing (T4, RTX 2080 Ti)
  - Ampere (A100, A30, A10, RTX 3090)
  - Ada Lovelace (L40, RTX 4090)
  - Hopper (H100, H200)

- **InfiniBand/RDMA tools**
  - infiniband-diags
  - ibv_devices
  - Standard RDMA libraries

- **Analysis tools**
  - Python with pandas, matplotlib, seaborn
  - jq, bc, numactl, pciutils

## Build Instructions

### Prerequisites

- Access to a build host with:
  - podman or docker
  - Sufficient disk space (~15GB for layers)
  - Network access to pull base images

### Building the Image

1. Navigate to the dockerfile directory:
   ```bash
   cd manifests/99-network-perf-tests/dockerfile
   ```

2. Build the image with TMPDIR set (if /tmp has limited space):
   ```bash
   export TMPDIR=/path/to/large/tmp
   podman build -t quay.io/bbenshab/perf-test:universal -f Dockerfile .
   ```

   Or with default /tmp:
   ```bash
   podman build -t quay.io/bbenshab/perf-test:universal -f Dockerfile .
   ```

3. Push the image to the registry:
   ```bash
   podman push quay.io/bbenshab/perf-test:universal
   ```

### Build Commands Used

The following commands were used to build and push the current image:

```bash
# On remote build host (n42-h01-b05-mx750c.rdu3.labs.perfscale.redhat.com)
cd /mnt/data/nccl-perf-test

# Build with large TMPDIR to avoid space issues
TMPDIR=/mnt/data/nccl-perf-test/tmp podman build \
  -t quay.io/bbenshab/perf-test:universal \
  -f Dockerfile .

# Push to quay.io
podman push quay.io/bbenshab/perf-test:universal
```

## Dockerfile Structure

The Dockerfile uses a multi-stage build:

### Stage 1: Build perftest with CUDA support
- Base: `nvcr.io/nvidia/cuda:12.3.1-devel-ubuntu22.04`
- Installs RDMA development libraries
- Clones perftest from GitHub
- Compiles with `--enable-cudart` flag to enable CUDA support

### Stage 2: Final image
- Base: `nvcr.io/nvidia/pytorch:24.01-py3`
- Copies perftest binaries from stage 1
- Installs RDMA runtime libraries
- Builds NCCL tests for all GPU architectures
- Adds GPU/network detection scripts

## Testing CUDA Support

To verify the image has CUDA support:

```bash
# Run a pod with the image
oc run test-perf --image=quay.io/bbenshab/perf-test:universal --rm -it -- /bin/bash

# Inside the pod, check for CUDA flags
ib_write_bw --help | grep cuda

# Expected output should show:
#   --use_cuda=<cuda device id>
#   --cuda_mem_type=<value>
#   etc.
```

## GPUDirect RDMA Testing

The CUDA-enabled perftest allows testing GPU-to-GPU transfers over InfiniBand:

```bash
# On server node
ib_write_bw --use_cuda=0 -d mlx5_0 -s 1048576 -D 20

# On client node
ib_write_bw --use_cuda=0 -d mlx5_0 -s 1048576 -D 20 <server-ip>
```

Flags:
- `--use_cuda=0`: Use GPU device 0
- `-d mlx5_0`: Use RDMA device mlx5_0
- `-s 1048576`: Message size 1MB
- `-D 20`: Test duration 20 seconds

## Image Registry

- **Registry**: quay.io
- **Repository**: bbenshab/perf-test
- **Tag**: universal
- **Full path**: `quay.io/bbenshab/perf-test:universal`

## Troubleshooting

### Build fails with "No space left on device"

Set TMPDIR to a location with more space:
```bash
export TMPDIR=/path/to/large/tmp
mkdir -p $TMPDIR
podman build ...
```

### CUDA tests fail with "GPU not found"

Ensure the pod has GPU resources requested:
```yaml
resources:
  limits:
    nvidia.com/gpu: 1
```

### perftest shows "flag not supported"

Verify you're using the correct flag syntax:
- Correct: `--use_cuda=0`
- Incorrect: `--use_cuda` (missing device ID)
- Incorrect: `--use_cudart` (wrong flag name)
