from pathlib import Path
import hashlib, json
root=Path('E:/Projects/Godot/FateDominationGame-master')
out=root/'scratch/net-batch-24/restore-seat-ui'
lines=(out/'restore-seat-ui.v4a').read_text(encoding='utf-8').splitlines()
assert lines[0]=='*** Begin Patch' and lines[-1]=='*** End Patch'
index=1; checked=[]
while index<len(lines)-1:
    header=lines[index]; index+=1
    kind, name=header[4:].split(' File: ',1)
    chunk=[]
    while index<len(lines)-1 and not lines[index].startswith('*** '):
        chunk.append(lines[index]); index+=1
    if kind=='Add':
        assert not (root/name).exists(), name
        assert all(x.startswith('+') for x in chunk)
        result=[x[1:] for x in chunk]
    else:
        assert kind=='Update'
        result=(root/name).read_text(encoding='utf-8').splitlines()
        cursor=0
        hunks=[]
        for line in chunk:
            if line=='@@': hunks.append([])
            else: hunks[-1].append(line)
        for hunk in hunks:
            before=[x[1:] for x in hunk if x[0] in ' -']
            after=[x[1:] for x in hunk if x[0] in ' +']
            matches=[i for i in range(cursor,len(result)-len(before)+1) if result[i:i+len(before)]==before]
            assert len(matches)==1,(name,matches)
            start=matches[0];result[start:start+len(before)]=after;cursor=start+len(after)
    expected=(out/'candidate'/(name+'.txt')).read_text(encoding='utf-8').splitlines()
    assert result==expected,name
    checked.append(name)
for name, digest in json.loads((out/'baseline.json').read_text()).items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest,name
report={'targets':checked,'v4a_in_memory_apply':'PASS','baseline_readonly':'PASS','production_writes':0}
(out/'patch-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
