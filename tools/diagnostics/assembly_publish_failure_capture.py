"""Capture the owned Godot engine's actual MoveFileW call, never a substitute.

Uses the existing runner Job/path gates and readonly native helper. Only the
same SHA256 engine, PE-verified call RVAs, owned child and local symbols are
accepted. Runtime warm-cache only; no import, retries or publication fallback.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import uuid

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parents[2]
OLD = PROJECT / 'reports/refactoring/round43-integrated-9128e0d5d8bf4625a717e7034b7112ee'
ENGINE_HASH = 'ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424'
SOURCE_HASH = '5dfc05882fb39e5e8bb10ea89ef97d5fc44299d70811cc13eaacaadb2d6a0730'


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def parse_capture(text):
    pending, rows = {}, []
    for line in text.splitlines():
        if line.startswith('API_BEGIN '):
            values = dict(re.findall(r'(\w+)=([^\s]+)', line))
            key = int(values['seq'])
            if key in pending:
                raise ValueError('duplicate API begin')
            pending[key] = {'seq':key, 'tid':int(values['tid']), 'target':values['target']}
        elif line.startswith('API_END '):
            values = dict(re.findall(r'(\w+)=([^\s]+)', line))
            key = int(values['seq'])
            if key not in pending or pending[key]['tid'] != int(values['tid']):
                raise ValueError('unpaired/different-thread API return')
            row = pending.pop(key)
            row.update(return_value=int(values['return']), last_error=int(values['last_error']), teb=values['teb'])
            rows.append(row)
    return rows


def validate_target_pair(source, destination, fixture, label):
    """Validate canonical Win32 directory pairs, not cache files/controls."""
    from pathlib import PureWindowsPath
    # Win32 extended drive namespace is real API syntax, not a repaired token.
    # Validate its drive/containment separately; returned evidence retains bytes.
    values = []
    for value in (source, destination, fixture):
        value = str(value)
        if value.startswith('\\\\?\\'):
            value = value[4:]
        values.append(value.replace('\\', '/'))
    if any('..' in x.split('/') or '.' in x.split('/') for x in values):
        raise ValueError('noncanonical target pair')
    src, dst, root = map(PureWindowsPath, values)
    if any(x.drive.upper() != 'E:' or not x.is_absolute() for x in (src, dst, root)):
        raise ValueError('only physical approved E directory pairs')
    if not src.is_relative_to(root) or not dst.is_relative_to(root):
        raise ValueError('target outside fixture')
    if src.parent != dst.parent or not src.name.startswith(dst.name+'.building-'):
        raise ValueError('not exact assembler staging pair')
    suffix = src.name[len(dst.name+'.building-'):]
    if not suffix.isdecimal():
        raise ValueError('invalid staging suffix')
    if label == 'formal-204':
        valid = dst == root/'formal-data'
    elif label == 'preparation-204':
        valid = dst.name == 'data' and dst.is_relative_to(root/'preparation-work') and dst.parent != root/'preparation-work'
    else:
        valid = False
    if not valid:
        raise ValueError('cache/control/nonformal directory excluded')
    return label


def parse_targeted_capture(text, fixture):
    """Reject sibling rows, incomplete pairs and mismatched return-site/TEB."""
    rows = parse_capture(text)
    begins, paths, ends = {}, {}, {}
    for line in text.splitlines():
        if line.startswith(('API_BEGIN ', 'API_PATH ', 'API_END ')):
            values = dict(re.findall(r'(\w+)=([^\s]+)', line))
            seq = int(values['seq'])
            table = begins if line.startswith('API_BEGIN ') else ends if line.startswith('API_END ') else paths
            if seq in table:
                raise ValueError('duplicate targeted evidence row')
            table[seq] = values
    if not (set(begins) == set(paths) == set(ends) == {x['seq'] for x in rows}):
        raise ValueError('incomplete targeted evidence')
    if len(rows)>2 or len({x['target'] for x in rows})!=len(rows):
        raise ValueError('duplicate/excess targeted directory calls')
    for row in rows:
        begin, end, pair = begins[row['seq']], ends[row['seq']], paths[row['seq']]
        rva = int(begin['rva'], 16)
        if rva not in (0x134851c,0x13486db) or int(end['return_rva'],16)!=rva+6:
            raise ValueError('not exact engine call return instruction')
        if begin['teb']!=end['teb']:
            raise ValueError('not same target-thread TEB')
        validate_target_pair(pair['source'],pair['destination'],fixture,row['target'])
        row.update(source=pair['source'],destination=pair['destination'],call_rva=begin['rva'],
                   return_rva=end['return_rva'],failure_error=row['last_error'] if row['return_value']==0 else None)
    return rows


def engine_binding(engine):
    if digest(engine) != ENGINE_HASH:
        raise ValueError('engine hash is not the original approved runtime')
    data = engine.read_bytes()
    pe = struct.unpack_from('<I', data, 60)[0]
    opt, size = pe + 24, struct.unpack_from('<H', data, pe+20)[0]
    if struct.unpack_from('<H', data, pe+4)[0] != 0x8664:
        raise ValueError('only approved x64 engine')
    count = struct.unpack_from('<H', data, pe+6)[0]
    sections = [struct.unpack_from('<8sIIII', data, opt+size+i*40) for i in range(count)]
    def offset(rva):
        return next(raw+rva-va for _, vs, va, rs, raw in sections if va <= rva < va+max(vs, rs))
    imports = {}
    descriptor = offset(struct.unpack_from('<I', data, opt+120)[0])
    while any(data[descriptor:descriptor+20]):
        il, _, _, _, iat = struct.unpack_from('<IIIII', data, descriptor)
        k = 0
        while (v := struct.unpack_from('<Q', data, offset(il or iat)+k*8)[0]):
            if not v >> 63:
                start = offset(v)+2
                imports[iat+k*8] = data[start:data.index(0,start)].decode()
            k += 1
        descriptor += 20
    calls = []
    for name, _, va, rs, raw in sections:
        if name.rstrip(b'\0') != b'.text':
            continue
        code = data[raw:raw+rs]
        cursor = 0
        while (cursor := code.find(b'\xff\x15', cursor)) >= 0:
            target = va+cursor+6+struct.unpack_from('<i',code,cursor+2)[0]
            if imports.get(target) == 'MoveFileW':
                calls.append(va+cursor)
            cursor += 2
    if calls != [0x134851c, 0x13486db]:
        raise ValueError('MoveFileW IAT callsites do not match reviewed disassembly')
    er, es = struct.unpack_from('<II', data, opt+112+3*8)
    functions = [struct.unpack_from('<III',data,offset(er)+i) for i in range(0,es,12)]
    function = next((a,b,c) for a,b,c in functions if a<=calls[0]<b)
    if function[:2] != (0x13481f0,0x13487fc) or not all(function[0]<=x<function[1] for x in calls):
        raise ValueError('rename callsites have mismatched unwind-function boundary')
    return {'engine_sha256':ENGINE_HASH,'commit':'ed1daf0bf', 'function_rva':'0x13481f0',
            'function_end_rva':'0x13487fc', 'movefile_call_rvas':[hex(x) for x in calls],
            'bytes':{hex(x):data[offset(x):offset(x)+16].hex() for x in [function[0],*calls]},
            'source_sha256':SOURCE_HASH, 'symbols':'raw module/RVA; no guessed nearest export names'}


# Prefix containing module/RVA and StackWalk64 is reused read-only from the
# established local-only debugger. Only this owned capture's wmain is new.
CPP = r'''
#include <bcrypt.h>
#include <algorithm>
#include <cwctype>
#include <fstream>
#include <sstream>
#include <set>

struct BP { unsigned char original; int kind; bool persistent; };
std::map<DWORD64,BP> bp;
std::map<DWORD,DWORD64> rearm;
struct Call { unsigned seq=0; bool called=false; std::wstring src,dst; DWORD64 teb=0; };
std::map<DWORD,Call> calls;
unsigned sequence=0;
HANDLE target_process=nullptr;
std::wstring fixture_root, source_root, gate_root, api_root, expected_source, expected_destination;
std::string expected_label;
std::set<std::wstring> seen_gates;

bool readmem(DWORD64 address,void *value,SIZE_T size) {
    SIZE_T got=0;
    return ReadProcessMemory(target_process,(LPCVOID)address,value,size,&got) && got==size;
}
void must(bool ok,const char *label) { if(!ok){std::printf("CAPTURE_BLOCK %s error=%lu\n",label,GetLastError());std::fflush(stdout);throw std::runtime_error(label);} }
void patch(DWORD64 pc,unsigned char byte) { SIZE_T got=0;must(WriteProcessMemory(target_process,(LPVOID)pc,&byte,1,&got)&&got==1,"owned_breakpoint_write");must(FlushInstructionCache(target_process,(LPVOID)pc,1)!=0,"owned_breakpoint_flush"); }
void arm(DWORD64 pc,int kind,bool persistent) {
    if(bp.count(pc)){must(bp[pc].kind==kind,"overlapping_breakpoint");return;}
    unsigned char byte=0;must(readmem(pc,&byte,1),"owned_breakpoint_read");must(byte!=0xcc,"preexisting_breakpoint");
    bp[pc]={byte,kind,persistent};patch(pc,0xcc);
}
std::wstring normalized(std::wstring p) {
    if(p.rfind(L"\\\\?\\",0)==0)p=p.substr(4);
    std::replace(p.begin(),p.end(),L'/',L'\\');
    std::transform(p.begin(),p.end(),p.begin(),[](wchar_t c){return (wchar_t)towlower(c);});return p;
}
bool inside(const std::wstring &path,const std::wstring &root){auto p=normalized(path),r=normalized(root);return p==r||(p.size()>r.size()&&p.substr(0,r.size())==r&&p[r.size()]==L'\\');}
std::wstring wide(DWORD64 ptr) {
    std::wstring out;
    for(unsigned i=0;i<32768;i++){wchar_t ch=0;must(readmem(ptr+i*2,&ch,2),"MoveFileW_path_read");if(!ch)return out;out.push_back(ch);}
    must(false,"MoveFileW_path_length");return out;
}
std::string utf8(const std::wstring &value) {
    int n=WideCharToMultiByte(CP_UTF8,0,value.data(),(int)value.size(),nullptr,0,nullptr,nullptr);
    std::string text(n,0);WideCharToMultiByte(CP_UTF8,0,value.data(),(int)value.size(),text.data(),n,nullptr,nullptr);return text;
}
void identity(const wchar_t *label,const std::wstring &path) {
    HANDLE file=CreateFileW(path.c_str(),FILE_READ_ATTRIBUTES,7,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
    if(file==INVALID_HANDLE_VALUE){std::printf("IDENTITY label=%ls absent_error=%lu path=%s\n",label,GetLastError(),utf8(path).c_str());return;}
    FILE_ID_INFO id{};FILE_ATTRIBUTE_TAG_INFO tag{};wchar_t name[32768]{};
    bool ok=GetFileInformationByHandleEx(file,FileIdInfo,&id,sizeof(id)) && GetFileInformationByHandleEx(file,FileAttributeTagInfo,&tag,sizeof(tag));
    DWORD len=GetFinalPathNameByHandleW(file,name,32768,0);DWORD error=GetLastError();CloseHandle(file);
    must(ok&&len&&len<32768&&!(tag.FileAttributes&FILE_ATTRIBUTE_REPARSE_POINT),"path_identity");
    must(normalized(name)==normalized(path),"path_identity_physical_mismatch");
    std::printf("IDENTITY label=%ls volume=%llu fileid=",label,id.VolumeSerialNumber);
    for(auto x:id.FileId.Identifier)std::printf("%02x",x);
    std::printf(" attributes=%lu path=%s query_last_error=%lu\n",tag.FileAttributes,utf8(path).c_str(),error);
}
std::wstring parent(const std::wstring &p){return p.substr(0,p.find_last_of(L"\\/"));}
using QueryProcess=LONG(NTAPI*)(HANDLE,ULONG,PVOID,ULONG,PULONG);
using QueryThread=LONG(NTAPI*)(HANDLE,ULONG,PVOID,ULONG,PULONG);
struct HE { HANDLE handle; ULONG_PTR hc,pc; ULONG access,type,attributes,reserved; };
std::vector<HE> handles(HANDLE p) {
    auto query=(QueryProcess)GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"NtQueryInformationProcess");must(query!=nullptr,"query_process_export");
    ULONG size=65536;
    for(int n=0;n<8;n++){std::vector<unsigned char>b(size);ULONG need=0;LONG status=query(p,51,b.data(),size,&need);
        if(!status){SIZE_T count=*(SIZE_T*)b.data();must(2*sizeof(SIZE_T)+count*sizeof(HE)<=size,"owned_handle_count");auto first=(HE*)(b.data()+2*sizeof(SIZE_T));return std::vector<HE>(first,first+count);}
        must(status==(LONG)0xc0000004||status==(LONG)0xc0000023,"owned_process_handle_query");size=std::max(size*2,need+65536);
    }must(false,"owned_handle_query_bound");return {};
}
void snapshot(DWORD pid,unsigned seq,const char *phase) {
    HANDLE sentinel=CreateFileW(fixture_root.c_str(),FILE_READ_ATTRIBUTES,7,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,nullptr);
    must(sentinel!=INVALID_HANDLE_VALUE,"owned_fixture_sentinel");ULONG type=0;
    for(auto e:handles(GetCurrentProcess()))if(e.handle==sentinel)type=e.type;
    CloseHandle(sentinel);must(type!=0,"File_type_index");unsigned match=0,denied=0;
    for(auto e:handles(target_process)){
        if(e.type!=type)continue;HANDLE copy=nullptr;
        if(!DuplicateHandle(target_process,e.handle,GetCurrentProcess(),&copy,0,FALSE,DUPLICATE_SAME_ACCESS)){denied++;std::printf("HANDLE_ERROR seq=%u phase=%s handle=%llu error=%lu\n",seq,phase,(unsigned long long)e.handle,GetLastError());continue;}
        if(GetFileType(copy)==FILE_TYPE_DISK){wchar_t p[32768]{};DWORD len=GetFinalPathNameByHandleW(copy,p,32768,0);
            if(!len||len>=32768){denied++;std::printf("HANDLE_ERROR seq=%u phase=%s path_query_error=%lu\n",seq,phase,GetLastError());}
            else if(inside(p,fixture_root)||inside(p,source_root)){match++;std::printf("OWNED_FILE seq=%u phase=%s pid=%lu handle=%llu access=%lu path=%s\n",seq,phase,pid,(unsigned long long)e.handle,e.access,utf8(p).c_str());}
        }CloseHandle(copy);
    }
    std::printf("HANDLE_SNAPSHOT seq=%u phase=%s pid=%lu matching=%u uninspectable=%u query=ProcessHandleInformation\n",seq,phase,pid,match,denied);must(denied==0,"owned_file_snapshot_incomplete");
}
void stack(HANDLE thread,CONTEXT ctx) {
    STACKFRAME64 f{};f.AddrPC.Offset=ctx.Rip;f.AddrPC.Mode=AddrModeFlat;f.AddrStack.Offset=ctx.Rsp;f.AddrStack.Mode=AddrModeFlat;f.AddrFrame.Offset=ctx.Rbp;f.AddrFrame.Mode=AddrModeFlat;
    std::printf("CALL_FRAME 0 pc=0x%llx",ctx.Rip);address(target_process,ctx.Rip);
    for(int i=1;i<40;i++){if(!StackWalk64(IMAGE_FILE_MACHINE_AMD64,target_process,thread,&f,&ctx,nullptr,SymFunctionTableAccess64,SymGetModuleBase64,nullptr)||!f.AddrPC.Offset)break;std::printf("CALL_FRAME %d pc=0x%llx",i,f.AddrPC.Offset);address(target_process,f.AddrPC.Offset);}
}
DWORD64 teb(HANDLE thread) {
    struct Basic { LONG status; PVOID teb; ULONG_PTR pid,tid,affinity; LONG priority,base; } info{};
    auto query=(QueryThread)GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"NtQueryInformationThread");must(query&&query(thread,0,&info,sizeof(info),nullptr)==0,"owned_thread_TEB");return (DWORD64)info.teb;
}
std::string sha(const std::string &text) {
    BCRYPT_ALG_HANDLE alg=nullptr;BCRYPT_HASH_HANDLE hash=nullptr;ULONG cb=0,size=0;
    must(BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,nullptr,0)==0,"scope_sha_provider");
    must(BCryptGetProperty(alg,BCRYPT_OBJECT_LENGTH,(PUCHAR)&size,sizeof(size),&cb,0)==0,"scope_sha_size");std::vector<unsigned char>object(size);unsigned char output[32]{};
    must(BCryptCreateHash(alg,&hash,object.data(),size,nullptr,0,0)==0&&BCryptHashData(hash,(PUCHAR)text.data(),(ULONG)text.size(),0)==0&&BCryptFinishHash(hash,output,32,0)==0,"scope_sha_hash");BCryptDestroyHash(hash);BCryptCloseAlgorithmProvider(alg,0);
    char value[65]{};for(int i=0;i<32;i++)sprintf_s(value+i*2,3,"%02x",output[i]);return value;
}
std::string jsonpath(const std::wstring &p){auto s=utf8(p);std::string out;for(char x:s){if(x=='\\'||x=='"')out+='\\';out+=x;}return out;}
void receive_gate() {
    if(!calls.empty()||!expected_label.empty())return;
    for(const auto &label:{L"formal-204",L"preparation-204"}) {
        if(seen_gates.count(label))continue;
        std::wstring request=gate_root+L"\\"+label+L".request";
        HANDLE input=CreateFileW(request.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,0,nullptr);
        if(input==INVALID_HANDLE_VALUE){must(GetLastError()==ERROR_FILE_NOT_FOUND||GetLastError()==ERROR_SHARING_VIOLATION,"gate_request_open");continue;}
        char raw[65536]{};DWORD got=0;must(ReadFile(input,raw,sizeof(raw)-1,&got,nullptr)!=0,"gate_request_read");CloseHandle(input);
        // A writer still present denies our read open. After close, read exact UTF8 pair.
        std::string text(raw,got);must(got>0&&got<sizeof(raw)-1,"gate_request_size");
        int length=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),(int)text.size(),nullptr,0);must(length>0,"gate_utf8");
        std::wstring wideText(length,0);MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),(int)text.size(),wideText.data(),length);
        std::wistringstream lines(wideText);std::wstring src,dst,extra;std::getline(lines,src);std::getline(lines,dst);must(!std::getline(lines,extra),"gate_exact_two_paths");
        if(!src.empty()&&src.back()==L'\r')src.pop_back();if(!dst.empty()&&dst.back()==L'\r')dst.pop_back();
        must(inside(src,api_root)&&inside(dst,api_root)&&parent(src)==parent(dst),"gate_fixture_pair");
        auto s=normalized(src),d=normalized(dst);must(s.rfind(d+L".building-",0)==0,"gate_staging_pair");
        auto suffix=s.substr(d.size()+10);must(!suffix.empty()&&std::all_of(suffix.begin(),suffix.end(),[](wchar_t x){return x>=L'0'&&x<=L'9';}),"gate_staging_suffix");
        must(s.find(L"\\..\\")==std::wstring::npos&&d.find(L"\\..\\")==std::wstring::npos,"gate_no_traversal");
        if(std::wstring(label)==L"formal-204")must(d==normalized(api_root+L"\\formal-data"),"gate_exact_formal");
        else must(inside(dst,api_root+L"\\preparation-work")&&d.substr(d.find_last_of(L'\\')+1)==L"data","gate_exact_preparation");
        DWORD attr=GetFileAttributesW(src.c_str());must(attr!=INVALID_FILE_ATTRIBUTES&&(attr&FILE_ATTRIBUTE_DIRECTORY)&&!(attr&FILE_ATTRIBUTE_REPARSE_POINT),"gate_source_directory");
        expected_source=src;expected_destination=dst;expected_label=utf8(label);seen_gates.insert(label);
        for(auto rva:{0x134851cULL,0x13486dbULL})arm(image_base+rva,2,false);
        std::wstring ack=gate_root+L"\\"+label+L".armed";std::ofstream output(ack,std::ios::binary);output<<"armed exact pair";output.close();must(output.good(),"gate_ack");
        std::printf("TARGET_ARM label=%s source=%s destination=%s\n",expected_label.c_str(),utf8(src).c_str(),utf8(dst).c_str());return;
    }
}
int wmain(int argc,wchar_t **argv) {
    if(argc!=12)return 2;
    SetErrorMode(SEM_FAILCRITICALERRORS|SEM_NOGPFAULTERRORBOX);
    HANDLE process=nullptr;PROCESS_INFORMATION pi{};bool exited=false,timedout=false;DWORD code=0;std::map<DWORD,HANDLE>threads;
    try {
        fixture_root=argv[3];source_root=argv[4];gate_root=argv[10];api_root=argv[11];
        must(inside(gate_root,parent(argv[2]))&&inside(api_root,fixture_root),"gate_owned_generated_scope");
        FILETIME ct,et,kt,ut;must(GetProcessTimes(GetCurrentProcess(),&ct,&et,&kt,&ut)!=0,"debugger_creation");
        std::string scope="{\"version\":1,\"run_id\":\""+utf8(argv[6])+"\",\"generated\":\""+jsonpath(parent(argv[2]))+"\",\"fixture_root\":\""+jsonpath(fixture_root)+"\",\"source_root\":\""+jsonpath(source_root)+"\",\"engine\":\""+jsonpath(argv[1])+"\",\"engine_sha256\":\""+utf8(argv[8])+"\",\"owner_pid\":"+std::to_string(GetCurrentProcessId())+",\"owner_creation\":\""+std::to_string(((uint64_t)ct.dwHighDateTime<<32)|ct.dwLowDateTime)+"\",\"helper_sha256\":\""+utf8(argv[7])+"\"}";
        std::ofstream scopefile(argv[5],std::ios::binary);scopefile<<scope;scopefile.close();must(scopefile.good(),"scope_write");
        SetEnvironmentVariableW(L"HERMES_ASSEMBLY_SCOPE",argv[5]);SetEnvironmentVariableW(L"HERMES_ASSEMBLY_TOKEN",argv[6]);std::string hex=sha(scope);std::wstring wh(hex.begin(),hex.end());SetEnvironmentVariableW(L"HERMES_ASSEMBLY_SCOPE_SHA256",wh.c_str());
        // Validate x64 TEB.LastErrorValue layout against this actual OS thread.
        SetLastError(0x4321);DWORD selfError=*(DWORD*)((unsigned char*)NtCurrentTeb()+0x68);must(selfError==0x4321,"TEB_LastErrorValue_layout");
        std::wstring cmd=L"\""+std::wstring(argv[1])+L"\" --headless --fixed-fps 60 --path \""+argv[2]+L"\" --scene res://tests/round47_assembly_targeted_capture_test.tscn -- \""+fixture_root+L"\"";
        std::vector<wchar_t>writable(cmd.begin(),cmd.end());writable.push_back(0);STARTUPINFOW start{};start.cb=sizeof(start);start.dwFlags=STARTF_USESTDHANDLES;start.hStdOutput=GetStdHandle(STD_OUTPUT_HANDLE);start.hStdError=GetStdHandle(STD_ERROR_HANDLE);start.hStdInput=GetStdHandle(STD_INPUT_HANDLE);
        must(CreateProcessW(argv[1],writable.data(),nullptr,nullptr,TRUE,DEBUG_ONLY_THIS_PROCESS|CREATE_NO_WINDOW,nullptr,argv[2],&start,&pi)!=0,"create_owned_engine");process=target_process=pi.hProcess;
        BOOL in_job=FALSE;must(IsProcessInJob(process,nullptr,&in_job)&&in_job,"owned_engine_inherited_job");
        must(GetProcessTimes(process,&ct,&et,&kt,&ut)!=0,"engine_creation");std::printf("OWNED_ENGINE pid=%lu parent=%lu creation=%llu in_job=%d command=%s\n",pi.dwProcessId,GetCurrentProcessId(),((uint64_t)ct.dwHighDateTime<<32)|ct.dwLowDateTime,in_job,utf8(cmd).c_str());
        SymSetOptions(SYMOPT_DEFERRED_LOADS|SYMOPT_FAIL_CRITICAL_ERRORS|SYMOPT_NO_PROMPTS);must(SymInitializeW(process,L".",FALSE)!=0,"local_symbol_init");
        ULONGLONG until=GetTickCount64()+180000;
        while(!exited){
            if(image_base&&!timedout)receive_gate();
            if(GetTickCount64()>until&&!timedout){std::printf("TIMEOUT owned_pid=%lu\n",pi.dwProcessId);TerminateProcess(process,125);timedout=true;}
            DEBUG_EVENT ev{};if(!WaitForDebugEvent(&ev,100)){must(GetLastError()==ERROR_SEM_TIMEOUT,"wait_debug_event");if(timedout&&WaitForSingleObject(process,0)==WAIT_OBJECT_0)break;continue;}
            must(ev.dwProcessId==pi.dwProcessId,"foreign_debug_event");DWORD status=DBG_CONTINUE;
            switch(ev.dwDebugEventCode){
            case CREATE_PROCESS_DEBUG_EVENT:{
                threads[ev.dwThreadId]=ev.u.CreateProcessInfo.hThread;image_base=(DWORD64)ev.u.CreateProcessInfo.lpBaseOfImage;
                module(process,ev.u.CreateProcessInfo.hFile,image_base);if(ev.u.CreateProcessInfo.hFile)CloseHandle(ev.u.CreateProcessInfo.hFile);if(ev.u.CreateProcessInfo.hProcess!=process)CloseHandle(ev.u.CreateProcessInfo.hProcess);
                unsigned char entry=0;must(readmem(image_base+0x13481f0,&entry,1)&&entry==0x41,"engine_entry_bytes");
                const unsigned char reviewed[2][6]={{0xff,0x15,0xb6,0x70,0xa3,0x09},{0xff,0x15,0xf7,0x6e,0xa3,0x09}};unsigned reviewedIndex=0;
                for(auto rva:{0x134851cULL,0x13486dbULL}){unsigned char bytes[6]{};must(readmem(image_base+rva,bytes,6)&&std::equal(bytes,bytes+6,reviewed[reviewedIndex++]),"engine_IAT_call_bytes");}
                // No permanent entry/callsite breakpoints: cache renames run untouched.
                break;}
            case CREATE_THREAD_DEBUG_EVENT:threads[ev.dwThreadId]=ev.u.CreateThread.hThread;break;
            case EXIT_THREAD_DEBUG_EVENT:if(threads.count(ev.dwThreadId)){if(threads[ev.dwThreadId]==pi.hThread)pi.hThread=nullptr;CloseHandle(threads[ev.dwThreadId]);threads.erase(ev.dwThreadId);}break;
            case LOAD_DLL_DEBUG_EVENT:module(process,ev.u.LoadDll.hFile,(DWORD64)ev.u.LoadDll.lpBaseOfDll);if(ev.u.LoadDll.hFile)CloseHandle(ev.u.LoadDll.hFile);break;
            case UNLOAD_DLL_DEBUG_EVENT:SymUnloadModule64(process,(DWORD64)ev.u.UnloadDll.lpBaseOfDll);modules.erase((DWORD64)ev.u.UnloadDll.lpBaseOfDll);break;
            case EXCEPTION_DEBUG_EVENT:{
                DWORD exceptionCode=ev.u.Exception.ExceptionRecord.ExceptionCode;DWORD64 pc=(DWORD64)ev.u.Exception.ExceptionRecord.ExceptionAddress;
                if(exceptionCode==EXCEPTION_SINGLE_STEP&&rearm.count(ev.dwThreadId)){
                    DWORD64 address=rearm[ev.dwThreadId];patch(address,0xcc);rearm.erase(ev.dwThreadId);CONTEXT context{};context.ContextFlags=CONTEXT_ALL;must(GetThreadContext(threads[ev.dwThreadId],&context)!=0,"step_context");context.EFlags&=~0x100;must(SetThreadContext(threads[ev.dwThreadId],&context)!=0,"step_context_clear");break;
                }
                if(exceptionCode==EXCEPTION_BREAKPOINT&&bp.count(pc)){
                    bool preserveFailure=false;BP b=bp[pc];patch(pc,b.original);CONTEXT context{};context.ContextFlags=CONTEXT_ALL;must(GetThreadContext(threads[ev.dwThreadId],&context)!=0,"break_context");context.Rip=pc;
                    if(b.kind==2){must(!expected_label.empty()&&calls.empty(),"API_exact_gate_required");Call call;call.seq=++sequence;must(sequence<=2,"only_two_formal_directory_calls");call.src=wide(context.Rcx);call.dst=wide(context.Rdx);
                        must(normalized(call.src)==normalized(expected_source)&&normalized(call.dst)==normalized(expected_destination),"API_exact_source_destination");
                        call.called=true;call.teb=teb(threads[ev.dwThreadId]);calls[ev.dwThreadId]=call;arm(pc+6,3,false);
                        for(auto rva:{0x134851cULL,0x13486dbULL}){auto other=image_base+rva;if(other!=pc&&bp.count(other)){patch(other,bp[other].original);bp.erase(other);}}
                        std::printf("API_BEGIN seq=%u tid=%lu target=%s rva=0x%llx rcx=0x%llx rdx=0x%llx teb=0x%llx\n",call.seq,ev.dwThreadId,expected_label.c_str(),pc-image_base,context.Rcx,context.Rdx,call.teb);
                        std::printf("API_PATH seq=%u source=%s destination=%s\n",call.seq,utf8(call.src).c_str(),utf8(call.dst).c_str());identity(L"source-before",call.src);identity(L"destination-before",call.dst);identity(L"parent-before",parent(call.dst));
                    }else if(b.kind==3){must(calls.count(ev.dwThreadId)!=0,"API_return_without_entry");auto &call=calls[ev.dwThreadId];DWORD lastError=0;must(readmem(call.teb+0x68,&lastError,4),"same_thread_LastErrorValue");
                        std::printf("API_END seq=%u tid=%lu return=%lu last_error=%lu teb=0x%llx return_rva=0x%llx\n",call.seq,ev.dwThreadId,(DWORD)context.Rax,lastError,call.teb,pc-image_base);
                        if(!(DWORD)context.Rax)snapshot(pi.dwProcessId,call.seq,"failed-return");
                        identity(L"source-after",call.src);identity(L"destination-after",call.dst);identity(L"parent-after",parent(call.dst));
                        if(!(DWORD)context.Rax){stack(threads[ev.dwThreadId],context);std::printf("CAPTURE_FORMAL_FAILURE seq=%u label=%s preserved_before_runtime_cleanup=1\n",call.seq,expected_label.c_str());std::fflush(stdout);preserveFailure=true;}
                        calls.erase(ev.dwThreadId);expected_label.clear();
                    }else must(false,"unexpected_breakpoint_kind");
                    if(b.persistent){context.EFlags|=0x100;rearm[ev.dwThreadId]=pc;}else bp.erase(pc);
                    must(SetThreadContext(threads[ev.dwThreadId],&context)!=0,"break_restore_context");
                    if(preserveFailure)must(TerminateProcess(process,124)!=0,"preserve_failed_owned_engine");break;
                }
                if(exceptionCode==EXCEPTION_BREAKPOINT&&ev.u.Exception.dwFirstChance)break;
                status=DBG_EXCEPTION_NOT_HANDLED;
                if(!ev.u.Exception.dwFirstChance){std::printf("SECOND_CHANCE code=0x%lx tid=%lu\n",exceptionCode,ev.dwThreadId);exception(process,threads[ev.dwThreadId],ev);}break;}
            case EXIT_PROCESS_DEBUG_EVENT:code=ev.u.ExitProcess.dwExitCode;exited=true;std::printf("ENGINE_EXIT pid=%lu code=%lu timedout=%d\n",pi.dwProcessId,code,timedout);break;
            }
            std::fflush(stdout);must(ContinueDebugEvent(ev.dwProcessId,ev.dwThreadId,status)!=0,"continue_owned_debug_event");
        }
        WaitForSingleObject(process,10000);SymCleanup(process);
    }catch(const std::exception &e){std::printf("CAPTURE_BLOCK exception=%s\n",e.what());if(process){TerminateProcess(process,126);WaitForSingleObject(process,10000);}code=126;}
    for(auto t:threads){if(t.second==pi.hThread)pi.hThread=nullptr;CloseHandle(t.second);}if(pi.hThread)CloseHandle(pi.hThread);if(process)CloseHandle(process);
    std::printf("DEBUGGER_EXIT engine_exited=%d engine_code=%lu timedout=%d\n",exited,code,timedout);return timedout?125:code?1:0;
}
'''


def compile_owned(runner, command, env, generated, evidence, records):
    """Compiler roots may leave their own persistent compiler service in Job.

    Observe the actual root exit, enumerate only this held Job's PIDs, then stop
    its remaining descendants. Runtime Godot still uses full-tree execute.
    """
    import ctypes
    from ctypes import wintypes as w
    import time
    out, err = evidence/'build.stdout.log', evidence/'build.stderr.log'
    job = runner.OwnedJob()
    record = {'label':'build','command':command,'exited':False}
    records.append(record)
    start=time.monotonic()
    proc=None
    try:
        with out.open('wb') as stdout, err.open('wb') as stderr:
            proc=subprocess.Popen(command,env=env,cwd=generated,stdout=stdout,stderr=stderr,creationflags=4)
            record['pid']=proc.pid
            job.attach_resume(proc)
            try:
                code=proc.wait(timeout=180)
                record['root_exit_before_descendant_cleanup']=code
            except subprocess.TimeoutExpired:
                record['budget_failure']='compile_root_timeout'
                raise
            finally:
                buf=ctypes.create_string_buffer(8+8*128)
                if job.kernel.QueryInformationJobObject(job.handle,3,buf,len(buf),None):
                    count=struct.unpack_from('<I',buf.raw,4)[0]
                    if count>128:raise ValueError('owned Job PID bound exceeded')
                    pids=[struct.unpack_from('<Q',buf.raw,8+i*8)[0] for i in range(count)]
                    native=load_module('build_native_identity',PROJECT/'tools/diagnostics/assembly_native_probe.py')
                    record['owned_job_members_before_cleanup']=[native.process_identity(pid) for pid in pids]
                else:
                    raise ctypes.WinError(ctypes.get_last_error())
                if job.active():job.stop()
                record.update(exit_code=proc.wait(timeout=15),active_owned_processes=job.active(),
                              exited=job.active()==0,duration_seconds=round(time.monotonic()-start,3))
        job.wait_log_release([out,err]);record['log_handles_released']=True
        return out.read_text(encoding='utf-8',errors='replace'),err.read_text(encoding='utf-8',errors='replace'),code
    finally:
        if job.active():job.stop()
        if proc is not None and proc.poll() is None:proc.kill();proc.wait(timeout=15)
        job.close()


def reparse_owned_evidence(path):
    """Offline parse correction; do not rerun or rewrite original manifest."""
    runner = load_module('round47_reparse_runner',PROJECT/'tools/run_isolated_godot_test.py')
    evidence = runner.physical_e(path)
    if evidence.name!='evidence' or not re.fullmatch(r'isolated-[0-9a-f]{32}',evidence.parent.name):
        raise ValueError('not an owned isolated evidence root')
    original = json.loads((evidence/'capture-manifest.json').read_text(encoding='utf-8'))
    if evidence.parent.name!='isolated-'+original['run_id']:
        raise ValueError('evidence ownership token mismatch')
    for name, expected in original['artifact_hashes'].items():
        file = runner.contained(evidence/name,evidence)
        if digest(file)!=expected:raise ValueError('original artifact hash mismatch: '+name)
    stdout = evidence/'original-assembly66.stdout.log'
    stderr = evidence/'original-assembly66.stderr.log'
    out, err = stdout.read_text(encoding='utf-8',errors='strict'),stderr.read_text(encoding='utf-8',errors='strict')
    runtime = [x for x in original['processes'] if x['label']=='original-assembly66']
    if len(runtime)!=1 or not runtime[0]['exited'] or runtime[0]['active_owned_processes']!=0:
        raise ValueError('missing exited owned runtime Job receipt')
    report = {'run_id':original['run_id'],'original_manifest_sha256':digest(evidence/'capture-manifest.json'),
              'parser_only':True,'godot_reexecuted':False,'parser_sha256':digest(Path(__file__)),
              'stdout_sha256':digest(stdout),'stderr_sha256':digest(stderr),
              'processes':original['processes'],'generated_exists':Path(original['generated']).exists(),
              'source_delta_vs_round43':original['preflight']['declared_current_source_delta'],
              'actual_argv_checked':original['actual_argv_checked'],'command':original['command']}
    report['api_calls']=parse_targeted_capture(out,original['actual_prelaunch_roots']['candidate'])
    report['analysis']=runner.analyze(out,err,runtime[0]['exit_code'])
    report['check_events']=len([x for x in out.splitlines() if x.startswith('CHECK ')])
    raw_manifest = (OLD/'native-input/reconstructed-manifest.raw.json').read_bytes()
    if hashlib.sha256(raw_manifest).hexdigest()!=original['original_manifest_sha256']:
        raise ValueError('original input hash mismatch')
    plans=[x.split(' ',1)[1] for x in out.splitlines() if x.startswith('ASSEMBLY_RECONSTRUCTED_MANIFEST ')]
    report['original_manifest_equal']=len(plans)==1 and plans[0].encode('utf-8')==raw_manifest
    report['source_drift_after']=[x['path'] for x in original['source_files'] if digest(PROJECT/x['path'])!=x['sha256']]
    report['blocks']=[x for x in (out+'\n'+err).splitlines() if 'CAPTURE_BLOCK' in x or 'SCRIPT ERROR' in x or x.startswith(('ERROR:','SECOND_CHANCE'))]
    report['formal_failure_captured']=any(x['return_value']==0 for x in report['api_calls'])
    report['root_cause']='UNKNOWN; historical formal204/preparation failure not reproduced'
    report['passed']=report['analysis']['passed'] and report['check_events']==66 and report['analysis']['result']['checks']==66 and [x['target'] for x in report['api_calls']]==['formal-204','preparation-204'] and report['original_manifest_equal'] and not report['source_drift_after'] and not report['blocks']
    report['raw_focused_lines']=[x for x in out.splitlines() if x.startswith(('API_','IDENTITY ','TARGET_','ENGINE_EXIT ','DEBUGGER_EXIT ','ASSEMBLY_FORMAL_PUBLICATION ','ASSEMBLY_PREPARATION_RESULT ','RESULT '))]
    destination = evidence/'reparse-manifest.json'
    if destination.exists():raise ValueError('keep previous offline parse artifact')
    text=json.dumps(report,ensure_ascii=False,indent=2)
    destination.write_text(text,encoding='utf-8')
    if destination.read_text(encoding='utf-8')!=text:raise ValueError('reparse report readback mismatch')
    print(json.dumps(report,ensure_ascii=False,indent=2));return 0 if report['passed'] else 2


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute',action='store_true')
    parser.add_argument('--preflight',action='store_true')
    parser.add_argument('--reparse',type=Path)
    args = parser.parse_args()
    if sum((args.execute,args.preflight,args.reparse is not None))!=1:
        parser.error('exactly one of --execute, --preflight, --reparse required')
    if args.reparse is not None:
        return reparse_owned_evidence(args.reparse)
    if os.name != 'nt':
        raise ValueError('Windows owned debugger required')
    runner = load_module('round47_runner',PROJECT/'tools/run_isolated_godot_test.py')
    engine = Path('D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe')
    runner.no_links(engine)
    binding = engine_binding(engine)
    source = Path('E:/scratch/round38-assembly-owner/dir_access_windows-official.cpp')
    if digest(source) != SOURCE_HASH:
        raise ValueError('exact reviewed Windows rename source missing/different')
    history = json.loads((OLD/'reparsed-manifest.json').read_text())
    drift = [x['path'] for x in history['source_files'] if digest(PROJECT/x['path']) != x['sha256']]
    # Current frozen candidate, original unmodified assembly66 test and input.
    # Explicit known Round46/current config delta; never claim original freeze.
    declared_delta = {'assets/config/server.cfg', 'scripts/net/validation/room_data_preparation.gd',
                      'scripts/net/validation/room_data_validation_worker.gd',
                      'scripts/net/validation/room_validation_task.gd',
                      'scripts/net/validation/rule_random_simulation.gd'}
    if set(drift)-declared_delta:
        raise ValueError('undeclared source drift: '+str(set(drift)-declared_delta))
    frozen = [{'path':x['path'],'sha256':digest(PROJECT/x['path'])} for x in history['source_files']]
    if digest(OLD/'native-input/reconstructed-manifest.raw.json') != '98469b47c4526f17a50633b3279567d17339fa61ed3895954e7ba9b3de58d568':
        raise ValueError('original input bytes mismatch')
    if digest(PROJECT/'tests/assembly_publish_lifecycle_test.gd') != 'df499eff188d781c57b90a5ded679b9c0cc732f7ace9d8ca87e0cb607c14792b':
        raise ValueError('original assembly66 scenario changed')
    preflight = {'engine_binding':binding,'physical_root':str(runner.physical_e('E:/scratch')),
                 'original_manifest_sha256':digest(OLD/'native-input/reconstructed-manifest.raw.json'),
                 'original_test_sha256':digest(PROJECT/'tests/assembly_publish_lifecycle_test.gd'),
                 'declared_current_source_delta':[{**x,'original_sha256':next(r['sha256'] for r in history['source_files'] if r['path']==x['path'])} for x in frozen if x['path'] in drift],
                 'argv_contract':['owned generated/Godot.exe','--headless','--fixed-fps','60','--path','owned generated/project','--scene','res://tests/round47_assembly_targeted_capture_test.tscn','--','owned generated/f/complete-0'],
                 'suite_inheritance':'unmodified assembly_publish_lifecycle_test, required_checks=66',
                 'maximum_runtime_seconds':180,'formal_scenarios_this_invocation':1,'retry':False}
    if args.preflight:
        print(json.dumps(preflight,ensure_ascii=False,indent=2));return 0
    token = uuid.uuid4().hex
    owner = runner.physical_e('E:/scratch')/('isolated-'+token)
    owner.mkdir()
    generated, evidence = owner/'generated',owner/'evidence'
    generated.mkdir(); evidence.mkdir()
    report = {'run_id':token,'generated':str(generated),'binding':binding,'preflight':preflight,'source_drift_before':drift,'processes':[],
              'debugger_schedule_changed':True,'runtime_import_requested':False,'passed':False}
    def save():
        text = json.dumps(report,ensure_ascii=False,indent=2)
        (evidence/'capture-manifest.json').write_text(text,encoding='utf-8')
        (owner/'manifest.json').write_text(text,encoding='utf-8')
    print('ROUND47_EVIDENCE '+str(evidence),flush=True)
    try:
        project = generated/'project';project.mkdir()
        for row in frozen:
            src=runner.contained(PROJECT/row['path'],PROJECT)
            dst=project/row['path'];dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
        # Reuse already imported cache; no --editor/--import/cold native cycle.
        cache_files=[]
        for rel in ['.godot/global_script_class_cache.cfg','.godot/uid_cache.bin','.godot/extension_list.cfg']:
            p=runner.contained(PROJECT/rel,PROJECT)
            dst=project/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst);cache_files.append({'path':rel,'sha256':digest(p)})
        imported=PROJECT/'.godot/imported'
        for p in imported.rglob('*'):
            runner.no_links(p)
            if p.is_file():
                rel=p.relative_to(PROJECT);dst=project/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dst);cache_files.append({'path':str(rel),'sha256':digest(p)})
        for name in ['round47_assembly_targeted_capture_test.gd','round47_assembly_targeted_capture_test.tscn']:
            shutil.copy2(PROJECT/'tests'/name,project/'tests'/name)
        # Exact previously authorized frozen config, not a new production edit.
        old_config=OLD/'evidence/failed-source/complete-assembly_publish_lifecycle_test/project.godot'
        shutil.copy2(old_config,project/'project.godot')
        shutil.copy2(engine,generated/'Godot.exe')
        helper=generated/'assembly_native_probe.py';shutil.copy2(PROJECT/'tools/diagnostics/assembly_native_probe.py',helper)
        manifest=generated/'original-manifest.json';shutil.copy2(OLD/'native-input/reconstructed-manifest.raw.json',manifest)
        shutil.copy2(source,evidence/'dir_access_windows.cpp')
        shutil.copy2(Path(__file__),evidence/'assembly_publish_failure_capture.py')
        report.update(source_files=frozen,warm_cache=cache_files,
                      diagnostic_files=[{'path':str(p.relative_to(PROJECT)),'sha256':digest(p)} for p in [Path(__file__),PROJECT/'tests/round47_assembly_targeted_capture_test.gd',PROJECT/'tests/round47_assembly_targeted_capture_test.tscn']],
                      original_manifest_sha256=digest(manifest),frozen_config_sha256=digest(project/'project.godot'))
        old_debug=load_module('round44_debug_readonly',PROJECT/'tools/diagnostics/native_cold_import_debug.py')
        prefix=old_debug.DEBUGGER_CPP.split('int wmain(',1)[0]
        cpp=generated/'capture.cpp';cpp.write_text(prefix+CPP,encoding='utf-8');shutil.copy2(cpp,evidence/'capture.cpp')
        build=generated/'build.cmd';build.write_text(f'@call "D:/VS2022/Common7/Tools/VsDevCmd.bat" -arch=x64 -host_arch=x64\n@cl /nologo /EHsc /std:c++17 /W4 "{cpp}" /Fe:"{generated / "capture.exe"}" /Fo:"{generated / "capture.obj"}" /link dbghelp.lib bcrypt.lib\n',encoding='utf-8')
        env=os.environ.copy();env['_NO_DEBUG_HEAP']='1';env['HERMES_ASSEMBLY_PROBE']=str(helper);env['HERMES_ASSEMBLY_PYTHON']=sys.executable
        fixture=generated/'f/complete-0';fixture.mkdir(parents=True)
        for key in ['APPDATA','LOCALAPPDATA','TEMP','TMP','TMPDIR']:
            directory=fixture/key.lower();directory.mkdir();env[key]=str(directory)
        approved=fixture/'localappdata/hermes/cache/scratch'
        approved.mkdir(parents=True)
        env['HERMES_RECOVERY_VALIDATION_ROOT']=(approved/('assembly-'+token)).as_posix()
        gate=generated/'gates';gate.mkdir();env['HERMES_ASSEMBLY_CAPTURE_GATE']=gate.as_posix()
        # Compilation and debugger live in the same held ownership Job. Original
        # helper validates debugger PID/time as direct Godot parent without relax.
        out,err,code=compile_owned(runner,['cmd.exe','/d','/c',str(build)],env,generated,evidence,report['processes'])
        if code:
            report['blocked']='debugger compilation failed';save();return 2
        shutil.copy2(generated/'capture.exe',evidence/'capture.exe')
        scope=generated/'scope.json'
        command=[str(generated/'capture.exe'),str(generated/'Godot.exe'),str(project),str(fixture),str(project/'data'),str(scope),token,digest(helper),ENGINE_HASH,'180000',str(gate),env['HERMES_RECOVERY_VALIDATION_ROOT']]
        # Static actual-root/argv validation BEFORE creating the Godot PID.
        runner.physical_e(approved);runner.contained(gate,generated);runner.contained(fixture,generated)
        candidate=Path(env['HERMES_RECOVERY_VALIDATION_ROOT']);runner.no_links(candidate)
        if candidate.exists() or candidate.parent!=approved or not candidate.is_relative_to(fixture):
            raise ValueError('approved candidate already present/outside scope')
        for row in frozen:
            if digest(project/row['path'])!=row['sha256'] and row['path']!='project.godot':
                raise ValueError('freeze copy mismatch: '+row['path'])
        if digest(generated/'Godot.exe')!=ENGINE_HASH:raise ValueError('frozen engine mismatch')
        report.update(command=command,actual_prelaunch_roots={'approved':approved.as_posix(),'candidate':candidate.as_posix(),'fixture':fixture.as_posix(),'gate':gate.as_posix()},actual_argv_checked=True)
        save()
        out,err,code=runner.execute(command,env,generated,evidence,'original-assembly66',{'seconds':180,'bytes':3*1024**3,'min_free':1024**3},report['processes'])
        report['api_calls']=parse_targeted_capture(out,env['HERMES_RECOVERY_VALIDATION_ROOT'])
        report['godot_result']=[s for s in out.splitlines() if s.startswith('RESULT ') or s.startswith('ASSEMBLY_FORMAL_PUBLICATION ') or s.startswith('ASSEMBLY_PREPARATION_RESULT ')]
        report['engine_exit']=[s for s in out.splitlines() if s.startswith('ENGINE_EXIT ') or s.startswith('DEBUGGER_EXIT ')]
        report['capture_blocks']=[s for s in out.splitlines()+err.splitlines() if 'CAPTURE_BLOCK' in s or 'SCRIPT ERROR' in s or s.startswith('ERROR:') or s.startswith('SECOND_CHANCE')]
        report['exact_formal_captured']=[x['target'] for x in report['api_calls']]==['formal-204','preparation-204']
        report['analysis']=runner.analyze(out,err,code)
        report['check_events']=len([s for s in out.splitlines() if s.startswith('CHECK ')])
        manifest_lines=[s.split(' ',1)[1] for s in out.splitlines() if s.startswith('ASSEMBLY_RECONSTRUCTED_MANIFEST ')]
        report['original_manifest_equal']=len(manifest_lines)==1 and manifest_lines[0].encode('utf-8')==manifest.read_bytes()
        report['source_drift_after']=[x['path'] for x in frozen if digest(PROJECT/x['path'])!=x['sha256']]
        report['formal_failure_captured']=any(x['return_value']==0 for x in report['api_calls'])
        report['passed']=report['exact_formal_captured'] and not report['capture_blocks'] and report['analysis']['passed'] and report['analysis']['result']['checks']==66 and report['check_events']==66 and report['original_manifest_equal'] and not report['source_drift_after']
        report['root_cause']='UNKNOWN; no historical failure reproduced' if not report['formal_failure_captured'] else 'real formal failure captured; examine owned handles, no automatic attribution'
        if scope.exists():shutil.copy2(scope,evidence/'scope.json')
        if (generated/'native-audit').exists():shutil.copytree(generated/'native-audit',evidence/'native-audit')
        shutil.copytree(gate,evidence/'gates')
        if report['formal_failure_captured']:
            runner.tree_bytes(fixture)
            shutil.copytree(fixture,evidence/'failure-original-fixture')
            runner.tree_bytes(project/'data')
            shutil.copytree(project/'data',evidence/'failure-original-source')
            report['failure_originals_preserved']=True
        return 0 if report['passed'] else 2
    except Exception as exc:
        report['blocked']=str(exc);raise
    finally:
        # Archive BEFORE parsing can erase optional raw audit/ownership records.
        # This executes even if a parser rejects an otherwise completed scene.
        for name in ['scope.json','assembly_native_probe.py','original-manifest.json','build.cmd']:
            src=generated/name
            if src.exists() and not (evidence/name).exists():
                runner.contained(src,generated);shutil.copy2(src,evidence/name)
        for name in ['native-audit','gates']:
            src=generated/name
            if src.exists() and not (evidence/name).exists():
                runner.tree_bytes(src);shutil.copytree(src,evidence/name)
        if (generated/'project').exists():
            for rel in ['project.godot','tests/assembly_publish_lifecycle_test.gd',
                        'tests/assembly_publish_lifecycle_test.tscn',
                        'tests/round47_assembly_targeted_capture_test.gd',
                        'tests/round47_assembly_targeted_capture_test.tscn']:
                src=generated/'project'/rel;dst=evidence/'executed-source'/rel
                if src.exists() and not dst.exists():
                    runner.contained(src,generated);dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
        # Archive all remaining owned output before recycling, including blocked runs.
        if (generated/'f').exists() and not (evidence/'owned-runtime').exists():
            runner.tree_bytes(generated/'f');shutil.copytree(generated/'f',evidence/'owned-runtime')
        report['artifact_hashes']={str(p.relative_to(evidence)):digest(p) for p in evidence.rglob('*') if p.is_file() and p.name!='capture-manifest.json'}
        save()
        # Evidence readback before deletion; no native/production source writes.
        for name,expected in report['artifact_hashes'].items():
            if digest(evidence/name)!=expected:raise ValueError('artifact readback mismatch')
        report['deleted_generated_bytes']=runner.tree_bytes(generated)
        runner.delete_owned(generated,owner)
        report['generated_exists_after_cleanup']=generated.exists()
        save()
        print(json.dumps({k:report.get(k) for k in ['run_id','passed','blocked','api_calls','engine_exit','capture_blocks','original_manifest_equal','deleted_generated_bytes','generated_exists_after_cleanup']},ensure_ascii=False,indent=2))


if __name__=='__main__':
    raise SystemExit(run())
