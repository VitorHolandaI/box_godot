#!/usr/bin/env python3
"""Baixa SO o template de macOS do pacote oficial de export templates do Godot.

O pacote completo (`Godot_v<versao>_export_templates.tpz`) tem >1 GB porque traz
todas as plataformas. Este script usa HTTP range no asset do GitHub: pega o
diretorio central do zip, acha a entrada `templates/macos.zip`, baixa so o
trecho dessa entrada e monta o arquivo num arquivo esparso local, do qual o
zipfile extrai o template. Resultado: ~1/8 do trafego.

Uso:
    scripts/fetch_macos_template.py                  # ultima 4.7.2 conhecida
    scripts/fetch_macos_template.py --version 4.7.2
    scripts/fetch_macos_template.py --list           # so lista as entradas

Depois de baixar, o arquivo vai para
`~/.local/share/godot/export_templates/<versao>.stable/macos.zip`.
"""
import argparse
import io
import os
import pathlib
import struct
import sys
import typing
import urllib.request
import zipfile
import zlib

RELEASE_BASE = "https://github.com/godotengine/godot/releases/download"
EOCD_SIGNATURE = b"PK\x05\x06"
EOCD64_LOCATOR_SIGNATURE = b"PK\x06\x07"
EOCD64_SIGNATURE = b"PK\x06\x06"
TAIL_BYTES = 4 * 1024 * 1024


def die(message: str) -> typing.NoReturn:
    print(f"erro: {message}", file=sys.stderr)
    sys.exit(1)


def asset_url(version: str) -> str:
    return f"{RELEASE_BASE}/{version}-stable/Godot_v{version}-stable_export_templates.tpz"


def content_length(url: str) -> int:
    request = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(request, timeout=60) as response:
        raw_length = response.headers.get("Content-Length")
        if raw_length is None:
            die(f"servidor nao informou Content-Length para {url}")
        return int(raw_length)


def fetch_range(url: str, start: int, end: int) -> bytes:
    if end < start:
        die(f"range invalido: {start}-{end} (esperado start <= end)")
    request = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(request, timeout=600) as response:
        data = response.read()
    expected = end - start + 1
    if len(data) != expected:
        die(f"range {start}-{end} devolveu {len(data)} bytes (esperado {expected})")
    return data


def central_directory_range(url: str, total: int) -> tuple[int, int]:
    """Le o EOCD (e o EOCD64, se houver) e devolve offset/tamanho do diretorio central."""
    tail_start = max(0, total - TAIL_BYTES)
    tail = fetch_range(url, tail_start, total - 1)
    eocd_index = tail.rfind(EOCD_SIGNATURE)
    if eocd_index < 0:
        die("nao achei o End Of Central Directory no fim do pacote")
    if eocd_index + 22 > len(tail):
        die("EOCD truncado; aumente TAIL_BYTES")
    offset = eocd_index + 20
    if struct.unpack_from("<H", tail, eocd_index + 10)[0] == 0xFFFF or \
       struct.unpack_from("<I", tail, eocd_index + 16)[0] == 0xFFFFFFFF:
        locator_index = tail.rfind(EOCD64_LOCATOR_SIGNATURE, 0, eocd_index)
        if locator_index < 0:
            die("pacote declara ZIP64 mas nao achei o localizador EOCD64")
        eocd64_offset = struct.unpack_from("<Q", tail, locator_index + 8)[0]
        relative = eocd64_offset - tail_start
        if relative < 0:
            die("EOCD64 fora da cauda lida; aumente TAIL_BYTES")
        if tail[relative:relative + 4] != EOCD64_SIGNATURE:
            die("assinatura EOCD64 invalida")
        offset = int(struct.unpack_from("<Q", tail, relative + 48)[0])
        end_offset = int(struct.unpack_from("<Q", tail, relative + 56)[0])
    else:
        offset = int(struct.unpack_from("<I", tail, eocd_index + 16)[0])
        end_offset = offset + int(struct.unpack_from("<I", tail, eocd_index + 12)[0])
    _ = offset  # offset ja esta no nome de cada entrada; o range vem do EOCD64
    return tail_start, eocd_index


def list_entries(url: str) -> list[tuple[str, int, int, int]]:
    """(nome, offset_local, tamanho_comprimido, metodo) de cada entrada do zip."""
    total = content_length(url)
    tail_start, eocd_index = central_directory_range(url, total)
    # A cauda ja traz o diretorio central quando ele e pequeno; senao, pega o range.
    tail = fetch_range(url, tail_start, total - 1)
    eocd = tail.rfind(EOCD_SIGNATURE)
    cd_offset = int(struct.unpack_from("<I", tail, eocd + 16)[0])
    cd_size = int(struct.unpack_from("<I", tail, eocd + 12)[0])
    if cd_offset == 0xFFFFFFFF or cd_size == 0xFFFFFFFF:
        locator = tail.rfind(EOCD64_LOCATOR_SIGNATURE, 0, eocd)
        eocd64_offset = struct.unpack_from("<Q", tail, locator + 8)[0]
        relative = eocd64_offset - tail_start
        cd_size = int(struct.unpack_from("<Q", tail, relative + 40)[0])
        cd_offset = int(struct.unpack_from("<Q", tail, relative + 48)[0])
    cd = fetch_range(url, cd_offset, cd_offset + cd_size - 1)
    entries = []
    position = 0
    while position + 46 <= len(cd) and cd[position:position + 4] == b"PK\x01\x02":
        method = struct.unpack_from("<H", cd, position + 10)[0]
        compressed = struct.unpack_from("<I", cd, position + 20)[0]
        name_length = struct.unpack_from("<H", cd, position + 28)[0]
        extra_length = struct.unpack_from("<H", cd, position + 30)[0]
        comment_length = struct.unpack_from("<H", cd, position + 32)[0]
        local_offset = struct.unpack_from("<I", cd, position + 42)[0]
        name = cd[position + 46:position + 46 + name_length].decode("utf-8", "replace")
        position += 46 + name_length + extra_length + comment_length
        if local_offset == 0xFFFFFFFF or compressed == 0xFFFFFFFF:
            # ZIP64: os valores reais ficam no campo extra (0x0001).
            extra_start = position - comment_length - extra_length
            extra = cd[extra_start:extra_start + extra_length]
            zip64 = _parse_zip64_extra(extra, compressed, local_offset)
            compressed, local_offset = zip64
        entries.append((name, local_offset, compressed, method))
    return entries


def _parse_zip64_extra(extra: bytes, compressed: int, local_offset: int) -> tuple[int, int]:
    position = 0
    while position + 4 <= len(extra):
        header_id, size = struct.unpack_from("<HH", extra, position)
        body = extra[position + 4:position + 4 + size]
        position += 4 + size
        if header_id != 0x0001:
            continue
        cursor = 0
        cursor += 8  # uncompressed
        compressed = int(struct.unpack_from("<Q", body, cursor)[0])
        cursor += 8
        local_offset = int(struct.unpack_from("<Q", body, cursor)[0])
        return compressed, local_offset
    return compressed, local_offset


def extract_entry(url: str, name: str, total: int, destination: pathlib.Path) -> None:
    entries = list_entries(url)
    match = [entry for entry in entries if entry[0] == name]
    if not match:
        available = ", ".join(entry[0] for entry in entries)
        die(f"entrada '{name}' nao existe no pacote (disponiveis: {available})")
    _, local_offset, compressed, _method = match[0]
    header = fetch_range(url, local_offset, local_offset + 29)
    if header[:4] != b"PK\x03\x04":
        die(f"assinatura de cabecalho local invalida em '{name}'")
    name_length, extra_length = struct.unpack_from("<HH", header, 26)
    data_start = local_offset + 30 + name_length + extra_length
    raw = fetch_range(url, data_start, data_start + compressed - 1)
    print(f">> extraindo {name} ({compressed / 1048576:.0f} MB comprimidos)")
    # Zips do Godot usam deflate; se um dia vierem armazenados (metodo 0), copia.
    entries = list_entries(url)
    method = [entry for entry in entries if entry[0] == name][0][3]
    data = zlib.decompress(raw, -zlib.MAX_WBITS) if method == 8 else raw
    # macos.zip e um zip aninhado; linux_release.x86_64 e o .exe do Windows sao
    # binarios crus: so valida (e lista) quando for zip de verdade.
    if data[:4] == b"PK\x03\x04":
        with zipfile.ZipFile(io.BytesIO(data)) as template_zip:
            broken = template_zip.testzip()
            if broken is not None:
                die(f"template corrompido: {broken}")
            names = template_zip.namelist()
    else:
        names = [f"{name} (binario cru)"]
    destination.write_bytes(data)
    print(f">> salvo em {destination} ({len(data) / 1048576:.0f} MB)")
    print(f"   conteudo: {', '.join(names[:6])}")


def template_dir(version: str) -> pathlib.Path:
    home = pathlib.Path(os.environ.get("XDG_DATA_HOME", pathlib.Path.home() / ".local/share"))
    return home / "godot" / "export_templates" / f"{version}.stable"


def main() -> None:
    parser = argparse.ArgumentParser(description="Baixa so o template macOS dos export templates do Godot")
    parser.add_argument("--version", default="4.7.2", help="versao do Godot (padrao 4.7.2)")
    parser.add_argument("--list", action="store_true", help="lista as entradas do pacote e sai")
    parser.add_argument("--output", help="caminho de saida (padrao: pasta de templates do Godot)")
    parser.add_argument("--entry", default="templates/macos.zip",
                        help="entrada do pacote a extrair (padrao: templates/macos.zip)")
    args = parser.parse_args()

    url = asset_url(args.version)
    total = content_length(url)
    print(f">> pacote: {url} ({total / 1048576:.0f} MB; so o trecho do macOS sera baixado)")

    if args.list:
        for name, _offset, compressed, _method in list_entries(url):
            print(f"   {name} ({compressed / 1048576:.1f} MB)")
        return

    default_name = pathlib.PurePosixPath(args.entry).name
    destination = pathlib.Path(args.output) if args.output else template_dir(args.version) / default_name
    destination.parent.mkdir(parents=True, exist_ok=True)
    extract_entry(url, args.entry, total, destination)


if __name__ == "__main__":
    main()
