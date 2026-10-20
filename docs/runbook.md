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
| 2026-10-19 | 6. Tenant end to end (Task 7, Steps 1-3) | ALL PASS (06-tenant-e2e) | **Pending** (Chris away) | alice: Keycloak (hub) → MaaS on local-cluster (key minted) → MaaS gateway → grid consumer (TLS) → mTLS → provider → vLLM: 200 with text. dave (org1, no group) refused, but MaaS answers 500 AUTH_FAILURE rather than 403 (upstream bug to report). Portal sign-in (Steps 5-6) not run: enforcing tenant-portal-idp edits the hub's own OAuth and must wait for Chris. |
| 2026-10-19 | 7. Tenant portal sign-in (Task 7, Steps 5-6) | ALL PASS (06-tenant-portal) | **Pending** (Chris away) | D6 as re-decided: alice opens `https://maas.<apps domain>/maas-consumer-portal/`, is sent to hub Keycloak realm ai-grid, signs in (user name, then password), and the portal opens; the cluster's OpenShift login lists only `rhbk`. Policy `tenant-portal` delivers an oauth2-proxy (namespace `aigrid-portal-auth`), two HTTPRoutes on the MaaS gateway, and Authorino policies. The proxy uses the public tenant client `maas-cli` with PKCE, because MaaS accepts one client per tenant. Cross-origin cookie writes are refused (CSRF fix, RED→GREEN). Gaps: maas-api can't name its external URL without a listener host name, so after a `maas-ui` restart the portal's model list answers 503; the portal's Kubernetes-backed calls (user, namespaces) are Unauthorized for Keycloak tokens. |

## Sample model (fixture)

`spokes/models/opt-125m` and `spokes/tenant/` (opt-125m, its ExternalModel and MaaSModelRef, and the
opt-125m-org1 subscription) are a smoke-test fixture for `verify/06-tenant-e2e.sh`. The provider
console replaces them once it deploys models and creates subscriptions; then they're deleted. The
model plumbing (the grid-backend Service, NetworkPolicy allow-grid-provider) stays.

## Known gaps

- **Portal model list** (`/maas-consumer-portal/maas/api/v1/models`): the portal's MaaS module finds
  maas-api's external URL from `/v1/tenants`, which reads the MaaS gateway's listener host name or an
  external status address. Ours has neither (the host stays out of git; the Service is ClusterIP), so
  discovery fails and the module answers 503 "maas-api is not available". Setting the listener host
  name by hand fixes discovery but breaks the Route: its re-encrypt hop doesn't send that SNI, so every
  MaaS call through `maas.<apps domain>` got 503 until it was reverted. A fix needs a decision (host
  name in git or by Policy, plus a passthrough Route and a certificate for that name).
- **Portal Kubernetes-backed calls** (`/api/v1/user`, `/maas/api/v1/namespaces`): the portal's BFFs
  check the forwarded token against the cluster API, which doesn't trust Keycloak tokens, so these
  answer 401 or 500. Making the API trust Keycloak means changing cluster authentication, which D6
  rules out.

## Known overrides of operator-owned objects

- **Authorino Deployment** (`kuadrant-system/authorino`): Policy `authorino-service-ca` adds env `SSL_CERT_DIR` and, through the Authorino CR, a service-CA volume, so Authorino can call maas-api over HTTPS. The authorino operator owns the Deployment. If the Policy's compliance history flips between NonCompliant and Compliant (`kc host get policy ai-grid-policies.authorino-service-ca -n local-cluster -o yaml`, `status.details[].history`), the operator is reverting it.
- **MaaS gateway** (`openshift-ingress`): Policy `maas-route` owns its parameters ConfigMap (ClusterIP Service, serving certificate, and a CA bundle from Policy `maas-gateway-ca` mounted over the proxy's CA file).
