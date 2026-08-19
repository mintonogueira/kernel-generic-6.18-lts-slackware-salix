#!/bin/bash
set -Eeuo pipefail

JOBS="${JOBS:-2}"
WORKROOT="${WORKROOT:-/work}"
INPUT="$WORKROOT/input"
BUILD="$WORKROOT/build"
OUTPUT="$WORKROOT/output"
TMPDIR="$WORKROOT/tmp"

mkdir -p "$INPUT" "$BUILD" "$OUTPUT" "$TMPDIR"
chmod 1777 "$TMPDIR"
export TMPDIR

exec > >(tee "$OUTPUT/build.log") 2>&1

trap 'rc=$?; echo; echo "ERRO na linha $LINENO (status $rc)"; exit $rc' ERR

log() {
  printf '\n==== %s ====\n' "$*"
}

log "Ambiente Slackware"
cat /etc/slackware-version
test "$(uname -m)" = "x86_64"
echo "Arquitetura: $(uname -m)"

log "Atualizando slackpkg"
SLACKPKG=(slackpkg -batch=on -default_answer=y)
"${SLACKPKG[@]}" update gpg || true
"${SLACKPKG[@]}" update

log "Instalando toolchain"
"${SLACKPKG[@]}" install \
  aaa_libraries \
  ca-certificates \
  wget \
  binutils \
  gcc \
  glibc \
  kernel-headers \
  make \
  bc \
  bison \
  flex \
  m4 \
  perl \
  openssl \
  openssl-solibs \
  elfutils \
  pkg-config \
  gmp \
  mpfr \
  libmpc \
  isl \
  guile \
  gc \
  libunistring \
  libffi \
  zlib \
  bzip2 \
  xz \
  zstd \
  kmod \
  cpio \
  patch \
  diffutils \
  file

update-ca-certificates || true
ldconfig

log "Validando toolchain"
for cmd in gcc ld make bc bison flex perl openssl makepkg explodepkg depmod xz wget sha256sum awk sed grep sort tar; do
  command -v "$cmd"
done

gcc --version | head -1
ld -v
make --version | head -1
openssl version
depmod -V

test -f /usr/include/libelf.h
test -f /usr/include/openssl/opensslv.h
printf '#include <stdio.h>\nint main(void){puts("toolchain-ok");return 0;}\n' > "$TMPDIR/toolchain-test.c"
gcc "$TMPDIR/toolchain-test.c" -o "$TMPDIR/toolchain-test"
"$TMPDIR/toolchain-test"

log "Detectando Linux 6.18.x mais recente"
KERNEL_INDEX="$(wget -qO- https://cdn.kernel.org/pub/linux/kernel/v6.x/)"
KERNEL_VERSION="$(
  printf '%s\n' "$KERNEL_INDEX" \
    | grep -oE 'linux-6\.18\.[0-9]+\.tar\.xz' \
    | sed -e 's/^linux-//' -e 's/\.tar\.xz$//' \
    | sort -Vu \
    | tail -1
)"
test -n "$KERNEL_VERSION"
TARBALL="linux-${KERNEL_VERSION}.tar.xz"
PACKAGE_NAME="kernel-generic-lts618-${KERNEL_VERSION}-x86_64-1.txz"
RELEASE_TAG="kernel-${KERNEL_VERSION}"
echo "Kernel: $KERNEL_VERSION"
echo "Pacote: $PACKAGE_NAME"

log "Detectando configuração Slackware-current 6.18 x86_64"
CONFIG_BASE_URL="https://mirrors.slackware.com/slackware/slackware64-current/source/k618/kernel-configs"
CONFIG_INDEX="$(wget -qO- "$CONFIG_BASE_URL/")"
CONFIG_NAME="$(
  printf '%s\n' "$CONFIG_INDEX" \
    | grep -oE 'config-6\.18\.[0-9]+\.x64' \
    | sort -Vu \
    | tail -1
)"
test -n "$CONFIG_NAME"
echo "Configuração-base: $CONFIG_NAME"

log "Baixando e verificando fonte do kernel"
rm -f "$INPUT/$TARBALL" "$INPUT/sha256sums.asc" "$INPUT/$CONFIG_NAME"
wget -O "$INPUT/$TARBALL" "https://cdn.kernel.org/pub/linux/kernel/v6.x/$TARBALL"
wget -O "$INPUT/sha256sums.asc" "https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc"
EXPECTED="$(awk -v f="$TARBALL" '$2 == f {print $1; exit}' "$INPUT/sha256sums.asc")"
test -n "$EXPECTED"
printf '%s  %s\n' "$EXPECTED" "$INPUT/$TARBALL" | sha256sum -c -

log "Baixando configuração oficial do Slackware"
wget -O "$INPUT/$CONFIG_NAME" "$CONFIG_BASE_URL/$CONFIG_NAME"
test -s "$INPUT/$CONFIG_NAME"

log "Preparando árvore do kernel"
SRC="$BUILD/linux-$KERNEL_VERSION"
PKGROOT="$BUILD/pkgroot"
VERIFY="$BUILD/verify"
rm -rf "$SRC" "$PKGROOT" "$VERIFY"
tar -xJf "$INPUT/$TARBALL" -C "$BUILD"
cd "$SRC"
cp "$INPUT/$CONFIG_NAME" .config
make olddefconfig

CFG=./scripts/config
"$CFG" --set-str LOCALVERSION ""
"$CFG" --disable LOCALVERSION_AUTO

# Mantém suporte amplo a módulos, mas remove dependências opcionais de CI.
"$CFG" --enable MODULES
"$CFG" --enable MODULE_UNLOAD
"$CFG" --disable MODULE_SIG || true
"$CFG" --disable MODULE_SIG_ALL || true
"$CFG" --set-str SYSTEM_TRUSTED_KEYS ""
"$CFG" --set-str SYSTEM_REVOCATION_KEYS ""
"$CFG" --disable DEBUG_INFO || true
"$CFG" --disable DEBUG_INFO_BTF || true
"$CFG" --disable RUST || true
"$CFG" --disable LTO || true
"$CFG" --enable LTO_NONE || true

# Módulos sem compressão para máxima compatibilidade com o kmod do Salix 15.0.
"$CFG" --enable MODULE_COMPRESS_NONE || true
"$CFG" --disable MODULE_COMPRESS_GZIP || true
"$CFG" --disable MODULE_COMPRESS_XZ || true
"$CFG" --disable MODULE_COMPRESS_ZSTD || true

# Boot sem initrd para o root XFS atual: stack crítica incorporada.
"$CFG" --enable BLK_DEV_INITRD
"$CFG" --enable DEVTMPFS
"$CFG" --enable DEVTMPFS_MOUNT
"$CFG" --enable TMPFS
"$CFG" --enable EFI
"$CFG" --enable EFI_STUB
"$CFG" --enable EFIVAR_FS
"$CFG" --enable EFI_PARTITION
"$CFG" --enable SCSI
"$CFG" --enable BLK_DEV_SD
"$CFG" --enable ATA
"$CFG" --enable SATA_AHCI
"$CFG" --enable BLK_DEV_DM
"$CFG" --enable DM_CRYPT
"$CFG" --enable XFS_FS
"$CFG" --enable BTRFS_FS
"$CFG" --enable EXT4_FS

# Suporte adicional comum.
"$CFG" --enable NVME_CORE || true
"$CFG" --enable BLK_DEV_NVME || true
"$CFG" --enable FAT_FS || true
"$CFG" --enable VFAT_FS || true

make olddefconfig

log "Validando configuração crítica"
for symbol in \
  MODULES DEVTMPFS SCSI BLK_DEV_SD ATA SATA_AHCI \
  BLK_DEV_DM DM_CRYPT XFS_FS BTRFS_FS EXT4_FS EFI EFI_STUB; do
  if ! grep -q "^CONFIG_${symbol}=y$" .config; then
    echo "CONFIG_${symbol} não ficou =y"
    grep -E "^CONFIG_${symbol}=|^# CONFIG_${symbol} is not set" .config || true
    exit 1
  fi
done

RELEASE="$(make -s kernelrelease)"
test "$RELEASE" = "$KERNEL_VERSION"
cp .config "$OUTPUT/config-${RELEASE}.final"

log "Compilando com ${JOBS} jobs"
make -j"$JOBS" bzImage modules

test -s arch/x86/boot/bzImage
test -s System.map

log "Montando pacote Slackware"
mkdir -p \
  "$PKGROOT/boot" \
  "$PKGROOT/lib/modules" \
  "$PKGROOT/usr/doc/kernel-generic-lts618-$RELEASE" \
  "$PKGROOT/install"

cp arch/x86/boot/bzImage "$PKGROOT/boot/vmlinuz-$RELEASE"
cp System.map "$PKGROOT/boot/System.map-$RELEASE"
cp .config "$PKGROOT/boot/config-$RELEASE"

make modules_install INSTALL_MOD_PATH="$PKGROOT" INSTALL_MOD_STRIP=1
rm -f "$PKGROOT/lib/modules/$RELEASE/build" "$PKGROOT/lib/modules/$RELEASE/source"

cat > "$PKGROOT/usr/doc/kernel-generic-lts618-$RELEASE/README" <<EOF_README
Linux $RELEASE para Slackware/Salix x86_64.

Compilado dentro de um container Slackware-current e empacotado com o
makepkg nativo do Slackware.

Conteúdo principal:
  /boot/vmlinuz-$RELEASE
  /boot/System.map-$RELEASE
  /boot/config-$RELEASE
  /lib/modules/$RELEASE/

XFS, Btrfs, SATA/AHCI, device-mapper e dm-crypt são incorporados ao kernel.
O pacote usa nomes versionados, preserva kernels anteriores e não altera o
bootloader automaticamente.
EOF_README

cat > "$PKGROOT/install/slack-desc" <<EOF_DESC
kernel-generic-lts618: kernel-generic-lts618 (Linux $RELEASE LTS)
kernel-generic-lts618:
kernel-generic-lts618: Kernel Linux $RELEASE para Slackware/Salix x86_64.
kernel-generic-lts618: Compilado em ambiente Slackware-current.
kernel-generic-lts618: Empacotado com o makepkg nativo do Slackware.
kernel-generic-lts618: Inclui kernel e módulos correspondentes.
kernel-generic-lts618: XFS e Btrfs são incorporados ao kernel.
kernel-generic-lts618: SATA/AHCI, dm-crypt e device-mapper ficam built-in.
kernel-generic-lts618: Usa nomes versionados e preserva kernels anteriores.
kernel-generic-lts618:
kernel-generic-lts618: Projeto kernel-generic-6.18-lts-slackware-salix
EOF_DESC

cat > "$PKGROOT/install/doinst.sh" <<EOF_DOINST
#!/bin/sh
if [ -x /sbin/depmod ]; then
  /sbin/depmod $RELEASE >/dev/null 2>&1 || true
fi
exit 0
EOF_DOINST
chmod 0755 "$PKGROOT/install/doinst.sh"
find "$PKGROOT" -type d -exec chmod 0755 {} +
chmod 0644 \
  "$PKGROOT/boot/vmlinuz-$RELEASE" \
  "$PKGROOT/boot/System.map-$RELEASE" \
  "$PKGROOT/boot/config-$RELEASE"

log "Criando TXZ com makepkg"
rm -f "$OUTPUT/$PACKAGE_NAME" "$OUTPUT/$PACKAGE_NAME.sha256"
cd "$PKGROOT"
makepkg -l y -c n "$OUTPUT/$PACKAGE_NAME"
test -s "$OUTPUT/$PACKAGE_NAME"

log "Validando TXZ com explodepkg"
mkdir -p "$VERIFY"
cd "$VERIFY"
explodepkg "$OUTPUT/$PACKAGE_NAME"
test -s "boot/vmlinuz-$RELEASE"
test -s "boot/System.map-$RELEASE"
test -s "boot/config-$RELEASE"
test -d "lib/modules/$RELEASE"
test -s "install/slack-desc"
test -x "install/doinst.sh"
MODULE_COUNT="$(find "lib/modules/$RELEASE" -type f -name '*.ko*' | wc -l)"
test "$MODULE_COUNT" -gt 0

cd "$OUTPUT"
sha256sum "$PACKAGE_NAME" > "$PACKAGE_NAME.sha256"
sha256sum -c "$PACKAGE_NAME.sha256"

cat > meta.env <<EOF_META
KERNEL_VERSION=$KERNEL_VERSION
PACKAGE_NAME=$PACKAGE_NAME
RELEASE_TAG=$RELEASE_TAG
CONFIG_NAME=$CONFIG_NAME
MODULE_COUNT=$MODULE_COUNT
EOF_META

log "Pacote concluído"
ls -lh "$PACKAGE_NAME" "$PACKAGE_NAME.sha256" "config-${RELEASE}.final"
cat "$PACKAGE_NAME.sha256"
echo "Módulos no pacote: $MODULE_COUNT"
