# imagens

Capturas usadas pelo `README.md` da raiz e pela documentacao. Só entram aqui
arquivos **otimizados**: JPEG de ~1280 px de largura, abaixo de 300 KB. Um PNG
de screenshot pesa ~700 KB e o repo publico nao precisa carregar isso por
imagem.

## Arquivos

| Arquivo | O que mostra |
|---|---|
| `sobrevivencia-cidade.jpg` | onda de zumbis cercando o jogador numa esquina da cidade (HUD de sobrevivencia, minimapa) |

## Padrao de nome

`<modo>-<assunto>.jpg`, por exemplo: `pvp-base-time-a.jpg`,
`pvp-rodada-eliminacao.jpg`, `pvp-menu-compra.jpg`, `tela-dividida.jpg`.

## Como adicionar

A partir de um screenshot PNG de 1899x1146 (tira a linha de debug do topo,
redimensiona e comprime):

```bash
magick screenshot.png \
  -crop 1899x1116+0+30 +repage \
  -resize 1280x -strip -interlace Plane -quality 82 \
  docs/imagens/modo-assunto.jpg
```

Se o screenshot tiver outro tamanho, troque a geometria do `-crop` (largura do
original x altura menos a faixa de debug + deslocamento da faixa). GIF/WebP de
gameplay e bem-vindo, mas mantenha abaixo de ~2 MB.
