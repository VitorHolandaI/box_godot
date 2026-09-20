# Jipe militar (carro dirigivel)

`military_jeep.glb` e o modelo do carro dirigivel do jogo. E um jipe militar
aberto (com roll bar, para-brisa, dois bancos dianteiros e area traseira para um
atirador), o que permite camera em primeira pessoa dentro do veiculo.

## Origem e licenca

- Modelo: **Military Jeep** por **Zsky** (pacote *Low Poly Military Vehicles*).
- Fonte: https://poly.pizza/m/AcSdGGrgYP
- Licenca: **CC-BY 3.0** (https://creativecommons.org/licenses/by/3.0/).
  Exige atribuicao: manter o credito ao autor no projeto.

## Como o jogo usa

- `scripts/drivable_car.gd` instancia o GLB em `Visual`, escala em
  `VISUAL_SCALE` (1,3 para casar com o boneco de 2,22 m), gira `MODEL_YAW` (PI,
  porque o bico encara +Z) e sobe `MODEL_GROUND_LIFT` (0,99) para o pneu tocar o
  chao.
- O material `Windows_Jeep` vira translucido em `_make_windows_transparent` para
  a camera interna enxergar a rua.
- O modelo e malha unica (rodas incluidas): as `VehicleWheel3D` fazem a fisica e
  as rodas visiveis do GLB ficam estaticas.
- Ancoras na cena `scenes/drivable_car.tscn`: `Seat` (motorista), `DriverEye`
  (camera em 1a pessoa), `GunnerSeat` (passageiro traseiro) e `ExitPoint`.
