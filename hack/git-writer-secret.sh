#!/usr/bin/env bash
# The backend's git writer token: Secret ai-grid-backend-git (key token) in namespace ai-grid on the hub,
# from a file the deployer keeps (a fine-grained PAT, contents: write on the cluster repository only).
# Usage: make git-writer-secret TOKEN_FILE=<path>
# The token goes from the file to the API server through a pipe: this script never reads it into a
# variable, prints it or puts it on a command line. Rerun it to rotate, then restart the console pod.
source "$(dirname "$0")/../bootstrap/lib.sh"
file=${1:-}
[[ -n $file ]] || die "usage: make git-writer-secret TOKEN_FILE=<path to the token file>"
[[ -f $file ]] || die "TOKEN_FILE=$file: no such file"
[[ -s $file ]] || die "TOKEN_FILE=$file is empty"
kc "$HOST" get namespace ai-grid >/dev/null || die "namespace ai-grid isn't on the hub yet: sync Argo CD app console first"
# Server-side apply: a client-side apply would also copy the token into the
# kubectl.kubernetes.io/last-applied-configuration annotation.
kc "$HOST" create secret generic ai-grid-backend-git -n ai-grid --from-file=token="$file" --dry-run=client -o yaml |
  kc "$HOST" apply --server-side --field-manager=git-writer-secret -f - >/dev/null
log "Secret ai-grid/ai-grid-backend-git written. The backend reads the token once, at start: oc rollout restart deployment/ai-grid-provider-console -n ai-grid"
