# SPDX-FileCopyrightText: 2026 Vitor Holanda
# SPDX-License-Identifier: AGPL-3.0-or-later
class_name MenuTheme
extends RefCounted

## Visual unico do menu e dos paineis (tema escuro com verde-oliva de acento).
## Centraliza cores, estilos e rotulos para o menu principal e o painel do Esc
## nao divergirem. Uso: root.theme = MenuTheme.build_theme()

const BG_TOP := Color(0.07, 0.1, 0.09)
const BG_BOTTOM := Color(0.015, 0.02, 0.02)
const PANEL_BG := Color(0.045, 0.06, 0.055, 0.97)
const ACCENT := Color(0.72, 0.83, 0.59)
const ACCENT_DIM := Color(0.32, 0.42, 0.27)
const ACCENT_DEEP := Color(0.16, 0.22, 0.14)
const TEXT := Color(0.88, 0.9, 0.86)
const TEXT_MUTED := Color(0.6, 0.63, 0.58)
const DANGER := Color(0.82, 0.36, 0.3)
const DANGER_BG := Color(0.2, 0.09, 0.08)
const WARNING := Color(0.86, 0.76, 0.46)


static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	_style_button_type(theme, "Button", ACCENT_DEEP, ACCENT_DIM)
	_style_button_type(theme, "OptionButton", ACCENT_DEEP, ACCENT_DIM)
	theme.set_stylebox("panel", "PanelContainer", box(PANEL_BG, ACCENT_DIM, 1, 14, 34))
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_color", "HSlider", TEXT)
	return theme


static func _style_button_type(theme: Theme, type: String, base: Color, border: Color) -> void:
	theme.set_stylebox("normal", type, box(base, border, 1, 6, 0, 12))
	theme.set_stylebox("hover", type, box(Color(0.2, 0.27, 0.17), ACCENT, 2, 6, 0, 12))
	theme.set_stylebox("pressed", type, box(Color(0.1, 0.13, 0.1), ACCENT, 2, 6, 0, 12))
	theme.set_stylebox("focus", type, box(Color(0, 0, 0, 0), ACCENT, 2, 6, 0, 12))
	theme.set_stylebox("disabled", type, box(Color(0.09, 0.1, 0.09), Color(0.24, 0.26, 0.24), 1, 6, 0, 12))
	theme.set_color("font_color", type, TEXT)
	theme.set_color("font_hover_color", type, Color(0.95, 1.0, 0.88))
	theme.set_color("font_pressed_color", type, ACCENT)
	theme.set_color("font_disabled_color", type, Color(0.42, 0.44, 0.42))
	theme.set_font_size("font_size", type, 18)


## Botao de destaque (acao principal): fundo de acento e texto escuro.
static func style_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(ACCENT_DIM, ACCENT, 1, 6, 0, 12))
	button.add_theme_stylebox_override("hover", box(ACCENT, ACCENT, 2, 6, 0, 12))
	button.add_theme_stylebox_override("pressed", box(Color(0.55, 0.65, 0.42), ACCENT, 2, 6, 0, 12))
	button.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), ACCENT, 2, 6, 0, 12))
	button.add_theme_color_override("font_color", Color(0.06, 0.08, 0.06))
	button.add_theme_color_override("font_hover_color", Color(0.04, 0.06, 0.04))
	button.add_theme_color_override("font_pressed_color", Color(0.06, 0.08, 0.06))


## Botao destrutivo (sair): fundo escuro avermelhado.
static func style_danger(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(DANGER_BG, Color(0.5, 0.25, 0.22), 1, 6, 0, 12))
	button.add_theme_stylebox_override("hover", box(Color(0.42, 0.16, 0.14), DANGER, 2, 6, 0, 12))
	button.add_theme_stylebox_override("pressed", box(Color(0.3, 0.11, 0.1), DANGER, 2, 6, 0, 12))
	button.add_theme_color_override("font_color", Color(0.92, 0.72, 0.68))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.82))


static func box(bg: Color, border: Color, border_width: int, radius: int, margin: int = -1, h_margin: int = -1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	if margin >= 0:
		style.content_margin_top = margin
		style.content_margin_bottom = margin
	if h_margin >= 0:
		style.content_margin_left = h_margin
		style.content_margin_right = h_margin
	return style


static func title_label(text: String, font_size: int = 40) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ACCENT)
	return label


static func section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", ACCENT)
	return label


static func muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", TEXT_MUTED)
	return label
