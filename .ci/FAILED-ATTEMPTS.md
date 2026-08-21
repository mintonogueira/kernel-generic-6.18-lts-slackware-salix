# Tentativas de CI que não devem ser repetidas

Este arquivo registra decisões negativas deste projeto para impedir que falhas já conhecidas sejam reintroduzidas em futuras alterações do workflow.

## Regra

Antes de alterar `.github/workflows/build-kernel.yml` ou `.github/scripts/build-kernel-slackware.sh`, revisar este arquivo e não reutilizar abordagens abaixo sem uma razão técnica nova e explicitamente verificada.

## Abordagens já descartadas

1. **Gerar o pacote Slackware em Ubuntu apenas com `tar -cJf`.**
   - Não atende ao objetivo deste projeto de gerar o `.txz` pelo `makepkg` nativo do Slackware.
   - O build e o empacotamento do pacote final devem ocorrer dentro de Slackware.

2. **Executar o job inteiro do GitHub Actions dentro de um container Slackware mínimo e depender de Actions de terceiros dentro dele.**
   - Essa arquitetura adicionou fragilidade desnecessária ao ambiente do job.
   - Preferência atual: runner GitHub Ubuntu apenas como host/orquestrador; compilação e `makepkg` executados explicitamente dentro do container Slackware via `docker run`.

3. **Usar `aclemons/slackware:15.0-full` como solução padrão.**
   - A imagem completa é excessivamente grande para este workflow e aumenta muito custo de pull, extração e uso de disco.
   - Não voltar para essa imagem apenas para contornar dependências ausentes.

4. **Usar `aclemons/slackware:15.0` e chamar `slackpkg` por HTTPS antes de disponibilizar uma cadeia CA confiável.**
   - Falha observada: `Unable to locally verify the issuer's authority` ao acessar `https://mirrors.kernel.org/...`.
   - Como consequência, as séries `a`, `ap`, `d`, `l` e `n` não eram instaladas e o toolchain não existia.

5. **Chamar `update-ca-certificates` antes de o pacote correspondente estar disponível no container mínimo.**
   - Falha observada: `update-ca-certificates: command not found`.
   - O bootstrap TLS precisa ocorrer antes do `slackpkg`; só depois o ambiente Slackware pode instalar/atualizar seus próprios certificados.

6. **Alterar repetidamente imagem, arquitetura ou configuração do kernel sem primeiro ler o erro exato da execução anterior.**
   - Toda nova correção deve partir do log concreto da última falha.
   - `.ci/last-failure.log` e os artifacts do Actions devem ser usados como fonte de diagnóstico.

7. **Tratar `slackpkg install a` como forma garantida de instalar a série `a` no container mínimo.**
   - Na execução `32378454480`, o `slackpkg` respondeu `No packages match the pattern for install` e retornou status 20.
   - O wrapper não deve interpretar status 20 como sucesso quando o objetivo é instalar uma série obrigatória: é necessário confirmar que o branch/série realmente resolveu pacotes e que o toolchain esperado foi instalado.
   - A instalação das séries deve usar uma seleção explícita baseada na localização oficial dos pacotes ou outro mecanismo verificável do próprio Slackware, e deve falhar se a seleção resultar vazia.

8. **Tratar qualquer status diferente de zero do `explodepkg` como falha antes de verificar o conteúdo extraído.**
   - Na execução `32384048881`, `makepkg` criou com sucesso `kernel-generic-lts618-6.18.45-x86_64-2.txz` e `kernel-devel-lts618-6.18.45-x86_64-2.txz`.
   - A validação do `kernel-devel` extraiu todo o pacote, detectou `install/doinst.sh` e então terminou com status 1, fazendo `set -e` abortar o script antes dos testes de conteúdo e antes de gerar `kernel-headers`.
   - O log terminou com `An installation script was detected in ./install/doinst.sh, but was not executed.` e `ERRO na linha 520 (status 1)`; havia aproximadamente 92 GB livres.
   - Aprendizado: a validação deve capturar explicitamente o retorno do `explodepkg`, aceitar somente o caso conhecido em que a árvore foi efetivamente extraída e contém `install/doinst.sh`, e depois validar os arquivos esperados. Qualquer outro retorno não zero continua sendo erro.

## Falha concreta registrada em 2026-08-19

Execução baseada no commit `4b67f52c2edeb0292a33a54e4c119c118d835ede` falhou antes da compilação do kernel.

Causa confirmada:

```text
ERROR: cannot verify mirrors.kernel.org's certificate
Unable to locally verify the issuer's authority.
```

Também foi observado:

```text
update-ca-certificates: command not found
```

O runner tinha aproximadamente 106 GB livres; portanto essa execução não falhou por falta de espaço.

## Falha concreta registrada em 2026-08-20 — run 32340594409

A execução baseada no commit `8ce5950dad1559c8ebb8e05b812d829259ebffc6` passou pelo bootstrap TLS e pelas séries `a`, `ap` e `d`, mas falhou durante a instalação da série `l`, antes da compilação do kernel.

Causa confirmada pelo artifact `kernel-build-failure-log`:

```text
One or more errors occurred while slackpkg was running:
...
libiodbc-3.52.15-x86_64-1.txz: md5sum
libpcap-1.10.6-x86_64-1_slack15.0.txz: md5sum
libxml2-2.11.9-x86_64-9_slack15.0.txz.asc: md5sum
...
ERRO na linha 32 (status 1)
```

O mesmo log registra diversos `Connection timed out` ao acessar `mirrors.kernel.org` e tentativas IPv6 com `Network is unreachable`. Havia aproximadamente 98 GB livres, portanto não foi falta de disco.

Aprendizado: uma instalação longa de séries completas via `slackpkg` não pode depender de uma única passagem de rede. Quando `slackpkg` retornar erro por downloads/checksums transitórios, a correção deve preservar os pacotes já instalados, limpar o cache parcial e repetir apenas a operação da série corrente, com número limitado de tentativas. Não desabilitar verificação de checksum/certificado para mascarar a falha.

## Falha concreta registrada em 2026-08-20 — run 32378454480

A execução baseada no commit `bfccc029244f038a1670c97abdd98fc9e7e4287f` passou pelo bootstrap TLS e atualizou corretamente os metadados do `slackpkg`, mas parou antes da compilação ao iniciar a série `a`.

Causa confirmada em `.ci/last-failure.log`:

```text
==== Instalando série Slackware: a ====

Looking for a in package list. Please wait... DONE

No packages match the pattern for install. Try:

    /usr/sbin/slackpkg reinstall|upgrade

ERRO na linha 32 (status 20)
```

Havia aproximadamente 98 GB livres. Portanto, esta falha não é de espaço, TLS, checksum ou compilação: é de seleção do conjunto de pacotes.

Aprendizado: não aceitar `20` indiscriminadamente como sucesso no bootstrap. Para uma série obrigatória, uma seleção vazia deve ser erro. A correção deve montar uma lista verificável de pacotes pertencentes a `slackware64/<série>` e instalar essa lista, preservando o mecanismo oficial de verificação do Slackware.

## Falha concreta registrada em 2026-08-20 — run 32384048881

A execução baseada no commit `69cf97197fd698e50331b626d2a5c806a469c5bf` concluiu a compilação do kernel e criou com o `makepkg` nativo do Slackware os pacotes principal e `kernel-devel` da revisão 2. O pacote `kernel-devel` foi criado e o `explodepkg` iniciou sua extração normalmente.

Causa confirmada pelo artifact `kernel-build-failure-log`:

```text
Slackware package /work/output/kernel-devel-lts618-6.18.45-x86_64-2.txz created.

==== Validando TXZ kernel-devel e compilando módulo externo mínimo ====
Exploding package /work/output/kernel-devel-lts618-6.18.45-x86_64-2.txz in current directory:
...
An installation script was detected in ./install/doinst.sh, but
was not executed.

ERRO na linha 520 (status 1)
```

O `df` registrado no mesmo log mostrava aproximadamente 92 GB livres. Portanto, a compilação e o `makepkg` não são a causa desta falha; o abortamento ocorreu no passo de validação por causa do retorno não zero de `explodepkg` sob `set -e` depois que o conteúdo já havia sido extraído.

Aprendizado: encapsular a extração de validação. Um retorno 1 só pode ser tolerado quando a extração produziu a árvore esperada e `install/doinst.sh` está presente; em seguida os testes estruturais continuam obrigatórios. Outros retornos, ou ausência da árvore esperada, devem falhar.

## Falha concreta registrada em 2026-08-20 — run 32412269511

A execução baseada no commit `59eeda66d1e776b07a35ca3a2945e4c4ad21357a` voltou a alcançar a validação do `kernel-devel`, porém a cópia efetivamente executada de `.github/scripts/build-kernel-slackware.sh` ainda continha uma chamada direta a `explodepkg` sob `set -e`.

Causa confirmada em `.ci/last-failure.log`:

```text
An installation script was detected in ./install/doinst.sh, but
was not executed.

ERRO na linha 538 (status 1)
```

O log mostrava aproximadamente 92 GB livres no momento da falha. Portanto não foi falta de espaço, compilação do kernel nem criação do TXZ: foi a mesma classe de retorno conhecida do `explodepkg`, mas ainda existente em outra revisão/trecho ativo do script.

Aprendizado adicional: não basta documentar ou corrigir uma ocorrência anterior. Antes de disparar nova execução, deve-se revisar todas as chamadas ativas a `explodepkg` na versão da branch `main` e garantir que cada validação capture o retorno explicitamente, aceite status 1 somente quando a árvore esperada foi extraída e `install/doinst.sh` existe, e mantenha os testes estruturais obrigatórios. Uma chamada direta a `explodepkg` sob `set -e` não deve permanecer.

## Falha concreta registrada em 2026-08-20 — run 32435699991

A execução baseada no commit `1a9a2a0ed0f9d79987df8955ca2b954b32292b5a` passou pela checagem TLS do workflow contra `CHECKSUMS.md5.asc`, mas falhou segundos depois na etapa 0 do container, antes de `slackpkg update` e antes de criar `output/build.log`.

Causa confirmada pelo log do job:

```text
==== Bootstrap resiliente das séries Slackware 15.0 ====
Process completed with exit code 4.
```

Na versão executada do bootstrap, o próximo comando após configurar a CA era um `wget -q --spider` único para a mesma URL. No GNU Wget, status 4 representa falha de rede. Como a checagem anterior do mesmo endpoint havia passado e havia aproximadamente 106 GB livres, esta execução não indica problema de disco, compilação, TLS permanentemente inválido ou `slackpkg`; ela abortou numa sondagem de rede sem retry e com saída silenciada.

Aprendizado: não colocar uma sondagem `wget -q --spider` de passagem única como gate fatal antes do mecanismo resiliente. A sondagem deve ter retry limitado, preservar verificação TLS, exibir o erro da última tentativa e só então falhar. Não usar `-q` em uma checagem cujo diagnóstico será necessário se ela abortar o build.

## Direção atual aceita

- Runner GitHub Ubuntu apenas como host/orquestrador.
- Container de build: Slackware 15.0.
- `JOBS=2`.
- Bootstrap TLS explícito antes do primeiro `slackpkg update`.
- Toolchain instalado e usado dentro do Slackware.
- Kernel compilado dentro do Slackware.
- `.txz` criado com `makepkg` nativo do Slackware.
- Pacote validado com `explodepkg` dentro do Slackware, tratando explicitamente o caso conhecido de retorno 1 após detectar `install/doinst.sh` e exigindo validação estrutural subsequente.
- Não substituir nem remover automaticamente o kernel antigo.
- Não alterar automaticamente o bootloader durante a instalação inicial do pacote.

## Política para futuras falhas

Se uma nova execução falhar, não reutilizar uma das abordagens descartadas acima. Primeiro capturar e ler o log da execução atual, identificar a causa específica e fazer a menor correção possível.