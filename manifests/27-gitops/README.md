# Self-Healing Health Monitor

Automated ArgoCD health monitoring and repair system that runs every 2 minutes to detect and fix common GitOps deployment issues.

## Table of Contents
- [Purpose](#purpose)
- [What It Fixes Automatically](#what-it-fixes-automatically)
- [How It Works](#how-it-works)
- [Usage](#usage)
- [Viewing Logs](#viewing-logs)
- [Resources](#resources)
- [Notes](#notes)

## Purpose

Prevents deployment blockages by automatically detecting and resolving stuck resources, failed syncs, and OLM timing issues without manual intervention.

## What It Fixes Automatically

1. **Stuck ArgoCD Sync Operations** - Clears operations waiting for deleted resources
2. **Stuck ArgoCD Hook Jobs** - Removes finalizers from PreSync/PostSync Jobs in Terminating state
3. **Failed PreSync Hooks** - Retriggers sync for Applications with SyncFailed resources
4. **Applications with Stuck Pods** - Retriggers sync for pods Running but not Ready
5. **Applications Stuck in Deletion** - Removes finalizers from Applications in Terminating state
6. **Stuck Pods in Pending State** - Logs scheduling failure reasons
7. **Stuck OLM Operators (CSVs)** - Deletes CSVs stuck in Pending phase
8. **Broken OLM Subscriptions** - Deletes Subscriptions with deleted InstallPlans
9. **Complete InstallPlans with Missing CSVs** - Forces OLM retry when CSV creation fails

## How It Works

- **CronJob**: Runs every 2 minutes in `openshift-gitops` namespace
- **Proactive**: Detects issues before they block deployments
- **Transparent**: All actions logged in Job output
- **Safe**: Only clears stuck states, doesn't modify application resources

## Usage

Deployed automatically as part of prerequisites:

```bash
oc apply -f rig/baremetal/bootstrap/00-prerequisites.yaml
```

## Viewing Logs

```bash
# See latest health check
oc logs -n openshift-gitops -l job-name=argocd-health-monitor --tail=100

# Watch CronJob schedule
oc get cronjob argocd-health-monitor -n openshift-gitops

# Follow logs in real-time
oc logs -n openshift-gitops -l job-name=argocd-health-monitor -f
```

## Resources

- **CronJob**: `argocd-health-monitor` - Runs every 2 minutes
- **ServiceAccount**: `argocd-health-monitor` - RBAC for cluster access
- **ClusterRole**: Permissions to read/modify ArgoCD Applications and stuck resources

## Notes

- CronJob creates completed Job pods every 2 minutes (this is normal)
- Jobs auto-delete after 1 hour to prevent clutter
- All repairs are logged with detailed reasoning
- Monitor runs independently of ArgoCD sync operations
