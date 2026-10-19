# AI Grid demo environment runbook

## Cluster facts

Recorded by Task 1, Step 5 (read-only, 2026-10-19). Host names stay out of this public repository.

| Cluster | Role | Order | Expires | Control plane | OpenShift | Region | Nodes | Gateway API | Pre-installed operators |
|---|---|---|---|---|---|---|---|---|---|
| hub (`local-cluster`) | ACM hub and its own `combined` spoke | demo.redhat.com "OpenShift Container Platform Cluster (Multi-Cloud)", ready 2026-10-18 | 2026-11-27 | Standard (`HighlyAvailable`) | 4.21.36 | AWS `us-east-2` | 3 × `m6a.4xlarge` control plane (schedulable, worker role), 2 × `m5a.4xlarge` workers, zones a/b/c | v1.3.0 | cert-manager 1.20.1, Red Hat build of Keycloak 26.4.16 |

Run every script with `HOST_KUBECONFIG` pointing at the hub's kubeconfig file, set in the shell, never in git.

## Access

Who can use the hub is per environment, so it isn't in git. `bootstrap/00-gitops.sh` makes the
person who runs it an Argo CD admin (OpenShift group `cluster-admins`, which Argo CD maps to
`role:admin`). To give someone else access, once they can log in to the cluster:

```bash
oc adm groups add-users cluster-admins <user>                           # Argo CD admin
oc adm policy add-cluster-role-to-user cluster-admin <user>              # cluster-admin, if needed
```

Remove them with `oc adm groups remove-users cluster-admins <user>` and
`oc adm policy remove-cluster-role-from-user cluster-admin <user>`.

## UAT log

| Date | Checkpoint | `make verify` | Pair UAT result | Notes |
|---|---|---|---|---|
| 2026-10-19 | 1. Hub platform (Task 2) | ALL PASS | Passed with Chris. Fixed during UAT: Argo CD showed nothing (deployer not in group `cluster-admins`); the hub moved to Argo CD apps (`apps/*`); access kept out of git. Database kept on CloudNativePG (persistent 20Gi gp3; no backups, no `Delete=false` guard, by choice). | Console perspective is "Fleet management" in ACM 2.17; CloudNativePG pods show under Pods, not Workloads. |
| 2026-10-19 | 2. Keycloak (Task 3) | ALL PASS | **Pending** (Chris away; built autonomously) | Realm ai-grid: org1/org2, alice/dave/bob, maas orgs claim verified in tokens; own CloudNativePG database; Route maas-keycloak (demo Keycloak untouched). |
| 2026-10-19 | 3. Grid enrollment (Task 4) | ALL PASS | **Pending** (Chris away) | grid-enrollment 0.2.0 on the hub; hub site local-cluster via hubSite; no Route until a remote spoke (D8); bootstrap hook reruns on every sync and keeps the CA (verified). |
| 2026-10-19 | 4. Spoke delivery (Task 5) | ALL PASS | **Pending** (Chris away) | Labelling local-cluster provisioned it through ACM: Placements, GitOpsCluster, Policies (pull secret, nightly catalog, maas-db, tenant OIDC, maas-route, ai-grid-ready Compliant), OpenShift AI 3.6 DSC Ready in ~20 min, MaaS health 200 at maas.<apps domain>, grid operator running. Pull-secret path: ACM Policy (D4), after fixing ACM auto-encryption of hub fromSecret. |
| 2026-10-19 | 5. Models and tenant intent (Task 6) | ALL PASS | **Pending** (Chris away) | opt-125m Ready on local-cluster (with a minimal chat template); grid path consumer → mTLS → provider → model returns 200 for chat; MaaS ExternalProvider/ExternalModel/MaaSModelRef Ready, org1-group1 subscription and auth policy Active. One InferenceProvider (ours). PR 966: downstream rhoai-3.6 has diverged from the merge and the installed controller has no InferenceProvider rights, so the nightly doesn't publish providers (as expected). |
