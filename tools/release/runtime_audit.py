"""G05 候选发行 EXE 运行审计；不启动源码 Godot。"""
from __future__ import annotations
import argparse, json, os, re, signal, subprocess, time
from pathlib import Path

READY = {
    "server": re.compile(r"^SERVER_GATEWAY_READY\s+(\{.*\})$"),
    "signaling": re.compile(r"^SERVER_SIGNALING_READY\s+(\{.*\})$")
}

MISSING_CONFIGURATION_ERRORS = {
    "server": "ERROR: 服务端配置无效，CFG 只接受 server、data 与 relay 段",
    "signaling": "ERROR: 信令配置不可读或包含未知 CFG 段/嵌套覆盖",
}


def error_lines(output):
    return [line.strip() for line in output.splitlines()
            if "ERROR:" in line or "SCRIPT ERROR" in line]


def runtime_passed(value):
    # READY/exit0 不覆盖后续 ERROR，也不把强制终止或旧 stdin 回退当合法 CtrlBreak。
    stop = "ctrl_break_shutdown" if value.get("role") == "server" else "ctrl_break"
    return (value.get("ready") is True
            and value.get("ready_payload", {}).get("ok") is True
            and value.get("exit_code") == 0
            and value.get("stop_method") == stop
            and not error_lines("\n".join(value.get("lines", []))))


def missing_config_passed(role, code, output):
    expected = MISSING_CONFIGURATION_ERRORS[role]
    # 原生产 signaling 当前 exit2 会明确 RED；AV 或其他非零不是配置拒绝证明。
    return code == 1 and error_lines(output) == [expected] and not any(
        READY[role].match(line) for line in output.splitlines())


def _run(exe: Path, args: list[str], timeout: float, cwd: Path):
    creationflags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    return subprocess.Popen(
        [str(exe), "--headless", "--audio-driver", "Dummy", "--", *args],
        cwd=str(cwd), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
        creationflags=creationflags,
    )


def _collect_ready(proc, role, timeout):
    deadline = time.monotonic() + timeout
    lines = []
    ready = None
    while time.monotonic() < deadline:
        line = proc.stdout.readline()
        if line:
            lines.append(line.rstrip("\r\n"))
            match = READY[role].match(lines[-1])
            if match:
                ready = json.loads(match.group(1))
                break
        elif proc.poll() is not None:
            break
        else:
            time.sleep(0.05)
    return ready, lines


def _stop_server(proc, timeout):
    # server_process_signals 将 CTRL_BREAK 转为 server_shutdown.start；这是
    # 服务端保存/关停路径。stdin stop 只作为旧控制台兼容回退。
    try:
        proc.send_signal(signal.CTRL_BREAK_EVENT)
        return proc.wait(timeout=timeout), "ctrl_break_shutdown"
    except (AttributeError, OSError, subprocess.TimeoutExpired):
        try:
            proc.stdin.write("stop\n")
            proc.stdin.flush()
            return proc.wait(timeout=timeout), "console_stop"
        except (OSError, subprocess.TimeoutExpired):
            proc.kill()
            return proc.wait(timeout=5), "forced_kill_after_shutdown_failure"


def _stop_signaling(proc, timeout):
    # server_process_signals 将 CTRL_BREAK 转换为正式退出请求。
    method = "ctrl_break"
    try:
        proc.send_signal(signal.CTRL_BREAK_EVENT)
        code = proc.wait(timeout=timeout)
        return code, method
    except (AttributeError, OSError, subprocess.TimeoutExpired):
        proc.kill()
        return proc.wait(timeout=5), "forced_kill_after_signal_failure"


def run_role(package: Path, role: str, config: Path, timeout: float = 30.0) -> dict:
    exe_name = "FateServer.exe" if role == "server" else "FateSignaling.exe"
    exe = package / exe_name
    if not exe.is_file() or exe.stat().st_size == 0:
        raise ValueError(f"缺少候选 EXE: {exe}")
    proc = _run(exe, ["--server-gateway" if role == "server" else "--server-signaling", "--config", str(config)], timeout, package)
    ready, lines = _collect_ready(proc, role, timeout)
    if ready is None:
        code = proc.poll()
        if code is None:
            proc.kill(); code = proc.wait(timeout=5)
        return {"role": role, "ready": False, "exit_code": code, "stop_method": "not_ready", "lines": lines}
    code, stop_method = (_stop_server(proc, timeout) if role == "server" else _stop_signaling(proc, timeout))
    tail = lines[:]
    while proc.stdout is not None:
        line = proc.stdout.readline()
        if not line: break
        tail.append(line.rstrip("\r\n"))
    return {"role": role, "ready": True, "ready_payload": ready, "exit_code": code, "stop_method": stop_method, "lines": tail}


def negative_missing_config(package: Path, role: str, missing: Path, timeout: float = 15.0) -> dict:
    exe_name = "FateServer.exe" if role == "server" else "FateSignaling.exe"
    proc = _run(package / exe_name, ["--server-gateway" if role == "server" else "--server-signaling", "--config", str(missing)], timeout, package)
    try:
        code = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill(); code = proc.wait(timeout=5)
    output = proc.stdout.read() if proc.stdout else ""
    return {"role": role, "exit_code": code,
            "rejected": missing_config_passed(role, code, output),
            "error_lines": error_lines(output), "output": output}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--package", type=Path, required=True)
    ap.add_argument("--role", choices=("server", "signaling"), required=True)
    ap.add_argument("--config", type=Path, required=True)
    ap.add_argument("--missing-config", type=Path)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--timeout", type=float, default=30.0)
    a = ap.parse_args(argv)
    result = {"runtime": run_role(a.package, a.role, a.config, a.timeout)}
    result["runtime"]["passed"] = runtime_passed(result["runtime"])
    result["runtime"]["error_lines"] = error_lines("\n".join(result["runtime"].get("lines", [])))
    if a.missing_config:
        result["missing_config"] = negative_missing_config(a.package, a.role, a.missing_config, a.timeout)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["runtime"]["passed"] and ("missing_config" not in result or result["missing_config"]["rejected"]) else 2


if __name__ == "__main__":
    raise SystemExit(main())
