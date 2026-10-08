"""验收证据门禁参考实现：只读取；不启动/清理进程，不将结构校验当真人验收。"""
import argparse
import ast
import json
import re
from pathlib import Path
STATUSES = {'NOT_RUN', 'RUNNING', 'BLOCKED', 'INCOMPLETE', 'FAIL', 'PASS'}
ERROR = re.compile(r'SCRIPT ERROR|Parse Error|SHADER ERROR|\bERROR:')

def reconcile(text, exit_code, minimum_checks=1):
    parsed = []
    malformed = False
    for line in text.splitlines():
        if not re.search(r'\bRESULT\b', line):
            continue
        body = line.split('RESULT', 1)[1].strip()
        try:
            if body.startswith('{'):
                obj = json.loads(body)
                checks, failures = obj.get('checks'), obj.get('failures')
                skipped = any(obj.get(k) is True for k in ('skipped','window_only','external_pair_only'))
            else:
                cm = re.search(r'\bchecks\s*=\s*(\d+)\b', body)
                fm = re.search(r'\bfailures\s*=\s*(\d+|\[.*\])', body)
                checks = int(cm[1]) if cm else None
                if fm and fm[1].isdigit():
                    failures = int(fm[1])
                elif fm:
                    try:
                        failures = ast.literal_eval(fm[1])
                    except (ValueError,SyntaxError):
                        failures = [] if fm[1].strip() == '[]' else ['unparsed_failure']
                else:
                    failures = None
                skipped = bool(re.search(r'\b(?:skipped|window_only|external_pair_only)\s*[=:]\s*true\b',body,re.I))
            count = len(failures) if isinstance(failures,list) else failures if type(failures) is int and failures >= 0 else None
            malformed |= type(checks) is not int or checks < 0 or count is None
            parsed.append({'checks':checks,'failures':count,'skipped':skipped})
        except (ValueError,AttributeError,TypeError):
            malformed = True
    errors = [line for line in text.splitlines() if ERROR.search(line)]
    failed = exit_code != 0 or bool(errors) or any(x['failures'] is not None and x['failures'] > 0 for x in parsed)
    skip = any(x['skipped'] for x in parsed)
    # 单一套件必须一个最终 RESULT；多角色协议必须显式另写聚合器。
    incomplete = malformed or len(parsed) != 1 or any(type(x['checks']) is not int or (not x['skipped'] and x['checks'] < minimum_checks) for x in parsed)
    status = 'FAIL' if failed else 'INCOMPLETE' if incomplete else 'NOT_RUN' if skip else 'PASS'
    return {'status':status,'scope':'AUTOMATED_LOG_ONLY','errors':errors,'results':parsed}

def validate(manifest, ledger, evidence_root):
    specs = manifest['cases']
    ids = [x['id'] for x in specs]
    errors = []
    if len(ids) != len(set(ids)):
        errors.append('duplicate manifest ID')
    rows = ledger.get('cases',[])
    row_ids = [x.get('id') for x in rows]
    if len(row_ids) != len(set(row_ids)):
        errors.append('duplicate ledger ID')
    if set(ids) != set(row_ids):
        errors.append('manifest/ledger IDs differ; NOT_RUN rows must not be dropped')
    indexed = {x.get('id'):x for x in rows}
    counts = {s:0 for s in sorted(STATUSES)}
    root = Path(evidence_root).resolve()
    for spec in specs:
        row = indexed.get(spec['id'],{'status':'NOT_RUN'})
        status = row.get('status')
        if status not in STATUSES:
            errors.append(f"{spec['id']}: unknown status")
            continue
        counts[status] += 1
        if status != 'PASS':
            continue
        reasons = []
        if row.get('run_id') != ledger.get('run_id') or not ledger.get('run_id'):
            reasons.append('run binding absent')
        if row.get('build_id') != ledger.get('build_id') or not ledger.get('build_id'):
            reasons.append('frozen build binding absent')
        if not row.get('operator') or not row.get('reviewer'):
            reasons.append('human signoff absent')
        if any(indexed.get(d,{}).get('status') != 'PASS' for d in spec.get('depends_on',[])):
            reasons.append('dependency not PASS')
        if row.get('evidence_gaps'):
            reasons.append('evidence gaps remain')
        assertions = row.get('assertions',{})
        if not spec.get('assertions') or set(assertions) != set(spec['assertions']) or any(v is not True for v in assertions.values()):
            reasons.append('required assertion set not satisfied')
        files = row.get('evidence',[])
        if not files:
            reasons.append('evidence absent')
        for relative in files:
            path = (root/relative).resolve()
            if not path.is_relative_to(root) or not path.is_file():
                reasons.append('evidence missing/outside private root')
        if spec['layer'] != 'static' and (row.get('real_window_observed') is not True or row.get('human_input_observed') is not True):
            reasons.append('human window/input absent')
        if spec['layer'] == 'lan' and (len(set(row.get('physical_devices',[]))) < spec.get('minimum_devices',2) or row.get('physical_distinct_confirmed') is not True or row.get('loopback_used') is not False):
            reasons.append('physical LAN unproven')
        if spec['layer'] == 'p2p' and row.get('different_public_egress_verified') is not True:
            reasons.append('different public egress unproven')
        if spec.get('requires_direct_connection') and (row.get('direct_connection_result') != 'PASS' or row.get('selected_candidate_types') not in [['host','host'],['host','srflx'],['srflx','host'],['srflx','srflx'],['prflx','host'],['host','prflx'],['prflx','srflx'],['srflx','prflx'],['prflx','prflx']] or row.get('game_relay_observed') is not False):
            reasons.append('direct data path unproven')
        if spec['layer'] == 'linux' and row.get('linux_runtime_verified') is not True:
            reasons.append('Linux runtime absent')
        errors += [spec['id']+': '+r for r in reasons]
    all_pass = bool(specs) and not errors and counts['PASS'] == len(specs)
    return {'overall':'PASS' if all_pass else 'INCOMPLETE','expected':len(specs),'counts':counts,'errors':errors,'note':'结构校验通过不代替审核证据内容；只读，不自动改状态。'}

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('manifest',type=Path)
    ap.add_argument('ledger',type=Path)
    ap.add_argument('evidence_root',type=Path)
    args = ap.parse_args()
    result = validate(json.loads(args.manifest.read_text(encoding='utf-8-sig')),json.loads(args.ledger.read_text(encoding='utf-8-sig')),args.evidence_root)
    print(json.dumps(result,ensure_ascii=False,indent=2))
    raise SystemExit(0 if result['overall']=='PASS' else 2)
