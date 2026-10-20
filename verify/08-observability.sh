#!/usr/bin/env bash
# Fleet metrics: ACM multicluster observability on the hub, Thanos storing into S4 (an in-cluster S3),
# and each spoke's OpenShift AI metrics federated in.
source "$(dirname "$0")/lib.sh"
h=$HOST
ns=open-cluster-management-observability
uat "app observability"      "Argo CD app not Synced/Healthy: a Job hook failed (kc host get jobs -n $ns), or MCO isn't Ready yet" app observability
uat "S4 ready"               "image pull, or Secret s4-credentials missing: kc host logs deploy/s4 -n $ns" \
  kc $h rollout status deploy/s4 -n $ns --timeout=5s
uat "S4 API not exposed"     "a Route or the web UI port (5000) reaches S4 from outside: only 7480 inside the cluster" \
  bash -c "[ -z \"\$(kc $h get route -n $ns -o name | grep s4)\" ] && ! kc $h get svc s4 -n $ns -o jsonpath='{.spec.ports[*].port}' | grep -qw 5000"
uat "thanos object storage" "Job s4-credentials didn't render it: kc host logs job/s4-credentials -n $ns" \
  bash -c "kc $h get secret thanos-object-storage -n $ns -o jsonpath='{.data.thanos\.yaml}' | base64 -d | grep -q 'bucket: thanos'"
uat "MCO ready"              "kc host get multiclusterobservability observability -o yaml: the not-Ready condition names the cause" \
  bash -c "kc $h get multiclusterobservability observability -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -qx True"
for sts in observability-thanos-compact observability-thanos-store-shard-0 observability-thanos-receive-default; do
  uat "$sts ready"           "Thanos can't use the bucket (kc host logs statefulset/$sts -n $ns), or no room to schedule" \
    bash -c "r=\$(kc $h get statefulset $sts -n $ns -o jsonpath='{.status.readyReplicas}/{.spec.replicas}'); [[ \${r%/*} -ge 1 && \${r%/*} == \${r#*/} ]]"
done
uat "thanos query ready"     "kc host get deploy observability-thanos-query -n $ns" \
  kc $h rollout status deploy/observability-thanos-query -n $ns --timeout=5s
# q <promql>: Thanos query result through the API server's service proxy (cluster-admin only).
q() { kc $HOST get --raw "/api/v1/namespaces/open-cluster-management-observability/services/http:observability-thanos-query:9090/proxy/api/v1/query?query=$(jq -rn --arg q "$1" '$q|@uri')"; }
export -f q
for s in $SPOKES; do
  uat "$s observability addon" "the addon can't install on $s: kc host get managedclusteraddon observability-controller -n $s -o yaml" \
    bash -c "kc $h get managedclusteraddon observability-controller -n $s -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}' | grep -qx True"
  uat "$s platform metrics in thanos" "the metrics collector on $s isn't forwarding: kc $s logs deploy/metrics-collector-deployment -n open-cluster-management-addon-observability" \
    bash -c "q 'count(up{cluster=\"$s\"})' | jq -e '.data.result | length > 0'"
  uat "$s OpenShift AI monitoring" "DSCI monitoring not Managed (spokes/platform/values/common.yaml), or its collector isn't up: kc $s get dscinitialization -o yaml" \
    kc $s get svc data-science-collector-collector -n redhat-ods-monitoring
  uat "$s OpenShift AI metrics in thanos" "ScrapeConfig rhai-metrics not distributed, or NetworkPolicy allow-acm-rhai-metrics missing on $s (Policy rhai-metrics)" \
    bash -c "q 'count({cluster=\"$s\",job=\"rhai-metrics\"})' | jq -e '.data.result | length > 0'"
done
summary
