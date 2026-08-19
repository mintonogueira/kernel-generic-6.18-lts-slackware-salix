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

## Direção atual aceita

- Runner GitHub Ubuntu apenas como host/orquestrador.
- Container de build: Slackware 15.0.
- `JOBS=2`.
- Bootstrap TLS explícito antes do primeiro `slackpkg update`.
- Toolchain instalado e usado dentro do Slackware.
- Kernel compilado dentro do Slackware.
- `.txz` criado com `makepkg` nativo do Slackware.
- Pacote validado com `explodepkg` dentro do Slackware.
- Não substituir nem remover automaticamente o kernel antigo.
- Não alterar automaticamente o bootloader durante a instalação inicial do pacote.

## Política para futuras falhas

Se uma nova execução falhar, não reutilizar uma das abordagens descartadas acima. Primeiro capturar e ler o log da execução atual, identificar a causa específica e fazer a menor correção possível.