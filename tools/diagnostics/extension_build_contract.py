"""Read-only static GDExtension audit: never loads a PE or launches Godot.

Only --output writes, and only to a new file on E:. Uses Python stdlib only.
Version strings/compile markers are evidence, NOT a complete ABI certificate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class PE:
    def __init__(self, data: bytes):
        self.data = data
        if data[:2] != b"MZ":
            raise ValueError("Not MZ")
        self.pe = self.u32(0x3C)
        if data[self.pe:self.pe + 4] != b"PE\0\0":
            raise ValueError("Not PE")
        self.machine, count = self.unpack("HH", self.pe + 4)
        self.optional = self.pe + 24
        magic = self.u16(self.optional)
        if magic not in (0x10B, 0x20B):
            raise ValueError("Unsupported optional header")
        self.bits = 64 if magic == 0x20B else 32
        self.image_base = self.unpack("Q" if self.bits == 64 else "I", self.optional + (24 if self.bits == 64 else 28))[0]
        self.directory_offset = self.optional + (112 if self.bits == 64 else 96)
        self.directory_count = self.u32(self.optional + (108 if self.bits == 64 else 92))
        section_table = self.optional + self.u16(self.pe + 20)
        self.sections = []
        for i in range(count):
            at = section_table + i * 40
            name = data[at:at + 8].rstrip(b"\0").decode("ascii", "replace")
            virtual_size, virtual_address, size, offset = self.unpack("IIII", at + 8)
            self.sections.append(dict(name=name, virtual_size=virtual_size, rva=virtual_address, size=size, offset=offset))

    def unpack(self, fmt: str, offset: int):
        return struct.unpack_from("<" + fmt, self.data, offset)

    def u16(self, at: int) -> int:
        return self.unpack("H", at)[0]

    def u32(self, at: int) -> int:
        return self.unpack("I", at)[0]

    def offset(self, rva: int) -> int:
        if rva < self.u32(self.optional + 60):
            return rva
        for section in self.sections:
            delta = rva - section["rva"]
            if 0 <= delta < section["size"]:
                return section["offset"] + delta
        raise ValueError(f"RVA not backed by file: {rva:#x}")

    def string(self, rva: int) -> str:
        at = self.offset(rva)
        end = self.data.index(b"\0", at)
        return self.data[at:end].decode("ascii", "replace")

    def directory(self, index: int):
        if index >= self.directory_count:
            return 0, 0
        return self.unpack("II", self.directory_offset + index * 8)

    def exports(self):
        rva, size = self.directory(0)
        if not rva:
            return []
        at = self.offset(rva)
        base, count, names, functions, name_table, ordinal_table = self.unpack("IIIIII", at + 16)
        result = []
        for i in range(names):
            name_rva = self.u32(self.offset(name_table) + i * 4)
            ordinal = self.u16(self.offset(ordinal_table) + i * 2)
            address = self.u32(self.offset(functions) + ordinal * 4)
            result.append(dict(name=self.string(name_rva), ordinal=base + ordinal, rva=hex(address), forwarder=self.string(address) if rva <= address < rva + size else None))
        return result

    def thunk_names(self, thunk_rva: int):
        if not thunk_rva:
            return []
        at, step = self.offset(thunk_rva), self.bits // 8
        result = []
        ordinal_bit = 1 << (self.bits - 1)
        for i in range(100000):
            value = self.unpack("Q" if step == 8 else "I", at + i * step)[0]
            if not value:
                return result
            result.append(f"ordinal:{value & 0xFFFF}" if value & ordinal_bit else self.string(value + 2))
        raise ValueError("Unterminated import thunk")

    def imports(self, delayed: bool = False):
        rva, size = self.directory(13 if delayed else 1)
        if not rva:
            return []
        at, step = self.offset(rva), 32 if delayed else 20
        result = []
        for i in range(size // step + 1):
            fields = self.unpack("IIIIIIII" if delayed else "IIIII", at + i * step)
            if not any(fields):
                return result
            if delayed:
                attributes, name, _, iat, thunk, *_ = fields
                if not attributes & 1:
                    name -= self.image_base
                    thunk = thunk - self.image_base if thunk else 0
                    iat = iat - self.image_base if iat else 0
            else:
                thunk, _, _, name, iat = fields
            result.append(dict(library=self.string(name), symbols=self.thunk_names(thunk or iat)))
        raise ValueError("Unterminated import descriptors")

    def selected_coff_symbols(self):
        pointer, count = self.unpack("II", self.pe + 12)
        if not pointer or not count:
            return []
        string_table = pointer + count * 18
        result, i = [], 0
        while i < count:
            at = pointer + i * 18
            raw = self.data[at:at + 8]
            if raw[:4] == bytes(4):
                start = string_table + struct.unpack_from("<I", raw, 4)[0]
                end = self.data.index(b"\0", start)
                name = self.data[start:end].decode("ascii", "replace")
            else:
                name = raw.rstrip(b"\0").decode("ascii", "replace")
            value, section, _, _, auxiliary = self.unpack("IhHBB", at + 8)
            selected = ("_GLOBAL__sub_I" in name or "register_fate_" in name or "initialize_signals" in name or "GDExtensionBinding4init" in name or "minimum_library_initialization" in name or name == "fate_server_signals_init")
            if selected and 0 < section <= len(self.sections):
                result.append(dict(name=name, rva=hex(self.sections[section - 1]["rva"] + value)))
            i += 1 + auxiliary
        return result

    def version(self):
        # Restrict scanning to .rsrc; fixed info signature is independent of locale.
        versions = []
        for section in self.sections:
            if section["name"] != ".rsrc":
                continue
            data = self.data[section["offset"]:section["offset"] + section["size"]]
            for match in re.finditer(re.escape(b"\xbd\x04\xef\xfe"), data):
                at = match.start()
                if at + 52 > len(data):
                    continue
                values = struct.unpack_from("<13I", data, at)
                if values[1] != 0x10000:
                    continue
                def dotted(ms, ls):
                    return f"{ms >> 16}.{ms & 65535}.{ls >> 16}.{ls & 65535}"
                versions.append(dict(file_version=dotted(values[2], values[3]), product_version=dotted(values[4], values[5]), file_flags=hex(values[7]), file_type=values[9]))
        return versions


def inspect_pe(path: Path):
    data = path.read_bytes()
    pe = PE(data)
    build_strings = sorted(set(m.group().decode("ascii", "replace") for m in re.finditer(rb"[0-9]+\.[0-9]+(?:\.[0-9]+)?\.(?:stable|dev|beta|rc)[A-Za-z0-9_.+\-]{0,100}", data)))
    markers = [s.decode() for s in [b"FateServerSignals", b"FateProcessOwner", b"FateAtomicFileReplace", b"FateCollectionIdentity", b"classdb_register_extension_class4", b"GCC: (", b"Mingw-w64 runtime failure:", b"REAL_T_IS_DOUBLE"] if s in data]
    commits = sorted(set(m.group(1).decode() for m in re.finditer(rb"\x00([0-9a-f]{40})\x00", data)))
    producers = sorted(set(m.group().decode("ascii", "replace") for m in re.finditer(rb"GCC: [^\x00\r\n]{1,160}", data)))
    return dict(path=str(path), size=len(data), sha256=sha256(data), machine=hex(pe.machine), bits=pe.bits, image_base=hex(pe.image_base), entry_rva=hex(pe.u32(pe.optional + 16)), sections=pe.sections, exports=pe.exports(), imports=pe.imports(), delayed_imports=pe.imports(True), fixed_version=pe.version(), build_strings=build_strings, markers=markers, embedded_commit_candidates=commits, gcc_producers=producers, selected_coff_symbols=pe.selected_coff_symbols())


def dependency_audit(path: Path, archive: Path | None):
    api = path / "gdextension/extension_api.json"
    data = json.loads(api.read_text(encoding="utf-8"))
    files = ["SConstruct", "tools/godotcpp.py", "tools/windows.py", "tools/common_compiler_flags.py", "gdextension/extension_api.json", "gdextension/gdextension_interface.h", "src/godot.cpp", "src/core/class_db.cpp", "gen/include/godot_cpp/core/version.hpp", "gen/include/godot_cpp/variant/builtin_types.hpp"]
    result = dict(path=str(path), git_metadata_present=(path / ".git").exists(), api_header=data["header"], builtin_sizes=data.get("builtin_class_sizes"), files={name:sha256((path / name).read_bytes()) for name in files if (path / name).is_file()})
    if archive:
        different, missing, compared = [], [], 0
        with zipfile.ZipFile(archive) as z:
            roots = sorted({entry.filename.split("/")[0] for entry in z.infolist()})
            for entry in z.infolist():
                if entry.is_dir():
                    continue
                relative = entry.filename.split("/", 1)[1]
                target = path / relative
                if not target.is_file():
                    missing.append(relative)
                else:
                    compared += 1
                    if sha256(z.read(entry)) != sha256(target.read_bytes()):
                        different.append(relative)
        result["archive_comparison"] = dict(archive=str(archive), sha256=sha256(archive.read_bytes()), roots=roots, compared=compared, missing=missing, different=different)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pe", type=Path, action="append", default=[])
    parser.add_argument("--godot-cpp", type=Path)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.pe and not args.godot_cpp:
        parser.error("Supply --pe and/or --godot-cpp")
    if args.output and (args.output.drive.upper() != "E:" or args.output.exists()):
        parser.error("--output must be a new file on E:")
    result = dict(mode="static_only_no_dll_load_no_engine_execution", pe=[inspect_pe(path) for path in args.pe])
    if args.godot_cpp:
        result["godot_cpp"] = dependency_audit(args.godot_cpp, args.archive)
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8") as output:
            output.write(text + "\n")
        print(json.dumps(dict(output=str(args.output), pe_count=len(result["pe"]), dependency=bool(args.godot_cpp))))
    else:
        print(text)


if __name__ == "__main__":
    main()
