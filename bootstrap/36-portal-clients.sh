#!/usr/bin/env bash
# One confidential client per ingress spoke, for that spoke's OpenShift login. Rerun after adding an ingress spoke (Task 11).
source "$(dirname "$0")/lib.sh"
ns=$KEYCLOAK_NS realm=ai-grid
kchost=$(kc $HOST get configmap ai-grid-hub-info -n ai-grid-policies -o jsonpath='{.data.keycloakHost}')
[[ -n $kchost ]] || die "run bootstrap/35-keycloak.sh first"
au=$(kc $HOST get secret maas-keycloak-initial-admin -n $ns -o jsonpath='{.data.username}' | base64 -d)
ap=$(kc $HOST get secret maas-keycloak-initial-admin -n $ns -o jsonpath='{.data.password}' | base64 -d)
tok=$(curl -fsS -d grant_type=password -d client_id=admin-cli -d username="$au" --data-urlencode password="$ap" \
  "https://$kchost/realms/master/protocol/openid-connect/token" | jq -r .access_token); unset ap
[[ -n $tok && $tok != null ]] || die "Keycloak admin login failed"
api() { curl -fsS -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' "$@"; }
base="https://$kchost/admin/realms/$realm"
for s in $SPOKES; do
  [[ $(role_of $s) == inference ]] && continue
  domain=$(kc $s get ingresses.config cluster -o jsonpath='{.spec.domain}')
  cid=ocp-$s
  body=$(jq -n --arg cid "$cid" --arg uri "https://oauth-openshift.$domain/oauth2callback/$realm" '{
    clientId: $cid, protocol: "openid-connect", publicClient: false,
    standardFlowEnabled: true, directAccessGrantsEnabled: false, redirectUris: [$uri],
    defaultClientScopes: ["maas", "profile", "email"] }')
  id=$(api "$base/clients?clientId=$cid" | jq -r '.[0].id // empty')
  if [[ -z $id ]]; then api -X POST "$base/clients" -d "$body" >/dev/null; id=$(api "$base/clients?clientId=$cid" | jq -r '.[0].id')
  else api -X PUT "$base/clients/$id" -d "$body" >/dev/null; fi
  sec=$(api "$base/clients/$id/client-secret" | jq -r .value)
  kc $HOST create secret generic portal-idp-$s -n ai-grid-policies \
    --from-literal=clientId="$cid" --from-literal=clientSecret="$sec" --dry-run=client -o yaml | kc $HOST apply -f - >/dev/null
  unset sec
  log "$s: client $cid ready; its secret is in ai-grid-policies/portal-idp-$s"
done
unset tok
