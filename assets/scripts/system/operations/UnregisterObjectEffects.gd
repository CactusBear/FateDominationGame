class_name UnregisterObjectEffects
extends RefCounted

#把对象上的_effects从效果池拿掉。与RegisterObjectEffects成对，不做替换或改归属。
func exec(object):

	if object == null or !("_effects" in object):
		return
	for effect in object._effects:
		if effect is BaseEffect:
			EffectManager.unregister_effect(effect)
