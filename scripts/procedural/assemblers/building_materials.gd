class_name ProceduralBuildingMaterials
extends RefCounted

## Fabrica dos materiais de edificio. Tudo que fica dentro de um predio usa os
## shaders com regra de visibilidade por andar; um StandardMaterial3D comum
## ficaria flutuando visivel nos andares ocultos (vidros, moveis, degraus).
## Uso:
##   var wall := ProceduralBuildingMaterials.opaque(Color(0.5, 0.4, 0.3), 3.4)
##   var glass := ProceduralBuildingMaterials.glass(3.4)

const CUTOUT_SHADER: Shader = preload("res://shaders/building_cutout.gdshader")
const GLASS_SHADER: Shader = preload("res://shaders/building_glass.gdshader")
const AURA_CUTOUT_RADIUS := 3.0
const DEFAULT_ROUGHNESS := 0.86
const GLASS_COLOR := Color(0.66, 0.82, 0.92, 0.32)
# Igual a ProceduralBuildingBlueprint.floor_height; pecas montadas sem acesso ao
# blueprint (portas, janelas, moveis) usam este valor.
const DEFAULT_FLOOR_HEIGHT := 3.4


## Material opaco do edificio. `section_cut_exempt` mantem a peca inteira no
## corte de meia altura (usado nos lances de escada).
## Uso: var steps := ProceduralBuildingMaterials.opaque(Color.GRAY, 3.4, false, 0.0, 0.86, true)
static func opaque(color: Color, floor_height: float, ceiling_cutout: bool = false, metallic: float = 0.0, roughness: float = DEFAULT_ROUGHNESS, section_cut_exempt: bool = false) -> ShaderMaterial:
	if floor_height <= 0.0:
		push_error("Altura de andar invalida %.2f para material de edificio; esperado > 0." % floor_height)
	var material := ShaderMaterial.new()
	material.shader = CUTOUT_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("material_roughness", roughness)
	material.set_shader_parameter("material_metallic", metallic)
	material.set_shader_parameter("cutout_radius", AURA_CUTOUT_RADIUS)
	material.set_shader_parameter("floor_height", floor_height)
	material.set_shader_parameter("ceiling_cutout", ceiling_cutout)
	material.set_shader_parameter("section_cut_exempt", section_cut_exempt)
	return material


## Vidro translucido que tambem some nos andares ocultos.
## Uso: var glass := ProceduralBuildingMaterials.glass(3.4)
static func glass(floor_height: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLASS_SHADER
	material.set_shader_parameter("glass_color", GLASS_COLOR)
	material.set_shader_parameter("floor_height", floor_height)
	material.set_shader_parameter("cutout_radius", AURA_CUTOUT_RADIUS)
	return material
