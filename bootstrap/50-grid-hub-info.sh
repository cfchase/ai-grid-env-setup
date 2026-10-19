#!/usr/bin/env bash
# What spokes need from enrollment, kept out of git: the hub site's certificate digest (Task 11
# adds enrollment's host once it has a Route). Policies read them from ConfigMap ai-grid-hub-info. Rerun after a rebuild.
source "$(dirname "$0")/lib.sh"
kc $HOST wait --for=create secret/grid-site-identity -n grid --timeout=15m
digest=$(kc $HOST get secret grid-site-identity -n grid -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | openssl x509 -outform DER | openssl dgst -sha256 -r | cut -d' ' -f1)
kc $HOST patch configmap ai-grid-hub-info -n ai-grid-policies --type merge \
  -p "{\"data\":{\"hubSiteDigest\":\"$digest\"}}"
