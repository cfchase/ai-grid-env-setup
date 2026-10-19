#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
h=$HOST
for a in ai-grid-spokes ai-grid-policies; do
  uat "app $a"               "Argo CD app not Synced/Healthy: a Helm render error (an unescaped {{ }}, Step 0) or a sync retry" app $a
  uat "$a keeps ACM/AppSet templates" "a {{ ... }} meant for ACM or an ApplicationSet wasn't wrapped as a Helm raw string (Step 0)" \
    bash -c "helm template x apps/$a/manifests --set gitRepo=r --set gitRef=b | grep -qE '\{\{ *(hub|\.name|index|fromSecret|fromConfigMap)'"
done
for s in $SPOKES; do
  r=$(role_of $s)
  uat "$s labelled $r"        "run bootstrap/40-spoke.sh (stands in for the console's Enroll)" \
    bash -c "kc $h get managedcluster $s -o json | jq -e '.metadata.labels[\"ai-grid/enabled\"]==\"true\" and .metadata.labels[\"ai-grid/role\"]==\"$r\"'"
  uat "$s placed"             "Placement ai-grid-spokes: no ManagedClusterSetBinding 'default' in openshift-gitops, or the cluster isn't in set default" \
    bash -c "kc $h get placementdecisions -n openshift-gitops -l cluster.open-cluster-management.io/placement=ai-grid-spokes -o json | jq -e --arg s $s '[.items[].status.decisions[]?.clusterName] | index(\$s)'"
  uat "$s argo cluster role"  "GitOpsCluster didn't create the cluster Secret, or didn't copy the ai-grid/role label" \
    bash -c "kc $h get secret -n openshift-gitops -l apps.open-cluster-management.io/acm-cluster=true,apps.open-cluster-management.io/cluster-name=$s -o json | jq -e '.items[0].metadata.labels[\"ai-grid/role\"]==\"$r\"'"
  if [[ $PULL_SECRET_MODE == policy ]]; then
    uat "$s pull secret policy" "template error or still inform: kc host get policy ai-grid-policies.rhoai-pull-secret -n $s -o yaml (status.details); fallback: Step 9" pol $s rhoai-pull-secret
  fi
  uat "$s nightly prereqs"    "waits on rhoai-pull-secret being Compliant (Policy dependency)" pol $s rhoai-nightly-prereqs
  uat "$s catalog READY"      "the node can't pull quay.io/rhoai: check the pull secret on the node (verify/01-clusters.sh)" \
    bash -c "kc $s get catalogsource rhoai-catalog-dev -n openshift-marketplace -o jsonpath='{.status.connectionState.lastObservedState}' | grep -qx READY"
  uat "$s platform app"       "Application platform-$s: a chart value error shows under .status.conditions; a missing CRD is retried" app platform-$s
  uat "$s DSC Ready"          "kc $s get datasciencecluster default-dsc -o yaml: the not-Ready component names the cause" \
    bash -c "kc $s get datasciencecluster default-dsc -o jsonpath='{.status.phase}' | grep -qx Ready"
  if [[ $r != inference ]]; then
    uat "$s maas-db policy"   "CNPG Secret maas-db-app missing on the hub (Task 2), or the hub template didn't resolve" \
      bash -c "kc $h get policy maas-db.maas-db -n $s -o jsonpath='{.status.compliant}' | grep -qx Compliant"
    uat "$s tenant-oidc policy" "hub ConfigMap ai-grid-hub-info missing (Task 3), or AITenant not created yet" pol $s tenant-oidc
    uat "$s portal idp policy rendered" "hub Secret portal-idp-$s missing (Task 3, Step 3), or the hub template failed: kc host get policy ai-grid-policies.tenant-portal-idp -n $s -o yaml" \
      bash -c "kc $h get policy ai-grid-policies.tenant-portal-idp -n $s -o jsonpath='{.status.compliant}' | grep -qE '^(Compliant|NonCompliant)$'"
    uat "$s maas-api ready"   "maas-db-config not on the spoke, or the hub database unreachable from it (kc $s logs deploy/maas-api -n redhat-ai-gateway-infra)" \
      kc $s rollout status deploy/maas-api -n redhat-ai-gateway-infra --timeout=5s
    maas=$(maas_url $s)
    uat "$s MaaS health 200"  "maas-default-gateway not Programmed, or its listener hostname differs: kc $s get gateway -n openshift-ingress" \
      bash -c "curl -sk -o /dev/null -w '%{http_code}' $maas/maas-api/health | grep -qx 200"
  else
    uat "$s has no MaaS"      "inference values enabled aigateway" bash -c "! kc $s get deploy maas-api -n redhat-ai-gateway-infra"
  fi
done
summary
