"""Source-level gate complements real ClassDB/IPC tests; never production source parsing."""
import ast
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    'FateServerSignals':['enable','protect_worker','disable','take_request'],
    'FateProcessOwner':['available','spawn','state','verify','terminate','release'],
    'FateAtomicFileReplace':['replace_validated_file'],
    'FateCollectionIdentity':['is_supported','candidate_key'],
}
CONTRACT = 'scripts/io/native_method_contract.gd'

def audit(root):
    errors = []
    source = root / CONTRACT
    if not source.is_file():
        errors.append('missing single explicit contract source')
    else:
        text = source.read_text(encoding='utf-8')
        match = re.search(r'const REQUIRED_METHODS:Dictionary = (\{.*?\n\})',text,re.S)
        if not match or ast.literal_eval(match[1]) != EXPECTED:
            errors.append('original four classes thirteen methods changed')
        if re.search(r'ClassDB|instantiate|\.call\(|load_extension|class_name',text):
            errors.append('contract is not pure local data')
    for name in ['scripts/net/server/server_bootstrap.gd','scripts/net/server/server_console_channel.gd']:
        text = (root/name).read_text(encoding='utf-8')
        if 'const NativeMethodContract = preload("res://'+CONTRACT+'")' not in text:
            errors.append(name+': does not reference actual shared source')
        if 'const NATIVE_METHOD_CONTRACT:Dictionary = NativeMethodContract.REQUIRED_METHODS' not in text:
            errors.append(name+': missing shared declaration alias')
        if any('"'+key+'":[' in text for key in EXPECTED):
            errors.append(name+': duplicated native method declaration')
        if name.endswith('server_bootstrap.gd') and 'var required:Dictionary = NATIVE_METHOD_CONTRACT' not in text:
            errors.append('bootstrap validation not wired to shared declaration')
        if name.endswith('server_console_channel.gd') and 'NativeCapabilityView.observe(NATIVE_METHOD_CONTRACT)' not in text:
            errors.append('status not wired to shared declaration')
    return errors

if __name__ == '__main__':
    errors = audit(Path(sys.argv[1]) if len(sys.argv)>1 else ROOT)
    print(json.dumps({'suite':'round64_native_source','failures':errors},ensure_ascii=False))
    raise SystemExit(1 if errors else 0)
