#!/usr/bin/env python
"""Read-only lexical copy audit; never load Godot or rewrite input files.

Exit: 0 = no confirmed hits, 1 = confirmed hits, 2 = read/parse errors.
Counts are distinct source-entry/rule pairs, not individual characters.
Uncertain visibility/identity/semantics is always manual_review.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import sys

RULES = {
    'R1': '描述行带效果前缀',
    'R2': '括号补充文字（本口径不处理）',
    'R3': '数值或数量词后带点/层/画/枚/个（本口径不处理）',
    'R4': '资源标签费用未使用魔力消耗',
}
OUT_OF_SCOPE_RULES = frozenset({'R2', 'R3'})
FEE_TERMS = ('费用', '降费')
COMPOUND_CANDIDATES = (
    ('费用', '魔力消耗', 'Q06 已确认的统一词；不改变数值。'),
    ('卡牌费用', '卡牌魔力消耗', '仅替换“费用”子串，保留“卡牌”修饰与原语义。'),
    ('移动费用', '移动魔力消耗', '仅替换“费用”子串，保留移动语义；是否改成“移动所需魔力”交 main。'),
    ('费用为X', '魔力消耗为X', '仅替换资源名，保留 X 与公式结构。'),
    ('费用减一', '魔力消耗减一', '仅替换资源名，保留减一数值；是否采用更自然的“魔力消耗减少1点”交 main。'),
    ('印刷费用', '印刷魔力消耗', '仅替换“费用”子串，保留印刷值语义。'),
    ('区域移动费用', '区域移动魔力消耗', '仅替换“费用”子串，保留区域移动限定。'),
    ('费用上限', '魔力消耗上限', '仅替换资源名，保留上限语义。'),
    ('返回费用', '返回魔力消耗', '仅替换资源名，保留返回值语义。'),
    ('费用计算完成时', '魔力消耗计算完成时', '仅替换资源名，保留时点语义。'),
    ('降费', '减少魔力消耗', '源码当前无“降费”字面；这是待 main 选择的复合词候选，不自动套用。'),
)
APPLIED_CHANGES = (
    {
        'file': 'assets/scenes/game_scene/tactical_board_ui.tscn',
        'line': 1644,
        'key_path': 'metadata/event_desc',
        'before': '深山町明置事件牌\\n\\n效果：本战场所有英灵进行光荣的正面对决，力量属性攻击的威力 +2。',
        'after': '深山町明置事件牌\\n\\n本战场所有英灵进行光荣的正面对决，力量属性攻击的威力 +2。',
    },
    {
        'file': 'assets/scenes/game_scene/battle_board_v2.tscn',
        'line': 1490,
        'key_path': 'text',
        'before': '移动路线 · 费用',
        'after': '移动路线 · 魔力消耗',
    },
)
IDENTITY_KEYS = frozenset({
    'shown_name', 'shown_card_name', 'shown_skill_name', 'shown_attack_name',
    'shown_thing_name', 'shown_buff_name', 'shown_servant_name',
    'shown_master_name', 'true_name', 'real_name', 'servant_name', 'card_name',
    'master_name', 'name', 'title',
})
DESCRIPTION_KEYS = frozenset({
    'description', 'desc', 'ui_description', 'card_description', 'effect_description',
    'shown_description', 'shown_effect_name', 'shown_option_name', 'shown_note',
    'shown_notes', 'tooltip', 'tooltip_text', 'help_text', 'message', 'dialog_text',
    'text', 'placeholder_text', 'label', 'resource_label', 'cost_label',
})
SCENE_KEYS = frozenset({
    'text', 'tooltip_text', 'placeholder_text', 'title', 'dialog_text',
    'metadata/event_desc', 'metadata/zoom_desc', 'metadata/event_title',
    'metadata/zoom_title', 'metadata/zoom_hint',
})
DISPLAY_METADATA = frozenset({'event_desc', 'zoom_desc', 'event_title', 'zoom_title', 'zoom_hint'})
HAN = re.compile(r'[\u3400-\u9fff]')
PREFIX = re.compile(r'(?:^|\n)[\s\u3000]*(?:\[(?:/?[a-z]+)(?:=[^\]]*)?\])*效果\s*[：:]')
PAREN = re.compile(r'\([^()\n]*\)|（[^（）\n]*）')
NUMBER = r'(?:[-+]?\d+(?:\.\d+)?|[零〇一二三四五六七八九十百千万两半]+|%(?:\d+\$)?[-+0-9.#]*[dfs]|\{[A-Za-z_0-9]+\}|\{\})'
QUANTITY = re.compile(r'(?:' + NUMBER + r'|若干|每|多|数|几)\s*[点层画枚个]')
FEE_LABEL = re.compile(
    r'(?:^|\n|[·•])\s*(?:\[[^\]]*\])*'
    r'(?:(?:魔力|卡牌|打出|发动|使用|移动|部署|预估|累计|总|追加))*费用'
    r'(?=\s*(?:[：:]|%|\d|$))'
)
NON_MAGIC_FEE = re.compile(r'(?:令咒|状态|BUFF|buff)[^\n：:]{0,6}费用')
DISPLAY = re.compile(
    r'\.(?:text|tooltip_text|placeholder_text|dialog_text|title)\s*(?:\+?=)(?!=)|'
    r'\b(?:set_text|set_tooltip_text|add_item|add_tab|add_button|add_text|append_text|'
    r'_toast|push_message|_show_help|_hint|_label|_button|_make_label|'
    r'attach_line|show_message|popup_message|tr|tr_n)\s*\('
)
# Labels/formats are an explicit presentation module, not inferred from card names.
FORMAT_MODULE = 'scripts/ui/text/'


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_entries(text: str):
    """Parse JSON value spans, preserving exact line/column and array key paths."""
    json.loads(text)  # Validate the full document before collecting anything.
    decoder = json.JSONDecoder()
    records = []
    length = len(text)

    def ws(pos):
        while pos < length and text[pos].isspace():
            pos += 1
        return pos

    def walk(pos, path, field):
        pos = ws(pos)
        if text[pos] == '{':
            pos = ws(pos + 1)
            seen = set()
            while text[pos] != '}':
                key, end = decoder.raw_decode(text, pos)
                if key in seen:
                    raise ValueError('duplicate JSON key at ' + path + ': ' + key)
                seen.add(key)
                value_pos = ws(end)
                value_pos = ws(value_pos + 1)  # colon already validated
                part = '.' + key if re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', key) else '[' + json.dumps(key, ensure_ascii=False) + ']'
                pos = ws(walk(value_pos, path + part, key))
                if text[pos] == ',':
                    pos = ws(pos + 1)
            return pos + 1
        if text[pos] == '[':
            pos = ws(pos + 1)
            index = 0
            while text[pos] != ']':
                pos = ws(walk(pos, path + '[' + str(index) + ']', field))
                index += 1
                if text[pos] == ',':
                    pos = ws(pos + 1)
            return pos + 1
        value, end = decoder.raw_decode(text, pos)
        if isinstance(value, str):
            records.append((pos, path, field, value, text[pos:end]))
        return end

    walk(ws(0), '$', '')
    return records


def literals(text: str):
    """GDScript/resource lexer: comments, escaped quotes and multiline strings."""
    pos = 0
    while pos < len(text):
        char = text[pos]
        if char == '#':
            end = text.find('\n', pos)
            pos = len(text) if end < 0 else end + 1
            continue
        if char not in '\"\'':
            pos += 1
            continue
        start = pos
        quote = char * 3 if text.startswith(char * 3, pos) else char
        pos += len(quote)
        parts = []
        while pos < len(text) and not text.startswith(quote, pos):
            if text[pos] == '\\' and pos + 1 < len(text):
                following = text[pos + 1]
                escapes = {'n': '\n', 'r': '\r', 't': '\t', '\\': '\\', '"': '"', "'": "'"}
                if following in ('u', 'U'):
                    size = 4 if following == 'u' else 6
                    value = text[pos + 2:pos + 2 + size]
                    if len(value) == size and all(c in '0123456789abcdefABCDEF' for c in value):
                        parts.append(chr(int(value, 16)))
                        pos += size + 2
                        continue
                parts.append(escapes.get(following, '\\' + following))
                pos += 2
            else:
                parts.append(text[pos])
                pos += 1
        if pos >= len(text):
            raise ValueError('unterminated string at offset ' + str(start))
        pos += len(quote)
        yield start, pos, ''.join(parts), text[start:pos]


def location(text: str, offset: int):
    return text.count('\n', 0, offset) + 1, offset - text.rfind('\n', 0, offset)


def classify(entry):
    value = entry['original']
    matched = {}
    prefix = [m.group() for m in PREFIX.finditer(value)]
    if prefix:
        matched['R1'] = prefix
    parens = [m.group() for m in PAREN.finditer(value)]
    if parens:
        matched['R2'] = parens
    quantities = [m.group() for m in QUANTITY.finditer(value)]
    if quantities:
        matched['R3'] = quantities
    if '费用' in value:
        matched['R4'] = [m.group() for m in re.finditer('费用', value)]
    findings = []
    for rule, hits in matched.items():
        if rule in OUT_OF_SCOPE_RULES:
            findings.append({**entry, 'rule': rule, 'rule_name': RULES[rule],
                             'status': 'out_of_scope', 'matches': hits,
                             'reason': '本口径不处理'})
            continue
        reason = ''
        if entry['identity']:
            reason = '名称/真名属于天然例外；不得按文案规则自动定罪'
        elif not entry['visible']:
            reason = '无明确展示字段或UI输出证据；需确认是否用户可见'
        elif rule == 'R4' and (not FEE_LABEL.search(value) or NON_MAGIC_FEE.search(value)):
            reason = '正文/操作文字/非魔力资源费用，非明确魔力标签；需确认替换口径'
        findings.append({**entry, 'rule': rule, 'rule_name': RULES[rule],
                         'status': 'manual_review' if reason else 'violation',
                         'matches': hits, 'reason': reason or '显式展示文本的词法命中'})
    return findings


def extract(path: str, text: str, suffix: str):
    entries = []
    if suffix == '.json':
        for offset, key_path, field, value, raw in json_entries(text):
            if not HAN.search(value):
                continue
            known = field in DESCRIPTION_KEYS or field.startswith('shown_')
            line, column = location(text, offset)
            entries.append(dict(file=path, line=line, column=column, key_path=key_path,
                                original=value, source_literal=raw, visible=known,
                                identity=field in IDENTITY_KEYS,
                                evidence='JSON展示字段:' + field if known else 'JSON未声明展示用途:' + field))
        return entries
    function = ''
    for start, end, value, raw in literals(text):
        if not HAN.search(value):
            continue
        line, column = location(text, start)
        line_start = text.rfind('\n', 0, start) + 1
        line_end = text.find('\n', end)
        if line_end < 0:
            line_end = len(text)
        before = text[line_start:start]
        # Remove other literals so a quoted '.text =' cannot establish visibility.
        line_source = text[line_start:line_end]
        funcs = list(re.finditer(r'^\s*(?:static\s+)?func\s+(\w+)\s*\(', text[:start], re.M))
        function = funcs[-1].group(1) if funcs else '<top-level>'
        field = before.split('=', 1)[0].strip()
        if suffix in ('.tscn', '.tres'):
            visible = field in SCENE_KEYS
            identity = field in {'title', 'metadata/zoom_title', 'metadata/event_title'}
            evidence = '场景展示属性:' + field if visible else '非展示场景字符串'
        elif suffix == '.gd':
            stripped = re.sub(r'\"(?:\\.|[^\"\\])*\"|\'(?:\\.|[^\'\\])*\'', '""', line_source)
            visible = bool(DISPLAY.search(stripped))
            formatter = path.startswith(FORMAT_MODULE) and (
                re.search(r'\breturn\b|\.append\s*\(', before) or
                function == '<top-level>' and re.search(r'^\s*\"[^\"]+\"\s*:', before)
            )
            visible = visible or bool(formatter)
            fee_visible = visible
            if re.search(r'\.(?:replace|find|begins_with|ends_with|contains)\s*\(', before):
                visible = False
            indirect_ui = (
                '"label"' in before
                or path == 'json_maker/json_maker_ui.gd' and function == '_confirm_fixed_number'
                or path == 'scripts/match/view_builder.gd' and function == 'public_description'
                or path == 'scripts/system/global/all_operations.gd' and '"summary"' in before
                or path == 'scripts/system/time_points.gd' and 294 <= line <= 512
            )
            if indirect_ui:
                fee_visible = True
                evidence = 'UI间接输出证据:' + function
            meta = re.search(r'\.set_meta\s*\(\s*[\"\'](\w+)[\"\']\s*,\s*$', before)
            visible = visible or bool(meta and meta.group(1) in DISPLAY_METADATA)
            identity = bool(meta and meta.group(1) in {'zoom_title', 'event_title'})
            if visible:
                evidence = 'UI输出入口:' + function
            elif indirect_ui:
                evidence = 'UI间接输出证据:' + function
            else:
                evidence = '脚本字面量，未证明可见:' + function
            if start > 0 and text[start - 1] in '$^&':
                visible = False
                evidence = 'NodePath/StringName/节点标识，不证明可见'
        else:
            visible, identity, evidence = False, False, '文本文件，未声明展示用途'
        entries.append(dict(file=path, line=line, column=column, key_path=function if suffix == '.gd' else field,
                            original=value, source_literal=raw, visible=visible,
                            fee_visible=fee_visible if suffix == '.gd' else visible,
                            identity=identity, evidence=evidence))
    return entries


def scan(root: Path):
    findings, errors, manifest, skipped, fee_mentions = [], [], [], Counter(), []
    entries_count = 0
    paths = set()
    for folder in ('data', 'assets', 'scripts', 'json_maker'):
        base = root / folder
        if base.exists():
            paths.update(p for p in base.rglob('*') if p.is_file())
    for target in sorted(paths, key=lambda p: p.as_posix()):
        relative = target.relative_to(root).as_posix()
        if target.is_symlink():
            skipped['symlink'] += 1
            continue
        suffix = target.suffix.lower()
        # All data/assets JSON/resources; all script literals, not just presumed UI folders.
        allowed = suffix in {'.json', '.gd', '.tscn', '.tres', '.txt'}
        if relative.startswith(('scripts/', 'json_maker/')):
            allowed = suffix == '.gd'
        if not allowed:
            skipped[suffix or '<no suffix>'] += 1
            continue
        try:
            data = target.read_bytes()
            text = data.decode('utf-8-sig')
            manifest.append({'file': relative, 'sha256': digest(data)})
            if suffix == '.txt':
                # Plain text lacks a declarative display contract: review only.
                for line, value in enumerate(text.splitlines(), 1):
                    if HAN.search(value):
                        entry = dict(file=relative, line=line, column=1, key_path='<text>', original=value,
                                     source_literal=value, visible=False, identity=False, evidence='文本文件，展示用途未知')
                        entries_count += 1
                        findings.extend(classify(entry))
            else:
                entries = extract(relative, text, suffix)
                entries_count += len(entries)
                for entry in entries:
                    if any(term in entry['original'] for term in FEE_TERMS):
                        fee_mentions.append({
                            'file': entry['file'], 'line': entry['line'], 'column': entry['column'],
                            'key_path': entry['key_path'], 'original': entry['original'],
                            'visible': entry.get('fee_visible', entry['visible']), 'evidence': entry['evidence'],
                        })
                    findings.extend(classify(entry))
        except (OSError, UnicodeError, ValueError, IndexError) as exc:
            errors.append({'file': relative, 'error': str(exc)})
    findings.sort(key=lambda f: (f['file'], f['line'], f['column'], f['rule']))
    violations = [f for f in findings if f['status'] == 'violation']
    reviews = [f for f in findings if f['status'] == 'manual_review']
    out_of_scope = [f for f in findings if f['status'] == 'out_of_scope']
    counts = lambda records: {r: sum(f['rule'] == r for f in records) for r in RULES}
    fee_mentions.sort(key=lambda f: (f['file'], f['line'], f['column'], f['key_path']))
    return {
        'schema_version': 1, 'root': str(root), 'rules': RULES,
        'scope': ['data/**', 'assets/**', 'scripts/**/*.gd', 'json_maker/**/*.gd'],
        'summary': {'scanned_files': len(manifest), 'chinese_entries': entries_count,
                    'violation_rule_hits': len(violations), 'violating_entries': len({(f['file'], f['line'], f['column']) for f in violations}),
                    'violating_files': len({f['file'] for f in violations}), 'violations_by_rule': counts(violations),
                    'manual_review_rule_hits': len(reviews), 'manual_reviews_by_rule': counts(reviews),
                    'out_of_scope_rule_hits': len(out_of_scope), 'out_of_scope_by_rule': counts(out_of_scope),
                    'visible_fee_mentions': sum(bool(f['visible']) for f in fee_mentions),
                    'fee_mentions': len(fee_mentions),
                    'errors': len(errors), 'skipped_files_by_extension': dict(sorted(skipped.items()))},
        'fee_mentions': fee_mentions,
        'applied_changes': APPLIED_CHANGES,
        'source_manifest': manifest,
        'source_manifest_sha256': digest(json.dumps(manifest, ensure_ascii=False, sort_keys=True).encode('utf-8')),
        'findings': findings, 'errors': errors,
    }


def markdown(result, top):
    s = result['summary']
    esc = lambda value: json.dumps(value, ensure_ascii=False).replace('|', '\\|')
    lines = ['# 用户可见文案静态扫描报告', '',
             '## 交付与运行', '',
             '- 脚本：`tools/scan_visible_copy_style.py`',
             '- SHA256：`' + result['scanner_sha256'] + '`',
             '- 命令：`' + result['command'] + '`',
             '- 扫描退出码：`' + str(result['exit_code']) + '`',
             '- 源文件清单 SHA256：`' + result['source_manifest_sha256'] + '`',
             '- 详细数据：与本报告同次生成的 JSON，含每项原文、源码字面量、行/列/键路径、匹配证据与源文件 SHA256。', '',
             '## 实际统计', '',
             f'- 扫描文本文件 {s["scanned_files"]}；中文文本条目 {s["chinese_entries"]}。',
             f'- 确认词法违例 {s["violation_rule_hits"]} 项规则命中，涉及 {s["violating_entries"]} 个文本条目 / {s["violating_files"]} 个文件。',
             f'- “本口径不处理” {s["out_of_scope_rule_hits"]} 项规则命中（R2 括号 {s["out_of_scope_by_rule"]["R2"]}、R3 量词 {s["out_of_scope_by_rule"]["R3"]}），不计违例、不影响退出码。',
             f'- 需人工确认 {s["manual_review_rule_hits"]} 项；读取/解析错误 {s["errors"]}。', '',
             '|规则|判定口径|确认违例|需人工确认|本口径不处理|', '|---|---|---:|---:|---:|']
    for rule, name in RULES.items():
        lines.append(f'|{rule}|{name}|{s["violations_by_rule"][rule]}|{s["manual_reviews_by_rule"][rule]}|{s["out_of_scope_by_rule"][rule]}|')
    lines.extend(['', '同一文本命中多条规则分别计数；同一文本同一规则重复命中只计一次。扫描所有版本和旧界面，不按运行入口删减。', '',
                  '## 本轮实际修正', '',
                  '|文件:行 / 键路径|前原文|后原文|', '|---|---|---|'])
    for change in result['applied_changes']:
        lines.append(f'|`{change["file"]}:{change["line"]}` / `{change["key_path"]}`|{esc(change["before"])}|{esc(change["after"])}|')
    lines.extend(['', '## 用户可见费用/降费位置', '',
                  f'- 扫描器按显式展示证据确认 {s["visible_fee_mentions"]} 项；扫描范围内共提取含“费用/降费”的字符串条目 {s["fee_mentions"]} 项。',
                  '- 下表逐一列出扫描器确认可见的位置；后表列出同词但当前词法规则未能确认可见的候选，避免把间接 UI 数据流误报为已确认可见。', '',
                  '|文件:行:列 / 键路径|原文|可见性依据|', '|---|---|---|'])
    for f in result['fee_mentions']:
        if f['visible']:
            lines.append(f'|`{f["file"]}:{f["line"]}:{f["column"]}` / `{f["key_path"]}`|{esc(f["original"])}|{f["evidence"]}|')
    if not any(f['visible'] for f in result['fee_mentions']):
        lines.append('|无|—|—|')
    lines.extend(['', '### 同词但未由词法证实可见', '', '|文件:行:列 / 键路径|原文|当前证据|', '|---|---|---|'])
    for f in result['fee_mentions']:
        if not f['visible']:
            lines.append(f'|`{f["file"]}:{f["line"]}:{f["column"]}` / `{f["key_path"]}`|{esc(f["original"])}|{f["evidence"]}|')
    if not any(not f['visible'] for f in result['fee_mentions']):
        lines.append('|无|—|—|')
    lines.extend(['', '### 复合词候选（仅交 main 定，不自动修改）', '', '|现有词形|最小一致候选|理由|', '|---|---|---|'])
    for source, candidate, reason in COMPOUND_CANDIDATES:
        lines.append(f'|{source}|{candidate}|{reason}|')
    lines.extend(['', '## Top 样本', '', 'Top 是按文件/行/规则排序每条规则取前 ' + str(top) + ' 项，不是风险评级。'])
    for rule in RULES:
        lines.extend(['', '### ' + rule, '', '|文件:行:列 / 键路径|原文|命中片段|', '|---|---|---|'])
        samples = [f for f in result['findings'] if f['status'] == 'violation' and f['rule'] == rule][:top]
        for f in samples:
            lines.append(f'|`{f["file"]}:{f["line"]}:{f["column"]}` / `{f["key_path"]}`|{esc(f["original"])}|{esc(f["matches"])}|')
        if not samples:
            lines.append('|无|—|—|')
    lines.extend(['', '## 待澄清与覆盖边界', '',
                  '- 规则①仅判断行首“效果：/效果:”。是否要求“附加效果：”“残留效果：”等也禁止，需要明确；不从分号、句号猜多个效果或强制分行。',
                  '- 规则②括号按 Q06 标为“本口径不处理”：仍记录命中位置，但不计违例、不修改、不影响退出码。',
                  '- 规则③量词按 Q06 标为“本口径不处理”：仍记录命中位置，但不计违例、不修改、不影响退出码。',
                  '- 规则④资源标签以及正文费用统一词待按 Q06 执行；本轮只自动确认并修正明确命中的资源标签，其余“费用/降费”位置与复合词候选单列交 main。',
                  '- 规则⑤按本次要求不验收。没有卡图OCR、逐项卡面比对或Godot执行，因此不证明卡面信息与UI描述对应完备。',
                  '- JSON展示字段采用显式字段名单与shown_前缀；名称/真名仅人工确认。未知字段若命中规则仍列人工确认，不静默丢弃。',
                  '- GDScript使用词法字符串提取、明确展示赋值/调用、已验证的event_desc/zoom_desc/zoom_hint说明元数据及scripts/ui/text返回/输出映射；其他命中列人工确认。不做跨函数数据流、运行时字符串拼接/翻译与动态数值求值；多行输出调用和间接变量绑定可能留在人工确认。',
                  '- 扫描data/assets全部JSON、场景、资源、文本及scripts/json_maker所有GDScript；图片、字体、音视频、配置、导入产物等不解析，跳过统计在JSON。普通文件按UTF-8读取，不跟随文件符号链接。',
                  '- 扫描只读取生产文件；仅按显式参数新建docs报告，不修改任何原文，不调用Godot、不操作进程。工作树原有改动不回滚。', '',
                  '## 完整命中清单', '', '|类别|规则|文件:行:列 / 键路径|原文|判定依据|', '|---|---|---|---|---|'])
    for f in result['findings']:
        status = {'violation': '违例', 'manual_review': '需人工确认', 'out_of_scope': '本口径不处理'}[f['status']]
        lines.append(f'|{status}|{f["rule"]}|`{f["file"]}:{f["line"]}:{f["column"]}` / `{f["key_path"]}`|{esc(f["original"])}|{f["reason"]}；{f["evidence"]}|')
    if result['errors']:
        lines.extend(['', '## 扫描错误', '', '```json', json.dumps(result['errors'], ensure_ascii=False, indent=2), '```'])
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--output', type=Path, help='New JSON report, under root/docs only')
    parser.add_argument('--report', type=Path, help='New Markdown report, under root/docs only')
    parser.add_argument('--top', type=int, default=5)
    parser.add_argument('--overwrite', action='store_true', help='Allow replacing the explicitly named reports under root/docs')
    args = parser.parse_args()
    root = args.root.resolve()
    if not root.is_dir() or args.top < 0:
        parser.error('root must exist and top must be nonnegative')
    for output in (args.output, args.report):
        if output and not output.resolve().is_relative_to((root / 'docs').resolve()):
            parser.error('reports must be under root/docs')
        if output and output.exists() and not args.overwrite:
            parser.error('reports already exist; pass --overwrite explicitly to replace them')
    if args.output and args.report and args.output.resolve() == args.report.resolve():
        parser.error('JSON and Markdown output must be distinct')
    result = scan(root)
    code = 2 if result['errors'] else 1 if result['summary']['violation_rule_hits'] else 0
    result.update(scanner_sha256=digest(Path(__file__).read_bytes()),
                  command='python -B ' + ' '.join('"' + a + '"' if ' ' in a else a for a in sys.argv), exit_code=code)
    payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    for target, content in ((args.output, payload), (args.report, markdown(result, args.top))):
        if target:
            target.parent.mkdir(parents=True, exist_ok=True)
            mode = 'w' if args.overwrite else 'x'
            with target.open(mode, encoding='utf-8', newline='\n') as stream:
                stream.write(content)
    if args.output:
        print(json.dumps(result['summary'], ensure_ascii=False, indent=2))
    else:
        print(payload, end='')
    return code


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    raise SystemExit(main())
