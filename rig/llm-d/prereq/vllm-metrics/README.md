# vLLM Metrics Collection

This component enables Prometheus metrics scraping for vLLM model serving pods across all llm-d deployment types.

## Prerequisites

**IMPORTANT**: OpenShift User Workload Monitoring must be enabled for ServiceMonitors in user namespaces to work.

To enable user workload monitoring, run:

```bash
oc patch configmap cluster-monitoring-config -n openshift-monitoring --type merge -p '{"data":{"config.yaml":"enableUserWorkload: true\n"}}'
```

This creates a Prometheus instance in the `openshift-user-workload-monitoring` namespace that discovers and scrapes ServiceMonitors from user namespaces.

Verification:
```bash
# Check that user-workload monitoring pods are running
oc get pods -n openshift-user-workload-monitoring

# You should see:
# - prometheus-operator-*
# - prometheus-user-workload-*
# - thanos-ruler-user-workload-*
```

## Components

- **service.yaml**: Creates a headless Service that selects all pods with `llm-d.ai/inference-serving: "true"` label
- **servicemonitor.yaml**: Configures Prometheus to scrape vLLM metrics from port 8000 at `/metrics`

## Metrics Exposed

vLLM exposes numerous metrics including:

- `vllm:e2e_request_latency_seconds` - End-to-end request latency histogram
- `vllm:time_to_first_token_seconds` - TTFT histogram
- `vllm:inter_token_latency_seconds` - ITL histogram
- `vllm:request_prefill_time_seconds` - Prefill time histogram
- `vllm:request_decode_time_seconds` - Decode time histogram
- `vllm:num_requests_running` - Current number of running requests
- `vllm:num_requests_waiting` - Current number of waiting requests
- `vllm:kv_cache_usage_perc` - KV cache utilization percentage
- `vllm:prompt_tokens_total` - Total prompt tokens processed
- `vllm:generation_tokens_total` - Total generation tokens produced

And many more. See `/metrics` endpoint on any vLLM pod for full list.

## Usage

This component is included as a prereq in overlay kustomizations:

```yaml
resources:
  - ../../prereq/vllm-metrics
```

## Compatibility

Works with all llm-d deployment types that use `llm-d.ai/inference-serving: "true"` label:
- EP (Expert Parallelism)
- PD (Prefill-Decode disaggregation)
- Inference Scheduling
- Other custom layouts

## Installation Steps

1. **Enable User Workload Monitoring** (cluster-admin required, one-time setup):
   ```bash
   oc patch configmap cluster-monitoring-config -n openshift-monitoring --type merge \
     -p '{"data":{"config.yaml":"enableUserWorkload: true\n"}}'
   ```

2. **Deploy vLLM metrics component**:
   ```bash
   oc apply -k rig/llm-d/prereq/vllm-metrics
   ```

3. **Wait for metrics to appear** (30-60 seconds after deployment)

## Verification

Check that metrics are being scraped:

```bash
# Check service endpoints
oc get endpoints -n llm-d vllm-metrics

# Verify ServiceMonitor is discovered
oc get servicemonitor -n llm-d vllm-metrics

# Check Prometheus targets (should show vllm-metrics with health=up)
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -- \
  curl -s http://localhost:9090/api/v1/targets | grep llm-d

# Query vLLM metrics from Thanos
TOKEN=$(cat /run/secrets/kubernetes.io/serviceaccount/token)
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://thanos-querier-openshift-monitoring.apps.<cluster>/api/v1/query?query=vllm:e2e_request_latency_seconds_count"
```
