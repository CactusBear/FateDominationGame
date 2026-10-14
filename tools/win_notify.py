"""Windows 系统通知：告诉用户此刻能不能操作电脑。

为什么需要它：非 headless（真窗口）测试会真的抢走鼠标/键盘（模拟点击、聚焦窗口、
截图）。这时候用户如果正在用电脑，双方会互相干扰——测试点到别处、用户点进测试窗口。
所以在真窗口测试的**开始**与**结束**各弹一条系统通知，明确告诉用户：
"现在不要操作电脑" / "现在可以操作电脑了"。

无第三方依赖：用 PowerShell + WinRT Toast（Windows 10/11 自带）。
Toast 不可用时退化为消息框，保证提示一定能到达用户。

用法（命令行）：
    python tools/win_notify.py start [标签]   # 通知：测试开始，勿操作电脑
    python tools/win_notify.py end   [标签]   # 通知：测试结束，可以操作
    python tools/win_notify.py say  标题 内容  # 任意通知

用法（当模块）：
    from tools.win_notify import occupy_start, occupy_end
    occupy_start("窗口验收")          # 测试前
    try: ...test...
    finally: occupy_end("窗口验收")   # 结束时也要弹（含异常/超时路径）

设计约定：本模块**不知道**是否 headless——那由调用方决定（headless 时不该弹，
因为不占用桌面）。只在真窗口路径调用。
"""

from __future__ import annotations

import contextlib
import os
import subprocess
import sys
from pathlib import Path

# 未注册的 AppId 在 Win10/11 上通常仍能弹出（显示为通用应用图标）。
# 需要固定显示名时可在系统里注册该 AppId，这里不写死任何机器相关路径。
APP_ID = "FateDomination.GodotTests"

# 通知标题前缀，让用户一眼分清是哪类事件；可被调用方覆盖。
START_TAGS = ("⚠", "开始")
END_TAGS = ("✓", "结束")

_PS_SOURCE = r"""
param([string]$Title, [string]$Message, [string]$AppId)
$ErrorActionPreference = 'Stop'
try {
  [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]
  [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime]
  $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
      [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
  $texts = $template.GetElementsByTagName('text')
  $texts.Item(0).AppendChild($template.CreateTextNode($Title)) | Out-Null
  $texts.Item(1).AppendChild($template.CreateTextNode($Message)) | Out-Null
  $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
  Write-Output 'TOAST_OK'
  exit 0
} catch {
  Write-Output ('TOAST_FAIL: ' + $_.Exception.Message)
  exit 1
}
"""


def _powershell() -> str:
    """优先 pwsh，退回 Windows PowerShell。"""
    for exe in ("pwsh", "powershell"):
        try:
            r = subprocess.run([exe, "-NoProfile", "-Command", "exit 0"],
                               capture_output=True, timeout=20)
            if r.returncode == 0:
                return exe
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
            continue
    return "powershell"


def _ps_script() -> Path:
    """把 PS 脚本落到临时目录（UTF-8 BOM，PowerShell 才不会把中文读成乱码）。"""
    tmp = os.environ.get("TMPDIR") or os.environ.get("TEMP") or os.environ.get("TMP") or "."
    path = Path(tmp) / "hermes_win_notify.ps1"
    # 内容变化时才重写，避免并发调用互相踩
    text = _PS_SOURCE.lstrip("\n")
    try:
        if not path.exists() or path.read_text(encoding="utf-8-sig") != text:
            path.write_text(text, encoding="utf-8-sig")
    except OSError:
        pass
    return path


def _fallback_messagebox(title: str, message: str) -> tuple[bool, str]:
    """Toast 不可用时的退化路径：一个短消息框。"""
    ps = (
        "Add-Type -AssemblyName System.Windows.Forms;"
        "[System.Windows.Forms.MessageBox]::Show($args[1], $args[0],"
        "'OK','Information') | Out-Null"
    )
    try:
        r = subprocess.run([_powershell(), "-NoProfile", "-Command", ps, title, message],
                           capture_output=True, timeout=60)
        return r.returncode == 0, "messagebox fallback"
    except Exception as exc:  # noqa: BLE001 - 通知失败不该让测试崩
        return False, f"messagebox failed: {exc}"


def notify(title: str, message: str, *, app_id: str = APP_ID,
           allow_fallback: bool = True) -> tuple[bool, str]:
    """弹一条 Windows 通知。返回 (是否成功, 说明)。

    绝不抛异常——通知失败不能影响测试本身。
    """
    if sys.platform != "win32":
        return False, "not windows"
    try:
        r = subprocess.run(
            [_powershell(), "-NoProfile", "-ExecutionPolicy", "Bypass",
             "-File", str(_ps_script()), title, message, app_id],
            capture_output=True, text=True, timeout=45,
        )
        out = (r.stdout or "").strip()
        if "TOAST_OK" in out:
            return True, "toast"
        detail = out or (r.stderr or "").strip() or f"exit {r.returncode}"
    except Exception as exc:  # noqa: BLE001
        detail = f"toast failed: {exc}"
    if allow_fallback:
        ok, why = _fallback_messagebox(title, message)
        return ok, f"{detail} -> {why}"
    return False, detail


def occupy_start(label: str = "窗口测试", *, foreground_required: bool = True) -> tuple[bool, str]:
    """通知：真窗口测试开始，马上会占用鼠标/键盘。

    foreground_required 由调用方按测试**真实需要**声明，本模块不猜：
      True  —— 测试靠真实前台窗口接收输入（例如从外部模拟 OS 点击），
               用户切走窗口或去点别处会让输入落空、测试直接失败；
      False —— 测试自己开窗口自行驱动（Godot 引擎内部输入、只做截图），
               窗口在后台也能跑，但**最小化或完全遮挡可能拍不到画面**。
    """
    mark, word = START_TAGS
    if foreground_required:
        body = ("测试【必须让窗口保持在前台】—— 请不要切换窗口、不要最小化，"
                "也不要操作鼠标键盘；结束时会再弹一条通知告诉你什么时候可以继续。")
    else:
        body = ("测试会自己开一个窗口（不需要它在前台）—— 你可以继续用电脑，"
                "只是不要最小化或整个盖住测试窗口；结束时会再弹一条通知。")
    return notify(f"{mark} {label}{word}", body)


def occupy_end(label: str = "窗口测试", ok: bool = True) -> tuple[bool, str]:
    """通知：真窗口测试结束，桌面已交还。"""
    mark, word = END_TAGS
    state = "已完成" if ok else "已结束（有失败项，请看报告）"
    return notify(f"{mark} {label}{word}",
                  f"测试{state} —— 现在【可以】操作电脑了。")


@contextlib.contextmanager
def window_occupancy(label: str = "窗口测试", *, enabled: bool = True,
                     foreground_required: bool = True):
    """把一段**真窗口**测试包起来：进入弹"勿操作电脑"，退出弹"可以操作"。

    enabled=False 时完全静默 —— "这次会不会占用桌面"由调用方判断
    （例如 argparse 的 --window），本模块不靠猜。

    foreground_required 同样由调用方按测试真实需要声明（见 occupy_start）：
    外部真实 OS 点击的验收传 True；Godot 自己驱动窗口的测试传 False。

    异常、超时、Ctrl-C 都会走到 finally，所以结束通知不会漏。

        with window_occupancy("窗口基线", enabled=args.window,
                              foreground_required=False):
            run_window_suite()          # 自己开窗口自行驱动
    """
    if not enabled:
        yield
        return
    occupy_start(label, foreground_required=foreground_required)
    failed = False
    try:
        yield
    except BaseException:
        failed = True
        raise
    finally:
        occupy_end(label, ok=not failed)


def main(argv: list[str]) -> int:
    args = argv[1:]
    if not args:
        print(__doc__)
        return 2
    action = args[0]
    label = args[1] if len(args) > 1 else "窗口测试"
    if action == "start":
        ok, how = occupy_start(label)
    elif action == "end":
        ok, how = occupy_end(label)
    elif action == "say":
        if len(args) < 3:
            print("say 需要 标题 与 内容")
            return 2
        ok, how = notify(args[1], args[2])
    else:
        print(f"未知动作：{action}")
        return 2
    print(f"{'OK' if ok else 'FAIL'} ({how})")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
