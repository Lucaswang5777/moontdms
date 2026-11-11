///|
test "interleaved heterogeneous widths preserve frame order" {
  let d : Document = {
    objects: [
      DataObject::new(ObjectPath::channel("g", "a"), kind=I16, values=[
        Signed(1L),
        Signed(-2L),
      ]),
      DataObject::new(ObjectPath::channel("g", "b"), kind=F64, values=[
        Real(3.5),
        Real(4.5),
      ]),
    ],
  }
  for big in [false, true] {
    let b = write_interleaved(d, big_endian=big)
    assert_eq(read(b), d)
    assert_true(flag(inspect(b)[0].toc, 32U))
  }
}
