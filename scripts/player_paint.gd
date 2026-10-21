# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PlayerPaint
extends RefCounted

## Cores do personagem do jogador (pele, camisa, calca, botas), salvas no PC em
## `user://player_paint.cfg`. A malha voxel e compartilhada; pintar e so trocar
## a cor do material de cada parte. Uso:
##   PlayerPaint.load_config()
##   PlayerPaint.apply_to_model($Model)

const CONFIG_PATH := "user://player_paint.cfg"
const DEFAULT_SKIN := Color(0.72, 0.48, 0.3)
const DEFAULT_SHIRT := Color(0.2, 0.3, 0.13)
const DEFAULT_PANTS := Color(0.11, 0.16, 0.08)
const DEFAULT_BOOTS := Color(0.16, 0.13, 0.11)

## Paletas prontas para o jogador comecar rapido na tela de aparencia.
const PRESETS: Array[Dictionary] = [
	{
		"name": "Rambo",
		"skin": Color(0.66, 0.44, 0.28),
		"shirt": Color(0.22, 0.26, 0.12),
		"pants": Color(0.16, 0.2, 0.1),
		"boots": Color(0.15, 0.11, 0.08),
	},
	{
		"name": "Pos-apocaliptico",
		"skin": Color(0.6, 0.47, 0.34),
		"shirt": Color(0.38, 0.3, 0.18),
		"pants": Color(0.22, 0.2, 0.16),
		"boots": Color(0.2, 0.14, 0.09),
	},
	{
		"name": "Militar",
		"skin": Color(0.7, 0.5, 0.34),
		"shirt": Color(0.24, 0.28, 0.16),
		"pants": Color(0.18, 0.22, 0.13),
		"boots": Color(0.12, 0.12, 0.1),
	},
	{
		"name": "Sobrevivente",
		"skin": Color(0.64, 0.46, 0.32),
		"shirt": Color(0.3, 0.24, 0.2),
		"pants": Color(0.2, 0.2, 0.22),
		"boots": Color(0.16, 0.12, 0.09),
	},
	{
		"name": "SWAT",
		"skin": Color(0.6, 0.43, 0.3),
		"shirt": Color(0.08, 0.09, 0.1),
		"pants": Color(0.06, 0.07, 0.08),
		"boots": Color(0.05, 0.05, 0.06),
	},
	{
		"name": "Policial",
		"skin": Color(0.68, 0.48, 0.32),
		"shirt": Color(0.12, 0.18, 0.32),
		"pants": Color(0.1, 0.14, 0.24),
		"boots": Color(0.06, 0.06, 0.07),
	},
	{
		"name": "Cacador",
		"skin": Color(0.66, 0.46, 0.3),
		"shirt": Color(0.18, 0.26, 0.14),
		"pants": Color(0.28, 0.2, 0.12),
		"boots": Color(0.16, 0.11, 0.07),
	},
	{
		"name": "Urbano",
		"skin": Color(0.72, 0.52, 0.36),
		"shirt": Color(0.3, 0.32, 0.34),
		"pants": Color(0.16, 0.22, 0.34),
		"boots": Color(0.14, 0.13, 0.13),
	},
	{
		"name": "Cowboy",
		"skin": Color(0.7, 0.5, 0.34),
		"shirt": Color(0.42, 0.14, 0.12),
		"pants": Color(0.16, 0.22, 0.34),
		"boots": Color(0.26, 0.16, 0.09),
	},
	{
		"name": "Zumbi",
		"skin": Color(0.42, 0.52, 0.34),
		"shirt": Color(0.18, 0.18, 0.16),
		"pants": Color(0.14, 0.13, 0.12),
		"boots": Color(0.08, 0.08, 0.07),
	},
	{
		"name": "Inverno",
		"skin": Color(0.76, 0.6, 0.46),
		"shirt": Color(0.72, 0.74, 0.76),
		"pants": Color(0.4, 0.42, 0.46),
		"boots": Color(0.2, 0.18, 0.16),
	},
	{
		"name": "Mercenario",
		"skin": Color(0.62, 0.44, 0.3),
		"shirt": Color(0.26, 0.1, 0.1),
		"pants": Color(0.1, 0.1, 0.11),
		"boots": Color(0.07, 0.06, 0.06),
	},
	{
		"name": "Desertor",
		"skin": Color(0.68, 0.48, 0.32),
		"shirt": Color(0.56, 0.48, 0.32),
		"pants": Color(0.42, 0.34, 0.22),
		"boots": Color(0.24, 0.17, 0.1),
	},
	{
		"name": "Medico",
		"skin": Color(0.7, 0.5, 0.34),
		"shirt": Color(0.82, 0.84, 0.82),
		"pants": Color(0.56, 0.6, 0.62),
		"boots": Color(0.16, 0.14, 0.13),
	},
]

static var skin := DEFAULT_SKIN
static var shirt := DEFAULT_SHIRT
static var pants := DEFAULT_PANTS
static var boots := DEFAULT_BOOTS
static var _loaded := false


## Le as cores do disco uma vez (o menu pode chamar antes da partida).
static func load_config() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	var error := config.load(CONFIG_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_error("Nao foi possivel ler %s: %s." % [CONFIG_PATH, error_string(error)])
		return
	skin = _read_color(config, "skin", skin)
	shirt = _read_color(config, "shirt", shirt)
	pants = _read_color(config, "pants", pants)
	boots = _read_color(config, "boots", boots)


## Grava a pintura atual. Devolve o erro do ConfigFile (OK no sucesso).
static func save_config() -> Error:
	var config := ConfigFile.new()
	var load_error := config.load(CONFIG_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_error("Nao foi possivel atualizar %s: %s." % [CONFIG_PATH, error_string(load_error)])
		return load_error
	config.set_value("paint", "skin", skin)
	config.set_value("paint", "shirt", shirt)
	config.set_value("paint", "pants", pants)
	config.set_value("paint", "boots", boots)
	var error := config.save(CONFIG_PATH)
	if error != OK:
		push_error("Nao foi possivel salvar %s: %s." % [CONFIG_PATH, error_string(error)])
	return error


## Volta para as cores de fabrica e salva.
static func reset_defaults() -> Error:
	skin = DEFAULT_SKIN
	shirt = DEFAULT_SHIRT
	pants = DEFAULT_PANTS
	boots = DEFAULT_BOOTS
	return save_config()


## Aplica uma paleta pronta (indice em PRESETS) e salva. Uso: apply_preset(0)
static func apply_preset(index: int) -> Error:
	if index < 0 or index >= PRESETS.size():
		push_error("Preset invalido %d; esperado entre 0 e %d." % [index, PRESETS.size() - 1])
		return ERR_INVALID_PARAMETER
	var preset: Dictionary = PRESETS[index]
	skin = preset["skin"]
	shirt = preset["shirt"]
	pants = preset["pants"]
	boots = preset["boots"]
	return save_config()


static func preset_name(index: int) -> String:
	if index < 0 or index >= PRESETS.size():
		return ""
	return String(PRESETS[index]["name"])


## Pinta as partes do modelo com as cores salvas. Uso: apply_to_model($Model)
static func apply_to_model(model: Node3D) -> void:
	load_config()
	if model == null:
		return
	_paint_mesh(model, "Head", skin, 0.85)
	_paint_mesh(model, "Torso", shirt, 0.9)
	_paint_mesh(model, "LeftArm/Mesh", shirt, 0.9)
	_paint_mesh(model, "RightArm/Mesh", shirt, 0.9)
	_paint_mesh(model, "LeftLeg/Mesh", pants, 0.9)
	_paint_mesh(model, "RightLeg/Mesh", pants, 0.9)
	_paint_csg(model, "LeftBoot", boots)
	_paint_csg(model, "RightBoot", boots)


static func _paint_mesh(model: Node3D, path: String, color: Color, roughness: float) -> void:
	var node := model.get_node_or_null(path) as MeshInstance3D
	if node == null:
		return
	node.material_override = VoxelCharacterBuilder.shaded_material(color, roughness)


static func _paint_csg(model: Node3D, path: String, color: Color) -> void:
	var node := model.get_node_or_null(path)
	if node == null:
		return
	node.set("material", VoxelCharacterBuilder.shaded_material(color, 0.9))


static func _read_color(config: ConfigFile, key: String, fallback: Color) -> Color:
	var value: Variant = config.get_value("paint", key, fallback)
	if value is Color:
		return value
	if value is String and Color.html_is_valid(String(value)):
		return Color.html(String(value))
	return fallback
