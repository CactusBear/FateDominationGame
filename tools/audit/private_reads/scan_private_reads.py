#!/usr/bin/env python
"""Read-only lexical inventory; output NEW artifacts under repository audit runs.
Never starts Godot, reads credentials, changes source, or changes the ratchet.
"""
from __future__ import annotations
import argparse
from pathlib import Path
from collections import Counter, defaultdict
import importlib.util
import sys
import re
import json
import hashlib

sys.dont_write_bytecode = True
ROOT = None
TEXT = {}
TOK = {}
PROD = {}
CLASSES = {}
BASES = {}
DECL = defaultdict(list)
PUBLIC = defaultdict(list)
ALIASES = {}
SCENES = {}
INPUT_HASHES = {}
FIELDS = defaultdict(dict)


def scoped_path(path):
    return path.startswith(('scripts/', 'json_maker/'))


def diagnostic(path):
    parts = path.split('/')
    name = parts[-1].lower()
    if path.startswith(('tests/', 'newtests/', 'tools/diagnostics/', 'tools/tests/', 'scripts/debug/')):
        return True
    if any(x in parts for x in ('tests', 'test', 'newtests', 'diagnostics', 'debug', 'testing')):
        return True
    if path.startswith(('reports/', 'scratch/')):
        # Keep diagnostic evidence, not copied production implementations.
        if any(name.endswith(Path(p).name) for p in PROD):
            return False
        if '/scripts/' in path or '/assets/' in path or '/deps/' in path:
            return False
        if any(x in name for x in ('test', 'probe', 'negative', 'loopback', 'window', 'fixture', 'green_', 'red_')):
            return True
        if path.startswith('reports/') and '/evidence/' in path:
            return True
    return any(x in name for x in ('_test.', '_probe.', '_diagnostic.', '_harness.'))


def scope(path):
    if path.startswith('reports/'):
        return '历史证据副本'
    if path.startswith('.claude/'):
        return '旧工作树'
    if path.startswith('addons/') or '/addons/' in path:
        return '第三方插件'
    if path.startswith('scratch/'):
        return 'scratch诊断'
    return '现行测试诊断'


def resource(value):
    if value.startswith('res://'):
        return value[6:]
    return ''


def scene_script(path):
    if path in SCENES:
        return SCENES[path]
    SCENES[path] = None
    full = ROOT / path
    if full.is_file() and path.endswith('.tscn'):
        text = full.read_text(encoding='utf-8-sig')
        entries = {m[2]:resource(m[1]) for m in re.finditer(r'\[ext_resource[^\n]*path="([^"]+\.gd)"[^\n]*id="([^"]+)"',text)}
        m = re.search(r'(?m)^script\s*=\s*ExtResource\("([^"]+)"\)',text)
        if m and m[1] in entries:
            SCENES[path] = entries[m[1]]
    return SCENES[path]


def base_path(path, seen=None):
    seen = set() if seen is None else seen
    if path in seen:
        return None
    seen.add(path)
    base = BASES.get(path, '')
    if base.startswith('res://'):
        return resource(base)
    if base in CLASSES:
        return CLASSES[base]
    return ALIASES.get(path, {}).get(base)


def ancestors(path):
    out = []
    while path and path not in out:
        out.append(path)
        path = base_path(path)
    return out


def resolve_type(name, path):
    return CLASSES.get(name) or ALIASES.get(path, {}).get(name)


def rhs_types(rhs, path, local):
    out = set()
    for m in re.finditer(r'(?:preload|load)\s*\(\s*["\'](res://[^"\']+)["\']\s*\)', rhs):
        r = resource(m[1]); r = scene_script(r) if r.endswith('.tscn') else r
        if r:
            out.add(r)
    for m in re.finditer(r'\b(\w+)\s*\.\s*(?:new|instantiate)\s*\(',rhs):
        r = resolve_type(m[1], path)
        if r:
            r = scene_script(r) if r.endswith('.tscn') else r
            if r: out.add(r)
    for m in re.finditer(r'\b(?:load|preload)\s*\(\s*(\w+)\s*\)',rhs):
        r = resolve_type(m[1],path)
        if r:
            r = scene_script(r) if r.endswith('.tscn') else r
            if r: out.add(r)
    for m in re.finditer(r'\bclass\s+(\w+)\s+extends',rhs):
        out.update(local.get(m[1],set()))
    m = re.match(r'^\s*(\w+)\s*(?:$|\.)',rhs)
    if m and m[1] in local:
        out.update(local[m[1]])
    return out


def file_types(path):
    local = defaultdict(set)
    # Parameters, type annotations, constructor/preload assignments, local aliases.
    text = TEXT[path]
    returns = {}
    for m in re.finditer(r'\b(\w+)\s*:\s*(\w+)\b',text):
        r = resolve_type(m[2],path)
        if r: local[m[1]].add(r)
    for _ in range(8):
        current_func = ''
        for line in text.splitlines():
            func = re.match(r'^(?:static\s+)?func\s+(\w+)\(',line)
            if func: current_func = func[1]
            m = re.search(r'(?<![.\w])(?:var\s+|const\s+)?(\w+)(?:\s*:\s*\w+)?\s*(?::=|=(?!=))\s*(.+)',line)
            if m:
                inferred = rhs_types(m[2],path,local)
                call = re.match(r'\s*(\w+)\(',m[2])
                if call: inferred.update(returns.get(call[1],set()))
                local[m[1]].update(inferred)
            ret = re.match(r'\s*return\s+(.+)',line)
            if ret and current_func:
                returns.setdefault(current_func,set()).update(rhs_types(ret[1],path,local))
            for m in re.finditer(r'\bclass\s+(\w+)\s+extends\s+(?:["\']([^"\']+)["\']|(\w+))',line):
                r = resource(m[2]) if m[2] else resolve_type(m[3],path)
                if r: local[m[1]].add(r)
    return local


def owner_for(member, receiver, path, local):
    choices = DECL.get(member, [])
    # A state declaration is not ambiguous merely because another owner has a
    # same-named private helper method (e.g. location._players vs console._players).
    state_choices = [d for d in choices if d['kind']=='state']
    if state_choices: choices = state_choices
    paths = sorted(set(d['path'] for d in choices))
    if not paths:
        return [], '未发现生产声明'
    hints = set()
    ids = re.findall(r'\b\w+\b',receiver)
    for name in ids:
        r = resolve_type(name,path)
        if r: hints.add(r)
        hints.update(local.get(name,set()))
    if receiver in ('self', 'super', '(inherited)'):
        hints.update(ancestors(path))
    compatible = {p for hint in hints for p in ancestors(hint)}
    # Follow production field construction for chained instance members.
    chain = receiver.split('.')
    current = set(local.get(chain[0],set()))
    root_type = resolve_type(chain[0],path)
    if root_type: current.add(root_type)
    for field in chain[1:]:
        next_types = set()
        for owner in current:
            for parent in ancestors(owner):next_types.update(FIELDS.get(parent,{}).get(field,set()))
        if next_types:current=next_types
    compatible.update(p for hint in current for p in ancestors(hint))
    structural = local.get('@receiver:'+receiver,set())
    compatible.update(p for hint in structural for p in ancestors(hint))
    narrowed = [d for d in choices if d['path'] in compatible]
    if len(set(d['path'] for d in narrowed)) == 1:
        return narrowed, ('成员组合静态推断' if structural and not hints and not current else '声明/类型/资源路径')
    if len(paths) == 1:
        # Useful but explicitly distinguish this from proven receiver type.
        return choices, '唯一生产符号（静态归属推断）'
    return choices, '多生产声明未消歧'


def receiver_before(tokens, dot):
    start = dot - 1
    depth = 0
    while start >= 0:
        if depth == 0 and tokens[start].line != tokens[dot].line: break
        value = tokens[start].value
        if value in (']', ')'):
            depth += 1
        elif value in ('[', '('):
            if depth: depth -= 1
            else: break
        elif depth == 0:
            if value not in ('.',) and tokens[start].kind != 'id': break
            if value in ('var','return','if','and','or','not','check','_check','assert','for','in','await'): break
        start -= 1
    return ''.join(t.value for t in tokens[start+1:dot])


def mode_after(tokens, i):
    # A direct assignment does not read the member. Subscript/mutating access
    # DOES fetch its container; keep it as read-for-write, not a scalar write.
    tail = [t.value for t in tokens[i+1:i+5]]
    if tail and tail[0] == '=' and (len(tail)<2 or tail[1]!='='):
        return '纯赋值排除'
    if len(tail)>1 and tail[0] in ('+','-','*','/','%','|','&','^') and tail[1]=='=':
        return '读改写'
    if tail and tail[0] == '(':
        return '私有方法调用排除'
    mutation_methods = {'append','append_array','push_back','push_front','pop_back','pop_front','pop_at','erase','clear','insert','remove_at','sort','sort_custom','reverse','resize','fill','merge','assign','set_num','set_value','set_text','set_visible','set_kind','queue_free','free','connect','disconnect','set_script','invalidate','set_seat'}
    if len(tail)>2 and tail[0]=='.' and tail[1] in mutation_methods and tail[2]=='(':
        return '对象/容器读取后修改'
    j=i+1
    while j<len(tokens) and tokens[j].line==tokens[i].line:
        if tokens[j].value=='[':
            depth=1;j+=1
            while j<len(tokens) and depth:
                if tokens[j].value=='[':depth+=1
                elif tokens[j].value==']':depth-=1
                j+=1
            continue
        if j+1<len(tokens) and tokens[j].value=='.' and tokens[j+1].kind=='id':j+=2;continue
        break
    if j<len(tokens) and tokens[j].value=='=' and (j+1==len(tokens) or tokens[j+1].value!='='):
        return '对象/容器读取后修改'
    if tail and tail[0] == '[':
        return '容器下标读取'
    return '读取'


def public_candidates(owner, member):
    result = []
    for item in PUBLIC.get(owner,[]):
        if member in item['members']:
            result.append(f"{item['name']}@{item['line']}")
    return result


def classify(rec, tokens, i):
    owner, member = rec['owner'], rec['member']
    pub = public_candidates(owner,member)
    near = ''.join(t.value for t in tokens[i+1:i+12])
    # Raw scalars returned unchanged by the public API. Container snapshots are
    # equivalent for value assertions, but not object identity/alias mutation.
    for item in PUBLIC.get(owner,[]):
        if item['direct'] == member and not item['params']:
            if rec['mode'] in ('读改写','对象/容器读取后修改'): break
            if item['copy'] and (rec['mode'].startswith('容器') or any(x in near for x in ('.clear(','.erase(','.append(','.push_', '.pop_', '.sort(','.resize('))):
                break
            return '可立即替换',f"{item['name']}()（{owner}:{item['line']}）",'直接标量/只读值快照；保留原断言语义'
    if owner == 'scripts/system/base_object.gd' and member == '_zoom_kind' and rec['mode']!='读改写':
        item = next((x for x in PUBLIC[owner] if x['name']=='get_zoom_kind'),None)
        if item: return '可立即替换',f"get_zoom_kind()（{owner}:{item['line']}；不传img_field）",'默认分支原样返回_zoom_kind'
    for mem, method in [('_attributes','has_attribute'),('_keywords','has_keyword')]:
        if owner == 'scripts/system/base_card.gd' and member==mem and near.startswith('.has('):
            item=next((x for x in PUBLIC[owner] if x['name']==method),None)
            if item: return '可立即替换',f"{method}(原参数)（{owner}:{item['line']}）",'完全等价的has查询'
    if owner=='scripts/system/base_effect.gd' and member=='_options' and near.startswith('.is_empty('):
        item=next((x for x in PUBLIC[owner] if x['name']=='has_options'),None)
        if item:return '可立即替换',f"not has_options()（{owner}:{item['line']}）",'has_options恰为not _options.is_empty'
    # These are deliberately stronger white-box facts than public behavior.
    private_security = {'_resume_hashes','_resume_previous','_member_identities','_resume_ticket','_inheritance_ticket','_identity_challenges','_inheritance_sequences'}
    if member in private_security or member == '_paused_runs':
        return '应保留许可（不可等价）',('paused_runs_snapshot()有值快照但无原容器身份等价入口' if member=='_paused_runs' else '无等价公开入口；不得公开凭据/哈希容器'),'精确认证/回滚/原容器隔离不变性白盒断言；只建议逐锚点许可，不是已获gate许可'
    if member == '_pending_announcements':
        return '应保留许可（不可等价）','无；pop_messages/pop_effect_results会消费并改变队列','队列原始对象/顺序冻结与消费型公开通道不可等价；现有精确gate许可'
    # Pointer-identity/alias equality, callable binding, introspection are not
    # equivalent to a detached public projection.
    line = rec['_code']
    if rec['kind']=='private_callable_reference':
        return '应保留许可（不可等价）','无等价公开回调引用','内部回调连接身份不是行为查询；单列方法引用，不并入状态读取总数'
    if rec['mode']=='读取' and member in {'_source','_builder','_held_action_ids','_ids','_network_presenter','_battle_commands','_driver','_journal','_seat_controller','_preparation','_validation','_codec','_host_identity_request_codec','_host_room_inbox','_host_match_request_inbox'} and re.search(r'==|!=|is_same',line) and not re.search(r'\.get\(|\.visible|\.running|\.is_empty|\.size|\.read_',line):
        return '应保留许可（不可等价）','无公开等价对象身份/共享实例查询','共享实例/内部接线身份断言，不可拿值投影伪装等价'
    partial = '; '.join(pub[:8])
    return '需要新增公开能力',('没有确认完全等价入口；相关但不等价：'+partial) if partial else '没有确认完全等价入口','应按此断言需要增加只读事实/投影，不直接公开可变成员；setter/通用反射不算等价只读封装'


def main():
    global ROOT,TEXT,TOK,PROD
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[3])
    ap.add_argument('--output',type=Path,required=True,help='repository-relative NEW directory under tools/audit/private_reads/runs')
    args=ap.parse_args();ROOT=args.root.resolve(strict=True)
    out=(ROOT/args.output).resolve()
    if not out.is_relative_to(ROOT/'tools/audit/private_reads/runs'):
        raise ValueError('outputs must be under tools/audit/private_reads/runs')
    gp=ROOT/'tools/check_layer_deps.py'
    sp=importlib.util.spec_from_file_location('private_read_gate_lexer',gp)
    gate=importlib.util.module_from_spec(sp);sys.modules[sp.name]=gate;sp.loader.exec_module(gate)
    for full in sorted(ROOT.rglob('*.gd')):
        p=full.relative_to(ROOT).as_posix()
        if any(x in {'.git','.godot'} for x in full.relative_to(ROOT).parts) or not full.is_file():continue
        if not full.resolve(strict=True).is_relative_to(ROOT): raise ValueError('source escaped root')
        raw=full.read_bytes();INPUT_HASHES[p]=hashlib.sha256(raw).hexdigest()
        TEXT[p]=raw.decode('utf-8-sig');TOK[p]=gate.lex(TEXT[p])
    PROD={p:t for p,t in TEXT.items() if scoped_path(p)}
    for p,text in TEXT.items():
        if p in PROD:
            m=re.search(r'(?m)^class_name\s+(\w+)',text)
            if m:CLASSES[m[1]]=p
        m=re.search(r'(?m)^extends\s+(?:["\']([^"\']+)["\']|(\w+))',text)
        if m:BASES[p]=m[1] or m[2]
        aliases={}
        for m in re.finditer(r'(?m)^\s*(?:const|var)\s+(\w+)(?:\s*:\s*\w+)?\s*(?::=|=)\s*(?:preload|load)\(["\'](res://[^"\']+)["\']\)',text):aliases[m[1]]=resource(m[2])
        for m in re.finditer(r'(?m)^\s*(?:const|var)\s+(\w+)(?:\s*:\s*\w+)?\s*(?::=|=)\s*["\'](res://[^"\']+\.(?:tscn|gd))["\']',text):aliases[m[1]]=resource(m[2])
        ALIASES[p]=aliases
    # Read only autoload resource bindings, never config values elsewhere.
    project=(ROOT/'project.godot').read_text(encoding='utf-8-sig')
    section=re.search(r'(?ms)^\[autoload\]\s*(.*?)(?=^\[|\Z)',project)
    if section:
        for m in re.finditer(r'(?m)^(\w+)="\*?(res://[^"\n]+\.gd)"',section[1]):CLASSES[m[1]]=resource(m[2])
    for p,text in PROD.items():
        lines=text.splitlines()
        for i,line in enumerate(lines):
            m=re.match(r'^(?:@[^\n]*?\s*)?(?:static\s+)?(?:var|const)\s+(_\w+)\b',line)
            if m: DECL[m[1]].append({'path':p,'line':i+1,'kind':'state'})
            m=re.match(r'^(?:static\s+)?func\s+(\w+)\(([^)]*)\)',line)
            if not m:continue
            if m[1].startswith('_'):
                DECL[m[1]].append({'path':p,'line':i+1,'kind':'private_callable_reference'});continue
            end=next((j for j in range(i+1,len(lines)) if lines[j] and not lines[j][0].isspace() and not lines[j].lstrip().startswith('#')),len(lines))
            body=gate.lex('\n'.join(lines[i+1:end]));bodycode=''.join(t.value for t in body)
            direct=re.fullmatch(r'return(_\w+)(\.duplicate\((?:true)?\))?',bodycode)
            PUBLIC[p].append({'name':m[1],'line':i+1,'params':m[2].strip(),'members':sorted(set(t.value for t in body if t.kind=='id' and t.value.startswith('_'))),'direct':direct[1] if direct else '', 'copy':bool(direct and direct[2])})
    for p in PROD:
        FIELDS[p] = file_types(p)
    rows=[]; unresolved=[];excluded=Counter(); candidates=0;diag_files=[]
    for p,text in TEXT.items():
        if not diagnostic(p):continue
        diag_files.append(p);tokens=TOK[p];local=file_types(p);lines=text.splitlines()
        own=set(re.findall(r'(?m)^\s*(?:var|const|func)\s+(_\w+)\b',text))
        sites=[]
        for i,t in enumerate(tokens):
            if t.kind=='id' and t.value.startswith('_'):
                if i>0 and tokens[i-1].value=='.':
                    sites.append((i,t.value,receiver_before(tokens,i-1),'dot'))
                elif base_path(p) in PROD and t.value in DECL and t.value not in own and (i==0 or tokens[i-1].value not in ('var','const','func',':')):
                    sites.append((i,t.value,'(inherited)','inherited'))
            if t.kind=='string' and i>=2 and tokens[i-1].value=='(' and tokens[i-2].value in ('get','get_indexed'):
                member=gate.literal(t).split(':')[0]
                if member.startswith('_'):
                    receiver=receiver_before(tokens,i-3) if i>=3 and tokens[i-3].value=='.' else '(inherited)'
                    sites.append((i,member,receiver,'reflection'))
        for i,t in enumerate(tokens[:-2]):
            if t.kind=='id' and tokens[i+1].value=='.' and tokens[i+2].kind=='id':
                choices=DECL.get(tokens[i+2].value,[])
                paths=set(d['path'] for d in choices)
                if len(paths)==1:
                    receiver=receiver_before(tokens,i+1)
                    local['@receiver:'+receiver].update(paths)
        for i,member,receiver,syntax in sites:
            candidates+=1
            mode='反射读取' if syntax=='reflection' else mode_after(tokens,i)
            if mode.endswith('排除'):excluded[mode]+=1;continue
            if receiver in ('self','super','(inherited)') and member in own:
                excluded['诊断自己定义成员']+=1;continue
            defs,evidence=owner_for(member,receiver,p,local)
            receiver_display = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '<literal>', receiver)
            if len(set(d['path'] for d in defs))!=1:
                unresolved.append({'path':p,'line':tokens[i].line,'member':member,'receiver':receiver_display,'reason':evidence,'possible_owners':sorted(set(d['path'] for d in defs)), 'scope':scope(p),'mode':mode});continue
            d=defs[0]
            if d['path']==p:excluded['owner自己访问']+=1;continue
            rec={'path':p,'line':tokens[i].line,'ordinal':len(rows)+1,'receiver':receiver,'member':member,'owner':d['path'],'declaration_line':d['line'],'kind':d['kind'],'syntax':syntax,'mode':mode,'resolution':evidence,'scope':scope(p),'gate_owner':d['path'] in gate.OWNERS.values(), '_code':lines[tokens[i].line-1]}
            rec['category'],rec['public_equivalent'],rec['reason']=classify(rec,tokens,i)
            del rec['_code'];rec['receiver']=receiver_display;rows.append(rec)
    state=[r for r in rows if r['kind']=='state'];callables=[r for r in rows if r['kind']!='state']
    active=[r for r in state if r['scope'] in ('现行测试诊断','scratch诊断')]
    historical=[r for r in state if r not in active]
    summary={'root':'.','gd_files':len(TEXT),'production_files':len(PROD),'diagnostic_files':len(diag_files),'lexical_candidates':candidates,'excluded':dict(excluded),'state_read_total':len(state),'active_state_read_total':len(active),'historical_state_read_total':len(historical),'categories':dict(Counter(r['category'] for r in state)),'active_categories':dict(Counter(r['category'] for r in active)),'by_scope':dict(Counter(r['scope'] for r in state)),'gate_owner_reads':sum(r['gate_owner'] for r in state),'outside_gate_owner_reads':sum(not r['gate_owner'] for r in state),'private_callable_references_separate':len(callables),'unresolved_candidates':len(unresolved),'resolution_counts':dict(Counter(r['resolution'] for r in state)),'source_sha256':{p:INPUT_HASHES[p] for p in diag_files+list(PROD)},'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'gate_sha256':hashlib.sha256(gp.read_bytes()).hexdigest()}
    observation=[r for r in state if r['mode'] not in ('读改写','对象/容器读取后修改')]
    active_observation=[r for r in observation if r['scope'] in ('现行测试诊断','scratch诊断')]
    summary['observation_read_total']=len(observation)
    summary['observation_categories']=dict(Counter(r['category'] for r in observation))
    summary['active_observation_read_total']=len(active_observation)
    summary['active_observation_categories']=dict(Counter(r['category'] for r in active_observation))
    summary['mode_counts']=dict(Counter(r['mode'] for r in state))
    summary['changed_during_scan']=[p for p in summary['source_sha256'] if not (ROOT/p).is_file() or hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=INPUT_HASHES[p]]
    summary['unresolved_with_production_declarations']=sum(bool(r['possible_owners']) for r in unresolved)
    summary['unresolved_by_scope']=dict(Counter(r['scope'] for r in unresolved))
    out.mkdir(parents=True,exist_ok=True)
    def save(name,value):
        with (out/name).open('x',encoding='utf-8',newline='\n') as f:f.write(value)
    save('inventory.json',json.dumps({'summary':summary,'reads':state,'private_callable_references':callables,'unresolved':unresolved,'public_index':PUBLIC},ensure_ascii=False,indent=2)+'\n')
    report=['# 测试/诊断读取生产私有成员：静态实测清单','', '## 口径与边界', '', '- 主口径是observation_read_total：排除读改写以及取容器/对象后修改。state_read_total额外计入这些确实取过私有成员的配置/修改依赖；三分类表逐条标注mode，可过滤主口径。','- 静态可归属不等于运行时类型证明：声明/类型/资源、成员组合推断、唯一符号推断分别统计；未消歧候选另列，不能宣称完整精确总数或清零。', '- 不改现有文件，不改gate，不启动Godot。只枚举真实*.gd；不使用git ignore；排除.git/.godot；拒绝越根链接。', '- 生产成员索引：scripts/**、json_maker/**的顶层_前缀var/const，以及私有方法引用（后者单列）。_前缀纯数据模型也纳入，不等同语言级访问限制。', '- 消费者：tests/newtests/tools诊断、scripts/debug、scratch测试探针、reports/evidence诊断及旧工作树测试。历史生产源码副本/第三方依赖实现不当成测试。', '- 词法剔除注释/字符串；字面量get/get_indexed显式取_成员纳入；继承生产脚本的未限定_读取纳入；动态反射/拼接、任意跨函数返回类型不保证穷尽。', '- 每处词法出现分别计数，同一行重复不合并；纯obj._x=value排除；复合赋值纳入；obj._dict[key]=value需要先读取成员容器，作为容器读取纳入；私有方法调用排除；方法引用另外列。', '- 声明/类型/资源能消歧的归属与“唯一生产符号推断”分别标明；后者仍是静态候选，不声称运行时证明。多owner/无生产声明在未决附录，不混入确认归属清单。', '- “可立即替换”只认可完全等价只读入口；显示名回退、has_name含别名、setter、泛用get/GetProperty、消费队列接口不冒充原始值等价。', '- “应保留许可”是逐处白盒许可建议，不表示gate已有许可；凭据和哈希只列字段名，不打印值。精确原始不变性可许可，通常行为读取建议新增最小只读能力。', '', '## 实数', '', '```json',json.dumps({k:v for k,v in summary.items() if 'sha256' not in k},ensure_ascii=False,indent=2),'```', '', '## 三分类逐条清单（含历史副本，scope可筛现行）','']
    for cat in ('可立即替换','需要新增公开能力','应保留许可（不可等价）'):
        group=[r for r in state if r['category']==cat]
        report += [f'### {cat}：{len(group)}处','', '| # | 文件:行 | 被读成员 | 所属生产文件:声明行 | 公开等价入口 | 范围/访问种类/归属证据 |','|---|---|---|---|---|---|']
        for r in group:
            cols=[str(r['ordinal']),f"{r['path']}:{r['line']}",r['receiver']+'.'+r['member'],f"{r['owner']}:{r['declaration_line']}",r['public_equivalent']+'；'+r['reason'],r['scope']+'/'+r['mode']+'/'+r['resolution']]
            report.append('| '+' | '.join(x.replace('|','\\|').replace('\n',' ') for x in cols)+' |')
        report.append('')
    report += ['## 私有方法引用（不是状态读取，不并入三分类总数）','']
    for r in callables:report.append(f"- {r['path']}:{r['line']} → {r['receiver']}.{r['member']} → {r['owner']}:{r['declaration_line']}")
    report += ['', '## 未决附录（不能用这些候选宣称全树精确清零）','']
    for r in unresolved:report.append(f"- {r['path']}:{r['line']} → {r['receiver']}.{r['member']}；{r['reason']}；可能owner：{', '.join(r['possible_owners']) or '无生产声明（可能是测试自有/第三方/漏索引）'}")
    save('report.md','\n'.join(report)+'\n')
    print(json.dumps({k:v for k,v in summary.items() if 'sha256' not in k},ensure_ascii=False,indent=2))
    print('REPORT',out/'report.md');print('INVENTORY',out/'inventory.json')
    return 0

if __name__=='__main__':raise SystemExit(main())
