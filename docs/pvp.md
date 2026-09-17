<!-- Documentacao detalhada do projeto. O README fica so com o essencial. -->

# Modo mata-mata (PVP)

Mata-mata (PVP estilo CS) por times, melhor de 3, com bots do servidor: cada time nasce na sua **safehouse**, em cantos opostos do mapa
(~165 m entre elas), nos marcadores fixos da casa, compra arma **so na fase de compra
e dentro dela** (tecla **B**) e quem morre fica fora ate o proximo round. Bots do servidor compram sozinhos a melhor arma que couber. A sala
aparece como **Mata-mata PVP** e o HUD nao mostra nada de zumbi (sem contador de
horda, sem sonar).

```bash
GAME_SERVER_GAME_MODE=--pvp docker compose up --build -d

# atalho: menu que escolhe no ato o modo (com ou sem rebuild) e cuida de
# parar/logs/status:
scripts/server_menu.sh            # menu interativo
scripts/server_menu.sh pvp up     # mata-mata: rebuild + sobe (sem bots)
PVP_BOTS=4 scripts/server_menu.sh pvp up  # com 4 bots, para testar

# cliente (mesmo build do servidor):
godot --path . -- --join=127.0.0.1 --server-port=27015
```
