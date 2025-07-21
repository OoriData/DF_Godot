extends Node

var tile_colors = {
	"highway": "#303030",
	"road": "#606060",
	"trail": "#CB8664",
	"desert": "#F6D0B0",
	"plains": "#3F5D4B",
	"forest": "#2C412E",
	"swamp": "#2A4B46",
	"mountains": "#273833",
	"impassable": "#142C55",
	"marked": "#9900FF"
}

var size = Vector2i(24, 24)

func _ready():
	for name in tile_colors.keys():
		var img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		img.fill(Color(tile_colors[name]))
		var path = "res://Assets/tiles/" + name + ".png"
		img.save_png(path)
		print("Saved: ", path)
	print("All tiles generated!")
