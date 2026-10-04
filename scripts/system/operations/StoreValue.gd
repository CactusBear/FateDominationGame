class_name StoreValue
extends RefCounted

#透传第一个参数，供foreach/for循环体把当前遍历元素存进self_var，
#这样后续func可以在任意参数位置用self_var引用它，而不必都挤在parameter_index那一格。
func exec(value):
	return value
