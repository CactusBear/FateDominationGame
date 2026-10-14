"""Bounded, isolated MSVC contract differential; never invokes Godot or edits SDK."""
from pathlib import Path
import argparse
import hashlib
import json
import msvcrt
import os
import pickle
import re
import subprocess
import sys
import time
import zipfile
import ctypes
from ctypes import wintypes as w


class CompileJob:
    """Gate launch before assigning an exclusive kill-on-close diagnostic Job."""
    def __init__(self):
        self.k = ctypes.WinDLL("kernel32", use_last_error=True)
        self.k.CreateJobObjectW.argtypes = [ctypes.c_void_p, w.LPCWSTR]
        self.k.CreateJobObjectW.restype = w.HANDLE
        self.k.SetInformationJobObject.argtypes = [w.HANDLE, ctypes.c_int, ctypes.c_void_p, w.DWORD]
        self.k.SetInformationJobObject.restype = w.BOOL
        self.k.AssignProcessToJobObject.argtypes = [w.HANDLE, w.HANDLE]
        self.k.AssignProcessToJobObject.restype = w.BOOL
        self.k.TerminateJobObject.argtypes = [w.HANDLE, w.UINT]
        self.k.CloseHandle.argtypes = [w.HANDLE]
        class Basic(ctypes.Structure):
            _fields_ = [("process_time", ctypes.c_int64), ("job_time", ctypes.c_int64),
                        ("flags", w.DWORD), ("min_ws", ctypes.c_size_t), ("max_ws", ctypes.c_size_t),
                        ("active", w.DWORD), ("affinity", ctypes.c_size_t), ("priority", w.DWORD), ("scheduling", w.DWORD)]
        class Extended(ctypes.Structure):
            _fields_ = [("basic", Basic), ("io", ctypes.c_uint64 * 6),
                        ("process_mem", ctypes.c_size_t), ("job_mem", ctypes.c_size_t),
                        ("peak_process_mem", ctypes.c_size_t), ("peak_job_mem", ctypes.c_size_t)]
        self.handle = self.k.CreateJobObjectW(None, None)
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())
        limit = Extended()
        limit.basic.flags = 0x2000
        if not self.k.SetInformationJobObject(self.handle, 9, ctypes.byref(limit), ctypes.sizeof(limit)):
            self.close()
            raise ctypes.WinError(ctypes.get_last_error())

    def run(self, command, cwd, env, log, timeout):
        gate = "import subprocess,sys; assert input()=='GO'; sys.exit(subprocess.run(sys.argv[1:]).returncode)"
        p = subprocess.Popen([sys.executable, "-c", gate, *command], cwd=cwd, env=env,
                             stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT)
        if not self.k.AssignProcessToJobObject(self.handle, int(p._handle)):
            error = ctypes.get_last_error()
            p.kill()
            p.wait()
            raise ctypes.WinError(error)
        p.stdin.write(b"GO\n")
        p.stdin.flush()
        p.stdin.close()
        try:
            p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.k.TerminateJobObject(self.handle, 124)
            p.wait(timeout=15)
            raise
        return p.returncode

    def close(self):
        if self.handle:
            self.k.CloseHandle(self.handle)
            self.handle = None


REPO = Path(__file__).resolve().parents[2]
BASE = REPO / "scratch/native-process-ownership-v6"
COMMIT = "714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa"
SDK = BASE / ("deps/godot-cpp-" + COMMIT)
SRC = REPO / "addons/fate_server_signals/src"
LIB = SDK / "bin/libgodot-cpp.windows.template_release.x86_64.lib"
VCVARS = Path("D:/VS2022/VC/Auxiliary/Build/vcvars64.bat")
OLD = Path("E:/FateNativeBuild-round51-red")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--stage", choices=["probe", "build"], required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    if out.drive.upper() != "E:" or out.exists():
        raise RuntimeError("Require a new physical E-drive output directory")
    out.mkdir(parents=True)
    for p in [out, *out.parents]:
        if p.stat(follow_symlinks=False).st_file_attributes & 0x400:
            raise RuntimeError("Reparse output path rejected: " + str(p))
    lock = open("E:/FateDiagnostics/round55-native-build.lock", "a+b")
    lock.seek(0)
    if not lock.read(1):
        lock.write(b"0")
        lock.flush()
    lock.seek(0)
    msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    deadline = time.monotonic() + 600
    report = {"output": str(out), "runtime": "NOTRUN", "commands": [], "laststage": "start"}
    formal = {str(p): sha(p) for p in (REPO / "addons/fate_server_signals/bin").glob("*.dll")}
    frozen = {str(p): sha(p) for p in SRC.iterdir() if p.suffix in [".cpp", ".hpp"]}
    frozen.update({str(LIB): sha(LIB)})
    env = dict(os.environ, TMP=str(out), TEMP=str(out), TMPDIR=str(out), PYTHONDONTWRITEBYTECODE="1")
    job = CompileJob()
    report["compile_job"] = {"exclusive": True, "kill_on_close": True, "gated_before_launch": True}
    sys.dont_write_bytecode = True

    def run(stage, command, cwd=out):
        report["laststage"] = stage
        entry = {"stage": stage, "argv": command, "cwd": str(cwd)}
        report["commands"].append(entry)
        dump(out / "manifest.json", report)
        started = time.monotonic()
        # One overall deadline, no retry; only this gated Job is terminated.
        with open(out / (stage + ".raw.log"), "wb") as log:
            try:
                exit_code = job.run(command, cwd, env, log, max(0.01, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                entry["timeout"] = True
                raise RuntimeError("600s overall deadline: " + stage)
        entry.update(exit=exit_code, seconds=round(time.monotonic() - started, 3))
        raw = (out / (stage + ".raw.log")).read_bytes()
        try:
            text = raw.decode("utf-8")
            encoding = "utf-8"
        except UnicodeDecodeError:
            text = raw.decode("gbk")
            encoding = "gbk"
        (out / (stage + ".utf8.log")).write_text(text, encoding="utf-8")
        entry.update(raw_sha256=hashlib.sha256(raw).hexdigest(), encoding=encoding)
        dump(out / "manifest.json", report)
        print(stage, "exit", exit_code, "seconds", entry["seconds"], flush=True)
        if exit_code:
            print("\n".join(x for x in text.splitlines() if "error " in x)[:5000], flush=True)
        return exit_code, text

    def batch(stage, command):
        path = out / (stage + ".cmd")
        path.write_text('@echo off\ncall "' + str(VCVARS) + '" >nul\nif errorlevel 1 exit /b 10\n' + command + '\nexit /b %errorlevel%\n', encoding="utf-8")
        return run(stage, ["cmd.exe", "/d", "/c", str(path)])

    try:
        report["sources"] = frozen
        report["formal_before"] = formal
        oldraw = (OLD / "binding-build.raw.log").read_bytes()
        (out / "previous-binding-build.raw.log").write_bytes(oldraw)
        (out / "previous-binding-build.utf8.log").write_text(oldraw.decode("gbk"), encoding="utf-8")
        report["previous_log"] = {"sha256": hashlib.sha256(oldraw).hexdigest(), "encoding": "gbk", "strict": True}
        report["previous_command"] = (OLD / "binding-build.cmd").read_text()
        includes = [SDK / "include", SDK / "gen/include", SDK / "gdextension", SRC]
        inc = " ".join('/I"' + str(p) + '"' for p in includes)
        common = "/nologo /std:c++17 /EHsc /W4 /DGDEXTENSION /D_WIN32_WINNT=0x0A00 " + inc
        required = "/DTYPED_METHOD_BIND /DNOMINMAX /utf-8 /MT"
        report["probe_base"] = common
        report["probe_delta"] = required
        report["include"] = [str(p) for p in includes]
        report["api"] = {"commit": COMMIT, "header": json.loads((SDK / "gdextension/extension_api.json").read_text())["header"], "api_sha256": sha(SDK / "gdextension/extension_api.json"), "interface_sha256": sha(SDK / "gdextension/gdextension_interface.h")}
        report["sdk_headers"] = {str(p.relative_to(SDK)): sha(p) for sub in ["include", "gen/include", "gdextension"] for p in (SDK / sub).rglob("*") if p.is_file()}
        with zipfile.ZipFile(BASE / "godot-cpp.zip") as z:
            original = {i.filename.split("/", 1)[1]: hashlib.sha256(z.read(i)).hexdigest() for i in z.infolist() if not i.is_dir()}
        matches = []
        for name, value in original.items():
            p = SDK / name
            if p.is_file() and p.suffix in [".cpp", ".hpp", ".h", ".py", ".json"]:
                if sha(p) != value:
                    raise RuntimeError("SDK archive mismatch " + name)
                matches.append(name)
        report["sdk_archive"] = {"sha256": sha(BASE / "godot-cpp.zip"), "matched_files": len(matches), "commit_root": z.namelist()[0].split("/")[0]}
        sys.path.insert(0, str(SDK))
        import binding_generator
        import build_profile
        reconstruction = out / "official-profile-reconstruction"
        reconstruction.mkdir()
        profile = REPO / "addons/fate_server_signals/build_profile.json"
        api = build_profile.generate_trimmed_api(str(SDK / "gdextension/extension_api.json"), str(profile))
        binding_generator._generate_bindings(api, True, "64", "single", str(reconstruction))
        report["profile"] = {"path": str(profile), "sha256": sha(profile), "generated_output": str(reconstruction), "sdk_unmodified": True}
        sys.path.insert(0, str(BASE / "tools-env/Lib/site-packages"))
        import SCons.SConsign
        import SCons.Node.FS
        dbpath = BASE / "overlay/addons/fate_server_signals/.sconsign.dblite"
        db = pickle.loads(dbpath.read_bytes())
        entries = {}
        for directory, values in db.items():
            for name, item in pickle.loads(values).items():
                entries[str(Path(directory) / name).lower()] = item
        libentry = entries[str(LIB).lower()]
        if hashlib.md5(LIB.read_bytes()).hexdigest() != libentry.ninfo.csig:
            raise RuntimeError("Existing library differs from historical SCons target signature")
        verified = []
        archive_bytes = LIB.read_bytes()
        members = {}
        offset, names = 8, b""
        while offset < len(archive_bytes):
            header = archive_bytes[offset:offset + 60]
            name = header[:16].decode("ascii").strip()
            size = int(header[48:58])
            data = archive_bytes[offset + 60:offset + 60 + size]
            offset += 60 + size + size % 2
            if name == "//":
                names = data
            elif name.startswith("/") and name[1:].isdigit():
                resolved = names[int(name[1:]):].split(b"\x00")[0].decode("ascii")
                members[str(Path(resolved)).lower()] = data
        newline_equivalent = {}
        for name, sig in zip(libentry.binfo.bsources, libentry.binfo.bsourcesigs):
            p = Path(name)
            object_bytes = members[str(p).lower()]
            if hashlib.md5(object_bytes).hexdigest() != sig.csig:
                raise RuntimeError("Historical library archive member changed " + name)
            obj = entries[str(p).lower()]
            dependencies = list(zip(obj.binfo.bsources, obj.binfo.bsourcesigs)) + list(zip(obj.binfo.bimplicit, obj.binfo.bimplicitsigs))
            for dep, dsig in dependencies:
                if not hasattr(dsig, "csig"):
                    continue
                dp = Path(dep)
                if dp.exists() and hashlib.md5(dp.read_bytes()).hexdigest() != dsig.csig:
                    rawdep = dp.read_bytes()
                    normalized = rawdep.replace(b"\r\n", b"\n")
                    if dp.is_relative_to(SDK / "gen") and dp.suffix in [".hpp", ".cpp"] and hashlib.md5(normalized).hexdigest() == dsig.csig:
                        newline_equivalent[dep] = {"historical_lf_md5": dsig.csig, "current_sha256": sha(dp), "difference": "CRLF only; exact LF bytes match historical dependency"}
                    elif dp.is_relative_to(SDK / "gen") and dp.suffix in [".hpp", ".cpp"]:
                        rebuilt = reconstruction / dp.relative_to(SDK)
                        if not rebuilt.is_file() or hashlib.md5(rebuilt.read_bytes().replace(b"\r\n", b"\n")).hexdigest() != dsig.csig:
                            raise RuntimeError("Official profile cannot reproduce historical header " + dep)
                        newline_equivalent[dep] = {"historical_lf_md5": dsig.csig, "current_sha256": sha(dp), "reconstructed_sha256": sha(rebuilt), "difference": "Current SDK generated full profile differs; official trimmed reconstruction matches historical LF bytes exactly"}
                    else:
                        raise RuntimeError("Historical object dependency changed " + dep)
            verified.append({"object": name, "sha256": hashlib.sha256(object_bytes).hexdigest(), "verified_from": "actual COFF archive member", "historical_action_sig": obj.binfo.bactsig})
        report["historical_generated_header_newlines"] = newline_equivalent
        directives = sorted({x.decode("ascii") for x in re.findall(rb'(?:/DEFAULTLIB|/FAILIFMISMATCH):[^\x00\r\n ]+', LIB.read_bytes())})
        if '/FAILIFMISMATCH:"RuntimeLibrary=MT_StaticRelease"' not in directives:
            raise RuntimeError("No actual /MT release CRT proof")
        report["library"] = {"path": str(LIB), "sha256": sha(LIB), "directives": directives, "sconsign_sha256": sha(dbpath), "verified_objects": verified}
        # Read the official environment without running generators or library builds.
        contract = out / "SConstruct"
        contract.write_text('import json\nfrom SCons.Script import *\nenv = SConscript(' + repr(str(SDK / "SConstruct")) + ')\nkeys = ["CCFLAGS", "CXXFLAGS", "CPPDEFINES", "CPPPATH", "LINKFLAGS", "SHLINKFLAGS", "LIBS", "precision", "target", "arch", "suffix", "disable_exceptions", "use_static_cpp", "is_msvc", "MSVC_VERSION"]\ndata = {k: str(env.get(k)) for k in keys}\nopen(' + repr(str(out / "official-env.json")) + ', "w").write(json.dumps(data, indent=2))\nDefault(Alias("contract"))\n', encoding="utf-8")
        py = BASE / "tools-env/Scripts/python.exe"
        code, _ = batch("official-env", '"' + str(py) + '" -m SCons -f "' + str(contract) + '" -n platform=windows use_mingw=no target=template_release arch=x86_64 precision=single disable_exceptions=false use_static_cpp=true build_library=false silence_msvc=false build_profile="' + str(REPO / "addons/fate_server_signals/build_profile.json") + '"')
        if code:
            raise RuntimeError("Official environment inspection failed")
        report["official_env"] = json.loads((out / "official-env.json").read_text())
        report["probe"] = {}
        for label, extra in [("A", ""), ("B", required)]:
            results = {}
            for name in ["process_owner_binding", "atomic_file_replace_binding"]:
                command = 'cl ' + common + ' ' + extra + ' /c "' + str(SRC / (name + ".cpp")) + '" /Fo:"' + str(out / (label + '-' + name + ".obj")) + '"'
                code, text = batch(label + "-" + name, command)
                results[name] = {"exit": code, "template_error": "error C2440" in text, "errors": re.findall(r"error C\d+", text)}
            report["probe"][label] = results
        dump(out / "manifest.json", report)
        if any(x["exit"] == 0 for x in report["probe"]["A"].values()):
            raise RuntimeError("A did not reproduce both binding failures")
        if any(x["exit"] != 0 for x in report["probe"]["B"].values()):
            raise RuntimeError("B required flags insufficient: inspect precise binding API")
        report["root_cause"] = "Same source/include: missing official MSVC binding/encoding/CRT contract; no header ABI mismatch established."
        if args.stage == "build":
            units = sorted(SRC.glob("*.cpp"))
            report["translation_units"] = [str(p) for p in units]
            build_includes = [SDK / "include", reconstruction / "gen/include", SDK / "gdextension", SRC]
            report["build_include"] = [str(p) for p in build_includes]
            report["reconstructed_headers"] = {str(p.relative_to(reconstruction)): sha(p) for p in (reconstruction / "gen/include").rglob("*.hpp")}
            build_common = common.replace(inc, " ".join('/I"' + str(p) + '"' for p in build_includes))
            defines = ["WINDOWS_ENABLED", "THREADS_ENABLED", "NDEBUG"]
            if "HOT_RELOAD_ENABLED" in report["official_env"]["CPPDEFINES"]:
                defines.append("HOT_RELOAD_ENABLED")
            flags = build_common + ' ' + required + ' /O2 ' + ' '.join('/D' + value for value in defines)
            objs = []
            for source in units:
                obj = out / (source.stem + ".obj")
                code, _ = batch("compile-" + source.stem, 'cl ' + flags + ' /c "' + str(source) + '" /Fo:"' + str(obj) + '"')
                if code:
                    raise RuntimeError("Plugin compile failed: " + source.name)
                objs.append(obj)
            dll = out / "libfate_server_signals.windows.template_release.x86_64.dll"
            link = 'link /nologo /DLL /WX /MACHINE:X64 /OUT:"' + str(dll) + '" /IMPLIB:"' + str(out / 'plugin.lib') + '" /MAP:"' + str(out / 'plugin.map') + '" ' + ' '.join('"' + str(p) + '"' for p in objs) + ' "' + str(LIB) + '" bcrypt.lib'
            response = out / "link.rsp"
            response.write_text(link[len('link '):], encoding="utf-8")
            code, _ = batch("plugin-link", '"D:/VS2022/VC/Tools/MSVC/14.44.35207/bin/HostX64/x64/link.exe" @"' + str(response) + '"')
            if code:
                raise RuntimeError("Plugin link failed")
            code, exports = batch("pe-exports", 'dumpbin /EXPORTS /HEADERS "' + str(dll) + '"')
            if code or "fate_server_signals_init" not in exports:
                raise RuntimeError("Entry point PE verification failed")
            data = dll.read_bytes()
            report["dll"] = {"path": str(dll), "sha256": sha(dll), "bytes": len(data), "pe_x64": "8664 machine (x64)" in exports or "8664 machine" in exports, "method_strings": {n: n.encode() in data for n in ["tree_observe", "remove_verified"]}}
            code, symbols = batch("binding-symbols", 'dumpbin /SYMBOLS "' + str(out / 'process_owner_binding.obj') + '" "' + str(out / 'atomic_file_replace_binding.obj') + '"')
            report["binding_symbols"] = {n: n in symbols for n in ["tree_observe", "remove_verified"]}
            if not all(report["binding_symbols"].values()) or not all(report["dll"]["method_strings"].values()) or not report["dll"]["pe_x64"]:
                raise RuntimeError("New method or architecture verification failed")
        report["laststage"] = "COMPLETE"
    except Exception as exc:
        report["error"] = str(exc)
        print("BLOCKED", str(exc), flush=True)
        raise
    finally:
        report["formal_after"] = {str(p): sha(p) for p in (REPO / "addons/fate_server_signals/bin").glob("*.dll")}
        report["formal_unchanged"] = report["formal_after"] == formal
        report["frozen_inputs_unchanged"] = all(Path(p).is_file() and sha(Path(p)) == value for p, value in frozen.items())
        report["sdk_headers_unchanged"] = all(sha(SDK / p) == value for p, value in report.get("sdk_headers", {}).items())
        dump(out / "manifest.json", report)
        job.close()
        lock.seek(0)
        msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
        lock.close()
        print("OUTPUT=" + str(out), "LASTSTAGE=" + report["laststage"], flush=True)


if __name__ == "__main__":
    main()
