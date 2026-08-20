# Curva de aprendizagem consolidada do projeto

Este arquivo é memória técnica operacional deste projeto. Deve ser consultado antes de novos diagnósticos, alterações no workflow, mudanças de configuração do kernel, empacotamento ou automação de atualização.

## Regra de uso

- Não repetir abordagens já registradas em `.ci/FAILED-ATTEMPTS.md` sem uma nova razão técnica comprovada.
- Antes de corrigir falhas de CI, ler o erro concreto do job/step/log atual.
- Fazer a menor alteração necessária e validar o efeito antes de ampliar o escopo.
- Preservar kernels anteriores e nunca alterar automaticamente o bootloader.
- Manter toda a cadeia de build e empacotamento final dentro de Slackware 15.0, usando `makepkg` nativo.

## 1. Arquitetura de CI aceita

- GitHub runner Ubuntu é somente host/orquestrador.
- Build executado em container `aclemons/slackware:15.0`.
- `JOBS=2`.
- Bootstrap TLS é obrigatório antes do primeiro uso de `slackpkg` no container mínimo.
- Depois da instalação dos pacotes Slackware necessários, ativar a cadeia CA nativa do Slackware.
- Não usar `aclemons/slackware:15.0-full` como solução padrão.
- Não gerar TXZ em Ubuntu com `tar -cJf`; pacote final deve ser produzido com `makepkg` do Slackware.
- Validar TXZ com `installpkg --warn`, `explodepkg`, SHA-256 e, após publicação, download e comparação byte a byte.

## 2. Entrega obrigatória do kernel 6.18

Cada entrega validada deve produzir três pacotes Slackware nativos:

1. `kernel-generic-lts618-<versão>-x86_64-<revisão>.txz`
2. `kernel-devel-lts618-<versão>-x86_64-<revisão>.txz`
3. `kernel-headers-<versão>-x86-<revisão>.txz`

Os três devem:

- ser construídos no mesmo ambiente Slackware da execução;
- ter SHA-256 próprio;
- ser publicados na Release;
- ser baixados novamente e conferidos;
- ser copiados para `packages/` na branch `main` após a validação remota.

### kernel-generic

Contém kernel, `System.map`, `.config` e `/lib/modules/<versão>`.

A stack crítica de boot permanece incorporada onde já decidido: XFS, Btrfs, SATA/AHCI, device-mapper e dm-crypt, permitindo boot sem depender de initrd para esse conjunto.

### kernel-devel

É a árvore preparada para compilar módulos externos contra a versão exata do kernel. Deve fornecer:

- `/usr/src/linux-<versão>`;
- `.config`;
- `Module.symvers`;
- headers gerados;
- scripts e ferramentas de build necessárias;
- `/lib/modules/<versão>/build` e `source` apontando para a árvore preparada.

Validação obrigatória: compilar um módulo externo mínimo e confirmar `vermagic` correspondente.

### kernel-headers

É diferente do `kernel-devel`. Representa os cabeçalhos UAPI para `/usr/include`, gerados com `make headers_install` e empacotados como pacote Slackware.

Por usar os mesmos caminhos do `kernel-headers` tradicional, sua substituição deve ser deliberada com `upgradepkg --install-new`, e não uma coexistência inconsistente.

## 3. Suporte USB ampliado

Decisão atual: habilitar amplamente suporte USB host e drivers USB úteis, preferencialmente como módulos quando apropriado, evitando opções de teste/fuzz/gadget que não pertencem ao objetivo do host.

O workflow deve manter suporte a controladores host, storage/UAS, HID, serial/class, rede USB, Bluetooth USB, áudio USB, mídia USB e famílias comuns de Wi-Fi USB.

## 4. Realtek USB 0bda:c820

Hardware detectado:

- USB ID: `0bda:c820`;
- Realtek 802.11ac NIC;
- interface USB Wi-Fi detectada fisicamente, mas originalmente sem driver associado.

No kernel 6.18.45 anterior:

```text
CONFIG_RTW88=m
CONFIG_RTW88_CORE=m
CONFIG_RTW88_8821C=m
# CONFIG_RTW88_8821CU is not set
```

`modinfo rtw88_8821cu` retornava módulo inexistente.

Diagnóstico: o barramento USB funcionava; faltava o frontend USB nativo do RTL8821C.

Build obrigatório:

```text
CONFIG_RTW88_USB=m
CONFIG_RTW88_8821C=m
CONFIG_RTW88_8821CU=m
```

Validar também:

- existência de `rtw88_core.ko`, `rtw88_usb.ko`, `rtw88_8821c.ko`, `rtw88_8821cu.ko`;
- alias USB do módulo compatível com `0bda:c820`.

Não instalar driver Realtek out-of-tree enquanto o suporte nativo puder ser usado.

## 5. RTL8723BE PCIe e tempestade AER

Hardware confirmado:

- endpoint `0000:02:00.0`;
- Realtek RTL8723BE `10ec:b723`;
- subsystem Dell Wireless 1801 `10ec:8739`;
- driver `rtl8723be`;
- root port Intel `0000:00:1c.6`, `8086:a116`.

Sintoma:

- tempestade de AER `Correctable`, `Physical Layer`, `RxErr` no root port;
- contadores chegaram a dezenas/centenas de milhões, apesar do rate-limit reduzir o texto visível no `dmesg`.

Teste causal confirmado:

- com `rtl8723be aspm=1`, endpoint mostrava `ASPM L0s L1 Enabled` e os RxErr continuavam;
- com reload `rtl8723be aspm=0`, `LnkCtl` passou a `ASPM Disabled`;
- delta de `RxErr` durante 15 segundos foi exatamente `0`.

Correção específica:

```text
options rtl8723be aspm=0
```

Não usar como primeira solução:

- `pci=noaer`, pois apenas esconde AER globalmente;
- `pcie_aspm=off`, pois desativa ASPM globalmente;
- `setpci` permanente, pois não foi necessário após o teste causal bem-sucedido.

Não tratar isso como regressão exclusiva do kernel 6.18: o mesmo tipo de problema já havia aparecido anteriormente.

## 6. Salix, XFS e boot

Ao reinstalar Salix em XFS, uma entrada incorreta em `/etc/fstab` fez o boot tentar `e2fsck` na raiz XFS. A correção correta foi declarar explicitamente:

```text
UUID=<uuid-da-raiz>  /  xfs  defaults  1  0
```

O campo final `0` evita fsck tradicional sobre XFS.

Entradas obsoletas para dispositivos inexistentes, como `/dev/fd0`, podem fazer `findmnt --verify` falhar e devem ser tratadas separadamente.

O kernel antigo deve ser preservado como fallback. A configuração de systemd-boot usada neste projeto é do tipo BLS `.conf`, apontando diretamente para kernel copiado à ESP. O workflow e futuros scripts de atualização não devem editar bootloader automaticamente.

## 7. Problema antigo de módulos 5.15.63

No kernel antigo 5.15.63 houve `Exec format error` em módulos como Btrfs/zstd, apesar de `vermagic` aparentemente correspondente. A causa exata não foi provada, mas o conjunto parecia misturado/incompatível.

Aprendizado:

- não usar `--force` para carregar módulos;
- não concluir compatibilidade apenas por `vermagic` igual;
- verificar árvore real de módulos, dependências, origem e coerência do pacote.

No kernel 6.18 atual, Btrfs foi incorporado ao kernel, portanto `modprobe btrfs` não é teste funcional válido para essa configuração.

## 8. Convenções para scripts de diagnóstico

Preferência operacional deste projeto:

- scripts verificam premissas antes de modificar;
- fazem backup quando alteram configuração;
- validam depois da alteração;
- produzem relatório `.txt` no mesmo diretório do script.

Padrão de saída recomendado:

```sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT="$SCRIPT_DIR/nome-do-relatorio.txt"
```

Para scripts Bash existentes, já foi usado `BASH_SOURCE`; para o script final de atualização, a exigência é POSIX `/bin/sh`.

Evitar armadilhas observadas:

- `set -o pipefail` com `find | sort | head`, que pode abortar por SIGPIPE;
- `set -e` com `grep -c`/`grep` quando zero ocorrências é um resultado esperado;
- tratar nós sysfs de serviço como `:pcie001` como se fossem BDF PCI válidos;
- usar `...` literal em comandos destinados ao usuário.

## 9. Política do script final de atualização

Após a entrega dos três TXZ, deve existir no repositório um script estritamente POSIX `/bin/sh` que:

- descubra no próprio repositório a entrega validada mais recente;
- baixe os três TXZ e seus checksums;
- valide SHA-256 antes de qualquer instalação;
- use `pkgtools` nativos do Slackware;
- registre em texto tudo que fez;
- falhe de modo seguro se metadados, download ou checksum forem inconsistentes;
- nunca modifique GRUB, LILO, ELILO, systemd-boot, initrd, EFI entries ou qualquer outro mecanismo de boot.

Política de preservação:

- kernels de outras famílias/linhas devem ser instalados lado a lado e preservados;
- dentro da mesma linha LTS 6.18, uma versão patch mais nova (`6.18.x`) ou revisão maior do mesmo pacote pode atualizar/substituir os pacotes dessa própria linha;
- não apagar kernels antigos de famílias diferentes automaticamente.

O script deve tratar de forma coerente kernel, kernel-devel e kernel-headers.

## 10. Critério de conclusão do projeto atual

O monitoramento só deve ser encerrado quando:

1. os três TXZ estiverem compilados, validados, publicados e presentes em `packages/` no `main`;
2. o script POSIX de atualização estiver versionado, validado e documentado;
3. a política de preservação de kernels estiver documentada;
4. o README principal estiver atualizado com o resultado final, instalação, atualização, suporte USB/RTL8821CU e a regra de não tocar no bootloader;
5. as falhas novas ocorridas durante o processo tiverem sido registradas para não serem repetidas.

## Referências internas obrigatórias

Antes de futuras mudanças, consultar em conjunto:

- `.ci/FAILED-ATTEMPTS.md`
- `.ci/HARDWARE-DIAGNOSTICS.md`
- `.ci/PACKAGE-DELIVERY.md`
- `.ci/PROJECT-LEARNING.md`
- `.ci/LAST-SUCCESS.md`, quando existir uma entrega concluída atual
- `.ci/last-failure.log`, quando houver falha de CI recente
