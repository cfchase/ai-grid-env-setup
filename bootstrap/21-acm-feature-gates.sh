#!/usr/bin/env bash
# The ClusterManager belongs to the ACM operator, so a script (not Argo CD) turns on the
# ManifestWorkReplicaSet gate once ACM is running. Safe to rerun.
source "$(dirname "$0")/lib.sh"
kc $HOST wait multiclusterhub/multiclusterhub -n open-cluster-management --for=jsonpath='{.status.phase}'=Running --timeout=30m
kc $HOST patch clustermanager cluster-manager --type merge \
  -p '{"spec":{"workConfiguration":{"featureGates":[{"feature":"ManifestWorkReplicaSet","mode":"Enable"}]}}}'
