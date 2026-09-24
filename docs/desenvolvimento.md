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

## Publicacao no GitHub

O GitHub e o unico remoto: a `main` de trabalho e a `main` publica sao a mesma
branch, e o push e direto. Nao ha mais espelho nem reescrita de historico na
publicacao.

Foi assim ate 2026-09-24: o repo publico era um espelho gerado por
`scripts/publish_public.sh`, que reescrevia o historico para tirar os IPs de
infraestrutura. A reescrita chegou a ser feita e depois **mergeada de volta** na
linha original, entao a historia ficou duplicada e os IPs continuaram
alcancaveis. Em 2026-09-24 o historico foi reescrito de vez com `git-filter-repo`
(o IP publico da VPS virou `bitssand.blog`, os internos viraram
`git-interno`/`host-interno`), a linha limpa virou a unica, e o script saiu.

Os valores trocados ficam fora daqui de proposito: escrever o IP no texto que
explica como ele foi removido o poe de volta no historico. Aconteceu uma vez.

Consequencia pratica: **nao versione IP de infraestrutura**. Endereco de
servidor entra por DNS, como o `OFFICIAL_SERVER` do `game_config.gd`.

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
