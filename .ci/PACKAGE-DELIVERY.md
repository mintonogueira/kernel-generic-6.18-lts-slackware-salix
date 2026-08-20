# Política de entrega dos pacotes do kernel 6.18

Esta decisão pertence a este projeto e deve ser preservada em futuras alterações do workflow.

## Entrega obrigatória

Cada build validado do Linux 6.18 deve gerar e publicar três pacotes `.txz` nativos do Slackware:

1. `kernel-generic-lts618-<versão>-x86_64-<revisão>.txz`
   - kernel, `System.map`, `.config` e módulos correspondentes;
   - inclui suporte USB host ampliado;
   - inclui `rtw88_8821cu` para o adaptador USB Realtek `0bda:c820`.

2. `kernel-devel-lts618-<versão>-x86_64-<revisão>.txz`
   - árvore preparada em `/usr/src/linux-<versão>`;
   - fornece `/lib/modules/<versão>/build` e `source`;
   - inclui `.config`, `Module.symvers`, headers gerados, scripts e ferramentas necessárias para módulos externos;
   - deve ser validado compilando um módulo externo mínimo e conferindo `vermagic`.

3. `kernel-headers-<versão>-x86-<revisão>.txz`
   - cabeçalhos UAPI sanitizados gerados com `make headers_install`;
   - instala em `/usr/include` e assume o papel do `kernel-headers` do Slackware;
   - é conceitualmente diferente do `kernel-devel`.

## Regras de empacotamento

- Os três pacotes devem ser criados dentro de Slackware 15.0.
- Os três pacotes devem ser produzidos com o `makepkg` nativo do Slackware.
- Não substituir `makepkg` por `tar -cJf` ou empacotamento equivalente.
- Validar cada TXZ com `installpkg --warn` e `explodepkg`.
- Gerar SHA-256 individual para cada pacote.
- Publicar os três pacotes e seus checksums na GitHub Release.
- Baixar novamente os três ativos publicados e comparar os TXZ byte a byte com os artefatos locais.
- Após a validação remota, copiar os três TXZ e checksums para `packages/` na branch `main`.

## Instalação prevista

Kernel e árvore de desenvolvimento podem ser instalados como pacotes versionados:

```bash
sudo installpkg kernel-generic-lts618-<versão>-x86_64-<revisão>.txz
sudo installpkg kernel-devel-lts618-<versão>-x86_64-<revisão>.txz
```

O pacote `kernel-headers` possui o mesmo papel e caminhos do pacote tradicional do Slackware, portanto a substituição deve ser deliberada:

```bash
sudo upgradepkg --install-new kernel-headers-<versão>-x86-<revisão>.txz
```

O workflow não deve instalar esses pacotes automaticamente em uma máquina do usuário e não deve alterar automaticamente o bootloader.
