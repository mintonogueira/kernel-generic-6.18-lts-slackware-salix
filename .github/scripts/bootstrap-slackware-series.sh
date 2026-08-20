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
  local attempt=1 rc=0

  while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    echo "slackpkg tentativa $attempt/$MAX_ATTEMPTS: $*"

    set +e
    slackpkg -default_answer=yes -batch=on "$@"
    rc=$?
    set -e

    if [ "$rc" -eq 0 ] || [ "$rc" -eq 20 ]; then
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
  log "Pré-instalando série Slackware com retry: $series"
  slackpkg_retry install "$series"
  rm -rf /var/cache/packages/* || true
done

log "Bootstrap das séries concluído"
