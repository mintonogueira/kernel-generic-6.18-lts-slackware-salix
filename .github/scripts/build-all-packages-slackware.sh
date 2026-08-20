#!/bin/bash
set -Eeuo pipefail

WORKROOT="${WORKROOT:-/work}"
BUILDROOT="${BUILDROOT:-$WORKROOT/.kernel-build}"

printf '\n==== Etapa 0/3: bootstrap resiliente das séries Slackware ====\n'
/bin/bash "$WORKROOT/.github/scripts/bootstrap-slackware-series.sh"

# A instalação das séries pertence exclusivamente ao bootstrap acima.
# O script histórico de kernel ainda contém esse bloco para uso isolado;
# no fluxo integrado removemos apenas esse trecho da cópia de execução para
# não repetir slackpkg update/install dentro do mesmo container.
RUNTIME_KERNEL_SCRIPT="$BUILDROOT/build-kernel-slackware.runtime.sh"
mkdir -p "$BUILDROOT"
awk '
  /^log "Preparando slackpkg para ambiente não interativo"/ { skip=1; next }
  /^log "Ativando cadeia CA nativa do Slackware"/ { skip=0 }
  !skip { print }
' "$WORKROOT/.github/scripts/build-kernel-slackware.sh" > "$RUNTIME_KERNEL_SCRIPT"
chmod +x "$RUNTIME_KERNEL_SCRIPT"

grep -q '^log "Ativando cadeia CA nativa do Slackware"' "$RUNTIME_KERNEL_SCRIPT"
if grep -q '^  log "Instalando série Slackware:' "$RUNTIME_KERNEL_SCRIPT"; then
  echo "ERRO: bootstrap duplicado permaneceu na cópia de execução"
  exit 1
fi

printf '\n==== Etapa 1/3: kernel + kernel-devel ====\n'
/bin/bash "$RUNTIME_KERNEL_SCRIPT"

printf '\n==== Etapa 2/3: kernel-headers ====\n'
/bin/bash "$WORKROOT/.github/scripts/build-kernel-headers-slackware.sh"

printf '\n==== Etapa 3/3: validar os três pacotes ====\n'
source "$WORKROOT/output/meta.env"
for v in PACKAGE_NAME DEVEL_PACKAGE_NAME HEADERS_PACKAGE_NAME; do
  test -n "${!v}"
  test -s "$WORKROOT/output/${!v}"
  test -s "$WORKROOT/output/${!v}.sha256"
done

printf '\n==== Três pacotes Slackware concluídos ====\n'
printf 'kernel: %s\n' "$PACKAGE_NAME"
printf 'kernel-devel: %s\n' "$DEVEL_PACKAGE_NAME"
printf 'kernel-headers: %s\n' "$HEADERS_PACKAGE_NAME"
