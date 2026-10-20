#!/usr/bin/env bash
# Stops delivery and leaves what it installed: every Application here has no resources finalizer and
# every ApplicationSet preserves resources on deletion, and ACM Policies don't prune what they
# created. local-cluster's OpenShift AI, the grid and the hub services (ACM, Keycloak, enrollment,
# maas-db) stay running; demo.redhat.com deletes the clusters themselves.
source "$(dirname "$0")/lib.sh"
for s in $SPOKES; do kc $HOST label managedcluster $s "$LABEL_ENABLED-" "$LABEL_ROLE-" >/dev/null 2>&1 || true; done
# First the root ApplicationSet, so Argo CD can't recreate the delivery Applications.
kc $HOST delete applicationset apps -n openshift-gitops --ignore-not-found
# Then what the two delivery apps (ai-grid-spokes, ai-grid-policies) created, found by Argo CD's
# tracking annotation, then the apps themselves.
owned_by() { # <app> <namespace> <kinds>
  kc $HOST get "$3" -n "$2" -o json | jq -r --arg a "$1:" \
    '.items[] | select((.metadata.annotations["argocd.argoproj.io/tracking-id"] // "") | startswith($a)) | "\(.kind)/\(.metadata.name)"'
}
for app in ai-grid-spokes ai-grid-policies; do
  for ns in openshift-gitops ai-grid-policies maas-db; do
    kc $HOST get ns $ns >/dev/null 2>&1 || continue
    for o in $(owned_by $app $ns applicationsets.argoproj.io,gitopsclusters.apps.open-cluster-management.io,policies.policy.open-cluster-management.io,placementbindings.policy.open-cluster-management.io,placements.cluster.open-cluster-management.io,managedclustersetbindings.cluster.open-cluster-management.io); do
      kc $HOST delete -n $ns "$o" --ignore-not-found
    done
  done
  kc $HOST delete applications.argoproj.io $app -n openshift-gitops --ignore-not-found
done
for s in $SITES; do kc $HOST delete managedcluster $s --ignore-not-found; done
log "delivery stopped; installed software stays. Rebuild: make all"
