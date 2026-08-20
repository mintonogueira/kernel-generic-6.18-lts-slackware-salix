#!/bin/bash
set -Eeuo pipefail

WORKROOT="${WORKROOT:-/work}"

printf '\n==== Etapa 1/2: kernel + kernel-devel ====\n'
/bin/bash "$WORKROOT/.github/scripts/build-kernel-slackware.sh"

printf '\n==== Etapa 2/2: kernel-headers ====\n'
/bin/bash "$WORKROOT/.github/scripts/build-kernel-headers-slackware.sh"

printf '\n==== Três pacotes Slackware concluídos ====\n'
source "$WORKROOT/output/meta.env"
for v in PACKAGE_NAME DEVEL_PACKAGE_NAME HEADERS_PACKAGE_NAME; do
  test -n "${!v}"
  test -s "$WORKROOT/output/${!v}"
  test -s "$WORKROOT/output/${!v}.sha256"
done

printf 'kernel: %s\n' "$PACKAGE_NAME"
printf 'kernel-devel: %s\n' "$DEVEL_PACKAGE_NAME"
printf 'kernel-headers: %s\n' "$HEADERS_PACKAGE_NAME"
