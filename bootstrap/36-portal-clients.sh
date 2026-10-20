#!/usr/bin/env bash
# The MaaS Portal's sign-in proxy (Policy tenant-portal) signs tenants in to realm ai-grid with one
# confidential client, maas-portal, whose redirect URIs list every ingress spoke's portal callback.
# Its secret goes into hub Secret ai-grid-policies/maas-portal-oidc, never git or argv. Tenant logins
# never touch a cluster's OpenShift login. Rerun after adding an ingress spoke (Task 11).
source "$(dirname "$0")/lib.sh"
ns=$KEYCLOAK_NS realm=ai-grid cid=maas-portal
kchost=$(kc $HOST get configmap ai-grid-hub-info -n ai-grid-policies -o jsonpath='{.data.keycloakHost}')
[[ -n $kchost ]] || die "run bootstrap/35-keycloak.sh first"
au=$(kc $HOST get secret maas-keycloak-initial-admin -n $ns -o jsonpath='{.data.username}' | base64 -d)
ap=$(kc $HOST get secret maas-keycloak-initial-admin -n $ns -o jsonpath='{.data.password}' | base64 -d)
tok=$(curl -fsS -d grant_type=password -d client_id=admin-cli -d username="$au" --data-urlencode password="$ap" \
  "https://$kchost/realms/master/protocol/openid-connect/token" | jq -r .access_token); unset ap
[[ -n $tok && $tok != null ]] || die "Keycloak admin login failed"
api() { curl -fsS -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' "$@"; }
base="https://$kchost/admin/realms/$realm"
uris=()
for s in $SPOKES; do
  [[ $(role_of $s) == inference ]] && continue
  domain=$(kc $s get ingresses.config cluster -o jsonpath='{.spec.domain}')
  uris+=("https://maas.$domain/oauth2/callback")
done
body=$(jq -n --arg cid "$cid" '{clientId: $cid, protocol: "openid-connect", publicClient: false,
  standardFlowEnabled: true, directAccessGrantsEnabled: false, redirectUris: $ARGS.positional,
  defaultClientScopes: ["maas"]}' --args "${uris[@]}")
id=$(api "$base/clients?clientId=$cid" | jq -r '.[0].id // empty')
if [[ -z $id ]]; then api -X POST "$base/clients" -d "$body" >/dev/null; id=$(api "$base/clients?clientId=$cid" | jq -re '.[0].id')
else api -X PUT "$base/clients/$id" -d "$body" >/dev/null; fi
# The secret reaches kubectl through the environment and a pipe, never argv.
SEC=$(api "$base/clients/$id/client-secret" | jq -r .value) jq -n --arg cid "$cid" \
  '{apiVersion: "v1", kind: "Secret", metadata: {name: "maas-portal-oidc", namespace: "ai-grid-policies"},
    stringData: {clientId: $cid, clientSecret: env.SEC}}' | kc $HOST apply -f - >/dev/null
# The earlier design (a cluster-login identity provider per spoke) is gone: remove its clients and Secrets.
for old in $(api "$base/clients" | jq -r '.[] | select(.clientId|startswith("ocp-")) | .id'); do api -X DELETE "$base/clients/$old" >/dev/null; done
for sname in $(kc $HOST get secret -n ai-grid-policies -o name | grep '/portal-idp-'); do kc $HOST delete -n ai-grid-policies "$sname" >/dev/null; done
unset tok
log "client $cid ready for ${#uris[@]} ingress spoke(s); its secret is in ai-grid-policies/maas-portal-oidc"
