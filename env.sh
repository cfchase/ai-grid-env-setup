# Sourced by every bootstrap and verify script.
export KUBEDIR="${KUBEDIR:-$HOME/.kube/aigrid}"
# The hub. Scripts use its kubeconfig file's current context. First build:
# HOST_KUBECONFIG=<workspace>/.config/aio/kubeconfig (passed by path only; set outside git).
export HOST=host
export HOST_KUBECONFIG="${HOST_KUBECONFIG:-$KUBEDIR/host}"
# Spokes: ManagedCluster names that get AI Grid. local-cluster is the hub itself (D1, 2026-10-19).
# A remote spoke's kubeconfig is $KUBEDIR/<name>, used to import it (Task 11) and by its verify checks.
export SPOKES="${SPOKES:-local-cluster}"
export SPOKE_ROLES="${SPOKE_ROLES:-local-cluster=combined}"       # ingress | inference | combined
export SPOKE_LOCATIONS="${SPOKE_LOCATIONS:-local-cluster=us-east}"
# The deployer's quay.io/rhoai login (QUAY_USER, QUAY_TOKEN), git-ignored, written by hack/quay-env.sh
# (Task 2). Read only by bootstrap/25-hub-secrets.sh and the fallback bootstrap/10-pull-secret.sh (Task 5).
export ENV_FILE="${ENV_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.env}"
# D4: policy (default: ACM Policy rhoai-pull-secret) or script (fallback: bootstrap/10-pull-secret.sh).
export PULL_SECRET_MODE="${PULL_SECRET_MODE:-policy}"
# Keycloak namespace on the hub (Task 3): the RHBK operator demo.redhat.com pre-installs (Chris, 2026-10-19).
export KEYCLOAK_NS="${KEYCLOAK_NS:-keycloak}"
# Grid release for every chart and image. Switch to 0.2.1 once its tag and charts are published
# (upstream main 5963265, "prepare Grid v0.2.1", wasn't tagged on 2026-10-19).
export GRID_VERSION=0.2.0 GRID_CHARTS=oci://ghcr.io/praxis-proxy/charts
# helm: the published grid charts (default). odh-gitops: PR 181 on local-cluster (Task 14).
export GRID_INSTALL="${GRID_INSTALL:-helm}"
export GRID_NS="${GRID_NS:-grid}"
export GRID_NETWORK=grid GRID_ID=aigrid-demo
export MODEL_NAME=facebook-opt-125m
# The spokes' platform chart: odh-gitops main at 8897054 (2026-10-16), which has dashboard.dsc.maasPortal.
export ODH_GITOPS_REF="${ODH_GITOPS_REF:-8897054}"
# The nightly catalog, copied deliberately from kahowell/ai-grid-tenant apps/rhoai/nightly.yaml.
export RHOAI_CATALOG_IMAGE="${RHOAI_CATALOG_IMAGE:-quay.io/rhoai/rhoai-fbc-fragment:rhoai-3.6@sha256:70c700e76cb23f13a4ccc1896bfcf37238229c5aa80af7daae7fc8028c7f1d9c}"
export LABEL_ENABLED=ai-grid/enabled LABEL_ROLE=ai-grid/role
export LABEL_LOCATION=location LABEL_PROVISIONED=ai-grid/provisioned
# During the build Argo CD reads the fork's build branch (Chris, 2026-10-19); Task 11 switches to upstream main.
export GIT_REPO="${GIT_REPO:-https://github.com/cfchase/ai-grid-env-setup.git}" GIT_REF="${GIT_REF:-build}"
# Provider console (Task 9). Registry ghcr.io/ai-grid-cloud (Chris, 2026-10-17). Set the tags after Task 9, Step 2.
export CONSOLE_REF="${CONSOLE_REF:-upstream/main}"   # git ref of ai-grid-cloud/ai-grid-provider-console
export CONSOLE_IMAGE="${CONSOLE_IMAGE:-ghcr.io/ai-grid-cloud/ai-grid-provider-console:unset}"
export BACKEND_IMAGE="${BACKEND_IMAGE:-ghcr.io/ai-grid-cloud/ai-grid-backend:unset}"
# The backend commit to build (ai-grid-cloud/ai-grid-provider-backend). The console's go.mod no longer
# names it, so it's pinned here. ff3f332 is backend PR 1 (2026-10-19); the console can't call it
# until a proto change lands (Task 9, "On hold").
export BACKEND_REF="${BACKEND_REF:-ff3f332}"
export CONSOLE_KEYCLOAK_REALM=ai-grid               # the backend's default realm for organizations
