## 武器旋转验证：6 把武器排成三排（朝右/朝左/朝上），一张图看完。
extends Node2D

const OUT_DIR := "user://screenshots_weapon_rot"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var ids: Array[StringName] = [&"sword", &"katana", &"big_sword", &"hammer", &"bow", &"wand"]
	var aims: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP]
	var ys: Array[float] = [100.0, 170.0, 240.0]

	for r: int in aims.size():
		for i: int in ids.size():
			var inst: WeaponController = WeaponController.create(DataRegistry.get_weapon(ids[i]), null)
			inst.position = Vector2(100 + i * 40, ys[r])
			inst.set_aim(aims[r])
			add_child(inst)

	var cam: Camera2D = Camera2D.new()
	cam.position = Vector2(200, 170)
	add_child(cam)
	cam.make_current()

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/01_weapons_gallery.png")
	print("[WeaponRot] saved")
	get_tree().quit(0)
