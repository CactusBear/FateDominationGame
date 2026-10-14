#!/usr/bin/env python
"""Read only four manually verified emitted GDScript literals in Python runners."""
import sys
sys.dont_write_bytecode=True
from pathlib import Path
import ast,json,re,importlib.util,hashlib,argparse,os
from collections import Counter
BASE=Path(__file__).resolve().parent
ap=argparse.ArgumentParser()
ap.add_argument('--root',type=Path,default=BASE.parents[2])
ap.add_argument('--core',type=Path,required=True,help='repository-relative GD inventory from the same run')
ap.add_argument('--output',type=Path,required=True,help='repository-relative NEW directory under tools/audit/private_reads/runs')
args=ap.parse_args()
ROOT=args.root.resolve(strict=True)
OUT=(ROOT/args.output).resolve()
CORE=(ROOT/args.core).resolve(strict=True)
if not OUT.is_relative_to(ROOT/'tools/audit/private_reads/runs'):
 raise ValueError('outputs must be under tools/audit/private_reads/runs')
if not CORE.is_relative_to(ROOT):raise ValueError('core inventory must be inside repository')
core=json.loads(CORE.read_text(encoding='utf-8'))
sp=importlib.util.spec_from_file_location('audit_core',BASE/'scan_private_reads.py');mod=importlib.util.module_from_spec(sp);sp.loader.exec_module(mod)
sp=importlib.util.spec_from_file_location('audit_gate',ROOT/'tools/check_layer_deps.py');gate=importlib.util.module_from_spec(sp);sys.modules[sp.name]=gate;sp.loader.exec_module(gate)
mod.ROOT=ROOT;mod.PUBLIC.update(core['public_index'])
for p in core['summary']['source_sha256']:
 if not mod.scoped_path(p):continue
 text=(ROOT/p).read_text(encoding='utf-8-sig');mod.TEXT[p]=text;mod.PROD[p]=text
 m=re.search(r'(?m)^class_name\s+(\w+)',text)
 if m:mod.CLASSES[m[1]]=p
 m=re.search(r'(?m)^extends\s+(?:["\']([^"\']+)["\']|(\w+))',text)
 if m:mod.BASES[p]=m[1] or m[2]
 for i,line in enumerate(text.splitlines(),1):
  m=re.match(r'^(?:@[^\n]*?\s*)?(?:static\s+)?(?:var|const)\s+(_\w+)\b',line)
  if m:mod.DECL[m[1]].append({'path':p,'line':i,'kind':'state'})
for p,text in mod.PROD.items():
 mod.ALIASES[p]={m[1]:m[2][6:] for m in re.finditer(r'(?m)^\s*(?:const|var)\s+(\w+)(?:\s*:\s*\w+)?\s*(?::=|=)\s*(?:preload|load)\(["\'](res://[^"\']+)["\']\)',text)}
for p in mod.PROD:mod.FIELDS[p]=mod.file_types(p)
mod.CLASSES.update({'EffectManager':'scripts/system/global/effect_manager.gd','GameProgress':'scripts/system/global/game_progress.gd','GameStart':'scripts/main_menu/game_start.gd','MapData':'scripts/system/global/mapdata.gd','GameData':'scripts/system/global/game_data.gd'})
verified={'tools/tests/round64_shared_browsing.py':{'BROWSING_SCRIPT','diagnostic'},'tools/tests/round69_modal_hover.py':{'SPECIAL_VIEWER_SCRIPT'},'tests/round55_gui_first_divergence_runner.py':{'NET_DIAGNOSTIC'}}
rows=[];unresolved=[];excluded=Counter();inputs={};templates=[]
for p,names in verified.items():
 raw=(ROOT/p).read_bytes();inputs[p]=hashlib.sha256(raw).hexdigest();text=raw.decode('utf-8-sig')
 tree=ast.parse(text)
 for node in ast.walk(tree):
  if not isinstance(node,ast.Assign) or not isinstance(node.value,ast.Constant) or not isinstance(node.value.value,str):continue
  name=next((t.id for t in node.targets if isinstance(t,ast.Name) and t.id in names),None)
  if not name:continue
  snippet=node.value.value;key=p+'::'+name;mod.TEXT[key]=snippet;mod.ALIASES[key]={}
  templates.append({'path':p,'line':node.value.lineno,'template':name,'generated_lines':len(snippet.splitlines())})
  local=mod.file_types(key);tokens=gate.lex(snippet)
  for i,t in enumerate(tokens[:-2]):
   if t.kind=='id' and tokens[i+1].value=='.' and tokens[i+2].kind=='id':
    member=tokens[i+2]
    if not member.value.startswith('_'):continue
    mode=mod.mode_after(tokens,i+2)
    if mode.endswith('排除'):excluded[mode]+=1;continue
    receiver=mod.receiver_before(tokens,i+1)
    defs,evidence=mod.owner_for(member.value,receiver,key,local)
    generated_line=member.line
    original_line=node.value.lineno+generated_line-1 if node.value.end_lineno>node.value.lineno else node.value.lineno
    if len(set(d['path'] for d in defs))!=1:
     unresolved.append({'path':p,'line':original_line,'template':name,'generated_line':generated_line,'member':member.value,'possible_owners':sorted(set(d['path'] for d in defs)),'public_equivalent':'未消歧，不能确认等价入口'});continue
    d=defs[0]
    r={'path':p,'line':original_line,'template':name,'generated_line':generated_line,'receiver':receiver,'member':member.value,'owner':d['path'],'declaration_line':d['line'],'mode':mode,'resolution':evidence,'kind':'state','_code':snippet.splitlines()[generated_line-1]}
    r['category'],r['public_equivalent'],r['reason']=mod.classify(r,tokens,i+2);del r['_code'];rows.append(r)
obs=[r for r in rows if r['mode'] not in ('读改写','对象/容器读取后修改')]
summary={'verified_templates':templates,'state_reads':len(rows),'observation_reads':len(obs),'categories':dict(Counter(r['category'] for r in rows)),'observation_categories':dict(Counter(r['category'] for r in obs)),'unresolved':len(unresolved),'excluded':dict(excluded),'source_sha256':inputs,'limitations':'仅四个经调用点人工确认会被write_text/replace真实注入的字面量；词法工具闸门测试和源码迁移旧锚点不算运行时读取；任意动态生成片段仍非穷尽证明'}
OUT.mkdir(parents=True,exist_ok=True)
with (OUT/'inventory.json').open('x',encoding='utf-8') as f:json.dump({'summary':summary,'reads':rows,'unresolved':unresolved},f,ensure_ascii=False,indent=2)
report=['# Python真实发射的GDScript诊断读取补充清单','',summary['limitations'],'','主报告：'+os.path.relpath(CORE.parent/'report.md',OUT).replace('\\','/')+'。本表与主报告没有文件路径重叠；每条保留Python原始行和发射后的GDScript行。','',json.dumps({k:v for k,v in summary.items() if k!='source_sha256'},ensure_ascii=False,indent=2),'']
for cat in ('可立即替换','需要新增公开能力','应保留许可（不可等价）'):
 group=[r for r in rows if r['category']==cat];report+=[f'## {cat}：{len(group)}处','']
 for r in group:report.append(f"- {r['path']}:{r['line']} [{r['template']}生成行{r['generated_line']}]：{r['receiver']}.{r['member']} → {r['owner']}:{r['declaration_line']}；公开等价：{r['public_equivalent']}；{r['mode']}；{r['resolution']}")
report+=['','## 未消歧候选','']
for r in unresolved:report.append(f"- {r['path']}:{r['line']} [{r['template']}生成行{r['generated_line']}]：{r['member']}；候选生产文件：{', '.join(r['possible_owners'])}；{r['public_equivalent']}")
with (OUT/'report.md').open('x',encoding='utf-8') as f:f.write('\n'.join(report)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k!='source_sha256'},ensure_ascii=False,indent=2))
print('REPORT',OUT/'report.md')
