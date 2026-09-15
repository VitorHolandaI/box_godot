extends Logger

## Conta erros de script (parse, chamada invalida, etc.) durante a suite.
## push_error de validacoes esperadas nao entra: so ERROR_TYPE_SCRIPT.
## Existe porque a suite chegou a dar UNIT_TEST_PASS com main.gd sem compilar,
## ja que os testes chamam metodos via call() e esses erros nao marcavam falha.
## Uso:
##   var counter := preload("res://scripts/test_script_error_counter.gd").new()
##   OS.add_logger(counter)
##   if counter.script_errors > 0: ...

var script_errors := 0
var messages: Array[String] = []
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type != ERROR_TYPE_SCRIPT:
		return
	_mutex.lock()
	script_errors += 1
	if messages.size() < 20:
		messages.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
	_mutex.unlock()
