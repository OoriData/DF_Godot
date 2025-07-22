extends Node
var settlement_colors = {
	   "near_impassible": "#0F2227" 
}

var size = Vector2i(24, 24)

func _ready():
	for name in settlement_colors.keys():
		var img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		img.fill(Color(settlement_colors[name]))
		var path = "res://Assets/tiles/" + name + ".png"
		img.save_png(path)
		print("Saved: ", path)
	print("All settlement tiles generated!")
