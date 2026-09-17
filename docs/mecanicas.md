<!-- Documentacao detalhada do projeto. O README fica so com o essencial. -->

# Mecanicas de jogo

## Safehouse e sistema de vidas


- **3 Vidas por Jogador**: Cada participante inicia com 3 vidas (`MAX_LIVES = 3`). Ao sofrer dano fatal, perde 1 vida e renasce dentro da Safehouse com vida e estamina cheias. Ao perder todas as 3 vidas, o jogador e eliminado da partida e o HUD exibe `[ELIMINADO]`.
- **Safehouse Fortificada de 2 Andares**: Localizada no lote central da cidade, conta com 4 estacoes de leitos e respawn demarcadas com kits medicos, bancada de armamentos, caixas de suprimento militar e dois pickups funcionais de municao (no terreo e no andar superior).
- **Porta Automatica**: O portal frontal abre para jogadores e zumbis proximos e fecha depois que a passagem fica vazia.
- **Segundo Andar e Mirante**: Acesso por escadaria de madeira real com corrimao e rampa suave, sacada de franco-atirador com sacos de areia, janela tatica e holofote defensivo voltado para a rua exterior.

## Propagacao sonora de tiros e ecolocalizacao


- **Atenuacao Sonora por Distancia**: Cada disparo de pistola gera um estampido que se propaga por um raio de ate 65 metros. A intensidade diminui conforme a distancia da fonte do tiro.
- **Trajetoria Fixa**: A bala preserva a direcao escolhida no instante do disparo e nao persegue alvos depois de sair da arma.
- **Ecolocalizacao e Investigacao Lenta**: Zumbis que nao estao engajados em combate direto captam o som, calculam a direcao da fonte sonora e se deslocam em marcha cadenciada e cautelosa (velocidade reduzida em ~40%) em direcao ao local de onde veio o tiro.
- Se avistarem um sobrevivente pelo caminho, transitam imediatamente para perseguição e investida direta.

Ao morrer, o zumbi usa ragdoll articulado. O pescoco possui limites de inclinacao
e torcao para impedir que a cabeca atravesse o torso.
