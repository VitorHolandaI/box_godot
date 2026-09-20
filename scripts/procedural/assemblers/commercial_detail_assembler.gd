class_name ProceduralCommercialDetailAssembler
extends RefCounted

## Fachadas e mobiliario visual dos tres tipos de comercio procedural. O
## posicionamento segue principios de varejo: a zona de descompressao logo apos
## a porta fica livre, o caixa aparece fora do eixo da porta, o ATM fica na
## parede oposta e estoque/escritorio funcionam como apoio no fundo. Os nomes
## dos nos (StoreCheckout, GroceryAisle, GunShopDisplayRack...) sao contrato
## com os testes.
## Uso: ProceduralCommercialDetailAssembler.add_details(body, building)

const BOX_BUILDER: GDScript = preload("res://scripts/procedural/assemblers/box_builder.gd")
const BUILDING_MATERIALS: GDScript = preload("res://scripts/procedural/assemblers/building_materials.gd")

## Primeiros metros apos a porta ficam sem movel: o cliente ainda "descomprime"
## e nao registra o que esta ali (Underhill; ver procedures/lojas-layout-pesquisa.md).
const DECOMPRESSION_DEPTH := 3.0
const DECOMPRESSION_HALF_WIDTH := 2.2
const CHECKOUT_Z := 2.4
const CHECKOUT_HALF_WIDTH := 2.1
const ATM_SIZE := Vector2(0.8, 0.62)


static func add_details(body: StaticBody3D, building) -> void:
	var layout := _store_layout(building)
	var accent := _accent_for(building.archetype)
	_add_front(body, building, accent, float(layout["entrance_x"]))
	_add_atm(body, building, layout)
	_add_checkout_counter(body, building, accent, layout)
	match building.archetype:
		"Grocery_A":
			_add_grocery_aisles(body, building, layout)
		"GunShop_A":
			_add_gun_shop_display(body, building, layout)
		_:
			_add_store_islands(body, building, layout)
	_add_stockroom_crates(body, building, layout)


static func _store_layout(building) -> Dictionary:
	var layout: Variant = building.metadata.get("store_layout", {})
	if layout is Dictionary and not (layout as Dictionary).is_empty():
		return layout
	var sales_depth: float = building.depth * 0.68
	var stock_width: float = building.width * 0.62
	return {
		"entrance_x": building.width * 0.5,
		"sales_depth": sales_depth,
		"office_on_left": false,
		"office_rect": Rect2(stock_width, sales_depth, building.width - stock_width, building.depth - sales_depth),
		"stock_rect": Rect2(0.0, sales_depth, stock_width, building.depth - sales_depth),
	}


## Caixa visivel, mas fora do eixo da porta e fora da zona de descompressao.
static func _checkout_x(building, layout: Dictionary) -> float:
	var entrance_x := float(layout["entrance_x"])
	return building.width * (0.78 if entrance_x <= building.width * 0.5 else 0.22)


## ATM na parede oposta a entrada, perto da porta: da tempo de saque sem
## atravessar a loja. Uso: interno.
static func _atm_rect(building, layout: Dictionary) -> Rect2:
	var entrance_x := float(layout["entrance_x"])
	var atm_x: float = 0.9 if entrance_x > building.width * 0.5 else building.width - 0.9
	return Rect2(atm_x - ATM_SIZE.x * 0.5, 0.9, ATM_SIZE.x, ATM_SIZE.y)


static func _decompression_rect(layout: Dictionary) -> Rect2:
	var entrance_x := float(layout["entrance_x"])
	return Rect2(entrance_x - DECOMPRESSION_HALF_WIDTH, 0.0, DECOMPRESSION_HALF_WIDTH * 2.0, DECOMPRESSION_DEPTH)


## O movel centrado em `center` (XZ) pode ocupar o vao? Nao pode invadir a zona
## de descompressao, o caixa nem o ATM. Uso: interno das colocacoes.
static func _fixture_clear(building, layout: Dictionary, center: Vector2, size: Vector2) -> bool:
	var rect := Rect2(center - size * 0.5, size).grow(-0.05)
	if _decompression_rect(layout).grow(-0.05).intersects(rect):
		return false
	var checkout := Rect2(Vector2(_checkout_x(building, layout) - CHECKOUT_HALF_WIDTH, CHECKOUT_Z - 0.55), Vector2(CHECKOUT_HALF_WIDTH * 2.0, 1.1))
	if checkout.grow(-0.05).intersects(rect):
		return false
	if _atm_rect(building, layout).grow(-0.05).intersects(rect):
		return false
	return true


static func _add_front(body: StaticBody3D, building, accent: Color, entrance_x: float) -> void:
	var material: Material = BUILDING_MATERIALS.opaque(accent, building.floor_height)
	var sign_material: Material = BUILDING_MATERIALS.opaque(accent.lightened(0.2), building.floor_height)
	var prefix := "Grocery" if building.archetype == "Grocery_A" else "GunShop" if building.archetype == "GunShop_A" else "Store"
	var canopy_width := minf(6.0, building.width - 0.6)
	var center_x := clampf(entrance_x, canopy_width * 0.5 + 0.3, building.width - canopy_width * 0.5 - 0.3)
	BOX_BUILDER.add_box(body, "%sAwning" % prefix, Vector3(canopy_width, 0.22, 0.9), Vector3(center_x, 2.2, -0.38), material, false)
	BOX_BUILDER.add_box(body, "%sSign" % prefix, Vector3(canopy_width * 0.72, 0.55, 0.08), Vector3(center_x, 2.52, -0.08), sign_material, false)


static func _add_atm(body: StaticBody3D, building, layout: Dictionary) -> void:
	var material: Material = BUILDING_MATERIALS.opaque(Color(0.18, 0.2, 0.24), building.floor_height, false, 0.4, 0.35)
	var screen: Material = BUILDING_MATERIALS.opaque(Color(0.3, 0.62, 0.66), building.floor_height, false, 0.1, 0.2)
	var rect := _atm_rect(building, layout)
	BOX_BUILDER.add_box(body, "AtmMachine", Vector3(rect.size.x, 1.85, rect.size.y), Vector3(rect.get_center().x, 0.925, rect.get_center().y), material, true)
	BOX_BUILDER.add_box(body, "AtmScreen", Vector3(0.34, 0.26, 0.03), Vector3(rect.get_center().x, 1.35, rect.position.y + rect.size.y), screen, false)


static func _add_checkout_counter(body: StaticBody3D, building, accent: Color, layout: Dictionary) -> void:
	var prefix := "GroceryCheckout" if building.archetype == "Grocery_A" else "GunShopCounter" if building.archetype == "GunShop_A" else "StoreCheckout"
	var material: Material = BUILDING_MATERIALS.opaque(accent.darkened(0.35), building.floor_height, false, 0.2, 0.4)
	var x := _checkout_x(building, layout)
	BOX_BUILDER.add_box(body, prefix, Vector3(CHECKOUT_HALF_WIDTH * 2.0, 0.98, 1.0), Vector3(x, 0.49, CHECKOUT_Z), material, false)


static func _add_grocery_aisles(body: StaticBody3D, building, layout: Dictionary) -> void:
	var material: Material = BUILDING_MATERIALS.opaque(Color(0.36, 0.34, 0.25), building.floor_height)
	var aisle_length := float(layout["sales_depth"]) - DECOMPRESSION_DEPTH - 0.6
	if aisle_length < 1.5:
		return
	var z_center := DECOMPRESSION_DEPTH + aisle_length * 0.5
	var x := 2.6
	var index := 0
	while x < building.width - 2.0:
		var center := Vector2(x, z_center)
		if _fixture_clear(building, layout, center, Vector2(0.62, aisle_length)):
			BOX_BUILDER.add_box(body, "GroceryAisle_%d" % index, Vector3(0.62, 1.62, aisle_length), Vector3(center.x, 0.81, center.y), material, false)
			index += 1
		x += 2.6


static func _add_store_islands(body: StaticBody3D, building, layout: Dictionary) -> void:
	var material: Material = BUILDING_MATERIALS.opaque(Color(0.34, 0.27, 0.18), building.floor_height)
	var sales_depth := float(layout["sales_depth"])
	var index := 0
	for fraction in [Vector2(0.3, 0.35), Vector2(0.62, 0.42), Vector2(0.4, 0.7), Vector2(0.72, 0.74)]:
		var center := Vector2(building.width * float(fraction.x), sales_depth * float(fraction.y))
		if not _fixture_clear(building, layout, center, Vector2(1.3, 1.3)):
			continue
		BOX_BUILDER.add_box(body, "StoreShelf_%d" % index, Vector3(1.3, 1.35, 1.3), Vector3(center.x, 0.68, center.y), material, false)
		index += 1


static func _add_gun_shop_display(body: StaticBody3D, building, layout: Dictionary) -> void:
	var material: Material = BUILDING_MATERIALS.opaque(Color(0.16, 0.18, 0.2), building.floor_height, false, 0.55, 0.3)
	var sales_depth := float(layout["sales_depth"])
	var z := DECOMPRESSION_DEPTH + 0.8
	var index := 0
	while z < sales_depth - 0.6:
		for x in [1.0, building.width - 1.0]:
			var center := Vector2(x, z)
			if _fixture_clear(building, layout, center, Vector2(0.3, 1.5)):
				BOX_BUILDER.add_box(body, "GunShopDisplayRack_%d" % index, Vector3(0.3, 1.75, 1.5), Vector3(center.x, 0.88, center.y), material, false)
				index += 1
		z += 2.6


static func _add_stockroom_crates(body: StaticBody3D, building, layout: Dictionary) -> void:
	var stock_rect: Rect2 = layout["stock_rect"]
	var material: Material = BUILDING_MATERIALS.opaque(Color(0.42, 0.33, 0.2), building.floor_height)
	var x := stock_rect.position.x + 0.9
	var index := 0
	while x < stock_rect.end.x - 0.6:
		BOX_BUILDER.add_box(body, "StockroomCrate_%d" % index, Vector3(1.0, 1.1, 1.0), Vector3(x, 0.55, stock_rect.end.y - 0.7), material, false)
		x += 1.6
		index += 1


static func _accent_for(archetype: String) -> Color:
	if archetype == "Grocery_A":
		return Color(0.26, 0.58, 0.32)
	if archetype == "GunShop_A":
		return Color(0.52, 0.14, 0.12)
	return Color(0.84, 0.36, 0.14)
