# Stage 1: Build perftest with CUDA support
FROM nvcr.io/nvidia/cuda:12.3.1-devel-ubuntu22.04 AS perftest-builder

RUN apt-get update && apt-get install -y \
    git \
    make \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libibverbs-dev \
    librdmacm-dev \
    libibumad-dev \
    libpci-dev \
    rdma-core \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/linux-rdma/perftest.git /tmp/perftest \
    && cd /tmp/perftest \
    && ./autogen.sh \
    && CUDA_H_PATH=/usr/local/cuda/include ./configure --prefix=/usr --enable-cudart \
    && make -j$(nproc) \
    && make install DESTDIR=/perftest-install

# Stage 2: Build GDRCopy user-space tools (no kernel module)
FROM nvcr.io/nvidia/cuda:12.3.1-devel-ubuntu22.04 AS gdrcopy-builder

RUN apt-get update && apt-get install -y \
    git \
    make \
    build-essential \
    check \
    libsubunit-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/NVIDIA/gdrcopy.git /tmp/gdrcopy \
    && cd /tmp/gdrcopy \
    && make PREFIX=/usr lib exes \
    && make PREFIX=/usr DESTDIR=/gdrcopy-install install

# Stage 3: Final image
FROM nvcr.io/nvidia/pytorch:24.01-py3

# Install RDMA libraries (runtime only, not dev)
RUN apt-get update && apt-get install -y \
    infiniband-diags \
    libibverbs1 \
    librdmacm1 \
    libibumad3 \
    libpci3 \
    rdma-core \
    iproute2 \
    iputils-ping \
    net-tools \
    ethtool \
    jq \
    bc \
    numactl \
    pciutils \
    vim \
    htop \
    curl \
    wget \
    check \
    iperf3 \
    && rm -rf /var/lib/apt/lists/*

# Copy perftest binaries from builder
COPY --from=perftest-builder /perftest-install/usr/bin/* /usr/bin/

# Remove old GDRCopy library from base image (version 2.3) to avoid conflicts
RUN rm -f /usr/lib/x86_64-linux-gnu/libgdrapi*

# Copy GDRCopy libraries and binaries from builder (version 2.5)
COPY --from=gdrcopy-builder /gdrcopy-install/usr/local/lib/* /usr/local/lib/
COPY --from=gdrcopy-builder /gdrcopy-install/usr/local/bin/* /usr/local/bin/

# Update library cache to include new GDRCopy library
RUN ldconfig

# Install Python packages for data analysis
RUN pip install --no-cache-dir \
    pandas \
    matplotlib \
    seaborn

# Build NCCL tests for ALL NVIDIA GPU architectures
RUN git clone https://github.com/NVIDIA/nccl-tests.git /opt/nccl-tests \
    && cd /opt/nccl-tests \
    && make MPI=0 CUDA_HOME=/usr/local/cuda NCCL_HOME=/usr/local/cuda \
         NVCC_GENCODE="\
         -gencode=arch=compute_70,code=sm_70 \
         -gencode=arch=compute_75,code=sm_75 \
         -gencode=arch=compute_80,code=sm_80 \
         -gencode=arch=compute_86,code=sm_86 \
         -gencode=arch=compute_89,code=sm_89 \
         -gencode=arch=compute_90,code=sm_90" \
    && rm -rf .git \
    && chmod +x build/*_perf

# Create GPU detection script
RUN printf '#!/bin/bash\n\
# GPU Detection Script\n\
\n\
echo "========================================="\n\
echo "GPU Detection"\n\
echo "========================================="\n\
\n\
if command -v nvidia-smi &> /dev/null; then\n\
    echo ""\n\
    echo "NVIDIA GPUs detected via nvidia-smi:"\n\
    nvidia-smi --query-gpu=gpu_name,compute_cap,memory.total --format=csv,noheader,nounits\n\
    echo ""\n\
\n\
    GPU_NAME=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | head -1)\n\
    COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1)\n\
    MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)\n\
    GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)\n\
\n\
    echo "Primary GPU: $GPU_NAME"\n\
    echo "Compute Capability: $COMPUTE_CAP"\n\
    echo "Memory: ${MEMORY} MiB"\n\
    echo "Total GPUs: $GPU_COUNT"\n\
fi\n\
\n\
echo ""\n\
echo "GPU details via lspci:"\n\
lspci | grep -i nvidia | grep -i "3D controller\\|VGA"\n\
\n\
echo ""\n\
echo "========================================="\n\
echo "RDMA/InfiniBand Devices"\n\
echo "========================================="\n\
if command -v ibv_devices &> /dev/null; then\n\
    ibv_devices\n\
else\n\
    echo "No RDMA tools found"\n\
fi\n\
\n\
echo ""\n\
echo "========================================="\n\
echo "perftest CUDA Support"\n\
echo "========================================="\n\
if ldd /usr/bin/ib_write_bw 2>&1 | grep -q cudart; then\n\
    echo "✓ ib_write_bw supports --use_cuda flag for GPUDirect testing"\n\
else\n\
    echo "✗ ib_write_bw does not support CUDA"\n\
fi\n\
\n\
echo ""\n\
echo "========================================="\n\
echo "GDRCopy Tools"\n\
echo "========================================="\n\
if command -v copybw &> /dev/null; then\n\
    echo "✓ copybw found (GDRCopy bandwidth test)"\n\
else\n\
    echo "✗ copybw not found"\n\
fi\n\
\n\
if command -v copylat &> /dev/null; then\n\
    echo "✓ copylat found (GDRCopy latency test)"\n\
else\n\
    echo "✗ copylat not found"\n\
fi\n\
\n\
echo ""\n\
echo "========================================="\n\
echo "Network Interfaces"\n\
echo "========================================="\n\
ip -br addr show\n\
\n\
echo "========================================="\n\
' > /usr/local/bin/detect-gpu.sh \
    && chmod +x /usr/local/bin/detect-gpu.sh

RUN mkdir -p /results

WORKDIR /opt/nccl-tests

CMD ["/bin/bash", "-c", "/usr/local/bin/detect-gpu.sh && echo 'Worker ready, waiting for test coordinator...' && sleep infinity"]
