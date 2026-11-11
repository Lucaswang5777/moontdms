///|
test "property scalar exactness on both endians" {
  let cases : Array[(DataType, Value)] = [
    (I8, Signed(-128L)),
    (I16, Signed(-30000L)),
    (I32, Signed(-2147483648L)),
    (I64, Signed(-9223372036854775808L)),
    (U8, Unsigned(255UL)),
    (U16, Unsigned(65535UL)),
    (U32, Unsigned(4294967295UL)),
    (U64, Unsigned(18446744073709551615UL)),
    (F32, Real(-1.25)),
    (F64, Real(1.0e200)),
    (Text, Textual("α 测试")),
    (Boolean, Logical(true)),
    (Time, Instant({ seconds: -1L, fractions: 18446744073709551615UL, })),
  ]
  for big in [false, true] {
    for (kind, value) in cases {
      let p : Property = { name: "属性", kind, value, }
      let w = Writer::new(big, Limits::default())
      write_property(w, p)
      let b = w.finish()
      let r = Reader::new(b, 0, b.length(), big, Limits::default())
      assert_eq(read_property(r), p)
      assert_eq(r.pos, r.end)
    }
  }
}
