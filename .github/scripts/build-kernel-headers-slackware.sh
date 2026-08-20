#!/bin/bash
set -Eeuo pipefail

WORKROOT="${WORKROOT:-/work}"
OUTPUT="$WORKROOT/output"
BUILDROOT="${BUILDROOT:-$WORKROOT/.kernel-build}"
TMPDIR="$BUILDROOT/tmp"
VERIFY_HEADERS="$BUILDROOT/verify-headers"
HEADERSROOT="$BUILDROOT/headersroot"

mkdir -p "$OUTPUT" "$TMPDIR"
exec > >(tee -a "$OUTPUT/build.log") 2>&1

log() {
  printf '\n==== %s ====\n' "$*"
}

trap 'rc=$?; echo; echo "ERRO no empacotamento de kernel-headers, linha $LINENO (status $rc)"; exit $rc' ERR

log "Lendo metadados do build principal"
test -s "$OUTPUT/meta.env"
# shellcheck disable=SC1090
source "$OUTPUT/meta.env"

test -n "${KERNEL_VERSION:-}"
test -n "${PACKAGE_REVISION:-}"

SRC="$BUILDROOT/src/linux-$KERNEL_VERSION"
test -d "$SRC"
test -s "$SRC/Makefile"

HEADERS_PACKAGE_NAME="kernel-headers-${KERNEL_VERSION}-x86-${PACKAGE_REVISION}.txz"
echo "Kernel: $KERNEL_VERSION"
echo "Pacote headers: $HEADERS_PACKAGE_NAME"

log "Gerando UAPI headers sanitizados do Linux $KERNEL_VERSION"
rm -rf "$HEADERSROOT" "$VERIFY_HEADERS"
mkdir -p \
  "$HEADERSROOT/usr" \
  "$HEADERSROOT/usr/doc/kernel-headers-$KERNEL_VERSION" \
  "$HEADERSROOT/install" \
  "$VERIFY_HEADERS"

make -C "$SRC" headers_install INSTALL_HDR_PATH="$HEADERSROOT/usr"

test -d "$HEADERSROOT/usr/include/linux"
test -d "$HEADERSROOT/usr/include/asm"
test -s "$HEADERSROOT/usr/include/linux/version.h"
test -s "$HEADERSROOT/usr/include/linux/types.h"
test -s "$HEADERSROOT/usr/include/linux/limits.h"

HEADER_COUNT="$(find "$HEADERSROOT/usr/include" -type f | wc -l)"
test "$HEADER_COUNT" -gt 100

echo "Headers instalados: $HEADER_COUNT"

cat > "$HEADERSROOT/usr/doc/kernel-headers-$KERNEL_VERSION/README" <<EOF_README
Linux UAPI headers $KERNEL_VERSION para Slackware/Salix.

Este pacote foi gerado diretamente da árvore Linux $KERNEL_VERSION com:

  make headers_install

Ele fornece os cabeçalhos UAPI sanitizados em /usr/include, equivalentes ao
papel do pacote kernel-headers do Slackware.

ATENÇÃO: este pacote substitui os cabeçalhos UAPI instalados no sistema.
Use upgradepkg para substituir deliberadamente o kernel-headers anterior.
Ele é diferente do pacote kernel-devel-lts618, que fornece a árvore preparada
para compilar módulos externos contra o kernel exato.
EOF_README

cat > "$HEADERSROOT/install/slack-desc" <<EOF_DESC
kernel-headers: kernel-headers (Linux UAPI headers $KERNEL_VERSION)
kernel-headers:
kernel-headers: Cabeçalhos UAPI sanitizados do Linux $KERNEL_VERSION.
kernel-headers: Gerados com make headers_install dentro do Slackware 15.0.
kernel-headers: Instalam em /usr/include para compilação de userspace.
kernel-headers: Correspondem à revisão do kernel 6.18 deste projeto.
kernel-headers: Não substituem o papel do kernel-devel-lts618.
kernel-headers: Pacote nativo Slackware criado com makepkg.
kernel-headers:
kernel-headers: Projeto kernel-generic-6.18-lts-slackware-salix
kernel-headers:
EOF_DESC

find "$HEADERSROOT" -type d -exec chmod 0755 {} +
chmod -R a+rX "$HEADERSROOT"

log "Criando TXZ kernel-headers com makepkg nativo"
rm -f "$OUTPUT/$HEADERS_PACKAGE_NAME" "$OUTPUT/$HEADERS_PACKAGE_NAME.sha256"
cd "$HEADERSROOT"
makepkg -l y -c n "$OUTPUT/$HEADERS_PACKAGE_NAME"
test -s "$OUTPUT/$HEADERS_PACKAGE_NAME"

log "Validando TXZ kernel-headers com pkgtools Slackware"
installpkg --warn "$OUTPUT/$HEADERS_PACKAGE_NAME" >/dev/null
cd "$VERIFY_HEADERS"
explodepkg "$OUTPUT/$HEADERS_PACKAGE_NAME"

test -s "usr/include/linux/version.h"
test -s "usr/include/linux/types.h"
test -s "usr/include/linux/limits.h"
test -s "install/slack-desc"

log "Compilando teste userspace contra os headers empacotados"
cat > "$TMPDIR/headers-test.c" <<'EOF_C'
#include <linux/version.h>
#include <linux/limits.h>

#ifndef LINUX_VERSION_CODE
#error LINUX_VERSION_CODE ausente
#endif

int main(void) {
    return (PATH_MAX > 0 && LINUX_VERSION_CODE > 0) ? 0 : 1;
}
EOF_C

gcc -I"$VERIFY_HEADERS/usr/include" "$TMPDIR/headers-test.c" -o "$TMPDIR/headers-test"
"$TMPDIR/headers-test"
echo "Teste userspace com headers $KERNEL_VERSION: OK"

log "Gerando checksum"
cd "$OUTPUT"
sha256sum "$HEADERS_PACKAGE_NAME" > "$HEADERS_PACKAGE_NAME.sha256"
sha256sum -c "$HEADERS_PACKAGE_NAME.sha256"

if grep -q '^HEADERS_PACKAGE_NAME=' meta.env; then
  sed -i "s|^HEADERS_PACKAGE_NAME=.*|HEADERS_PACKAGE_NAME=$HEADERS_PACKAGE_NAME|" meta.env
else
  printf 'HEADERS_PACKAGE_NAME=%s\n' "$HEADERS_PACKAGE_NAME" >> meta.env
fi

if grep -q '^HEADERS_COUNT=' meta.env; then
  sed -i "s|^HEADERS_COUNT=.*|HEADERS_COUNT=$HEADER_COUNT|" meta.env
else
  printf 'HEADERS_COUNT=%s\n' "$HEADER_COUNT" >> meta.env
fi

chmod -R a+rX "$OUTPUT"

log "Pacote kernel-headers concluído"
ls -lh "$HEADERS_PACKAGE_NAME" "$HEADERS_PACKAGE_NAME.sha256"
cat "$HEADERS_PACKAGE_NAME.sha256"
echo "HEADERS_PACKAGE_NAME=$HEADERS_PACKAGE_NAME"
echo "HEADERS_COUNT=$HEADER_COUNT"
