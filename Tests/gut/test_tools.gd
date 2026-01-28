extends "res://addons/gut/test.gd"

const Tools = preload("res://Scripts/System/tools.gd")

func test_big_endian_reads() -> void:
	# u16 big endian: 0x1234
	var b := PackedByteArray([0x12, 0x34])
	assert_eq(Tools._read_u16_be(b, 0), 0x1234)
	# s16 big endian: 0xFFFE -> -2
	var b2 := PackedByteArray([0xFF, 0xFE])
	assert_eq(Tools._read_s16_be(b2, 0), -2)
	# u32 big endian: 0x01020304
	var b3 := PackedByteArray([0x01, 0x02, 0x03, 0x04])
	assert_eq(Tools._read_u32_be(b3, 0), 0x01020304)

func test_f32_big_endian_read() -> void:
	# f32 big endian: 1.0 = 0x3F800000
	var b := PackedByteArray([0x3F, 0x80, 0x00, 0x00])
	assert_almost_eq(Tools._read_f32_be(b, 0), 1.0, 0.0001)

func test_bounds_checks_do_not_crash_and_return_defaults() -> void:
	assert_eq(Tools._read_u16_be(PackedByteArray([0x00]), 0), 0)
	assert_eq(Tools._unpack_string(PackedByteArray([0x41]), 0, 5), "")
