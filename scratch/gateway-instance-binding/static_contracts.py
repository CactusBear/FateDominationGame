"""只检验源码契约，不模拟规则运行、不执行 Godot。"""
from pathlib import Path
import json
from gdtoolkit.parser import parser

ROOT = Path(__file__).resolve().parents[2]
gateway = (ROOT / 'scripts/net/server_gateway.gd').read_text(encoding='utf-8')
manager = (ROOT / 'scripts/net/server_room_manager.gd').read_text(encoding='utf-8')
test = (ROOT / 'tests/gateway_instance_binding_test.gd').read_text(encoding='utf-8')

def section(text, name):
    begin = text.index('func ' + name + '(')
    end = text.find('\nfunc ', begin + 5)
    return text[begin:end if end >= 0 else None]

contracts = [
    ('实例四元组', lambda g,m: all('"'+k+'":' in section(m,'instance_binding') for k in ('room','pid','instance_id','authority_host_mode')), 'manager', '"authority_host_mode":room.authority_host_mode', '"mode":room.authority_host_mode'),
    ('权威模式比较', lambda g,m: 'binding.get("authority_host_mode") != room.get("authority_host_mode")' in section(m,'binding_matches'), 'manager', 'binding.get("authority_host_mode") != room.get("authority_host_mode")', 'false'),
    ('可信句柄缺失拒绝', lambda g,m: 'not process_identity_verifier.is_valid()' in section(m,'process_identity_verified'), 'manager', 'not process_identity_verifier.is_valid()', 'false'),
    ('严格 bool 验证', lambda g,m: 'verified is bool and verified' in section(m,'process_identity_verified'), 'manager', 'verified is bool and verified', 'bool(verified)'),
    ('回调路由 link 比较', lambda g,m: 'is_same(current.get("link"),route.link)' in section(g,'_same_route'), 'gateway', 'is_same(current.get("link"),route.link)', 'true'),
    ('旧回复拒绝', lambda g,m: 'not _route_is_current(peer,route): return' in section(g,'_room_response'), 'gateway', 'if sender != 1 or not _route_is_current(peer,route): return', 'if sender != 1: return'),
    ('旧断线拒绝', lambda g,m: 'not _route_is_current(peer,route): return' in section(g,'_room_disconnected'), 'gateway', 'if not _route_is_current(peer,route): return', 'if false: return'),
    ('排队回收身份', lambda g,m: '_detach_route(callback.peer,callback.route)' in section(g,'poll'), 'gateway', '_detach_route(callback.peer,callback.route)', '_detach(callback.peer,false)'),
    ('先撤销后关闭', lambda g,m: section(g,'_detach_route').index('routes.erase(peer)') < section(g,'_detach_route').index('route.link.close()'), 'gateway', '\troutes.erase(peer)\n\t_release_creator(peer,route)\n\troute.link.close()', '\troute.link.close()\n\t_release_creator(peer,route)\n\troutes.erase(peer)'),
    ('停止绑定旧实例', lambda g,m: 'manager.stop_room(binding.room,binding.pid,binding.instance_id)' in section(g,'_detach'), 'gateway', 'manager.stop_room(binding.room,binding.pid,binding.instance_id)', 'manager.stop_room(binding.room)'),
    ('pending 捕获绑定', lambda g,m: '_pending[peer] = binding' in g and 'var binding:Dictionary = _pending[peer]' in section(g,'poll'), 'gateway', '_pending[peer] = binding', '_pending[peer] = id'),
]

results=[]
for name, check, target, old, new in contracts:
    assert check(gateway,manager), name + ': current contract missing'
    source = gateway if target == 'gateway' else manager
    assert old in source, name + ': mutation anchor missing'
    mutant = source.replace(old,new,1)
    parser.parse(mutant)
    mg,mm = (mutant,manager) if target == 'gateway' else (gateway,mutant)
    assert not check(mg,mm), name + ': mutation was not detected'
    results.append({'contract':name,'current':'PASS','removed_guard':'RED detected'})
for label,source in [('gateway',gateway),('manager',manager),('test',test)]:
    parser.parse(source)
print(json.dumps({'scope':'source contracts and gdtoolkit syntax only; no Godot execution','contracts':results,'parsed':['server_gateway.gd','server_room_manager.gd','gateway_instance_binding_test.gd']},ensure_ascii=False,indent=2))
