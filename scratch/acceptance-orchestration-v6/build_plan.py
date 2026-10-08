"""只生成本目录验收计划；所有动态条目初始化 NOT_RUN。"""
import csv
import json
from pathlib import Path
P=Path('E:/Projects/Godot/FateDominationGame-master')
OUT=Path(__file__).resolve().parent
cases=[]
def add(id,layer,title,deps,assertions,**extra):
    cases.append(dict(id=id,layer=layer,title=title,depends_on=deps,assertions=assertions,**extra))
add('FREEZE','static','冻结代码/测试/资源/构建清单',[],['source_and_tests_frozen','ignored_tests_in_manifest','build_hashes_recorded'])
add('STATIC','static','静态入口、权限和数据屏障',['FREEZE'],['parse_and_resource_checks','all_transport_entrypoints_reviewed','no_runtime_claim'])
add('WINDOW','window','真实窗口单机多进程入口',['STATIC'],['isolated_users_and_caches','formal_ui_human_inputs','authority_on_host','actual_window_branches_executed'])
rwdeps={1:['WINDOW'],2:['RW01'],3:['RW02'],4:['RW01'],5:['RW04'],6:['RW04'],7:['RW06'],8:['RW06'],9:['RW08'],10:['RW09'],11:['RW10'],12:['RW10'],13:['RW11'],14:['RW13'],15:['RW04'],16:['RW10'],17:['LINUX-MATCH'],18:['LINUX-MATCH','RW03'],19:['RW18'],20:['RW04'],21:['RW20'],22:['RW20'],23:['LINUX-MATCH'],24:['LINUX-MATCH']}
with (P/'tests/real_world_acceptance_v5/checklist.csv').open(encoding='utf-8-sig',newline='') as f:
    for row in csv.DictReader(f):
        id=row['case_id']; n=int(id[2:])
        add(id,'window',row['title'],rwdeps[n],['all_declared_branches_observed','authority_log_and_state_comparison','all_steps_reviewed'],source='tests/real_world_acceptance_v5/checklist.csv',expected=row['expected'],steps=row['steps'])
lan=json.loads((P/'tests/real_world_acceptance_v5/lan_matrix.json').read_text(encoding='utf-8-sig'))
for x in lan['cases']:
    add(x['id'],'lan',x['title'],x['depends_on'] or ['WINDOW'],x['acceptance_assertions'],minimum_devices=x['minimum_physical_windows_devices'],source='tests/real_world_acceptance_v5/lan_matrix.json')
cn=json.loads((P/'tests/real_world_acceptance_v5/cross_network_matrix.json').read_text(encoding='utf-8-sig'))
for x in cn['tasks']:
    deps=['LAN-01','P2P-BUILD'] if x['id']=='CN01' else ['CN01']
    add(x['id'],'p2p',x['scenario'],deps,['all_modes_directions_and_declared_variants_reviewed','business_or_expected_rejection_observed','host_authority_no_ai_takeover','no_turn_or_game_relay'],modes=x['modes'],requires_direct_connection=x['id'] in ['CN01','CN02','CN03','CN04','CN08','CN11'],source='tests/real_world_acceptance_v5/cross_network_matrix.json')
add('P2P-BUILD','static','WebRTC扩展与信令包前置',['STATIC'],['target_extension_exported','stun_only_config','signal_server_role_isolated'])
linux=[('LINUX-PREFLIGHT','Linux导出包/依赖/帮助/存储',['STATIC'],['real_linux_process','native_libraries_loaded','isolated_storage','actual_help_commands_recorded']),('LINUX-MATCH','独立网关+房间工作进程+远端真人完整局',['LINUX-PREFLIGHT','RW10'],['authority_on_linux','gateway_and_worker_id_bound','real_human_match_and_private_answers','public_spectator_privacy']),('LINUX-WORKER-RESTART','仅子进程重新就绪',['LINUX-MATCH'],['exact_owned_worker_fault','new_pid_and_instance','fresh_ready_not_match_recovery']),('LINUX-LOBBY-RECOVERY','大厅登记与数据恢复',['LINUX-WORKER-RESTART'],['gateway_keeps_room','verified_existing_data','no_empty_state_overwrite']),('LINUX-MATCH-RECOVERY','原局恢复',['LINUX-LOBBY-RECOVERY','RW17'],['save_restart_reconnect_restore_order','all_original_humans_key_bound','restoring_before_playing','state_and_pending_actions_equal']),('LINUX-SIGNALS','SIGINT/SIGTERM保存关闭',['LINUX-MATCH'],['request_pid_instance_receipt_bound','saved_before_exit','actual_exit_observed','ready_cleanup','disk_replay_verified']),('LINUX-SAVE-FAIL','保存失败保留旧档',['LINUX-MATCH','RW24'],['failed_save_not_success','old_state_retained','owned_fault_restored']),('LINUX-GATEWAY-RESTART','网关异常恢复独立验证',['LINUX-MATCH-RECOVERY'],['gateway_restart_not_worker_restart','room_registration_restored','authenticated_clients_reconnect']),('LINUX-LOAD','多房间并发与故障隔离',['LINUX-MATCH-RECOVERY','LINUX-SIGNALS'],['distinct_room_instances','fault_confined_to_one_room','remaining_humans_continue','no_process_leaks'])]
for id,title,deps,assertions in linux:
    add(id,'linux',title,deps,assertions)
# 验证依赖图闭合且无循环。
index={x['id']:x for x in cases}
assert len(index)==len(cases)
seen=set(); active=set()
def visit(id):
    assert id in index,id
    if id in seen:return
    assert id not in active, id
    active.add(id)
    for dep in index[id]['depends_on']:visit(dep)
    active.remove(id);seen.add(id)
for id in index:visit(id)
manifest={'schema_version':6,'scope':'PLAN_ONLY_NOT_RUNTIME_RESULTS','cases':cases}
ledger={'schema_version':6,'run_id':'','build_id':'','cases':[{'id':x['id'],'status':'NOT_RUN','run_id':'','build_id':'','evidence':[],'assertions':{}} for x in cases]}
for filename,data in [('manifest.json',manifest),('ledger-template.json',ledger)]:
    (OUT/filename).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
lines=['flowchart TD']
for x in cases:
    lines.append('  '+x['id'].replace('-','_')+'["'+x['id']+' '+x['title']+'"]')
    for dep in x['depends_on']:lines.append('  '+dep.replace('-','_')+' --> '+x['id'].replace('-','_'))
(OUT/'dependencies.mmd').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(json.dumps({'planned_cases':len(cases),'acyclic':True,'all_statuses':'NOT_RUN','runtime_executed':False},ensure_ascii=False))
