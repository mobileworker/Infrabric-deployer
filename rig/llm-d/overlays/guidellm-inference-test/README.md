# llm-d Inference Test Overlay

Automated inference testing overlay that dynamically discovers the deployed gateway and runs a guidellm benchmark test.

## Purpose

This overlay provides automated validation of llm-d deployments by:
- **Automatically discovering** the gateway service (no hardcoded URLs)
- **Detecting the model** name from deployed resources
- **Running guidellm benchmarks** with real inference requests
- **Reporting performance metrics** (latency, throughput, success rate)

## What It Tests

The inference test validates:
- ✅ Gateway accessibility and routing
- ✅ Model server responsiveness
- ✅ End-to-end inference pipeline
- ✅ Request latency and throughput
- ✅ API compatibility (OpenAI-compatible endpoints)

## When to Use

Run this overlay to:
1. **Validate new deployments** - Ensure everything is working after deployment
2. **Test after updates** - Verify functionality after configuration changes
3. **Performance baseline** - Establish latency/throughput benchmarks
4. **CI/CD integration** - Automated testing in deployment pipelines
5. **Troubleshooting** - Quick sanity check when issues arise

## Usage

### Run the Test

```bash
# Deploy the inference test job
oc apply -k rig/llm-d/overlays/guidellm-inference-test

# Watch test progress
oc logs -n llm-d job/llm-d-inference-test -f

# Check test status
oc get job llm-d-inference-test -n llm-d
```

### Expected Output

```
=========================================
llm-d Inference Test with guidellm
=========================================
Start time: 2026-02-26 08:00:00 UTC

📦 Installing dependencies...
✅ Dependencies installed

=========================================
Step 1: Discovering Gateway Service
=========================================
✅ Found gateway service: infra-pd-inference-gateway-istio
   Gateway URL: http://infra-pd-inference-gateway-istio.llm-d.svc.cluster.local:80

=========================================
Step 2: Discovering Model Name
=========================================
   ✅ Detected model: RedHatAI/Meta-Llama-3.1-8B-FP8

=========================================
Step 3: Installing guidellm
=========================================
✅ guidellm installed

=========================================
Step 4: Running Inference Benchmark
=========================================

Configuration:
  - Gateway: http://infra-pd-inference-gateway-istio.llm-d.svc.cluster.local:80
  - Model: RedHatAI/Meta-Llama-3.1-8B-FP8
  - Test type: Short benchmark (10 requests)
  - Max tokens: 50

Running 10 inference requests...
============================================================
✓ Request 1/10: 2.34s, 56 tokens, 23.9 tok/s
✓ Request 2/10: 1.89s, 52 tokens, 27.5 tok/s
✓ Request 3/10: 2.12s, 58 tokens, 27.4 tok/s
✓ Request 4/10: 1.95s, 54 tokens, 27.7 tok/s
✓ Request 5/10: 2.01s, 55 tokens, 27.4 tok/s
✓ Request 6/10: 2.08s, 57 tokens, 27.4 tok/s
✓ Request 7/10: 1.92s, 53 tokens, 27.6 tok/s
✓ Request 8/10: 2.15s, 59 tokens, 27.4 tok/s
✓ Request 9/10: 1.88s, 51 tokens, 27.1 tok/s
✓ Request 10/10: 2.03s, 56 tokens, 27.6 tok/s
============================================================

Benchmark Results:
  Successful requests: 10/10
  Failed requests: 0/10
  Total tokens: 551
  Total time: 20.37s
  Average latency: 2.04s/request
  Average throughput: 27.0 tokens/s

=========================================
✅ Inference Test PASSED
=========================================
End time: 2026-02-26 08:00:45 UTC
```

## Test Parameters

The test runs:
- **10 inference requests** with diverse prompts
- **50 max tokens** per request
- **Temperature: 0.7** for varied responses
- **Success threshold: 80%** (8/10 requests must succeed)

## Gateway Discovery

The job automatically discovers the gateway using:

1. **Pattern matching** - Looks for services with names like:
   - `*gateway-istio*`
   - `*inference-gateway*`
   - `*gateway*`

2. **Gateway API resources** - Finds Gateway resources and their services

3. **Fallback** - Uses `llm-d-inference` service if found

## Model Discovery

The job automatically detects the model name:

1. **Pod annotations** - Checks `inference.lanl.gov/model-name`
2. **API query** - Calls `/v1/models` endpoint
3. **Fallback** - Uses `RedHatAI/Meta-Llama-3.1-8B-FP8`

## Success Criteria

The test **PASSES** if:
- ✅ Gateway service is discovered
- ✅ At least 8/10 requests succeed (80% success rate)
- ✅ Responses are valid completions

The test **FAILS** if:
- ❌ Gateway service not found
- ❌ Less than 8 requests succeed
- ❌ API incompatibility errors

## Cleanup

```bash
# Delete the test job after completion
oc delete job llm-d-inference-test -n llm-d

# Or let TTL clean up automatically (1 hour after completion)
```

## Integration with Other Overlays

This overlay works with **any** llm-d deployment:

```bash
# Deploy P/D disaggregation
oc apply -k rig/llm-d/overlays/pd-disaggregation

# Wait for deployment to be ready
oc wait --for=condition=available deployment/pd-prefill -n llm-d --timeout=5m

# Run inference test
oc apply -k rig/llm-d/overlays/guidellm-inference-test

# Monitor results
oc logs -n llm-d job/llm-d-inference-test -f
```

## ArgoCD Integration

When deployed via ArgoCD:
- **Sync Wave: 50** - Runs after all deployment overlays
- **Hook: Sync** - Executes during ArgoCD sync
- **Delete Policy: BeforeHookCreation** - Recreates on each sync

## Troubleshooting

### Gateway Not Found

```bash
# List all services to find the gateway
oc get svc -n llm-d

# Check Gateway API resources
oc get gateway -n llm-d
oc get httproute -n llm-d
```

### Requests Failing

```bash
# Check if pods are ready
oc get pods -n llm-d

# Test direct connectivity to gateway
oc run test -n llm-d --rm -it --image=curlimages/curl -- curl http://<gateway-service>:80/v1/models
```

### Python/pip Issues

```bash
# Check job logs for detailed errors
oc logs -n llm-d job/llm-d-inference-test

# Describe the job for resource/permission issues
oc describe job llm-d-inference-test -n llm-d
```

## Customization

### Modify Test Parameters

Edit `inference-test-job.yaml` to change:

```yaml
# Number of requests (default: 10)
prompts = [...] # Add/remove prompts

# Max tokens per request (default: 50)
max_tokens=50

# Temperature (default: 0.7)
temperature=0.7

# Success threshold (default: 8/10)
exit(0 if success_count >= 8 else 1)
```

### Add Custom Prompts

```yaml
# In the Python script section
prompts = [
    "Your custom prompt 1",
    "Your custom prompt 2",
    # ... add more
]
```

## Performance Benchmarking

For detailed performance testing, consider:
- Increasing request count (100+)
- Adding concurrent requests
- Testing different prompt lengths
- Measuring P99 latency

## CI/CD Example

```yaml
# .gitlab-ci.yml or similar
test-inference:
  stage: test
  script:
    - oc apply -k rig/llm-d/overlays/pd-disaggregation
    - oc wait --for=condition=available deployment/pd-prefill -n llm-d --timeout=10m
    - oc apply -k rig/llm-d/overlays/guidellm-inference-test
    - oc wait --for=condition=complete job/llm-d-inference-test -n llm-d --timeout=5m
    - oc logs job/llm-d-inference-test -n llm-d
```

## Notes

- Test runs as a **Kubernetes Job** (one-time execution)
- Uses **llm-d-client** service account (same RBAC as client-tools)
- Automatically cleans up after **1 hour** (ttlSecondsAfterFinished)
- **Lightweight** - No persistent storage required
- **Fast** - Completes in ~1 minute for 10 requests

## Related Documentation

- [Client Tools Prereq](../../prereq/client-tools/README.md)
- [Gateway Provider](../../prereq/gateway-provider/README.md)
- [P/D Disaggregation](../pd-disaggregation/README.md)
- [guidellm Documentation](https://github.com/neuralmagic/guidellm)
