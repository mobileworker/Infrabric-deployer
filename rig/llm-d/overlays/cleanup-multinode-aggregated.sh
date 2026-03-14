#!/bin/bash
set -e

echo "========================================="
echo "Safe Cleanup: multinode-aggregated"
echo "========================================="
echo ""
echo "This script will DELETE the following resources:"
echo "  - LeaderWorkerSet: wide-aggregated"
echo "  - Gateway: infra-aggregated-gateway"
echo "  - HTTPRoute: wide-aggregated-route"
echo "  - InferencePool: gaie-aggregated"
echo "  - Deployments: gaie-aggregated-epp, infra-aggregated-gateway-istio"
echo "  - Services: gaie-aggregated-epp, gaie-aggregated-ip-*, infra-aggregated-gateway-istio, vllm-metrics, wide-aggregated"
echo "  - ConfigMaps: gaie-aggregated-*, ms-manifests-aggregated, infra-aggregated-gateway"
echo "  - PVCs: wide-aggregated-model-cache"
echo "  - Route: infra-aggregated-gateway"
echo "  - Jobs: wide-aggregated-model-download, deploy-wide-aggregated, install-gaie-aggregated-controller"
echo ""
echo "This script will PRESERVE:"
echo "  - Namespace: llm-d"
echo "  - a-aye-benchmark pod"
echo "  - a-aye-benchmark-ui service & route"
echo "  - a-aye-benchmark-storage PVC (with all test data)"
echo "  - llm-d-client pod"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Starting cleanup..."
echo ""

# Delete LeaderWorkerSet (this will delete the statefulset and pods)
echo "1. Deleting LeaderWorkerSet..."
kubectl delete leaderworkerset wide-aggregated -n llm-d --ignore-not-found=true

# Delete InferencePool
echo "2. Deleting InferencePool..."
kubectl delete inferencepool gaie-aggregated -n llm-d --ignore-not-found=true

# Delete Gateway and HTTPRoute
echo "3. Deleting Gateway and HTTPRoute..."
kubectl delete gateway infra-aggregated-gateway -n llm-d --ignore-not-found=true
kubectl delete httproute wide-aggregated-route -n llm-d --ignore-not-found=true

# Delete Deployments
echo "4. Deleting Deployments..."
kubectl delete deployment gaie-aggregated-epp -n llm-d --ignore-not-found=true
kubectl delete deployment infra-aggregated-gateway-istio -n llm-d --ignore-not-found=true

# Delete Services
echo "5. Deleting Services..."
kubectl delete service gaie-aggregated-epp -n llm-d --ignore-not-found=true
kubectl delete service infra-aggregated-gateway-istio -n llm-d --ignore-not-found=true
kubectl delete service vllm-metrics -n llm-d --ignore-not-found=true
kubectl delete service wide-aggregated -n llm-d --ignore-not-found=true
kubectl delete service -n llm-d -l inferencepool=gaie-aggregated --ignore-not-found=true

# Delete Route
echo "6. Deleting Route..."
kubectl delete route infra-aggregated-gateway -n llm-d --ignore-not-found=true

# Delete ConfigMaps
echo "7. Deleting ConfigMaps..."
kubectl delete configmap gaie-aggregated-manifests -n llm-d --ignore-not-found=true
kubectl delete configmap gaie-aggregated-values -n llm-d --ignore-not-found=true
kubectl delete configmap ms-manifests-aggregated -n llm-d --ignore-not-found=true
kubectl delete configmap infra-aggregated-gateway -n llm-d --ignore-not-found=true

# Delete Jobs
echo "8. Deleting Jobs..."
kubectl delete job wide-aggregated-model-download -n llm-d --ignore-not-found=true
kubectl delete job deploy-wide-aggregated -n llm-d --ignore-not-found=true
kubectl delete job install-gaie-aggregated-controller -n llm-d --ignore-not-found=true

# Delete PVC (WARNING: This deletes the model cache!)
echo "9. Deleting PVC (model cache)..."
read -p "Delete wide-aggregated-model-cache PVC? This will delete downloaded models. (yes/no): " delete_pvc
if [ "$delete_pvc" = "yes" ]; then
    kubectl delete pvc wide-aggregated-model-cache -n llm-d --ignore-not-found=true
    echo "   PVC deleted."
else
    echo "   PVC preserved."
fi

echo ""
echo "========================================="
echo "✅ Cleanup Complete!"
echo "========================================="
echo ""
echo "Remaining resources:"
kubectl get pods,pvc,svc,route -n llm-d | grep -E "a-aye-benchmark|llm-d-client|NAME"

echo ""
echo "You can now deploy pd-disaggregation-multinode:"
echo "  kubectl apply -k /Users/bbenshab/Infrabric-deployer/rig/llm-d/overlays/pd-disaggregation-multinode"
