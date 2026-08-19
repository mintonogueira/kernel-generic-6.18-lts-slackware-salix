# Kernel Generic 6.18 LTS para Slackware/Salix

Build automatizado do kernel Linux 6.18 LTS para sistemas Slackware/Salix x86_64.

O GitHub Actions detecta a versão mais recente da série 6.18.x, compila o kernel e os módulos, monta um pacote `.txz` instalável com `installpkg` e publica o pacote em GitHub Releases.

O pacote preserva arquivos versionados em `/boot` e `/lib/modules`, sem remover automaticamente o kernel anterior nem alterar o gerenciador de boot.
