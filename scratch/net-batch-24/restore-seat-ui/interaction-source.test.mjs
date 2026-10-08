import fs from 'node:fs';
import assert from 'node:assert/strict';
import {isDeepStrictEqual} from 'node:util';
const out='scratch/net-batch-24/restore-seat-ui/';
const code=fs.readFileSync(out+'candidate/scripts/net/identity/restore_seat_panel.gd.txt','utf8');
// 有限语法转译真实候选方法，不另写JS恢复业务。节点/继承依赖由夹具代替；不是Godot验收。
function expr(s){return s.replace(/\$Content\/Buttons\/(\w+)/g,'ui.$1').replace(/\$Content\/Target/g,'ui.Target').replace(/_session.view != _context/g,'!equal(_session.view,_context)').replace(/([\w.]+)\.get\(([^)]*)\)/g,'get($1,$2)').replace(/([\w.]+)\.duplicate\(([^)]*)\)/g,'duplicate($1)').replace(/([\w.]+)\.is_empty\(\)/g,'empty($1)').replace(/([\w.]+)\.size\(\)/g,'size($1)').replace(/([\w.]+)\.clear\(\)/g,'clear($1)').replace(/\.append\(/g,'.push(').replace(/\bnot\b/g,'!').replace(/\band\b/g,'&&').replace(/\bor\b/g,'||');}
function compile(name){
 const m=code.match(new RegExp('^func '+name+'\\([^\\n]*\\).*:\\n([\\s\\S]*?)(?=^func |^static func |$(?![\\s\\S]))','m'));assert.ok(m,name);
 const output=[],blocks=[];
 for(const raw of m[1].split('\n')){
  if(!raw.trim()||raw.trim().startsWith('#'))continue;
  const depth=raw.match(/^\t*/)[0].length;let line=raw.trim();
  while(blocks.length&&depth<=blocks.at(-1)){output.push('}');blocks.pop();}
  if(line.startsWith('if ')){
   const x=line.match(/^if (.*):(?: (.*))?$/);assert.ok(x,line);
   if(x[2])output.push(`if(${expr(x[1])}){${expr(x[2])};}`);
   else{output.push(`if(${expr(x[1])}){`);blocks.push(depth);}continue;
  }
  if(line.startsWith('for ')){const x=line.match(/^for (\w+) in (.*):$/);assert.ok(x,line);output.push(`for(const ${x[1]} of iterate(${expr(x[2])})){`);blocks.push(depth);continue;}
  line=line.replace(/^var (\w+)(?::\w+)?\s*=/,'let $1 =');output.push(expr(line)+';');
 }
 while(blocks.length){output.push('}');blocks.pop();}
 return new Function('s','index','with(s){'+output.join('\n')+'}');
}
const methods=Object.fromEntries(['_query_candidates','_select_candidate','_complete','_submit','refresh_context'].map(n=>[n,compile(n)]));
function fixture(){
 const list={rows:[],item_count:0,clear(){this.rows=[];this.item_count=0;},add_item(label){this.rows.push({label});this.item_count++;},set_item_metadata(i,id){this.rows[i].id=id;},get_item_metadata(i){return this.rows[i].id;},get_item_text(i){return this.rows[i].label;}};
 const view={owner:41,phase:'lobby',revision:3,members:[{id:41,name:'同名（Owner）',connected:true,spectator:false},{id:99,name:'同名（Peer）',connected:true,spectator:false},{id:100,name:'旁观',connected:true,spectator:true},{id:101,name:'离线',connected:false,spectator:false}]};
 const s={_session:{view},_context:structuredClone(view),_revision:3,_saved_bindings:{'7':1,'12':2,'19':0},_selected:{},_submit_pending:false,_source:'C:/local/archive',_metadata_source:'C:/local/archive/restore-identity.json',visible:true,allowed:true,feedback:{text:''},candidates:list,seats:{selected:0,item_count:2,texts:[],get_item_metadata(i){return ['7','12'][i];},set_item_text(i,t){this.texts[i]=t;},get_item_text(i){return this.texts[i];}},ui:{Confirm:{disabled:true},Refresh:{disabled:false},Target:{text:''}},emitted:[],equal:isDeepStrictEqual,get:(o,k,d)=>o[k]??d,duplicate:structuredClone,empty:o=>Object.keys(o).length===0,size:o=>Object.keys(o).length,clear:o=>{for(const k of Object.keys(o))delete o[k];},iterate:o=>Array.isArray(o)?o:Object.keys(o),int:Number,str:String};
 s.range=n=>Array.from({length:n},(_,i)=>i);
 s._session.authority_host={restore_member_candidates:()=>s._session.view.members.filter(m=>m.connected&&!m.spectator).map(m=>({member_id:m.id,label:m.name}))};
 s._input={candidates:[],accept(model){this.revision=model.revision;this.candidates=model.candidates;return true;},select_member(id){return this.candidates.some(r=>r.member_id===id);}};
 s.can_restore=()=>s.allowed;s.close_panel=()=>{s._session=null;s.visible=false;s._selected={};};
 s._clear_candidates=()=>{list.clear();s._input.candidates=[];s._submit_pending=false;s.ui.Confirm.disabled=true;};
 s.restore_selected={emit:(...a)=>s.emitted.push(a)};
 for(const[n,fn]of Object.entries(methods))s[n]=(index)=>fn(s,index);
 s._query_candidates();return s;
}
let checks=0;function check(n,f){f();checks++;console.log('PASS '+n);}
function selectAll(s){s._select_candidate(0);s.seats.selected=1;s._select_candidate(1);}
check('加载无真人自动认领，AI保留0',()=>assert.deepEqual(fixture()._selected,{'19':0}));
check('候选仅在线非观战，保留公开重名标签',()=>assert.deepEqual(fixture().candidates.rows,[{label:'同名（Owner）',id:41},{label:'同名（Peer）',id:99}]));
check('新房间不同成员号逐座映射，全选才可确认',()=>{const s=fixture();s._select_candidate(0);assert.deepEqual(s._selected,{'7':41,'19':0});assert.equal(s.ui.Confirm.disabled,true);s.seats.selected=1;s._select_candidate(1);assert.equal(s.ui.Confirm.disabled,false);});
check('重复占座拒绝',()=>{const s=fixture();s._select_candidate(0);s.seats.selected=1;s._select_candidate(0);assert.equal(Object.hasOwn(s._selected,'12'),false);assert.match(s.feedback.text,/不能重复/);});
check('越界点击拒绝',()=>{const s=fixture();s._select_candidate(-1);s._select_candidate(2);assert.deepEqual(s._selected,{'19':0});});
check('未全选不能提交',()=>{const s=fixture();s._submit();assert.equal(s.emitted.length,0);});
check('完整映射与本机路径提交，禁止双击，映射拷贝',()=>{const s=fixture();selectAll(s);s._submit();s._submit();assert.deepEqual(s.emitted,[[s._source,{'7':41,'12':99,'19':0},s._metadata_source]]);s._selected['7']=123;assert.equal(s.emitted[0][1]['7'],41);});
check('刷新清真人映射',()=>{const s=fixture();s._select_candidate(0);s._query_candidates();assert.deepEqual(s._selected,{'19':0});assert.equal(s.ui.Confirm.disabled,true);});
check('修订变化丢弃旧索引点击',()=>{const s=fixture();s._select_candidate(0);s._session.view.revision++;s._select_candidate(1);assert.deepEqual(s._selected,{'19':0});assert.match(s.feedback.text,/重新逐座/);});
check('同修订成员掉线拒绝提交并清空',()=>{const s=fixture();selectAll(s);s._session.view.members[1].connected=false;s._submit();assert.equal(s.emitted.length,0);assert.deepEqual(s._selected,{'19':0});assert.equal(s.candidates.rows.length,1);});
check('权限失效关闭',()=>{const s=fixture();s.allowed=false;s.refresh_context();assert.equal(s._session,null);assert.equal(s.visible,false);});
check('AI全席明确保留声明',()=>{const s=fixture();s._saved_bindings={'19':0};s._query_candidates();s._submit();assert.deepEqual(s.emitted[0][1],{'19':0});});
const read=p=>fs.readFileSync(out+'candidate/'+p+'.txt','utf8');const lobby=read('scripts/net/ui/lobby_screen.gd');
check('真实提交及轮询关闭接线',()=>{assert.match(lobby,/restore_local_match\(source, selected, metadata_source\)/);assert.doesNotMatch(lobby,/await session.restore_local_match\(source\)/);for(const x of ['restore_selected.connect(_restore_archive)','$RestoreSeatPanel.refresh_context()','$RestoreSeatPanel.close_panel()'])assert.ok(lobby.includes(x));});
check('仅选中档元数据只读且明确拒绝',()=>{for(const x of ['local.path_join("restore-identity.json")','Paths.checked(local, metadata)','Archive.read_metadata(metadata)','valid_state(saved, true)','Decode.decode(saved)','缺少本机 restore-identity.json'])assert.ok(code.includes(x),x);assert.doesNotMatch(code,/FileAccess.WRITE|write_json|recovery.json|fingerprint|ticket|actor_key|member_identities|identity_candidates/);});
check('复用候选场景和选择入口',()=>{assert.match(code,/extends "res:\/\/scripts\/net\/identity\/identity_inheritance_panel.gd"/);assert.match(read('assets/scenes/main_menu/restore_seat_panel.tscn'),/identity_inheritance_panel.tscn/);assert.match(code,/_input.select_member\(member\)/);});
check('座位映射可见且刷新去除旧标签',()=>{const s=fixture();s._select_candidate(0);assert.equal(s.seats.texts[0],'座位 7 · 同名（Owner）');assert.equal(s.ui.Target.text,s.seats.texts[0]);s._query_candidates();assert.equal(s.seats.texts[0],'座位 7 · 待指定');});
check('公开候选复用认证桥与重名标签规则',()=>{const host=read('scripts/net/session/authority_host_client.gd');assert.match(host,/_identity_bridge.snapshot_for\(gateway, target, session\)/);assert.match(host,/public_member_labels\(members, identities, snapshot.profiles\)/);assert.match(host,/if member.get\("connected"\) == true and member.get\("spectator"\) == false/);const registry=fs.readFileSync('scripts/net/identity/player_registry.gd','utf8');assert.match(registry,/if counts\[row.label\] > 1: row.label \+=/);assert.match(registry,/row.erase\("username"\)/);});
const {createHash}=await import('node:crypto');
check('生产基线未修改',()=>{const m=JSON.parse(fs.readFileSync(out+'baseline.json'));for(const[p,h]of Object.entries(m))assert.equal(createHash('sha256').update(fs.readFileSync(p)).digest('hex'),h,p);});
const result={checks,failed:0,scope:'Node有限语法转译真实候选GDScript交互与接线断言，非Godot运行/画面验收'};fs.writeFileSync(out+'results.json',JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
