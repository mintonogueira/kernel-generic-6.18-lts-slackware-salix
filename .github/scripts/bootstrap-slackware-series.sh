#!/bin/bash
set -Eeuo pipefail

BOOTSTRAP_CA="${BOOTSTRAP_CA:-}"
MIRROR="https://mirrors.kernel.org/slackware/slackware64-15.0/"
MAX_ATTEMPTS="${SLACKPKG_MAX_ATTEMPTS:-4}"

log() {
  printf '\n==== %s ====\n' "$*"
}

configure_wget_ca() {
  local ca="$1"
  test -s "$ca"
  cat > /root/.wgetrc <<EOF_WGETRC
check_certificate = on
ca_certificate = $ca
tries = 5
timeout = 30
waitretry = 3
retry_connrefused = on
EOF_WGETRC
  chmod 0600 /root/.wgetrc
  export WGETRC=/root/.wgetrc
}

slackpkg_retry() {
  local attempt=1 rc=0 command="${1:-}"

  while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    echo "slackpkg tentativa $attempt/$MAX_ATTEMPTS: $*"

    set +e
    slackpkg -default_answer=yes -batch=on "$@"
    rc=$?
    set -e

    if [ "$rc" -eq 0 ]; then
      return 0
    fi

    # O slackpkg pode retornar 20 quando um update não tem alterações.
    # Para install isso significa seleção vazia e não pode ser aceito como sucesso.
    if [ "$rc" -eq 20 ] && [ "$command" = "update" ]; then
      return 0
    fi

    echo "slackpkg retornou status $rc. Limpando downloads parciais antes de repetir."
    rm -rf /var/cache/packages/* || true

    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
      echo "ERRO: slackpkg falhou após $MAX_ATTEMPTS tentativas: $*"
      return "$rc"
    fi

    sleep $((attempt * 5))
    attempt=$((attempt + 1))
  done

  return "$rc"
}

log "Bootstrap resiliente das séries Slackware 15.0"
grep -q '^Slackware 15\.0' /etc/slackware-version
test "$(uname -m)" = "x86_64"
test -n "$BOOTSTRAP_CA"
configure_wget_ca "$BOOTSTRAP_CA"
wget -q --spider "${MIRROR}CHECKSUMS.md5.asc"

printf '%s\n' "$MIRROR" > /etc/slackpkg/mirrors

if [ -f /usr/libexec/slackpkg/functions.d/post-functions.sh ]; then
  sed -i 's,SIZE=\$( stty size )$,SIZE=$( [[ $- != *i* ]] \&\& stty size || echo "0 0"),' \
    /usr/libexec/slackpkg/functions.d/post-functions.sh || true
fi

export TERSE=0
slackpkg_retry update

if grep -q '^DOWNLOAD_ALL=on' /etc/slackpkg/slackpkg.conf; then
  sed -i 's/^DOWNLOAD_ALL=on/DOWNLOAD_ALL=off/' /etc/slackpkg/slackpkg.conf
fi

for series in a ap d l n; do
  branch="slackware64/$series"
  log "Pré-instalando série Slackware com retry: $branch"
  slackpkg_retry install "$branch"
  rm -rf /var/cache/packages/* || true
done

log "Validando resultado do bootstrap"
for cmd in gcc ld make bc bison flex perl openssl makepkg installpkg wget sha256sum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERRO: comando obrigatório ausente após instalar as séries: $cmd"
    exit 1
  fi
done

test -f /usr/include/libelf.h
test -f /usr/include/openssl/opensslv.h

log "Bootstrap das séries concluído"
