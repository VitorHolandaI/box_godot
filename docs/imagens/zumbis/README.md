# imagens/zumbis

Um GIF por variante de zumbi, no indice do enum `ZombieMutator.Type`
(`zumbi-00.gif` = walker, `zumbi-14.gif` = Tita). Cada um tem 560 px de largura,
~14 fps e 150-280 KB (a pasta inteira fica em ~3,9 MB).

Nao edite na mao: o GIF vem do proprio jogo.

```bash
bash scripts/capture_shots.sh --shot=zumbi-14   # uma variante
bash scripts/capture_shots.sh --gif             # as 21
```

O runner roda o jogo com `--write-movie` (Movie Maker, 15 fps fixos), recorta os
ultimos 4,2 s do AVI (que e o trecho do ataque) e converte com `ffmpeg`
(paleta em 2 passos). Os artefatos intermediarios (PNG e AVI) ficam em
`dist/capturas/`, fora do repo.

A descricao de cada variante esta em [`../../zumbis.md`](../../zumbis.md).
