# -*- coding: utf-8 -*-
"""生成 battle_ui_concept_v2 的 assets/：卡图缩放、御主头像、战区底图调色、data.js。
数值只从 data/**.json 与 map_data.gd 声明中取，不在页面里写死。
运行：python docs/battle_ui_concept_v2/build_assets.py（在仓库根目录）"""
import json, glob, os, re, shutil
import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(os.path.dirname(__file__), 'assets')
os.makedirs(OUT, exist_ok=True)
TMP = os.path.join(os.environ.get('LOCALAPPDATA', '/tmp'), 'Temp')
FUYUKI = os.path.join(ROOT, 'assets', 'references', 'fuyuki')


def J(p):
    with open(p, encoding='utf-8') as f:
        return json.load(f)


def num(d, k, default=0):
    v = d.get(k)
    return v['number'] if isinstance(v, dict) else (v if v is not None else default)


def save_card(src, name, width=360):
    im = Image.open(src).convert('RGB')
    im.thumbnail((width, 10000))
    im.save(os.path.join(OUT, name), quality=88)
    return 'assets/' + name


def save_head(src, name, size=200):
    im = Image.open(src).convert('RGBA')
    im.thumbnail((size, size))
    im.save(os.path.join(OUT, name))
    return 'assets/' + name


def effects(lst):
    return [e.get('shown_effect_name', e.get('effect_name', '')) for e in lst or []]


# ---------- 御主 ----------
masters = []
for p in sorted(glob.glob(os.path.join(ROOT, 'data/masters/*/*.json'))):
    d = J(p); folder = os.path.dirname(p); key = d['master_name']
    m = {
        'key': key, 'name': d['shown_master_name'],
        'head': save_head(os.path.join(folder, d['header_img']), f'h_{key}.png'),
        'card': save_card(os.path.join(folder, d['master_card_img']), f'mc_{key}.jpg'),
        'cs': save_card(os.path.join(folder, d['command_spell_img']), f'cs_{key}.jpg'),
        'effects': effects(d.get('effects')),
        'upgrade': [], 'things': []
    }
    ups = d.get('upgrade_skill') or []
    if isinstance(ups, dict):
        ups = [ups]
    for u in ups:
        m['upgrade'].append({
            'name': u['shown_skill_name'], 'attr': u.get('attributes', []),
            'cost': num(u, 'cost'), 'power': num(u, 'power'),
            'img': save_card(os.path.join(folder, u['skill_card_img']), f'up_{key}_{u["skill_name"]}.jpg'),
            'effects': effects(u.get('effects'))
        })
    seen = {}
    for t in d.get('other_master_things') or []:
        n = t['thing_name']
        if n in seen:
            seen[n]['count'] += 1; continue
        seen[n] = {'name': t['shown_thing_name'], 'count': 1,
                   'img': save_card(os.path.join(folder, t['card_img']), f'th_{key}_{n}.jpg') if t.get('card_img') else '',
                   'effects': effects(t.get('effects'))}
    m['things'] = list(seen.values())
    masters.append(m)

# ---------- 从者 ----------
servants = []
for p in sorted(glob.glob(os.path.join(ROOT, 'data/servants/*/*.json'))):
    d = J(p); folder = os.path.dirname(p); key = d['servant_name']
    s = {'key': key, 'name': d['shown_servant_name'], 'cls': d['servant_class'],
         'card': save_card(os.path.join(folder, d['servant_card_img']), f'sv_{key}.jpg'),
         'effects': effects(d.get('effects')), 'skills': []}
    for sk in (d.get('specials') or {}).get('SKILLS', []):
        s['skills'].append({'name': sk['shown_skill_name'], 'attr': sk.get('attributes', []),
                            'cost': num(sk, 'cost'), 'power': num(sk, 'power'),
                            'img': save_card(os.path.join(folder, sk['skill_card_img']), f'sk_{key}_{sk["skill_name"]}.jpg'),
                            'effects': effects(sk.get('effects'))})
    servants.append(s)

# ---------- 攻击牌 ----------
attacks = []
for p in sorted(glob.glob(os.path.join(ROOT, 'data/attacks/basic/*/*.json'))):
    d = J(p); folder = os.path.dirname(p)
    attacks.append({'key': d['attack_name'], 'name': d['shown_attack_name'], 'attr': d.get('attributes', []),
                    'cost': num(d, 'cost'), 'power': num(d, 'power'),
                    'img': save_card(os.path.join(folder, d['attack_card_img']), f'at_{d["attack_name"]}.jpg'),
                    'effects': effects(d.get('effects'))})

# ---------- 事件 / 局势 ----------
events = []
for p in sorted(glob.glob(os.path.join(ROOT, 'data/events/origin/*/*.json'))):
    d = J(p); folder = os.path.dirname(p)
    events.append({'key': d['card_name'], 'name': d['shown_name'], 'score': num(d, 'score'),
                   'img': save_card(os.path.join(folder, d['card_img']), f'ev_{d["card_name"]}.jpg'),
                   'effects': effects(d.get('effects'))})
situations = []
for p in sorted(glob.glob(os.path.join(ROOT, 'data/situations/origin/*/*.json'))):
    d = J(p); folder = os.path.dirname(p)
    situations.append({'key': d['card_name'], 'name': d['shown_name'], 'magic': num(d, 'magic'),
                       'climax': bool(d.get('is_climax')), 'climax_round': d.get('climax_round', 0),
                       'img': save_card(os.path.join(folder, d['card_img']), f'si_{d["card_name"]}.jpg'),
                       'effects': effects(d.get('effects'))})

# ---------- 卡背 ----------
backs = {}
for k in ['attack', 'skill', 'event', 'situation', 'master', 'servant', 'command_spell', 'upgrade_skill']:
    backs[k] = save_card(os.path.join(ROOT, f'data/card_backs/{k}_card_back.png'), f'back_{k}.jpg')

# ---------- 地图数值（从 map_data.gd 声明抽取） ----------
gd = open(os.path.join(ROOT, 'assets/scripts/system/map_data.gd'), encoding='utf-8').read()
def loc(name):
    m = re.search(rf'var {name} = BaseLocation\.new\(BaseNumber\.new\((\d+)\),BaseNumber\.new\((\d+)\)(?:,(-?\d+))?(?:,(true|false))?(?:,(true|false))?', gd)
    return {'magic': int(m.group(1)), 'benefit': int(m.group(2)),
            'limit': int(m.group(3)) if m.group(3) else 1,
            'deploy': (m.group(5) or 'true') == 'true'}
def cost(name):
    m = re.search(rf'{name}\._move_cost = BaseNumber\.new\((\d+)\)', gd)
    return int(m.group(1)) if m else 0
def area_score(name):
    m = re.search(rf'{name}:BaseMapArea = BaseMapArea\.new\(\s*"[^"]+",\s*BaseNumber\.new\((\d+)\)', gd)
    return int(m.group(1)) if m else 0
areas = [
    {'key': 'workshop', 'name': '魔术工房', 'score': area_score('magic_workshop'), 'move_cost': cost('magic_workshop'),
     'seats': [loc(f'magic_workshop{i}') for i in range(4)] + [loc('magic_workshop4')],
     'score_need_win': False, 'img': 'assets/area_workshop.jpg'},
    {'key': 'miyama', 'name': '深山町', 'score': area_score('miyama'), 'move_cost': cost('miyama'),
     'seats': [loc(f'miyama{i}') for i in range(3)],
     'score_need_win': True, 'img': 'assets/area_miyama.jpg'},
    {'key': 'shinto', 'name': '新都', 'score': area_score('shinto'), 'move_cost': cost('shinto'),
     'seats': [loc(f'shinto{i}') for i in range(3)],
     'score_need_win': True, 'img': 'assets/area_shinto.jpg'},
    {'key': 'scout', 'name': '侦察', 'score': area_score('scout'), 'move_cost': 0,
     'seats': [loc('scout0'), loc('scout1')],
     'score_need_win': False, 'img': 'assets/area_scout.jpg'},
]

# v1 圆盘展示坐标：普通席位保留原角度；混战玩家排在单独的圆弧。
seat_layout = {
    'workshop': [155, 200, 340, 25, None],
    'miyama': [160, 20, None],
    'shinto': [160, 20, None],
    'scout': [180, None],
}
for area in areas:
    area['seat_angles'] = seat_layout[area['key']]
    area['melee_arc'] = {'start': 55, 'end': 125, 'gap': 14}

# ---------- 规则常量（GameData 声明 + 局势牌高潮数据） ----------
gdata = open(os.path.join(ROOT, 'assets/scripts/system/global/game_data.gd'), encoding='utf-8').read()
def gconst(name):
    return int(re.search(rf'var {name}:BaseNumber = BaseNumber\.new\((\d+)\)', gdata).group(1))
def pconst(name):
    return int(re.search(rf'"{name}" : BaseNumber\.new\((\d+)\)', gdata).group(1))
rules = {
    'magic_limit': gconst('magic_limit'), 'hand_limit': gconst('hand_limit'),
    'skill_zone_magic_limit': gconst('skill_zone_magic_limit'),
    'play_limit': pconst('play_limit'), 'regular_play_min': pconst('regular_play_min'),
    'command_spell_limit': pconst('command_spell_limit'), 'start_magic': pconst('magic'),
    'rounds': max(s['climax_round'] for s in situations),
    'climax_rounds': sorted(s['climax_round'] for s in situations if s['climax']),
    'phases': ['准备', '前哨', '行动', '战斗'],
}

# ---------- 战区底图与全屏背景 ----------
def to_night(im):
    a = np.asarray(im.convert('RGB')).astype(np.float32) / 255
    lum = a.mean(axis=2, keepdims=True)
    a = a * 0.25 + lum * 0.75
    a = a ** 2.4
    a = a * np.array([0.45, 0.58, 1.0])
    h = a.shape[0]
    grad = np.linspace(0.35, 0.95, h)[:, None, None]
    a = a * grad
    warm = np.clip((lum - 0.62) * 2.2, 0, 1) * np.array([1.0, 0.62, 0.2])
    a = np.clip(a + warm * 0.55, 0, 1)
    return Image.fromarray((a * 255).astype(np.uint8))

def gamma(im, g):
    a = np.asarray(im.convert('RGB')).astype(np.float32) / 255
    return Image.fromarray((np.clip(a, 0, 1) ** g * 255).astype(np.uint8))

def square_crop(im, cx_ratio, size_ratio=1.0):
    w, h = im.size; s = int(h * size_ratio); x0 = int(cx_ratio * w - s / 2)
    x0 = max(0, min(w - s, x0))
    return im.crop((x0, 0, x0 + s, s))

def cover(im, tw, th):
    w, h = im.size; r = max(tw / w, th / h)
    im = im.resize((int(w * r) + 1, int(h * r) + 1), Image.LANCZOS)
    x0 = (im.size[0] - tw) // 2; y0 = (im.size[1] - th) // 2
    return im.crop((x0, y0, x0 + tw, y0 + th))

ws = Image.open(os.path.join(FUYUKI, 'tohsaka_summoning.jpg'))
gamma(square_crop(ws, 0.58), 0.62).resize((900, 900), Image.LANCZOS).save(os.path.join(OUT, 'area_workshop.jpg'), quality=88)
cover(to_night(Image.open(os.path.join(FUYUKI, 'intersection.png'))), 900, 900).save(os.path.join(OUT, 'area_miyama.jpg'), quality=88)
cover(to_night(Image.open(os.path.join(FUYUKI, 'shinto.jpg'))), 900, 900).save(os.path.join(OUT, 'area_shinto.jpg'), quality=88)
cover(gamma(Image.open(os.path.join(FUYUKI, 'shinto_roof.png')), 0.75), 900, 900).save(os.path.join(OUT, 'area_scout.jpg'), quality=88)
bg_src = os.path.join(TMP, 'church_night.jpg')
if os.path.exists(bg_src):
    cover(gamma(Image.open(bg_src), 0.9), 1920, 1080).save(os.path.join(OUT, 'bg_church_night.jpg'), quality=85)

# 字体沿用主菜单概念稿
for f in ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']:
    shutil.copy(os.path.join(ROOT, 'docs/main_menu_concept_v1/assets', f), os.path.join(OUT, f))

data = {'masters': masters, 'servants': servants, 'attacks': attacks, 'events': events,
        'situations': situations, 'backs': backs, 'areas': areas, 'rules': rules}
with open(os.path.join(OUT, 'data.js'), 'w', encoding='utf-8') as f:
    f.write('window.FD_DATA=' + json.dumps(data, ensure_ascii=False, indent=1) + ';')
open(os.path.join(os.path.dirname(__file__), '.gdignore'), 'w').close()
print('masters', len(masters), 'servants', len(servants), 'attacks', len(attacks), 'events', len(events), 'situations', len(situations))
print('rules', rules)
print('areas', [(a['name'], a['score'], a['move_cost'], a['seats']) for a in areas])
