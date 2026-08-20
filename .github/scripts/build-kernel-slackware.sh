#!/bin/bash
set -Eeuo pipefail

JOBS="${JOBS:-2}"
WORKROOT="${WORKROOT:-/work}"
OUTPUT="$WORKROOT/output"
BUILDROOT="${BUILDROOT:-$WORKROOT/.kernel-build}"
DOWNLOAD="$BUILDROOT/download"
SRCROOT="$BUILDROOT/src"
PKGROOT="$BUILDROOT/pkgroot"
DEVELROOT="$BUILDROOT/develroot"
VERIFY="$BUILDROOT/verify"
VERIFY_DEVEL="$BUILDROOT/verify-devel"
TMPDIR="$BUILDROOT/tmp"
BOOTSTRAP_CA="${BOOTSTRAP_CA:-}"
CONFIG_SHA256="d5ef048c336d06d66673cbe425519a84f67748383db91c132c41e702a04dfc77"
MIRROR="https://mirrors.kernel.org/slackware/slackware64-15.0/"
PKGREV="2"

mkdir -p "$OUTPUT"
: > "$OUTPUT/build.log"
exec > >(tee -a "$OUTPUT/build.log") 2>&1

trap 'rc=$?; echo; echo "ERRO na linha $LINENO (status $rc)"; echo; df -h / /work 2>/dev/null || true; exit $rc' ERR

log() {
  printf '\n==== %s ====\n' "$*"
}

slackpkg_run() {
  set +e
  "$@"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 20 ]; then
    echo "ERRO: slackpkg terminou com status $rc: $*"
    return "$rc"
  fi
  return 0
}

configure_wget_ca() {
  local ca="$1"
  test -s "$ca"
  cat > /root/.wgetrc <<EOF_WGETRC
check_certificate = on
ca_certificate = $ca
EOF_WGETRC
  chmod 0600 /root/.wgetrc
  export WGETRC=/root/.wgetrc
}

kconfig_has_symbol() {
  local sym="$1"
  grep -RqsE "^[[:space:]]*(menu)?config[[:space:]]+${sym}([[:space:]]|$)" \
    Kconfig arch drivers fs kernel lib mm net sound security crypto 2>/dev/null
}

cfg_module_if_present() {
  local sym="$1"
  if kconfig_has_symbol "$sym"; then
    "$CFG" --module "$sym" || true
  fi
}

cfg_enable_if_present() {
  local sym="$1"
  if kconfig_has_symbol "$sym"; then
    "$CFG" --enable "$sym" || true
  fi
}

log "Ambiente Slackware 15.0"
cat /etc/slackware-version
grep -q '^Slackware 15\.0' /etc/slackware-version
test "$(uname -m)" = "x86_64"
echo "Arquitetura: $(uname -m)"
echo "Jobs: $JOBS"
df -h / /work || true

log "Bootstrap TLS seguro"
test -n "$BOOTSTRAP_CA"
configure_wget_ca "$BOOTSTRAP_CA"
wget -q --spider "${MIRROR}CHECKSUMS.md5.asc"
echo "Bootstrap TLS OK usando $BOOTSTRAP_CA"

log "Preparando slackpkg para ambiente não interativo"
printf '%s\n' "$MIRROR" > /etc/slackpkg/mirrors

if [ -f /usr/libexec/slackpkg/functions.d/post-functions.sh ]; then
  sed -i 's,SIZE=\$( stty size )$,SIZE=$( [[ $- != *i* ]] \&\& stty size || echo "0 0"),' \
    /usr/libexec/slackpkg/functions.d/post-functions.sh || true
fi

export TERSE=0
SLACKPKG=(slackpkg -default_answer=yes -batch=on)
slackpkg_run "${SLACKPKG[@]}" update

if grep -q '^DOWNLOAD_ALL=on' /etc/slackpkg/slackpkg.conf; then
  sed -i 's/^DOWNLOAD_ALL=on/DOWNLOAD_ALL=off/' /etc/slackpkg/slackpkg.conf
fi

for series in a ap d l n; do
  log "Instalando série Slackware: $series"
  slackpkg_run "${SLACKPKG[@]}" install "$series"
  rm -rf /var/cache/packages/* || true
done

log "Ativando cadeia CA nativa do Slackware"
command -v update-ca-certificates
update-ca-certificates --fresh
ldconfig
rm -rf /var/cache/packages/* || true

NATIVE_CA=""
for candidate in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem; do
  if [ -s "$candidate" ]; then
    NATIVE_CA="$candidate"
    break
  fi
done
test -n "$NATIVE_CA"
configure_wget_ca "$NATIVE_CA"
wget -q --spider "${MIRROR}CHECKSUMS.md5.asc"
echo "TLS nativo Slackware OK usando $NATIVE_CA"

log "Validando toolchain Slackware 15.0"
for cmd in \
  gcc ld make bc bison flex perl openssl \
  makepkg explodepkg installpkg depmod modinfo xz wget sha256sum \
  awk sed grep sort tar strip file find cp ln; do
  command -v "$cmd"
done

gcc --version | sed -n '1p'
ld -v
make --version | sed -n '1p'
openssl version
depmod -V

test -f /usr/include/libelf.h
test -f /usr/include/openssl/opensslv.h

rm -rf "$BUILDROOT"
mkdir -p "$DOWNLOAD" "$SRCROOT" "$PKGROOT" "$DEVELROOT" "$VERIFY" "$VERIFY_DEVEL" "$TMPDIR"
chmod 1777 "$TMPDIR"
export TMPDIR

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
    | tail -n 1
)"
test -n "$KERNEL_VERSION"

TARBALL="linux-${KERNEL_VERSION}.tar.xz"
PACKAGE_NAME="kernel-generic-lts618-${KERNEL_VERSION}-x86_64-${PKGREV}.txz"
DEVEL_PACKAGE_NAME="kernel-devel-lts618-${KERNEL_VERSION}-x86_64-${PKGREV}.txz"
RELEASE_TAG="kernel-${KERNEL_VERSION}"
CONFIG_NAME="slackware64-15.0-huge.s.config"
CONFIG_URL="${MIRROR}kernels/huge.s/config"

echo "Kernel: $KERNEL_VERSION"
echo "Pacote kernel: $PACKAGE_NAME"
echo "Pacote de desenvolvimento: $DEVEL_PACKAGE_NAME"

log "Baixando e verificando fonte do kernel"
wget --tries=5 --waitretry=2 -O "$DOWNLOAD/$TARBALL" \
  "https://cdn.kernel.org/pub/linux/kernel/v6.x/$TARBALL"
wget --tries=5 --waitretry=2 -O "$DOWNLOAD/sha256sums.asc" \
  "https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc"

EXPECTED="$(awk -v f="$TARBALL" '$2 == f {print $1; exit}' "$DOWNLOAD/sha256sums.asc")"
test -n "$EXPECTED"
printf '%s  %s\n' "$EXPECTED" "$DOWNLOAD/$TARBALL" | sha256sum -c -

log "Baixando e verificando config oficial Slackware64 15.0"
wget --tries=5 --waitretry=2 -O "$DOWNLOAD/$CONFIG_NAME" "$CONFIG_URL"
test -s "$DOWNLOAD/$CONFIG_NAME"
printf '%s  %s\n' "$CONFIG_SHA256" "$DOWNLOAD/$CONFIG_NAME" | sha256sum -c -

log "Preparando árvore do kernel"
tar -xJf "$DOWNLOAD/$TARBALL" -C "$SRCROOT"
SRC="$SRCROOT/linux-$KERNEL_VERSION"
cd "$SRC"
cp "$DOWNLOAD/$CONFIG_NAME" .config
make olddefconfig

CFG=./scripts/config
"$CFG" --set-str LOCALVERSION ""
"$CFG" --disable LOCALVERSION_AUTO
"$CFG" --disable WERROR || true

"$CFG" --enable MODULES
"$CFG" --enable MODULE_UNLOAD

"$CFG" --disable MODULE_SIG || true
"$CFG" --disable MODULE_SIG_ALL || true
"$CFG" --set-str SYSTEM_TRUSTED_KEYS ""
"$CFG" --set-str SYSTEM_REVOCATION_KEYS ""
"$CFG" --disable DEBUG_INFO || true
"$CFG" --enable DEBUG_INFO_NONE || true
"$CFG" --disable DEBUG_INFO_BTF || true
"$CFG" --disable DEBUG_INFO_BTF_MODULES || true
"$CFG" --disable RUST || true
"$CFG" --disable LTO || true
"$CFG" --enable LTO_NONE || true

"$CFG" --enable MODULE_COMPRESS_NONE || true
"$CFG" --disable MODULE_COMPRESS_GZIP || true
"$CFG" --disable MODULE_COMPRESS_XZ || true
"$CFG" --disable MODULE_COMPRESS_ZSTD || true

log "Configurando stack crítica de boot"
for sym in \
  BLK_DEV_INITRD DEVTMPFS DEVTMPFS_MOUNT TMPFS \
  EFI EFI_STUB EFIVAR_FS EFI_PARTITION \
  SCSI BLK_DEV_SD ATA SATA_AHCI \
  BLK_DEV_DM DM_CRYPT \
  XFS_FS BTRFS_FS EXT4_FS \
  ZSTD_COMPRESS ZSTD_DECOMPRESS; do
  "$CFG" --enable "$sym"
done

for sym in NVME_CORE BLK_DEV_NVME FAT_FS VFAT_FS HID HID_GENERIC USB_HID; do
  cfg_enable_if_present "$sym"
done

log "Habilitando suporte USB host abrangente"
for sym in \
  USB_SUPPORT USB USB_COMMON USB_PCI \
  USB_XHCI_HCD USB_XHCI_PCI \
  USB_EHCI_HCD USB_EHCI_PCI \
  USB_OHCI_HCD USB_OHCI_HCD_PCI \
  USB_UHCI_HCD \
  USB_STORAGE USB_UAS \
  USB_HID HID_GENERIC \
  USB_ACM USB_WDM \
  USB_USBNET \
  BT BT_HCIBTUSB; do
  cfg_enable_if_present "$sym"
done

USB_KCONFIG_DIRS=(
  drivers/usb/core
  drivers/usb/host
  drivers/usb/storage
  drivers/usb/class
  drivers/usb/serial
  drivers/usb/misc
  drivers/usb/typec
  drivers/usb/roles
  drivers/net/usb
  sound/usb
  drivers/media/usb
  drivers/bluetooth
)

USB_SYMBOLS="$TMPDIR/usb-symbols.txt"
: > "$USB_SYMBOLS"
for dir in "${USB_KCONFIG_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  find "$dir" -type f -name 'Kconfig*' -print0 \
    | xargs -0 awk '$1=="config" || $1=="menuconfig" {print $2}' \
    >> "$USB_SYMBOLS" || true
done

sort -u "$USB_SYMBOLS" -o "$USB_SYMBOLS"
while IFS= read -r sym; do
  [ -n "$sym" ] || continue
  case "$sym" in
    *TEST*|*FUZZ*|USB_RAW_GADGET|USB_GADGET|USB_DUMMY_HCD|USB_ZERO)
      continue
      ;;
  esac
  "$CFG" --module "$sym" || true
done < "$USB_SYMBOLS"

log "Habilitando rede USB e Wi-Fi USB amplamente"
for sym in \
  USB_NET_AX8817X USB_NET_AX88179_178A USB_NET_CDCETHER USB_NET_CDC_EEM \
  USB_NET_CDC_NCM USB_NET_CDC_MBIM USB_NET_RNDIS_HOST USB_NET_SMSC95XX \
  USB_NET_LAN78XX USB_NET_MCS7830 USB_NET_SR9700 USB_RTL8150 USB_RTL8152 \
  WLAN CFG80211 MAC80211 WLAN_VENDOR_REALTEK RTW88 RTW88_CORE RTW88_USB \
  RTW88_8821C RTW88_8821CU RTW88_8822BU RTW88_8822CU RTW88_8723DU \
  RTW88_8821AU RTW88_8812AU RTW88_8814AU \
  RTL8XXXU RTL8192CU RTL8187 \
  ATH9K_HTC CARL9170 ZD1211RW MT7601U MT76_USB MT76X0U MT76X2U \
  RT2X00 RT2800USB RT73USB; do
  cfg_module_if_present "$sym"
done

for sym in RTW88_USB RTW88_8821C RTW88_8821CU; do
  kconfig_has_symbol "$sym" || {
    echo "ERRO: CONFIG_${sym} não existe no kernel $KERNEL_VERSION"
    exit 1
  }
  "$CFG" --module "$sym"
done

make olddefconfig

log "Validando configuração crítica"
for symbol in \
  MODULES SCSI BLK_DEV_SD ATA SATA_AHCI \
  BLK_DEV_DM DM_CRYPT XFS_FS BTRFS_FS EXT4_FS \
  EFI EFI_STUB ZSTD_COMPRESS ZSTD_DECOMPRESS; do
  if ! grep -q "^CONFIG_${symbol}=y$" .config; then
    echo "ERRO: CONFIG_${symbol} não ficou =y"
    grep -E "^CONFIG_${symbol}=|^# CONFIG_${symbol} is not set" .config || true
    exit 1
  fi
done

log "Validando USB/RTL8821CU obrigatório"
for symbol in RTW88_USB RTW88_8821C RTW88_8821CU; do
  if ! grep -q "^CONFIG_${symbol}=m$" .config; then
    echo "ERRO: CONFIG_${symbol} não ficou =m"
    grep -E "^CONFIG_${symbol}=|^# CONFIG_${symbol} is not set" .config || true
    exit 1
  fi
done

for symbol in USB USB_XHCI_HCD USB_STORAGE; do
  if ! grep -Eq "^CONFIG_${symbol}=(y|m)$" .config; then
    echo "ERRO: CONFIG_${symbol} não foi habilitado"
    grep -E "^CONFIG_${symbol}=|^# CONFIG_${symbol} is not set" .config || true
    exit 1
  fi
done

echo "Resumo USB habilitado:"
grep -E '^CONFIG_(USB|RTW88|RTL8|RTL81|ATH9K_HTC|CARL9170|ZD1211RW|MT76|RT2X00|RT2800USB|RT73USB)' .config \
  | sed -n '1,300p' || true

RELEASE="$(make -s kernelrelease)"
test "$RELEASE" = "$KERNEL_VERSION"
cp .config "$OUTPUT/config-${RELEASE}.final"

log "Espaço antes da compilação"
df -h / /work || true

log "Compilando com ${JOBS} jobs"
export KBUILD_BUILD_USER=github-actions
export KBUILD_BUILD_HOST=slackware15
make -j"$JOBS" bzImage modules

test -s arch/x86/boot/bzImage
test -s System.map
test -s Module.symvers

log "Validando módulos RTL8821CU compilados"
for mod in rtw88_core rtw88_usb rtw88_8821c rtw88_8821cu; do
  path="$(find "$SRC/drivers/net/wireless/realtek/rtw88" -type f -name "${mod}.ko" -print | awk 'NR==1{print; exit}')"
  test -n "$path"
  test -s "$path"
  echo "$mod -> $path"
done

RTW8821CU_KO="$(find "$SRC/drivers/net/wireless/realtek/rtw88" -type f -name 'rtw88_8821cu.ko' -print | awk 'NR==1{print; exit}')"
modinfo -F alias "$RTW8821CU_KO" | grep -Eiq 'usb:v0BDApC820'
echo "Alias USB 0bda:c820 confirmado em rtw88_8821cu."

log "Montando pacote principal Slackware"
rm -rf "$PKGROOT"
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
depmod -b "$PKGROOT" "$RELEASE"

cat > "$PKGROOT/usr/doc/kernel-generic-lts618-$RELEASE/README" <<EOF_README
Linux $RELEASE para Slackware/Salix x86_64.

Compilado dentro de Slackware 15.0 e empacotado com o makepkg nativo do
Slackware.

Conteúdo principal:
  /boot/vmlinuz-$RELEASE
  /boot/System.map-$RELEASE
  /boot/config-$RELEASE
  /lib/modules/$RELEASE/

XFS, Btrfs, SATA/AHCI, device-mapper e dm-crypt são incorporados ao kernel.
Esta revisão amplia fortemente o suporte USB host e inclui o driver nativo
rtw88_8821cu para o adaptador Realtek USB 0bda:c820.
O pacote usa nomes versionados, preserva kernels anteriores e não altera o
bootloader automaticamente.
EOF_README

cat > "$PKGROOT/install/slack-desc" <<EOF_DESC
kernel-generic-lts618: kernel-generic-lts618 (Linux $RELEASE LTS)
kernel-generic-lts618:
kernel-generic-lts618: Kernel Linux $RELEASE para Slackware/Salix x86_64.
kernel-generic-lts618: Compilado dentro de Slackware 15.0.
kernel-generic-lts618: Empacotado com o makepkg nativo do Slackware.
kernel-generic-lts618: Inclui kernel e módulos correspondentes.
kernel-generic-lts618: Inclui amplo suporte USB host e Wi-Fi USB.
kernel-generic-lts618: Inclui rtw88_8821cu para Realtek USB 0bda:c820.
kernel-generic-lts618: XFS/Btrfs/SATA/AHCI/dm-crypt ficam built-in.
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

log "Criando TXZ principal com makepkg nativo"
rm -f "$OUTPUT/$PACKAGE_NAME" "$OUTPUT/$PACKAGE_NAME.sha256"
cd "$PKGROOT"
makepkg -l y -c n "$OUTPUT/$PACKAGE_NAME"
test -s "$OUTPUT/$PACKAGE_NAME"

log "Validando TXZ principal com pkgtools Slackware"
installpkg --warn "$OUTPUT/$PACKAGE_NAME" >/dev/null
rm -rf "$VERIFY"
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

for mod in rtw88_core rtw88_usb rtw88_8821c rtw88_8821cu; do
  test -n "$(find "lib/modules/$RELEASE" -type f -name "${mod}.ko*" -print | awk 'NR==1{print; exit}')"
done

log "Montando pacote kernel-devel preparado para módulos externos"
rm -rf "$DEVELROOT"
DEVEL_SRC="$DEVELROOT/usr/src/linux-$RELEASE"
mkdir -p \
  "$DEVEL_SRC" \
  "$DEVELROOT/lib/modules/$RELEASE" \
  "$DEVELROOT/usr/doc/kernel-devel-lts618-$RELEASE" \
  "$DEVELROOT/install"

cp -a "$SRC/Makefile" "$DEVEL_SRC/"
[ -f "$SRC/Kbuild" ] && cp -a "$SRC/Kbuild" "$DEVEL_SRC/"
[ -f "$SRC/Kconfig" ] && cp -a "$SRC/Kconfig" "$DEVEL_SRC/"
cp -a "$SRC/.config" "$SRC/Module.symvers" "$DEVEL_SRC/"
cp -a "$SRC/include" "$DEVEL_SRC/"
mkdir -p "$DEVEL_SRC/arch/x86"
cp -a "$SRC/arch/x86/include" "$DEVEL_SRC/arch/x86/"
find "$SRC/arch/x86" -maxdepth 1 -type f -name 'Makefile*' -exec cp -a {} "$DEVEL_SRC/arch/x86/" \;
cp -a "$SRC/scripts" "$DEVEL_SRC/"
mkdir -p "$DEVEL_SRC/tools"
for d in objtool include lib; do
  if [ -e "$SRC/tools/$d" ]; then
    cp -a "$SRC/tools/$d" "$DEVEL_SRC/tools/"
  fi
done

ln -s "/usr/src/linux-$RELEASE" "$DEVELROOT/lib/modules/$RELEASE/build"
ln -s "/usr/src/linux-$RELEASE" "$DEVELROOT/lib/modules/$RELEASE/source"

cat > "$DEVELROOT/usr/doc/kernel-devel-lts618-$RELEASE/README" <<EOF_DEVEL
Árvore de desenvolvimento preparada para Linux $RELEASE.

Destinada à compilação de módulos externos contra exatamente este kernel.
Não substitui automaticamente o pacote Slackware kernel-headers usado como
UAPI do userspace.

Árvore:
  /usr/src/linux-$RELEASE

Links:
  /lib/modules/$RELEASE/build
  /lib/modules/$RELEASE/source
EOF_DEVEL

cat > "$DEVELROOT/install/slack-desc" <<EOF_DEVEL_DESC
kernel-devel-lts618: kernel-devel-lts618 (build tree Linux $RELEASE)
kernel-devel-lts618:
kernel-devel-lts618: Árvore preparada para compilar módulos externos.
kernel-devel-lts618: Corresponde exatamente ao kernel Linux $RELEASE.
kernel-devel-lts618: Inclui .config, Module.symvers, headers gerados,
kernel-devel-lts618: scripts e ferramentas de build necessárias.
kernel-devel-lts618: Instala em /usr/src/linux-$RELEASE.
kernel-devel-lts618: Fornece links build/source em /lib/modules/$RELEASE.
kernel-devel-lts618: Não substitui automaticamente kernel-headers do Slackware.
kernel-devel-lts618:
kernel-devel-lts618:
kernel-devel-lts618: Projeto kernel-generic-6.18-lts-slackware-salix
EOF_DEVEL_DESC

find "$DEVELROOT" -type d -exec chmod 0755 {} +
chmod -R a+rX "$DEVELROOT"

log "Criando TXZ kernel-devel com makepkg nativo"
rm -f "$OUTPUT/$DEVEL_PACKAGE_NAME" "$OUTPUT/$DEVEL_PACKAGE_NAME.sha256"
cd "$DEVELROOT"
makepkg -l y -c n "$OUTPUT/$DEVEL_PACKAGE_NAME"
test -s "$OUTPUT/$DEVEL_PACKAGE_NAME"

log "Validando TXZ kernel-devel e compilando módulo externo mínimo"
installpkg --warn "$OUTPUT/$DEVEL_PACKAGE_NAME" >/dev/null
rm -rf "$VERIFY_DEVEL"
mkdir -p "$VERIFY_DEVEL"
cd "$VERIFY_DEVEL"
explodepkg "$OUTPUT/$DEVEL_PACKAGE_NAME"

test -s "usr/src/linux-$RELEASE/.config"
test -s "usr/src/linux-$RELEASE/Module.symvers"
test -d "usr/src/linux-$RELEASE/include/generated"
test -d "usr/src/linux-$RELEASE/arch/x86/include/generated"
test -L "lib/modules/$RELEASE/build"
test -L "lib/modules/$RELEASE/source"

EXTMOD="$TMPDIR/extmod"
rm -rf "$EXTMOD"
mkdir -p "$EXTMOD"
cat > "$EXTMOD/hello.c" <<'EOF_EXT_C'
#include <linux/init.h>
#include <linux/module.h>

static int __init hello_init(void) { return 0; }
static void __exit hello_exit(void) { }

module_init(hello_init);
module_exit(hello_exit);
MODULE_LICENSE("GPL");
EOF_EXT_C

cat > "$EXTMOD/Makefile" <<'EOF_EXT_MAKE'
obj-m += hello.o
EOF_EXT_MAKE

make -C "$VERIFY_DEVEL/usr/src/linux-$RELEASE" M="$EXTMOD" modules
test -s "$EXTMOD/hello.ko"
VERMAGIC="$(modinfo -F vermagic "$EXTMOD/hello.ko")"
echo "Vermagic módulo externo: $VERMAGIC"
printf '%s\n' "$VERMAGIC" | grep -q "^${RELEASE}[[:space:]]"

log "Gerando checksums"
cd "$OUTPUT"
sha256sum "$PACKAGE_NAME" > "$PACKAGE_NAME.sha256"
sha256sum "$DEVEL_PACKAGE_NAME" > "$DEVEL_PACKAGE_NAME.sha256"
sha256sum -c "$PACKAGE_NAME.sha256"
sha256sum -c "$DEVEL_PACKAGE_NAME.sha256"

cat > meta.env <<EOF_META
KERNEL_VERSION=$KERNEL_VERSION
PACKAGE_NAME=$PACKAGE_NAME
DEVEL_PACKAGE_NAME=$DEVEL_PACKAGE_NAME
RELEASE_TAG=$RELEASE_TAG
CONFIG_NAME=$CONFIG_NAME
PACKAGE_REVISION=$PKGREV
MODULE_COUNT=$MODULE_COUNT
EOF_META

chmod -R a+rX "$OUTPUT"

log "Pacotes concluídos"
ls -lh \
  "$PACKAGE_NAME" "$PACKAGE_NAME.sha256" \
  "$DEVEL_PACKAGE_NAME" "$DEVEL_PACKAGE_NAME.sha256" \
  "config-${RELEASE}.final"
cat "$PACKAGE_NAME.sha256"
cat "$DEVEL_PACKAGE_NAME.sha256"
echo "Módulos no pacote principal: $MODULE_COUNT"
df -h / /work || true
