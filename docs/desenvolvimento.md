<!-- Documentacao detalhada do projeto. O README fica so com o essencial. -->

# Desenvolvimento: builds, export e testes

## Builds Linux, Windows e macOS


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

### macOS

`bash scripts/build_exports.sh` gera tambem `dist/box-godot-macos.zip`, com um
`.app` **universal** (x86_64 + arm64) sem assinatura. Duas coisas precisam estar
no lugar:

1. **Template universal do Godot.** O pacote oficial de export templates tem
   >1 GB porque traz todas as plataformas. Baixe so o do macOS (HTTP range, na
   faixa de 120 MB):
   ```bash
   python3 scripts/fetch_macos_template.py          # Godot 4.7.2
   python3 scripts/fetch_macos_template.py --list   # so lista o pacote
   ```
   Ele instala em `~/.local/share/godot/export_templates/4.7.2.stable/macos.zip`
   e exige a versao do engine igual a do editor (4.7.2). Sem o arquivo, o export
   pula o macOS com aviso, sem quebrar Linux/Windows.
2. **ETC2 ASTC habilitado no projeto** (`rendering/textures/vram_compression/
   import_etc2_astc=true` em `project.godot`): o export recusa universal/arm64
   sem isso, porque GPUs da Apple usam esse formato. Ja vem ligado no projeto.

### Assinatura e notarizacao (macOS)

O `.app` sai **sem assinatura**. No Mac de quem for jogar, o Gatekeeper bloqueia
o primeiro abrir: use botao direito -> Abrir, ou remova a quarentena:

```bash
xattr -dr com.apple.quarantine "Box Godot.app"
```

Para distribuir fora da App Store, o fluxo oficial e Developer ID + `codesign` +
notarizacao com `notarytool` (conta Apple Developer paga). Essas ferramentas
existem **apenas no macOS**, entao essa etapa roda numa maquina Mac: no preset
`macOS` de `export_presets.cfg`, preencha `codesign/codesign` (identidade),
`codesign/identity`, `codesign/apple_team_id`, `codesign/provisioning_profile`,
`notarization/notarization` e as credenciais (`apple_id_name`/`apple_id_password`
ou `api_key`/`api_key_id`) e exporte de la. Do Linux o Godot so gera o app sem
assinatura.

Observacao: o cliente macOS sai com o template **oficial** (completo), enquanto
Linux/Windows usam o engine custom enxuto do projeto. O handshake do jogo compara
o `GAME_BUILD`, nao a versao do engine, entao o cliente de macOS conecta nos
servidores normalmente.
