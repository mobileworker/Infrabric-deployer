# Operator Readiness Health Check (Wave 25)

This wave ensures that operators deployed in wave 20 are fully ready before proceeding with configuration in wave 28+.

## Purpose

Prevents deployment issues by:
- Waiting for NVIDIA Network Operator CSV to reach "Succeeded" state
- Verifying operator controller-manager deployment is ready
- Detecting OLM issues early (missing CSV, failed CSV, duplicate OperatorGroups)
- Providing clear failure messages for troubleshooting

## Job: wait-for-network-operator-ready

**Timeout**: 30 minutes
**Interval**: 10 seconds

Checks:
1. Subscription exists and has valid state
2. CSV is assigned to subscription
3. CSV phase is "Succeeded" (not Pending or Failed)
4. Operator deployment has ready replicas

**Failure modes**:
- CSV in "Failed" state → Exit with error and debugging info
- Timeout after 30 minutes → Exit with full subscription/CSV/OperatorGroup status

## Why Wave 25?

- Wave 20: Operators installed (subscriptions created)
- **Wave 25: Health check ensures operators are ready** ← This wave
- Wave 26: VF configuration (depends on nodes being ready)
- Wave 27: MCP wait (waits for VF config to apply)
- Wave 28: Network operator configuration (requires operator to be running)

This prevents wave 28 from running the discover-ofed-version job before the operator exists.
