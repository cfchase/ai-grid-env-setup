#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ns=$KEYCLOAK_NS realm=ai-grid
# Realm ai-grid's generic setup: the broker's flow, scopes and lockdowns. Organizations, their identity
# providers and test users aren't here: the provider console creates organizations, or a cluster
# repository's demo tenants do (docs/runbook.md, "Organizations").
wait_created $HOST route/maas-keycloak $ns 900
kchost=$(kc $HOST get route maas-keycloak -n $ns -o jsonpath='{.spec.host}')
wait_created $HOST keycloakrealmimport/$realm $ns 900
kc $HOST wait keycloakrealmimport/$realm -n $ns --for=jsonpath='{.status.conditions[?(@.type=="Done")].status}'=True --timeout=15m
# Pin Keycloak's hostname to the Route's host, so links and the issuer never come from request
# headers. Set here, not in git, to keep the host name out of the repository; Argo CD doesn't
# manage this field, so it doesn't revert it.
if [[ $(kc $HOST get keycloak maas-keycloak -n $ns -o jsonpath='{.spec.hostname.hostname}') != "https://$kchost" ]]; then
  kc $HOST patch keycloak maas-keycloak -n $ns --type merge -p "{\"spec\":{\"hostname\":{\"hostname\":\"https://$kchost\"}}}"
  kc $HOST wait keycloak/maas-keycloak -n $ns --for=condition=Ready --timeout=10m
fi
# Ready can be reported before a restarted pod serves; wait until the realm answers.
for _ in $(seq 1 60); do curl -fsS -o /dev/null "https://$kchost/realms/$realm/.well-known/openid-configuration" && break; sleep 10; done
au=$(kc $HOST get secret maas-keycloak-initial-admin -n $ns -o jsonpath='{.data.username}' | base64 -d)
ap=$(kc $HOST get secret maas-keycloak-initial-admin -n $ns -o jsonpath='{.data.password}' | base64 -d)
# Secrets reach curl through a pipe or a file descriptor, never argv (where ps shows them).
tok=$(printf %s "$ap" | curl -fsS -d grant_type=password -d client_id=admin-cli --data-urlencode "username=$au" \
  --data-urlencode password@- "https://$kchost/realms/master/protocol/openid-connect/token" | jq -r .access_token); unset ap
[[ -n $tok && $tok != null ]] || die "Keycloak admin login failed"
api() { curl -fsS -H @<(printf 'Authorization: Bearer %s\n' "$tok") -H 'Content-Type: application/json' "$@"; }
base="https://$kchost/admin/realms/$realm"
# The operator never re-imports a realm that exists, so a hub whose realm ai-grid predates the broker
# has no first-broker-login flow. Stop with the upgrade steps.
api "$base/authentication/flows" | jq -e 'any(.[]; .alias == "ai-grid first broker login")' >/dev/null ||
  die "realm $realm predates the broker (no flow \"ai-grid first broker login\"). Upgrade it (docs/runbook.md, \"Upgrading realm ai-grid to the broker\"): delete realm $realm, delete keycloakrealmimport/$realm -n $ns (Argo CD recreates it), then rerun bootstrap/35-keycloak.sh, 36-portal-clients.sh and 60-console.sh"
# The realm import runs once, so apply brute-force protection (as in realm-ai-grid.yaml) to an
# existing realm too.
api "$base" | jq '.bruteForceProtected = true | .permanentLockout = false | .failureFactor = 10
  | .waitIncrementSeconds = 60 | .maxFailureWaitSeconds = 900 | .resetPasswordAllowed = false' | api -X PUT "$base" -d @- >/dev/null
realm_yaml="$(dirname "$0")/../apps/keycloak/manifests/realm-ai-grid.yaml"
[[ -f $realm_yaml ]] || die "$realm_yaml not found"
# Scope maas's groups mapper as in git; a mapper's type can't change in place, so replace it.
sid=$(api "$base/client-scopes" | jq -r '.[] | select(.name == "maas") | .id')
[[ -n $sid ]] || die "client scope maas not found in realm $realm"
want_gm=$(yq -o=json -I=0 '.spec.realm.clientScopes[] | select(.name == "maas") | .protocolMappers[] | select(.name == "groups")' "$realm_yaml")
have_gm=$(api "$base/client-scopes/$sid/protocol-mappers/models" | jq -c '.[] | select(.name == "groups")')
if [[ -z $have_gm ]] || ! jq -e --argjson w "$want_gm" '. as $h | .protocolMapper == $w.protocolMapper and ($w.config | to_entries | all($h.config[.key] == .value))' <<<"$have_gm" >/dev/null; then
  [[ -z $have_gm ]] || api -X DELETE "$base/client-scopes/$sid/protocol-mappers/models/$(jq -r .id <<<"$have_gm")" >/dev/null
  api -X POST "$base/client-scopes/$sid/protocol-mappers/models" -d "$want_gm" >/dev/null
fi
# The realm import doesn't apply a user profile, and the default profile drops unknown
# attributes: let admins set unmanaged ones such as maas_orgs (feeds the MaaS organization claim).
api "$base/users/profile" | jq '.unmanagedAttributePolicy = "ADMIN_EDIT"' | api -X PUT "$base/users/profile" -d @- >/dev/null
# Only an admin edits a user's email (a realm import can't set the user profile): a local user who set
# another organization's address would block that person's first brokered sign-in (no account linking,
# so a duplicate email fails).
api "$base/users/profile" | jq '(.attributes[] | select(.name == "email") | .permissions.edit) = ["admin"]' \
  | api -X PUT "$base/users/profile" -d @- >/dev/null
# No self-service account or password in the broker realm. A brokered user who set a local password could
# then use maas-cli's password grant and never sign in through their organization's provider again, so
# removing them there would not reach Keycloak (the provider's mappers run only on a brokered sign-in).
# Users lose manage-account (account linking, credentials, profile edits), the account console is off,
# and UPDATE_PASSWORD is disabled: a kc_action=UPDATE_PASSWORD from any client is then skipped
# (kc_action_status=error). Admins still set the local test users' passwords. Applied here, not in the
# realm import: the import can't drop a default role, and listing requiredActions replaces them all.
acct=$(api "$base/clients?clientId=account" | jq -r '.[0].id // empty')
[[ -n $acct ]] || die "client account not found in realm $realm"
manage=$(api "$base/roles/default-roles-$realm/composites/clients/$acct" | jq -c 'map(select(.name == "manage-account"))')
[[ $manage == "[]" ]] || api -X DELETE "$base/roles/default-roles-$realm/composites" -d "$manage" >/dev/null
acon=$(api "$base/clients?clientId=account-console" | jq -r '.[0].id // empty')
[[ -z $acon ]] || api "$base/clients/$acon" | jq '.enabled = false' | api -X PUT "$base/clients/$acon" -d @- >/dev/null
api "$base/authentication/required-actions/UPDATE_PASSWORD" | jq '.enabled = false' \
  | api -X PUT "$base/authentication/required-actions/UPDATE_PASSWORD" -d @- >/dev/null
# A brokered user (one with an identity provider link) who set a password before this keeps it: delete it.
# Every lookup fails closed: a $(...) failure doesn't stop the script, so each is checked.
users=$(api "$base/users?briefRepresentation=true&max=10000") && jq -e 'type == "array" and length < 10000' <<<"$users" >/dev/null \
  || die "can't list the users of realm $realm (or it has 10000 or more: page this cleanup)"
for u in $(jq -r '.[].id' <<<"$users"); do
  fed=$(api "$base/users/$u/federated-identity") || die "can't read user $u's identity provider links in realm $realm"
  [[ $(jq length <<<"$fed") == 0 ]] && continue
  creds=$(api "$base/users/$u/credentials") || die "can't read user $u's credentials in realm $realm"
  for c in $(jq -r '.[] | select(.type == "password") | .id' <<<"$creds"); do
    api -X DELETE "$base/users/$u/credentials/$c" >/dev/null
  done
done
# The realm import runs once, and listing clientScopes replaced Keycloak's built-in ones, so make
# sure scope maas carries sub, email, and preferred_username (MaaS's user name; email for the portal's
# sign-in proxy) on an existing realm too.
msid=$(api "$base/client-scopes" | jq -r '.[] | select(.name=="maas") | .id')
have=$(api "$base/client-scopes/$msid/protocol-mappers/models" | jq -r '.[].name')
grep -qx sub <<<"$have" || api -X POST "$base/client-scopes/$msid/protocol-mappers/models" -d '{"name":"sub","protocol":"openid-connect","protocolMapper":"oidc-sub-mapper","config":{"access.token.claim":"true","introspection.token.claim":"true"}}' >/dev/null
grep -qx email <<<"$have" || api -X POST "$base/client-scopes/$msid/protocol-mappers/models" -d '{"name":"email","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper","config":{"user.attribute":"email","claim.name":"email","jsonType.label":"String","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}' >/dev/null
grep -qx username <<<"$have" || api -X POST "$base/client-scopes/$msid/protocol-mappers/models" -d '{"name":"username","protocol":"openid-connect","protocolMapper":"oidc-usermodel-attribute-mapper","config":{"user.attribute":"username","claim.name":"preferred_username","jsonType.label":"String","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}' >/dev/null
unset tok
kc $HOST create configmap ai-grid-hub-info -n ai-grid-policies --dry-run=client -o yaml | kc $HOST apply -f - >/dev/null
kc $HOST patch configmap ai-grid-hub-info -n ai-grid-policies --type merge -p "{\"data\":{
  \"keycloakHost\":\"$kchost\",\"tenantIssuer\":\"https://$kchost/realms/$realm\",\"tenantClientId\":\"maas-cli\"}}"
