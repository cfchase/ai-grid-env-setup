#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."
kc $HOST apply -f - <<'YAML'
apiVersion: v1
kind: Namespace
metadata: { name: openshift-gitops-operator }
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata: { name: openshift-gitops-operator, namespace: openshift-gitops-operator }
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata: { name: openshift-gitops-operator, namespace: openshift-gitops-operator }
spec: { channel: latest, name: openshift-gitops-operator, source: redhat-operators, sourceNamespace: openshift-marketplace }
---
apiVersion: v1
kind: Namespace
metadata: { name: ai-grid-policies }
YAML
until kc $HOST get argocd openshift-gitops -n openshift-gitops >/dev/null 2>&1; do sleep 10; done
kc $HOST adm policy add-cluster-role-to-user cluster-admin -z openshift-gitops-argocd-application-controller -n openshift-gitops
# Argo CD admin for the deployer (its RBAC grants role:admin to group cluster-admins only).
kc $HOST get group cluster-admins >/dev/null 2>&1 || kc $HOST adm groups new cluster-admins
kc $HOST adm groups add-users cluster-admins $ARGO_ADMIN_USERS
kc $HOST patch argocd openshift-gitops -n openshift-gitops --type merge \
  -p '{"spec":{"controller":{"resources":{"requests":{"memory":"2Gi"},"limits":{"memory":"4Gi"}}}}}'
kc $HOST apply -f - <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: praxis-charts
  namespace: openshift-gitops
  labels: { argocd.argoproj.io/secret-type: repository }
stringData: { type: helm, name: praxis-charts, url: ghcr.io/praxis-proxy/charts, enableOCI: "true" }
YAML
kc $HOST apply -f hub/acm/subscription.yaml
until kc $HOST get crd multiclusterhubs.operator.open-cluster-management.io >/dev/null 2>&1; do sleep 15; done
# The CRD appears before the operator's validating webhook has endpoints: retry until it accepts the CR.
until kc $HOST apply -f hub/acm/multiclusterhub.yaml 2>/dev/null; do log "waiting for the ACM operator webhook"; sleep 20; done
log "waiting for ACM (about 15 minutes)"
kc $HOST wait multiclusterhub/multiclusterhub -n open-cluster-management \
  --for=jsonpath='{.status.phase}'=Running --timeout=30m
kc $HOST patch clustermanager cluster-manager --type merge \
  -p '{"spec":{"workConfiguration":{"featureGates":[{"feature":"ManifestWorkReplicaSet","mode":"Enable"}]}}}'
