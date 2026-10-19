#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
h=$HOST
console=$(kc $h get route console -n openshift-console -o jsonpath='{.spec.host}' 2>/dev/null)
uat "gitops ready"         "GitOps operator not installed: kc host get csv -n openshift-gitops-operator" \
  kc $h get argocd openshift-gitops -n openshift-gitops
uat "root ApplicationSet"  "bootstrap/00-gitops.sh not run: the root ApplicationSet apps creates one app per apps/*/application.yaml" \
  kc $h get applicationset apps -n openshift-gitops
for a in gitops-config acm maas-db ai-grid-policies; do
  uat "app $a"            "Argo CD app not Synced/Healthy: open it in the Argo CD UI, or kc host get application $a -n openshift-gitops -o yaml" app $a
done
uat "argo cluster-admin"   "bootstrap/00-gitops.sh didn't apply bootstrap/gitops-admin.yaml" \
  bash -c "kc $h auth can-i '*' '*' --all-namespaces --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller | grep -qx yes"
uat "argo admin group"   "group cluster-admins lacks the users in apps/gitops-config/manifests/group.yaml: Argo CD shows nothing to them" \
  bash -c "for u in \$(yq '.users[]' apps/gitops-config/manifests/group.yaml); do kc $h get group cluster-admins -o json | jq -e --arg u \"\$u\" '.users | index(\$u)' >/dev/null || exit 1; done"
uat "praxis OCI repo"      "Argo CD app gitops-config didn't create Secret praxis-charts" kc $h get secret praxis-charts -n openshift-gitops
uat "ACM running"          "MultiClusterHub still installing (about 15 minutes), or short of CPU: kc host get mch -n open-cluster-management -o yaml" \
  bash -c "kc $h get multiclusterhub multiclusterhub -n open-cluster-management -o jsonpath='{.status.phase}' | grep -qx Running"
uat "ACM console answers"  "the acm console plugin isn't enabled: kc host get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}'" \
  bash -c "kc $h get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}' | grep -q '\"acm\"' && curl -sk -o /dev/null -w '%{http_code}' https://$console/ | grep -qE '^(200|302)$'"
uat "local-cluster Available" "the hub's self-import didn't finish: kc host get managedcluster local-cluster -o yaml" \
  bash -c "kc $h get managedcluster local-cluster -o jsonpath='{.status.conditions[?(@.type==\"ManagedClusterConditionAvailable\")].status}' | grep -qx True"
uat "MWRS feature gate"    "the ACM operator reset ClusterManager; rerun bootstrap/21-acm-feature-gates.sh" \
  bash -c "kc $h get clustermanager cluster-manager -o json | jq -e '.spec.workConfiguration.featureGates[] | select(.feature==\"ManifestWorkReplicaSet\" and .mode==\"Enable\")'"
uat "maas-db healthy"      "Argo CD app maas-db not synced, the CNPG operator (certified-operators) not installed, or the PVC not bound" \
  bash -c "kc $h get cluster.postgresql.cnpg.io maas-db -n maas-db -o jsonpath='{.status.phase}' | grep -qx 'Cluster in healthy state'"
uat "maas-db app secret"   "CNPG didn't bootstrap the database" kc $h get secret maas-db-app -n maas-db
uat "hub rhoai-quay-pull"  "run hack/quay-env.sh, then bootstrap/25-hub-secrets.sh" kc $h get secret rhoai-quay-pull -n ai-grid-policies
uat "one cert-manager OG"  "something added a second OperatorGroup to cert-manager-operator (Gaps 19)" \
  bash -c "[ \$(kc $h get operatorgroup -n cert-manager-operator --no-headers | wc -l) -eq 1 ]"
summary
