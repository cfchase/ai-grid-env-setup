# AI Grid demo environment runbook

## Cluster facts

Recorded by Task 1, Step 5 (read-only, 2026-10-19). Host names stay out of this public repository.

| Cluster | Role | Order | Expires | Control plane | OpenShift | Region | Nodes | Gateway API | Pre-installed operators |
|---|---|---|---|---|---|---|---|---|---|
| hub (`local-cluster`) | ACM hub and its own `combined` spoke | demo.redhat.com "OpenShift Container Platform Cluster (Multi-Cloud)", ready 2026-10-18 | 2026-11-27 | Standard (`HighlyAvailable`) | 4.21.36 | AWS `us-east-2` | 3 × `m6a.4xlarge` control plane (schedulable, worker role), 2 × `m5a.4xlarge` workers, zones a/b/c | v1.3.0 | cert-manager 1.20.1, Red Hat build of Keycloak 26.4.16 |

Run every script with `HOST_KUBECONFIG` pointing at the hub's kubeconfig file, set in the shell, never in git.

## UAT log

| Date | Checkpoint | `make verify` | Pair UAT result | Notes |
|---|---|---|---|---|
