#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
h=$HOST
uat "app grid-enrollment"    "Argo CD app not Synced/Healthy: the OCI chart pull (praxis-charts), or the bootstrap hook" app grid-enrollment
uat "enrollment pod ready"   "image pull from ghcr.io, or the bootstrap Job failed: kc host get jobs -n grid-enrollment, then its log" \
  kc $h rollout status deploy/grid-enrollment -n grid-enrollment --timeout=5s
uat "grid CA issued"         "the CA bootstrap Job failed: kc host get jobs -n grid-enrollment, then its log" \
  bash -c "kc $h get secret grid-ca-bundle -n grid-enrollment && kc $h get secret enrollment-serving-tls -n grid-enrollment -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -issuer | grep -q grid-ca"
uat "hub site identity"      "hubSite.name unset, or namespace grid created after the release" \
  kc $h get secret grid-site-identity -n grid
uat "hub swim key"           "hubSite.swimKeySecretName empty" kc $h get secret grid-swim-key -n grid
uat "enrollment db ready"    "PVC not bound (gp3-csi) or the DB cert missing" \
  bash -c "kc $h get pods -n grid-enrollment -l app.kubernetes.io/component=db -o jsonpath='{.items[0].status.containerStatuses[0].ready}' | grep -qx true"
uat "hub info for spokes"    "bootstrap/50-grid-hub-info.sh not run" \
  bash -c "kc $h get configmap ai-grid-hub-info -n ai-grid-policies -o json | jq -e '.data.hubSiteDigest | length == 64'"
for s in $SPOKES; do
  r=$(role_of $s)
  uat "$s grid operator app" "chart pull from ghcr.io (repository praxis-charts) or a values error" app grid-operator-$s
  uat "$s operator ready"    "no grid-site-identity in $GRID_NS (enrollment, Task 4; invite, Task 11)" \
    kc $s rollout status deploy/grid-operator -n $GRID_NS --timeout=5s
  # A site goes Discovered -> Connecting -> Active only once it has a provider gateway to probe (Task 6).
  kc $s get deploy grid-provider -n $GRID_NS >/dev/null 2>&1 && \
  uat "$s sites Active"      "gossip not converged: kc $s logs deploy/grid-operator -n $GRID_NS" \
    bash -c "! kc $s get gridsites -o jsonpath='{range .items[*]}{.status.phase}{\"\\n\"}{end}' | grep -v Active"
  uat "$s ai-grid-ready"     "DSC not Ready or the grid operator not running on $s (D3)" pol $s ai-grid-ready
done
summary
