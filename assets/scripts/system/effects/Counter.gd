class_name Counter
extends RefCounted

#反制。countered_func留空时整个效果不结算；
#否则只跳过效果里的那一个func，其余func照常结算
func exec(effect:BaseEffect, countered_func:BaseFunc = null):

	EffectManager.counter_effect(effect, countered_func)




#判断
