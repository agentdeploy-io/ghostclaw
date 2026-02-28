#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p /home/ironclaw/.ironclaw
# Ensure onboarding can create/write local libsql DB files on mounted volume.
chown -R ironclaw:ironclaw /home/ironclaw/.ironclaw

if [[ $# -eq 0 ]]; then
  set -- ironclaw run
elif [[ "$1" != "ironclaw" && "$1" != "/"* ]]; then
  set -- ironclaw "$@"
fi

exec gosu ironclaw "$@"
