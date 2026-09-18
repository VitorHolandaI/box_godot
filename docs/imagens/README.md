# imagens

Capturas usadas pelo `README.md` da raiz e pela documentacao. Só entram aqui
arquivos **otimizados**: JPEG de ~1600 px de largura, abaixo de 300 KB. Um PNG
de screenshot pesa ~700 KB e o repo publico nao precisa carregar isso por
imagem.

## Arquivos

| Arquivo | O que mostra |
|---|---|
| `hero-horda.jpg` | imagem de abertura do README: horda cercando o jogador num cruzamento |
| `horda-onda-alta.jpg` | onda 8, com variantes maiores e o HUD de onda/restantes |
| `sonar.jpg` | sonar ativo, zumbis revelados no minimapa |
| `tela-dividida.jpg` | tela dividida 2x2 com 4 jogadores locais |
| `cidade-ampla.jpg` | cidade procedural vista de cima (sem nevoa nesta receita) |
| `aereo-na-horda.jpg` | ataque aereo marcado no chao, bombas caindo em linha |
| `granada-na-horda.jpg` | granada explodindo no meio da horda |
| `swat-aliado.jpg` | esquadrao SWAT aliado entrando na rua (sem fumaca: o jogo nao tem esse efeito) |
| `airdrop-aviao.jpg` | aviao de suprimentos cruzando a cidade (sobrevoo) |
| `airdrop.jpg` | crate de armas descendo de paraquedas |
| `pvp-freezetime.jpg` | tempo de compra na base, com banner e placar |
| `pvp-fim-de-rodada.jpg` | fim de rodada por eliminacao (`Time A x Time B`) |
| `pvp-rodada.jpg` | rodada valendo na base (sem acao no quadro) |
| `sobrevivencia-cidade.jpg` | captura manual antiga, mantida so para comparacao |

Todas (menos a ultima) sao geradas por `scripts/capture_shots.sh`: o jogo abre
numa receita de `scripts/shot_capture.gd`, se posiciona e salva o PNG bruto em
`dist/capturas/` (fora do repo); o script so entao converte para JPEG aqui.

## Padrao de nome

`<modo>-<assunto>.jpg`, por exemplo: `pvp-base-time-a.jpg`,
`pvp-rodada-eliminacao.jpg`, `pvp-menu-compra.jpg`, `tela-dividida.jpg`.

## Como adicionar

O caminho normal e `bash scripts/capture_shots.sh` (captura + otimizacao numa
etapa). Para refazer so uma receita:

```bash
bash scripts/capture_shots.sh --shot=sonar
bash scripts/preview_shots.sh          # album local para aprovar antes de publicar
```

A partir de um screenshot manual (tira a linha de debug do topo, redimensiona e
comprime):

```bash
magick screenshot.png -crop 1899x1116+0+30 +repage \
  -resize 1600x -strip -interlace Plane -quality 82 docs/imagens/modo-assunto.jpg
```

GIF/WebP de gameplay e bem-vindo, mas mantenha abaixo de ~2 MB.
