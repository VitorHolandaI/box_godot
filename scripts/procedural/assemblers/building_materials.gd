# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
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


## Material opaco com imagem projetada em metros no mundo. Mantem o shader de
## visibilidade e evita depender do UV fragmentado das caixas procedurais.
## Uso: var wall := ProceduralBuildingMaterials.textured_opaque(Color.WHITE, 3.4, brick, 1.2)
static func textured_opaque(color: Color, floor_height: float, texture: Texture2D, texture_meters: float, ceiling_cutout: bool = false, metallic: float = 0.0, roughness: float = DEFAULT_ROUGHNESS, section_cut_exempt: bool = false) -> ShaderMaterial:
	if texture == null:
		push_error("Textura de edificio ausente; esperado Texture2D para %.2f m por repeticao." % texture_meters)
	if texture_meters <= 0.0:
		push_error("Escala de textura invalida %.2f; esperado > 0." % texture_meters)
	var material := opaque(color, floor_height, ceiling_cutout, metallic, roughness, section_cut_exempt)
	material.set_shader_parameter("use_texture", texture != null)
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("texture_meters", maxf(texture_meters, 0.1))
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


## Vidro da vitrine de loja: translucido simples, SEM o shader de visibilidade
## por andar — aquele tem `depth_draw_opaque` e `cull_disabled`, que numa caixa
## fina de vitrine vira aureola. Uso:
##   var glass := ProceduralBuildingMaterials.storefront_glass()
static func storefront_glass() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.78, 0.88, 0.34)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.1
	material.metallic = 0.1
	return material
