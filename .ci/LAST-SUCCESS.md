# Última entrega TXZ concluída

- Kernel: 6.18.45
- Pacote kernel: kernel-generic-lts618-6.18.45-x86_64-2.txz
- SHA-256 kernel: 0922f8224cf32acab89892eb73e130b2d0ec9da5f1bd597166739d9b1fe1eb3f
- Pacote devel: kernel-devel-lts618-6.18.45-x86_64-2.txz
- SHA-256 devel: ead13faefe289ebed7a7cf5ba682dd1b393372ac2fdf202e3d7afaf5fbba719b
- Pacote headers: kernel-headers-6.18.45-x86-2.txz
- SHA-256 headers: 90ba54506302634318dbb704252ce2750285d0d18dae56ee0a8554ecbcfcb1d5
- Tag: kernel-6.18.45
- Release: https://github.com/mintonogueira/kernel-generic-6.18-lts-slackware-salix/releases/tag/kernel-6.18.45
- Workflow run: 32445287784
- Commit do workflow: b343f10e7336a3cf523cc4146931c18ed50970c7
- Ambiente de build: Slackware 15.0
- Empacotamento: makepkg nativo do Slackware para os três pacotes
- Validação kernel: installpkg --warn, explodepkg, módulos RTL8821CU e alias USB 0bda:c820
- Validação devel: installpkg --warn, explodepkg e compilação de módulo externo com vermagic correspondente
- Validação headers: make headers_install, installpkg --warn, explodepkg e compilação userspace de teste
- Validação remota: SHA-256 e download da Release comparado byte a byte

Instalação no Slackware/Salix:

```bash
sudo installpkg kernel-generic-lts618-6.18.45-x86_64-2.txz
sudo installpkg kernel-devel-lts618-6.18.45-x86_64-2.txz
sudo upgradepkg --install-new kernel-headers-6.18.45-x86-2.txz
```
