"""Read declared JSON and rule scripts only; emit bounded search evidence."""
import sys
sys.dont_write_bytecode = True
import hashlib
import json
from pathlib import Path
import re
import zipfile
import xml.etree.ElementTree as ET

repo = Path(__file__).resolve().parents[1]
roots = ['data','game_data','json_maker']
negative = re.compile(r'透支|负魔力|魔力[^\n。]{0,30}(?:负数|负值|负点|借贷|借用|欠债)|(?:负数|负值|借贷|欠债)[^\n。]{0,30}魔力|overdraft|allow[_ -]*(?:negative|debt)|negative[_ -]*(?:mana|magic)|(?:mana|magic)[_ -]*(?:debt|borrow)|magic_min',re.I)
interesting = re.compile(r'magic_limit|is_magic_immune|ignore_skill_zone_magic_limit|self_card_cost_calculated|edit_card_cost|魔力上限|魔力不足|不消耗魔力|无需消耗魔力',re.I)
result = {'scope':roots,'search_regex':negative.pattern,'files':[],'parse_errors':[],'overdraft_matches':[],'relevant_lines':[],'negative_cost_declarations':[]}

def walk(value, pointer, file):
    if isinstance(value,dict):
        c = value.get('cost')
        if isinstance(c,dict) and isinstance(c.get('number'),(int,float)) and c['number'] < 0:
            result['negative_cost_declarations'].append({'file':file,'pointer':pointer+'/cost','number':c['number']})
        for key,child in value.items(): walk(child,pointer+'/'+str(key),file)
    elif isinstance(value,list):
        for i,child in enumerate(value): walk(child,pointer+'/'+str(i),file)

for root in roots:
    for path in sorted((repo / root).rglob('*.json')):
        raw = path.read_bytes(); text = raw.decode('utf-8-sig'); rel = path.relative_to(repo).as_posix()
        result['files'].append({'path':rel,'sha256':hashlib.sha256(raw).hexdigest()})
        try: walk(json.loads(text),'',rel)
        except Exception as exc: result['parse_errors'].append({'file':rel,'error':repr(exc)})
        for line_no,line in enumerate(text.splitlines(),1):
            if negative.search(line): result['overdraft_matches'].append({'file':rel,'line':line_no,'text':line.strip()})
            if interesting.search(line): result['relevant_lines'].append({'file':rel,'line':line_no,'text':line.strip()})
result['rule_scripts'] = []
for path in sorted((repo / 'scripts/system').rglob('*.gd')):
    text = path.read_text(encoding='utf-8-sig'); rel = path.relative_to(repo).as_posix()
    result['rule_scripts'].append({'path':rel,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    for line_no,line in enumerate(text.splitlines(),1):
        if negative.search(line): result['overdraft_matches'].append({'file':rel,'line':line_no,'text':line.strip()})
result['json_count'] = len(result['files'])
result['rule_script_count'] = len(result['rule_scripts'])
doc = Path('E:/Users/Administrator/Downloads/Fate_Domination 基础规则【墨水修订1版】.docx')
with zipfile.ZipFile(doc) as z:
    tree = ET.fromstring(z.read('word/document.xml'))
    ns = {'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
    # Text nodes only; do not duplicate nested formatting.
    paras = [''.join(n.text or '' for n in p.findall('.//w:t',ns)) for p in tree.findall('.//w:p',ns)]
result['base_rules'] = {'path':str(doc),'sha256':hashlib.sha256(doc.read_bytes()).hexdigest(),'overdraft_matches':[p for p in paras if negative.search(p)],'magic_quotes':[p for p in paras if '从 0 到 12' in p or '同时花费这些牌' in p or '不消耗魔力' in p]}
out = repo / 'docs/magic-overdraft-declaration-scan.json'
if out.exists(): raise RuntimeError('refuse overwriting evidence')
out.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'output':str(out),'json_count':result['json_count'],'rule_script_count':result['rule_script_count'],'parse_errors':result['parse_errors'],'overdraft_matches':result['overdraft_matches'],'negative_cost_declarations':result['negative_cost_declarations'],'base_rule_quotes':result['base_rules']['magic_quotes']},ensure_ascii=False))
