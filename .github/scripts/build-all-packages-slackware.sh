#!/bin/bash
set -Eeuo pipefail

WORKROOT="${WORKROOT:-/work}"
BUILDROOT="${BUILDROOT:-$WORKROOT/.kernel-build}"

# O bootstrap faz parte do fluxo integrado e inclui retry para a sondagem de
# rede inicial, sem desativar validação TLS ou checksums do Slackware.
printf '\n==== Etapa 0/3: bootstrap resiliente das séries Slackware ====\n'
/bin/bash "$WORKROOT/.github/scripts/bootstrap-slackware-series.sh"

# A instalação das séries pertence exclusivamente ao bootstrap acima.
# O script histórico de kernel ainda contém esse bloco para uso isolado;
# no fluxo integrado removemos apenas esse trecho da cópia de execução para
# não repetir slackpkg update/install dentro do mesmo container.
RUNTIME_KERNEL_SCRIPT="$BUILDROOT/build-kernel-slackware.runtime.sh"
mkdir -p "$BUILDROOT"

# O explodepkg do pkgtools pode retornar 1 depois de extrair corretamente um
# pacote que contém install/doinst.sh, avisando que o script de instalação não
# foi executado. Para validação offline isso é esperado: o conteúdo extraído
# continua sendo verificado logo depois. Qualquer outro retorno não zero, ou o
# retorno 1 sem doinst.sh dentro do próprio TXZ, continua sendo erro fatal.
# A presença do doinst.sh é confirmada pela listagem do pacote, pois explodepkg
# pode detectar o script e ainda assim não deixá-lo disponível para um teste -f
# após retornar 1.
cat > "$RUNTIME_KERNEL_SCRIPT" <<'EOF_RUNTIME_HEADER'
#!/bin/bash

explodepkg_validate() {
  local pkg="$1" rc

  if explodepkg "$pkg"; then
    return 0
  else
    rc=$?
  fi

  if [ "$rc" -eq 1 ]; then
    if tar -tf "$pkg" | grep -E '^(\./)?install/doinst\.sh$' >/dev/null; then
      echo "explodepkg retornou 1 para pacote com install/doinst.sh; validação estrutural continuará."
      return 0
    fi
  fi

  echo "ERRO: explodepkg falhou com status $rc ao validar $pkg"
  return "$rc"
}
EOF_RUNTIME_HEADER

awk '
  NR == 1 { next }
  /^log "Preparando slackpkg para ambiente não interativo"/ { skip=1; next }
  /^log "Ativando cadeia CA nativa do Slackware"/ { skip=0 }
  !skip {
    if ($0 ~ /^explodepkg "\$OUTPUT\/\$PACKAGE_NAME"$/) {
      print "explodepkg_validate \"$OUTPUT/$PACKAGE_NAME\""
    } else if ($0 ~ /^explodepkg "\$OUTPUT\/\$DEVEL_PACKAGE_NAME"$/) {
      print "explodepkg_validate \"$OUTPUT/$DEVEL_PACKAGE_NAME\""
      print "test -f install/doinst.sh"
      print "/bin/sh install/doinst.sh"
    } else {
      print
    }
  }
' "$WORKROOT/.github/scripts/build-kernel-slackware.sh" >> "$RUNTIME_KERNEL_SCRIPT"
chmod +x "$RUNTIME_KERNEL_SCRIPT"

grep -q '^log "Ativando cadeia CA nativa do Slackware"' "$RUNTIME_KERNEL_SCRIPT"
grep -q '^explodepkg_validate "$OUTPUT/$PACKAGE_NAME"$' "$RUNTIME_KERNEL_SCRIPT"
grep -q '^explodepkg_validate "$OUTPUT/$DEVEL_PACKAGE_NAME"$' "$RUNTIME_KERNEL_SCRIPT"
grep -q '^/bin/sh install/doinst.sh$' "$RUNTIME_KERNEL_SCRIPT"
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
