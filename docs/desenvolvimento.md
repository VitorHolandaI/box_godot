<!-- Documentacao detalhada do projeto. O README fica so com o essencial. -->

# Desenvolvimento: builds, export e testes

## Builds Linux e Windows


Com os export templates do Godot 4.7.2 instalados, gere os dois clientes com:

```bash
bash scripts/build_exports.sh
```

Os executaveis autocontidos e o arquivo `SHA256SUMS` ficam em `dist/`:

- Linux x86_64: `dist/box-godot-linux.x86_64`
- Windows x86_64: `dist/box-godot-windows.exe`

## Testes automatizados


Teste nativo de servidor dedicado:

```bash
bash scripts/test_dedicated.sh
```

Teste completo do container:

```bash
bash scripts/test_container.sh
```

O cliente-bot conecta com um slot, move o personagem, equipa a pistola e atira.
O teste so passa depois que o cliente observa movimento, consumo de stamina,
projetil visual e a morte de um zumbi.
Entrada nao predeterminada e erros de script embarcam nesses smoke tests.

## Publicacao no GitHub (historico limpo)

O repositorio publico **nao** recebe push direto do repo de trabalho: os binarios
de release e os IPs de infraestrutura que existem no historico antigo seriam
levados junto. A publicacao passa por `scripts/publish_public.sh`, que clona um
espelho, reescreve o historico (remove `*.x86_64`/`*.exe`/`*.pck` e troca os IPs
do mapa, tanto no conteudo quanto nas mensagens de commit), confere o resultado e
so entao empurra para o repositorio publico.

Requisito: `git-filter-repo` no PATH (`pacman -S git-filter-repo` ou
`pip install --user git-filter-repo`). Sem ele, aponte o caminho do script:
`FILTER_REPO_BIN=/caminho/git-filter-repo`.

```bash
cp .publish-ip-map.example.txt .publish-ip-map.txt   # e ponha os IPs reais
scripts/publish_public.sh --dry-run                  # ve o plano
scripts/publish_public.sh                            # publica (pede confirmacao)
PUBLIC_REMOTE=git@github.com:user/outro.git scripts/publish_public.sh
```

O mapa `.publish-ip-map.txt` fica fora do repositorio (gitignored) porque contem
os valores reais; o `.example` mostra o formato. O script recusa mapa malformado
e falha se ainda sobrar binario ou IP no historico reescrito.

