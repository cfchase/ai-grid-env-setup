#!/usr/bin/env bash
# Commits and pushes one spoke's invite and models directory, which Argo CD reads from git:
#   bash hack/spoke-commit.sh <spoke> [--ask]      (make spoke-commit SPOKE=<spoke>)
# Stages only apps/grid-enrollment/manifests/values.yaml and spokes/clusters/<spoke>, never anything
# else, and pushes the current branch, which must be $GIT_REF. --ask (46-spoke-join.sh) shows the
# change and asks first when stdin is a terminal; otherwise it prints the make command and stops.
source "$(dirname "$0")/../bootstrap/lib.sh"
spoke=${1:?usage: spoke-commit.sh <spoke> [--ask]} ask=${2:-}
cd "$(dirname "$0")/.."
paths=(apps/grid-enrollment/manifests/values.yaml "spokes/clusters/$spoke")
if git diff --quiet HEAD -- "${paths[@]}" && [[ -z $(git ls-files --others --exclude-standard -- "${paths[@]}") ]]; then
  log "$spoke: invite and models directory already committed"; exit 0
fi
if [[ $ask ]]; then
  if [[ ! -t 0 ]]; then
    log "Commit and push the invite and models directory (Argo CD reads $GIT_REF), then add $spoke in the console:"
    echo "  make spoke-commit SPOKE=$spoke"; exit 0
  fi
  git --no-pager diff --stat HEAD -- "${paths[@]}"
  git ls-files --others --exclude-standard -- "${paths[@]}" | sed 's/^/ new: /'
  read -r -p "Commit and push to $GIT_REF? [y/N] " a
  [[ $a == [yY]* ]] || { log "not committed; later: make spoke-commit SPOKE=$spoke"; exit 0; }
fi
branch=$(git branch --show-current)
[[ $branch == "$GIT_REF" ]] || die "on branch ${branch:-(detached)}, but Argo CD reads $GIT_REF: check out $GIT_REF, or set GIT_REF"
git add -- "${paths[@]}"
git commit -q -m "spoke $spoke: invite and models" -- "${paths[@]}"
git push -q
log "pushed $(git rev-parse --short HEAD) to $GIT_REF: add $spoke in the console"
