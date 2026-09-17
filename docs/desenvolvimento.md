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
