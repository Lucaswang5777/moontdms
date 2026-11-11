///|
test "endian integers signed extension and strict hex" {
  let lim = Limits::default()
  for big in [false, true] {
    let w = Writer::new(big, lim)
    w.uint(0xfedcba9876543210UL, 8)
    w.uint(65535UL, 2)
    w.string("测量 α")
    let b = w.finish()
    let r = Reader::new(b, 0, b.length(), big, lim)
    assert_eq(r.uint(8), 0xfedcba9876543210UL)
    assert_eq(r.signed(2), -1L)
    assert_eq(r.string(), "测量 α")
    assert_eq(r.pos, r.end)
    assert_eq(decode_hex(encode_hex(b)), b)
  }
}
