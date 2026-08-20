# Diagnósticos de hardware e decisões do kernel

Este arquivo registra diagnósticos confirmados neste projeto para evitar repetir investigação já concluída e para orientar futuras configurações do kernel.

## 1. Wi-Fi PCIe Realtek RTL8723BE

Hardware observado:

- Endpoint PCIe: `0000:02:00.0`
- Vendor/device: `10ec:b723`
- Subsystem: `10ec:8739` — Dell Wireless 1801
- Driver: `rtl8723be`
- Root Port: `0000:00:1c.6`
- Root Port Intel: `8086:a116`

Diagnóstico confirmado:

- Com `rtl8723be aspm=1`, o endpoint ficava com `LnkCtl: ASPM L0s L1 Enabled`.
- O Root Port acumulava uma tempestade de erros AER corrigíveis do tipo `Physical Layer / RxErr`.
- Foram observadas dezenas de milhões de ocorrências, sem erros AER fatais ou não fatais.
- Teste controlado com `modprobe rtl8723be aspm=0` alterou o endpoint para `LnkCtl: ASPM Disabled`.
- Durante uma janela de 15 segundos com `aspm=0`, o delta de `RxErr` foi exatamente `0`.

Decisão:

```text
options rtl8723be aspm=0
```

A correção deve ser específica para o módulo `rtl8723be`.

Não usar como primeira solução:

- `pci=noaer` — apenas oculta os relatórios AER globalmente.
- `pcie_aspm=off` — desativa ASPM globalmente e afeta dispositivos não relacionados.
- `setpci` permanente — não é necessário para o diagnóstico confirmado atual.

## 2. Wi-Fi USB Realtek 802.11ac

Hardware observado via USB:

- USB ID: `0bda:c820`
- Identificação: Realtek Semiconductor Corp. 802.11ac NIC
- A interface USB Wi-Fi aparece como `Vendor Specific Class`, porém sem driver associado.
- As interfaces Bluetooth do mesmo conjunto são reconhecidas por `btusb`.

Configuração encontrada no kernel 6.18.45 instalado:

```text
CONFIG_RTW88=m
CONFIG_RTW88_CORE=m
CONFIG_RTW88_8821C=m
# CONFIG_RTW88_8821CU is not set
```

Também foi confirmado:

```text
modinfo: ERROR: Module rtw88_8821cu not found.
```

Diagnóstico confirmado:

O dispositivo USB é detectado fisicamente pelo barramento, mas o kernel atual não contém o módulo USB `rtw88_8821cu`. O suporte ao core RTL8821C existe, porém o frontend USB correspondente foi omitido da configuração.

Decisão de build:

- habilitar `CONFIG_RTW88_USB=m`;
- manter `CONFIG_RTW88_8821C=m`;
- habilitar `CONFIG_RTW88_8821CU=m`;
- validar que os módulos `rtw88_usb`, `rtw88_8821c`, `rtw88_8821cu` e `rtw88_core` existem no pacote;
- validar que `rtw88_8821cu` contém alias compatível com USB `0bda:c820`.

Não instalar driver Realtek externo/out-of-tree enquanto o driver nativo do kernel puder ser habilitado e validado.

## 3. Cabeçalhos e árvore de desenvolvimento do kernel 6.18

Decisão técnica:

O pacote Slackware `kernel-headers` instalado no sistema representa cabeçalhos UAPI usados pelo userspace e não deve ser substituído automaticamente apenas para acompanhar a versão do kernel em execução.

Para compilar módulos externos contra o kernel 6.18, o necessário é uma árvore de desenvolvimento preparada para a versão exata do kernel, contendo `.config`, cabeçalhos gerados, scripts de build e `Module.symvers`.

Por isso, este projeto deve gerar um pacote separado e versionado:

```text
kernel-devel-lts618-<versão>-x86_64-<build>.txz
```

Esse pacote deve instalar a árvore preparada em:

```text
/usr/src/linux-<versão>
```

e fornecer:

```text
/lib/modules/<versão>/build -> /usr/src/linux-<versão>
/lib/modules/<versão>/source -> /usr/src/linux-<versão>
```

A validação obrigatória deve compilar um módulo externo mínimo contra a árvore empacotada e confirmar `vermagic` correspondente à versão do kernel.

## 4. Revisão de pacote

A configuração do kernel mudou para adicionar suporte de hardware. Portanto o número de build do pacote Slackware deve ser incrementado, evitando publicar conteúdo diferente com exatamente o mesmo nome/revisão do pacote anterior.

Direção atual: build de pacote `2` para esta revisão de configuração.