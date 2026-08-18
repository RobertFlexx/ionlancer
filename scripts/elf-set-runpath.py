#!/usr/bin/env python3
import struct
import sys
from pathlib import Path

DT_NULL = 0
DT_RPATH = 15
DT_STRTAB = 5
DT_STRSZ = 10
DT_RUNPATH = 29
PT_LOAD = 1
PT_DYNAMIC = 2


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def main():
    if len(sys.argv) != 3:
        die("usage: elf-set-runpath.py ELF NEW_RUNPATH")

    path = Path(sys.argv[1])
    new = sys.argv[2].encode()
    data = bytearray(path.read_bytes())

    if data[:4] != b"\x7fELF":
        die(f"{path} is not an ELF file")
    if data[4] != 2:
        die("only ELF64 is supported")

    if data[5] == 1:
        endian = "<"
    elif data[5] == 2:
        endian = ">"
    else:
        die("unknown ELF endianness")

    phoff = struct.unpack_from(endian + "Q", data, 32)[0]
    phentsize = struct.unpack_from(endian + "H", data, 54)[0]
    phnum = struct.unpack_from(endian + "H", data, 56)[0]
    if phentsize < 56:
        die("unexpected program-header size")

    loads = []
    dyn_off = None
    dyn_size = None

    for i in range(phnum):
        off = phoff + i * phentsize
        p_type = struct.unpack_from(endian + "I", data, off)[0]
        p_offset, p_vaddr, _, p_filesz, _, _ = struct.unpack_from(endian + "QQQQQQ", data, off + 8)
        if p_type == PT_LOAD:
            loads.append((p_vaddr, p_vaddr + p_filesz, p_offset))
        elif p_type == PT_DYNAMIC:
            dyn_off = p_offset
            dyn_size = p_filesz

    if dyn_off is None:
        die("ELF has no PT_DYNAMIC segment")

    strtab_vaddr = None
    strsz = None
    string_index = None

    for off in range(dyn_off, dyn_off + dyn_size, 16):
        tag, value = struct.unpack_from(endian + "QQ", data, off)
        if tag == DT_NULL:
            break
        if tag == DT_STRTAB:
            strtab_vaddr = value
        elif tag == DT_STRSZ:
            strsz = value
        elif tag == DT_RUNPATH or (tag == DT_RPATH and string_index is None):
            string_index = value

    if strtab_vaddr is None or strsz is None:
        die("ELF dynamic string table is incomplete")
    if string_index is None:
        die("ELF has no RUNPATH or RPATH")

    strtab_off = None
    for lo, hi, file_off in loads:
        if lo <= strtab_vaddr < hi:
            strtab_off = file_off + strtab_vaddr - lo
            break
    if strtab_off is None:
        die("could not locate the dynamic string table")

    start = strtab_off + string_index
    end = data.find(b"\0", start, strtab_off + strsz)
    if end < 0:
        die("unterminated RUNPATH string")

    old_len = end - start
    if len(new) > old_len:
        die("replacement RUNPATH is too long")

    data[start:start + old_len] = new + b"\0" * (old_len - len(new))
    path.write_bytes(data)
    print(f"runpath: {new.decode()}")


if __name__ == "__main__":
    main()
