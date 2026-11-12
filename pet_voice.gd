extends RefCounted

enum Cue { GREET, WHEEL, LIFT, DROP, FOOD, WATER, BEDDING }

# 顺序对应 Care.NAMES。把台词和音频放在一起，字幕与配音同步更新。
const LINES := [
	{
		Cue.GREET: ["川川，我是肥嘟嘟！", preload("res://assets/voices/huihui-greet.wav")],
		Cue.WHEEL: ["看我跑得多快！", preload("res://assets/voices/huihui-wheel.wav")],
		Cue.LIFT: ["嘿，我飞起来了！", preload("res://assets/voices/huihui-lift.wav")],
		Cue.DROP: ["稳稳落地！", preload("res://assets/voices/huihui-drop.wav")],
		Cue.FOOD: ["川川，开饭啦！", preload("res://assets/voices/huihui-food.wav")],
		Cue.WATER: ["有水喝啦，谢谢！", preload("res://assets/voices/huihui-water.wav")],
		Cue.BEDDING: ["新垫料真软！", preload("res://assets/voices/huihui-bedding.wav")],
	},
	{
		Cue.GREET: ["川川，你好呀，我是好可爱！", preload("res://assets/voices/baibai-greet.wav")],
		Cue.WHEEL: ["我在跑滚轮呢！", preload("res://assets/voices/baibai-wheel.wav")],
		Cue.LIFT: ["被抱起来啦！", preload("res://assets/voices/baibai-lift.wav")],
		Cue.DROP: ["我回来了！", preload("res://assets/voices/baibai-drop.wav")],
		Cue.FOOD: ["有好吃的啦！", preload("res://assets/voices/baibai-food.wav")],
		Cue.WATER: ["川川，谢谢你给我换水！", preload("res://assets/voices/baibai-water.wav")],
		Cue.BEDDING: ["好软呀，谢谢你！", preload("res://assets/voices/baibai-bedding.wav")],
	},
]
