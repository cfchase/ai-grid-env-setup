# ai-grid-env-setup

Builds a rebuildable AI Grid demo environment: an ACM hub (ACM, Argo CD, Keycloak, grid enrollment,
the provider console) that provisions labelled spoke clusters with OpenShift AI, MaaS, and the grid
from the [odh-gitops](https://github.com/opendatahub-io/odh-gitops) chart.

- `env.sh`: every setting and pin, sourced by all scripts.
- `bootstrap/`: idempotent scripts for the steps that carry secrets or run before Argo CD.
- `verify/`: user-level checks; `make verify` runs them all.
- `docs/runbook.md`: cluster facts and the UAT log.

Set `HOST_KUBECONFIG` to the hub's kubeconfig file in your shell before running anything.
Nothing secret is stored in this repository.
