extends RefCounted

## 原 bootstrap 与可信 status 共同使用的显式最低方法合同；不是授权或 ABI 完备证明。
## 新增原生接口不自动进入此合同；此脚本只声明数据，不查询或创建原生对象。
const REQUIRED_METHODS:Dictionary = {
	"FateServerSignals":["enable","protect_worker","disable","take_request"],
	"FateProcessOwner":["available","spawn","state","verify","terminate","release"],
	"FateAtomicFileReplace":["replace_validated_file"],
	"FateCollectionIdentity":["is_supported","candidate_key"]
}
