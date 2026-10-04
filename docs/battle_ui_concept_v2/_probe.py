# -*- coding: utf-8 -*-
"""一次性探测脚本：卡图长宽比、令咒图尺寸、command_spell_limit 是否统一"""
import json, glob, os, re
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

def J(p):
    with open(p, encoding='utf-8') as f:
        return json.load(f)

print('=== 御主卡图 / 令咒图尺寸 ===')
for p in sorted(glob.glob(os.path.join(ROOT, 'data/masters/*/*.json'))):
    if p.endswith('.bak'):
        continue
    d = J(p)
    folder = os.path.dirname(p)
    card = Image.open(os.path.join(folder, d['master_card_img']))
    cs = Image.open(os.path.join(folder, d['command_spell_img']))
    print(f"{d['shown_master_name']:6s} card={card.size} ratio={card.size[0]/card.size[1]:.3f}  cs={cs.size} ratio={cs.size[0]/cs.size[1]:.3f}")

print('=== game_data.gd 里 command_spell_limit 相关声明 ===')
gdata = open(os.path.join(ROOT, 'scripts/system/global/game_data.gd'), encoding='utf-8').read()
for m in re.finditer(r'.*command_spell.*', gdata):
    print(m.group(0).strip())

print('=== 是否有御主的令咒数量上限声明与默认3不同（搜 command_spell_limit 相关 effect） ===')
for p in sorted(glob.glob(os.path.join(ROOT, 'data/masters/*/*.json'))):
    if p.endswith('.bak'):
        continue
    d = J(p)
    for e in d.get('effects', []):
        txt = e.get('shown_effect_name', '')
        if '令咒' in txt:
            print(d['shown_master_name'], '|', txt[:60])
