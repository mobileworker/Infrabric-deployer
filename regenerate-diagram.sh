#!/bin/bash

# Regenerate network topology diagram from existing test results
# This script reads data from the completed test job logs

set -e

CYAN='\033[1;36m'
RESET='\033[0m'

echo -e "${CYAN}=========================================="
echo -e "Network Topology Diagram"
echo -e "==========================================${RESET}"
echo ""

# Get worker pods
WORKER_PODS=$(oc get pods -l app=network-perf-test-worker -o jsonpath='{.items[*].metadata.name}')
PODS=($WORKER_PODS)

if [ ${#PODS[@]} -lt 2 ]; then
  echo "ERROR: Need at least 2 worker pods, found ${#PODS[@]}"
  exit 1
fi

# Get test results from job logs
JOB_LOGS=$(oc logs -n default job/network-perf-test 2>/dev/null || echo "")

if [ -z "$JOB_LOGS" ]; then
  echo "ERROR: Could not read job logs. Make sure network-perf-test job exists."
  exit 1
fi

# Extract TEST_ROWS data from logs (from the results table)
declare -a TEST_ROWS=()
declare -a TCP_ROWS=()

# Strip ANSI color codes from logs
CLEAN_LOGS=$(echo "$JOB_LOGS" | sed 's/\x1b\[[0-9;]*m//g')

# Parse RDMA results - extract only from Network Performance Test Results section
while read -r line; do
  # Parse columns: src tgt src_gpu src_gpu_model tgt_gpu tgt_gpu_model nic size link roce_seq ... roce_par
  read -r src tgt src_gpu1 src_gpu2 tgt_gpu1 tgt_gpu2 nic size link \
    roce_seq roce_seq_iter roce_seq_stat \
    cuda_seq cuda_seq_iter cuda_seq_stat \
    roce_par rest <<< "$line"

  src_gpu="$src_gpu1 $src_gpu2"
  tgt_gpu="$tgt_gpu1 $tgt_gpu2"
  # Strip 'G' suffix from link speed
  link_speed=$(echo "$link" | sed 's/G$//')

  TEST_ROWS+=("$src|$tgt|$src_gpu|$tgt_gpu|$nic|$size|$link_speed|$roce_par")
done < <(echo "$CLEAN_LOGS" | sed -n '/^Network Performance Test Results/,/^Column Descriptions:/p' | grep "^network-perf-test-worker")

# Parse TCP results - extract only from TCP Bandwidth Results section
while read -r line; do
  read -r src tgt nic link tcp_seq tcp_par <<< "$line"
  # Strip 'G' suffix from link speed
  link_speed=$(echo "$link" | sed 's/G$//')
  TCP_ROWS+=("$src|$tgt|$nic|$link_speed|$tcp_par")
done < <(echo "$CLEAN_LOGS" | sed -n '/^TCP Bandwidth Results/,/^Column Descriptions:/p' | grep "^network-perf-test-worker")

SOURCE_POD=${PODS[0]}

for ((i=1; i<${#PODS[@]}; i++)); do
  TARGET_POD="${PODS[$i]}"

  # Get GPU models from TEST_ROWS
  SOURCE_GPU="N/A"
  TARGET_GPU="N/A"
  for row in "${TEST_ROWS[@]}"; do
    IFS='|' read -r src_pod tgt_pod src_gpu tgt_gpu nic size link host_par <<< "$row"
    if [ "$src_pod" = "$SOURCE_POD" ] && [ "$tgt_pod" = "$TARGET_POD" ]; then
      SOURCE_GPU="$src_gpu"
      TARGET_GPU="$tgt_gpu"
      break
    fi
  done

  # Get eth0 IPs
  SOURCE_ETH0=$(oc exec $SOURCE_POD -- bash -c "ip -4 addr show eth0 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" 2>/dev/null | tr -d '\n' | tr -d ' ')
  TARGET_ETH0=$(oc exec $TARGET_POD -- bash -c "ip -4 addr show eth0 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" 2>/dev/null | tr -d '\n' | tr -d ' ')
  [ -z "$SOURCE_ETH0" ] && SOURCE_ETH0="N/A"
  [ -z "$TARGET_ETH0" ] && TARGET_ETH0="N/A"

  # Shorten pod names
  SOURCE_SHORT=$(echo "$SOURCE_POD" | sed 's/network-perf-test-worker-/worker-/')
  TARGET_SHORT=$(echo "$TARGET_POD" | sed 's/network-perf-test-worker-/worker-/')

  # Draw connection box header with more spacing (60 chars between boxes)
  echo "┌──────────────────────────────────────┐                                                            ┌──────────────────────────────────────┐"
  printf "│ %-36s │                                                            │ %-36s │\n" "$SOURCE_SHORT" "$TARGET_SHORT"
  printf "│ GPU: %-31s │                                                            │ GPU: %-31s │\n" "$SOURCE_GPU" "$TARGET_GPU"
  printf "│ eth0: %-30s │                                                            │ eth0: %-30s │\n" "$SOURCE_ETH0" "$TARGET_ETH0"
  echo "├──────────────────────────────────────┤                                                            ├──────────────────────────────────────┤"

  # Draw bandwidth lines for each NIC
  for row in "${TEST_ROWS[@]}"; do
    IFS='|' read -r src_pod tgt_pod src_gpu tgt_gpu nic size link host_par <<< "$row"
    if [ "$src_pod" = "$SOURCE_POD" ] && [ "$tgt_pod" = "$TARGET_POD" ]; then
      # Get IPs
      SRC_IP=$(oc exec $SOURCE_POD -- bash -c "ip -4 addr show $nic 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" 2>/dev/null | tr -d '\n' | tr -d ' ')
      TGT_IP=$(oc exec $TARGET_POD -- bash -c "ip -4 addr show $nic 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" 2>/dev/null | tr -d '\n' | tr -d ' ')

      # Find TCP bandwidth
      TCP_PAR_GBPS="N/A"
      for tcp_row in "${TCP_ROWS[@]}"; do
        IFS='|' read -r tcp_src tcp_tgt tcp_nic tcp_link tcp_par <<< "$tcp_row"
        if [ "$tcp_src" = "$SOURCE_POD" ] && [ "$tcp_tgt" = "$TARGET_POD" ] && [ "$tcp_nic" = "$nic" ]; then
          TCP_PAR_GBPS="$tcp_par"
          break
        fi
      done

      # Format bandwidth label
      BW_LABEL=$(printf "%s Gb/s (RoCE), %s Gb/s (TCP)" "$host_par" "$TCP_PAR_GBPS")

      # Format box content
      LEFT_CONTENT=$(printf "%-4s %-15s (%3sG)" "$nic:" "$SRC_IP" "$link")
      RIGHT_CONTENT=$(printf "%-4s %-15s (%3sG)" "$nic:" "$TGT_IP" "$link")

      # Print with 60 chars spacing
      printf "│ %-36s │──%-54s─>│ %-36s │\n" "$LEFT_CONTENT" "$BW_LABEL" "$RIGHT_CONTENT"
    fi
  done

  echo "└──────────────────────────────────────┘                                                            └──────────────────────────────────────┘"
  echo ""
done

echo "Legend:"
echo "  • Each diagram shows connection from source (left) to target (right)"
echo "  • eth0: Pod management network (CNI)"
echo "  • netX: SR-IOV NICs with link speed in parentheses (e.g., 100G)"
echo "  • Bandwidth: Parallel RoCE and TCP performance (all NICs tested simultaneously)"
echo "  • Source pod: ${SOURCE_POD}"
echo ""
