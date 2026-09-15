class_name LoadTestOptions
extends RefCounted

## Opcoes de linha de comando para teste de carga do servidor dedicado.
## Uso:
##   godot --headless --path . -- --server --prespawn-zombies=600
##   var count := LoadTestOptions.prespawn_zombie_count(OS.get_cmdline_user_args())

const MAX_PRESPAWN_ZOMBIES := 2000


## Quantidade de zumbis a criar ao iniciar o servidor (0 quando ausente/invalido).
## Uso: var count := LoadTestOptions.prespawn_zombie_count(PackedStringArray(["--prespawn-zombies=600"]))
static func prespawn_zombie_count(arguments: PackedStringArray) -> int:
	for argument in arguments:
		if not argument.begins_with("--prespawn-zombies="):
			continue
		var raw_value := argument.trim_prefix("--prespawn-zombies=")
		if not raw_value.is_valid_int() or int(raw_value) < 0 or int(raw_value) > MAX_PRESPAWN_ZOMBIES:
			push_error("Valor invalido para --prespawn-zombies: '%s'; esperado inteiro entre 0 e %d." % [raw_value, MAX_PRESPAWN_ZOMBIES])
			return 0
		return int(raw_value)
	return 0
