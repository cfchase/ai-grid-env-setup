#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."
kc $HOST apply -f hub/postgres/operator.yaml
until kc $HOST get crd clusters.postgresql.cnpg.io >/dev/null 2>&1; do sleep 10; done
# The CRD appears before the operator's webhook has endpoints: retry until it accepts the Cluster.
until kc $HOST apply -f hub/postgres/maas-db.yaml 2>/dev/null; do log "waiting for the CloudNativePG webhook"; sleep 15; done
kc $HOST wait cluster.postgresql.cnpg.io/maas-db -n maas-db   --for=jsonpath='{.status.phase}'='Cluster in healthy state' --timeout=15m
# rhoai-quay-pull: the deployer's quay login for Policy rhoai-pull-secret (D4). Never printed.
[[ -f "$ENV_FILE" ]] || die "missing $ENV_FILE: run hack/quay-env.sh (Step 2)"
(
  set -a; source "$ENV_FILE"; set +a
  [[ -n "${QUAY_USER:-}" && -n "${QUAY_TOKEN:-}" ]] || die "QUAY_USER or QUAY_TOKEN empty in $ENV_FILE"
  printf '%s:%s' "$QUAY_USER" "$QUAY_TOKEN" | base64 | tr -d '\n' \
    | kc $HOST create secret generic rhoai-quay-pull -n ai-grid-policies --from-file=auth=/dev/stdin \
        --dry-run=client -o yaml | kc $HOST apply -f - >/dev/null
)
