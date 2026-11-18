#!/usr/bin/env python3
"""
Entpackt ein geteiltes Zip-Archiv (name.zip + name.z01 ... name.zNN, erzeugt mit
`zip -s <groesse>`) mit genau einer Datei, ohne die Teile vorher zusammenzufuegen.

Hintergrund: `zip -s 0` + `unzip` lieferte bei diesem Archiv "invalid compressed data".
Die Teile sind aber nur ein in Stuecke geschnittener Datenstrom; dieses Skript liest sie
nacheinander, entpackt den Deflate-Strom und prueft die CRC.

Aufruf: extract_split_zip.py <archiv.zip> <zielordner>
Nur Python-Standardbibliothek.
"""
import os
import struct
import sys
import zlib


def parts_for(zip_path):
    base = zip_path[:-4]
    parts, i = [], 1
    while os.path.exists(f"{base}.z{i:02d}"):
        parts.append(f"{base}.z{i:02d}")
        i += 1
    return parts + [zip_path]


class ConcatReader:
    def __init__(self, paths):
        self.files = [open(p, "rb") for p in paths]
        self.index = 0

    def read(self, n):
        out = bytearray()
        while n > 0 and self.index < len(self.files):
            chunk = self.files[self.index].read(n)
            if not chunk:
                self.index += 1
                continue
            out += chunk
            n -= len(chunk)
        return bytes(out)


def central_directory(last_part):
    data = open(last_part, "rb").read()
    eocd = data.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise ValueError("Ende des Zip-Verzeichnisses nicht gefunden")
    _sig, _disk, _cd_disk, n_disk, n_total, _cd_size, cd_off, _clen = struct.unpack("<4s4H2LH", data[eocd:eocd + 22])
    if n_total != 1:
        raise ValueError(f"Archiv enthaelt {n_total} Dateien, erwartet 1")
    cd = data.find(b"PK\x01\x02", cd_off if n_disk else 0)
    f = struct.unpack("<4s6H3L5H2L", data[cd:cd + 46])
    method, crc, csize, usize, nlen = f[4], f[7], f[8], f[9], f[10]
    name = data[cd + 46:cd + 46 + nlen].decode("utf-8")
    disk_start, local_off = f[13], f[16]
    if csize == 0xFFFFFFFF or usize == 0xFFFFFFFF:
        raise ValueError("Zip64 wird nicht unterstuetzt")
    return name, method, crc, csize, usize, disk_start, local_off


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 1
    zip_path, target = argv[1], argv[2]
    parts = parts_for(zip_path)
    name, method, crc, csize, usize, disk_start, local_off = central_directory(parts[-1])
    if disk_start != 0:
        raise ValueError("Datei beginnt nicht im ersten Teil")
    if method not in (0, 8):
        raise ValueError(f"Kompressionsmethode {method} nicht unterstuetzt")

    reader = ConcatReader(parts)
    reader.read(local_off)  # ggf. Split-Signatur PK\x07\x08
    lh = reader.read(30)
    if lh[:4] != b"PK\x03\x04":
        raise ValueError("Lokaler Header nicht gefunden")
    nlen, elen = struct.unpack("<2H", lh[26:30])
    reader.read(nlen + elen)

    os.makedirs(target, exist_ok=True)
    out_path = os.path.join(target, os.path.basename(name))
    tmp_path = out_path + ".part"
    inflater = zlib.decompressobj(-15) if method == 8 else None
    left, written, crc_calc, step = csize, 0, 0, 1 << 22
    next_report = 0
    with open(tmp_path, "wb") as out:
        while left > 0:
            chunk = reader.read(min(step, left))
            if not chunk:
                raise ValueError("Archiv unvollstaendig (Teil fehlt?)")
            left -= len(chunk)
            data = inflater.decompress(chunk) if inflater else chunk
            out.write(data)
            crc_calc = zlib.crc32(data, crc_calc)
            written += len(data)
            if written >= next_report:
                print(f"\r    ... {written * 100 // usize:3d} %", end="", flush=True)
                next_report += usize // 50
        if inflater:
            data = inflater.flush()
            out.write(data)
            crc_calc = zlib.crc32(data, crc_calc)
            written += len(data)
    print("\r    ... 100 %")
    if written != usize or (crc_calc & 0xFFFFFFFF) != crc:
        os.remove(tmp_path)
        raise ValueError("CRC/Groesse stimmt nicht – Archiv beschaedigt")
    os.replace(tmp_path, out_path)
    print(out_path)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except ValueError as exc:
        print(f"Fehler: {exc}", file=sys.stderr)
        sys.exit(1)
