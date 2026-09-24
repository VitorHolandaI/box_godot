# Créditos e licenças

O **código** do box_godot é AGPL-3.0-or-later (ver `LICENSE`). Os **assets** têm
licença própria e não são cobertos pela AGPL: cada um continua sob a licença com
que foi publicado. Esta é a lista, e é ela que cumpre a exigência de atribuição
do CC-BY.

## Motor

- **Godot Engine** 4.7.2, licença MIT. https://godotengine.org

## Modelos 3D

| Pasta | Origem | Licença | Atribuição obrigatória |
| --- | --- | --- | --- |
| `assets/models/jeep_military/` | jipe militar | **CC-BY 3.0** | **sim** |
| `assets/models/jeep/` | jipe civil | CC0 1.0 | não |
| `assets/models/city/` | kit modular de cidade | CC0 1.0 | não |
| `assets/models/modular_urban/` | Kenney Retro Urban Kit | CC0 1.0 | não |
| `assets/models/kenney_suburban/` | Kenney Suburban Kit | CC0 1.0 | não |
| `assets/models/kenney_commercial/` | Kenney Commercial Kit | CC0 1.0 | não |

O detalhe de cada kit (autor, link e data de download) está no `README.md`
dentro da própria pasta. O `assets/models/jeep_military/README.md` é o que
carrega o crédito exigido pelo CC-BY 3.0
(https://creativecommons.org/licenses/by/3.0/): ao redistribuir o jogo, esse
crédito tem que ir junto.

## Addons

- `addons/gdscript-linter/` — **MIT**, de Poplava. Tem `LICENSE` e
  `THIRD_PARTY_LICENSES.txt` próprios dentro da pasta e **não** leva o
  cabeçalho SPDX deste projeto: é código de terceiro, não nosso.

## Áudio

Não há arquivo de áudio no repositório. Todo som é sintetizado em código por
`scripts/weapon_sound_synth.gd` e `scripts/audio_feedback.gd`, então o áudio é
código e cai na AGPL como o resto.

## Ao adicionar um asset novo

Antes do commit: crie o `README.md` da pasta com autor, link, data e licença, e
acrescente a linha na tabela acima. Asset sem procedência registrada não entra.
