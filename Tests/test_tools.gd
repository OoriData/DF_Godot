extends RefCounted

const TestUtil = preload("res://Tests/test_util.gd")
const Tools = preload("res://Scripts/System/tools.gd")

func run() -> void:
	# u16 big endian: 0x1234
	var b := PackedByteArray([0x12, 0x34])
	TestUtil.assert_eq(Tools._read_u16_be(b, 0), 0x1234, "u16 be")
	# s16 big endian: 0xFFFE -> -2
	var b2 := PackedByteArray([0xFF, 0xFE])
	TestUtil.assert_eq(Tools._read_s16_be(b2, 0), -2, "s16 be")
	# u32 big endian: 0x01020304
	var b3 := PackedByteArray([0x01, 0x02, 0x03, 0x04])
	TestUtil.assert_eq(Tools._read_u32_be(b3, 0), 0x01020304, "u32 be")
	# f32 big endian: 1.0 = 0x3F800000
	var b4 := PackedByteArray([0x3F, 0x80, 0x00, 0x00])
	TestUtil.assert_approx(Tools._read_f32_be(b4, 0), 1.0, 0.0001, "f32 be")
	# bounds checks should not crash and return 0/""
	TestUtil.assert_eq(Tools._read_u16_be(PackedByteArray([0x00]), 0), 0, "u16 bounds")
	TestUtil.assert_eq(Tools._unpack_string(PackedByteArray([0x41]), 0, 5), "", "string bounds")
