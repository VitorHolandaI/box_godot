#!/usr/bin/env bash
# Monta o preview local dos frames ANTES de publicar.
#
# Uso:
#   scripts/preview_shots.sh            # album em HTML + servidor local (tmux)
#   scripts/preview_shots.sh --grip     # tambem abre o README renderizado pelo GitHub (uvx grip)
#   scripts/preview_shots.sh --stop     # derruba o servidor do album
#
# O album fica em dist/capturas/preview.html (fora do repo) e mostra cada JPEG
# no tamanho que ele tera no README, com peso do arquivo e link para o PNG
# bruto. Nada aqui toca no repositorio publico.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/dist/capturas"
IMG_DIR="$PROJECT_DIR/docs/imagens"
PORT="${PREVIEW_PORT:-8765}"
SESSION="box-godot-preview"
CSS_URL="https://raw.githubusercontent.com/sindresorhus/github-markdown-css/main/github-markdown.css"

mode="album"
case "${1:-}" in
	--grip) mode="grip" ;;
	--stop)
		tmux kill-session -t "$SESSION" 2>/dev/null && echo "servidor do album derrubado" || echo "servidor do album nao estava rodando"
		tmux kill-session -t grip-preview 2>/dev/null && echo "render do GitHub (grip) derrubado" || true
		exit 0
		;;
	--help|-h)
		sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	"") ;;
	*)
		echo "arg desconhecido: '$1' (use --grip, --stop ou nada)" >&2
		exit 2
		;;
esac

mkdir -p "$OUT_DIR"
if [[ ! -f "$OUT_DIR/github-markdown.css" ]]; then
	echo ">> baixando o CSS do GitHub (uma vez)"
	curl -fsSL -o "$OUT_DIR/github-markdown.css" "$CSS_URL" \
		|| echo "   (aviso: sem CSS externo; o album usa estilo minimo)"
fi

python3 - "$OUT_DIR" "$IMG_DIR" <<'PY'
import html
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
img_dir = Path(sys.argv[2])

# Ordem de leitura do README: hero primeiro, depois os modos.
order = ["hero-horda", "horda-onda-alta", "sonar", "tela-dividida", "cidade-ampla", "sobrevivencia-cidade"]
captions = {
    "hero-horda": "Sobrevivência: horda cercando o jogador num cruzamento (HUD e minimapa)",
    "horda-onda-alta": "Onda 8: mix de variantes grandes, HUD mostrando Hora/Onda e restantes",
    "sonar": "Sonar ativo: zumbis revelados no minimapa (blips laranja)",
    "tela-dividida": "Tela dividida com 4 jogadores locais (2x2, um HUD por jogador)",
    "cidade-ampla": "Cidade procedural por cima: quadras, ruas, muralha e a borda da floresta",
    "sobrevivencia-cidade": "Frame já publicado no README (comparação)",
}
found = [name for name in order if (img_dir / f"{name}.jpg").exists()]
extra = sorted(p.stem for p in img_dir.glob("*.jpg") if p.stem not in order)

def card(name: str) -> str:
    image = img_dir / f"{name}.jpg"
    raw = out_dir / f"{name}.png"
    size_kb = image.stat().st_size // 1024
    link = f'<a href="{raw.name}">PNG 1920x1080</a>' if raw.exists() else "sem PNG bruto"
    return f"""<section class="card">
  <h2>{html.escape(name)}</h2>
  <p class="caption">{html.escape(captions.get(name, ""))}</p>
  <img src="../docs/imagens/{image.name}" alt="{html.escape(name)}">
  <p class="meta">{image.name} &middot; {size_kb} KB no README &middot; {link}</p>
</section>"""

cards = "\n".join(card(name) for name in found + extra)
total_kb = sum((img_dir / f"{name}.jpg").stat().st_size for name in found + extra) // 1024

document = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>Box Godot - frames do README (preview local)</title>
<link rel="stylesheet" href="github-markdown.css">
<style>
  body {{ box-sizing: border-box; max-width: 980px; margin: 0 auto; padding: 32px 16px; }}
  .card {{ margin: 0 0 40px; padding: 0 0 24px; border-bottom: 1px solid #d8dee4; }}
  .card img {{ max-width: 100%; height: auto; border: 1px solid #d0d7de; border-radius: 6px; }}
  .caption {{ margin: 4px 0 12px; }}
  .meta {{ font-size: 13px; color: #57606a; }}
  .summary {{ background: #f6f8fa; border: 1px solid #d0d7de; border-radius: 6px; padding: 12px 16px; }}
  @media (prefers-color-scheme: dark) {{
    body {{ background: #0d1117; }}
    .card {{ border-color: #30363d; }}
    .card img {{ border-color: #30363d; }}
    .meta {{ color: #8b949e; }}
    .summary {{ background: #161b22; border-color: #30363d; }}
  }}
</style>
</head>
<body class="markdown-body">
<p class="summary">Preview local dos frames do README - {len(found) + len(extra)} imagens, {total_kb} KB no total.
Os PNG brutos 1920x1080 estao no mesmo servidor. Nada aqui foi publicado: o repo publico so muda
quando <code>scripts/publish_public.sh</code> roda.</p>
{cards}
</body>
</html>
"""
(out_dir / "preview.html").write_text(document, encoding="utf-8")
print(f"album gerado: {out_dir / 'preview.html'} ({len(found) + len(extra)} imagens)")
PY

if tmux has-session -t "$SESSION" 2>/dev/null; then
	tmux kill-session -t "$SESSION"
fi
# A raiz do projeto e servida para o album alcançar ../../docs/imagens via caminho relativo.
tmux new-session -d -s "$SESSION" "python3 -m http.server $PORT --directory '$PROJECT_DIR' > '$OUT_DIR/preview-server.log' 2>&1"
sleep 1
echo "album local: http://localhost:$PORT/dist/capturas/preview.html"
echo "pngs brutos: http://localhost:$PORT/dist/capturas/  (pasta $OUT_DIR)"

if [[ "$mode" == "grip" ]]; then
	command -v uvx >/dev/null 2>&1 || { echo "uvx nao encontrado; instale uv ou rode 'pip install --user grip'" >&2; exit 1; }
	echo ">> abrindo o README no render do GitHub (uvx grip)"
	(cd "$PROJECT_DIR" && uvx grip --browser README.md 6419)
fi
