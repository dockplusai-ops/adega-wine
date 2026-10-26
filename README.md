# Adega Wine

O Wine usado pelo [Adega](https://github.com/dockplusai-ops), compilado para macOS a partir dos **fontes abertos do CrossOver** (CodeWeavers, LGPL), com os patches deste repositório.

## O que tem aqui

| Caminho | O quê |
|---|---|
| `scripts/build.sh` | Baixa os fontes do CrossOver (SHA-256 fixo), aplica `patches/`, configura, compila, junta Wine Mono e Gecko, empacota |
| `scripts/bundle-libs.sh` | Copia as bibliotecas do Homebrew para dentro do pacote, para ele rodar em qualquer Mac |
| `patches/` | Alterações do Adega sobre os fontes do CrossOver |
| `.github/workflows/build.yml` | Build num runner Intel do GitHub; com o campo `release` preenchido, publica a release |

## Patches

- `0001-kernelbase-adega-append-args.patch`: acrescenta argumentos a programas específicos quando são abertos, conforme a variável `ADEGA_APPEND_ARGS` (`programa.exe|argumentos|texto que desativa;…`). Usado, por exemplo, para a interface da Steam (`steamwebhelper.exe`), que só desenha no Wine do macOS com `--in-process-gpu`.

## Compilar

No GitHub: **Actions → build → Run workflow**. Para publicar, preencha `release` com a versão (ex.: `v26.3.0-1`).

Localmente (Mac Intel, com as dependências do workflow instaladas pelo Homebrew):

```sh
./scripts/build.sh   # gera out/adega-wine-<versão>.tar.xz
```

## Licença

Wine é LGPL 2.1 ou posterior (`COPYING.LIB`). Os fontes usados estão em https://media.codeweavers.com/pub/crossover/source/, e as alterações e scripts de build estão neste repositório. Nada aqui inclui código proprietário da CodeWeavers nem o D3DMetal da Apple.
