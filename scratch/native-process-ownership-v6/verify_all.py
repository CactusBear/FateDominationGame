from pathlib import Path
import json
import subprocess
import sys
out = Path(__file__).resolve().parent
logs = out / 'logs'
logs.mkdir(exist_ok=True)
root = out.parents[1]
linux_root = '/mnt/e/Projects/Godot/FateDominationGame-master/scratch/native-process-ownership-v6'
steps = [
    ('generate', [sys.executable, str(out / 'generate_patch.py')], root),
    ('static', [str(out / 'tools-env/Scripts/python.exe'), str(out / 'static_test.py')], root),
    ('patch-check', ['git', 'apply', '--check', str(out / 'ownership-v6.patch')], root),
    ('windows-native', ['cmd.exe', '/c', 'verify_windows.cmd'], out),
    ('linux-native', ['wsl', '-d', 'FateLinux', '-e', 'sh', '-lc', f'cd {linux_root} && g++ -std=c++17 -Wall -Wextra -Werror -pthread -Ioverlay/addons/fate_server_signals/src native_test.cpp overlay/addons/fate_server_signals/src/process_owner_core.cpp -o native_test_linux && ./native_test_linux && ./native_test_linux --blocked'], out),
    ('windows-extension', ['cmd.exe', '/c', 'build_windows.cmd'], out),
    ('linux-extension', ['wsl', '-d', 'FateLinux', '-e', 'sh', '-lc', f'cd {linux_root} && PYTHONPATH="$PWD/tools-env/Lib/site-packages" python3 -m SCons -C overlay/addons/fate_server_signals platform=linux target=template_release arch=x86_64 godot_cpp_dir="$PWD/deps/godot-cpp-714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa" build_profile=/mnt/e/Projects/Godot/FateDominationGame-master/addons/fate_server_signals/build_profile.json -j2'], out),
]
results = {}
for name, command, cwd in steps:
    result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    (logs / (name + '.log')).write_bytes(result.stdout)
    results[name] = {'exit_code':result.returncode, 'log':str(logs / (name + '.log'))}
    print(name, 'exit=', result.returncode)
    if result.returncode:
        print(result.stdout.decode('utf-8', errors='replace'))
        break
(logs / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
if len(results) != len(steps) or any(r['exit_code'] for r in results.values()): sys.exit(1)
print('PASS all seven verification stages; no Godot execution')
