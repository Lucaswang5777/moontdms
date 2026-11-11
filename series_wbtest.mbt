///|
fn test_segment(
  meta : Bytes,
  raw : Bytes,
  toc : UInt32,
) -> Bytes raise TdmsError {
  let w = Writer::new(false, Limits::default())
  w.append(b"TDSm")
  w.uint(toc.to_uint64(), 4)
  w.uint(4713UL, 4)
  w.uint((meta.length() + raw.length()).to_uint64(), 8)
  w.uint(meta.length().to_uint64(), 8)
  w.append(meta)
  w.append(raw)
  w.finish()
}

///|
test "raw-only following segments reuse channel layout and repeat complete chunks" {
  let d : Document = {
    objects: [
      DataObject::new(ObjectPath::channel("g", "a"), kind=I16, values=[
        Signed(1L),
        Signed(2L),
      ]),
    ],
  }
  let out = Writer::new(false, Limits::default())
  out.append(write(d))
  out.append(test_segment(b"", decode_hex("0300040005000600"), 8U))
  assert_eq(read(out.finish()).objects[0].values, [
    Signed(1L),
    Signed(2L),
    Signed(3L),
    Signed(4L),
    Signed(5L),
    Signed(6L),
  ])
}

///|
test "metadata reuse updates properties without changing sample indexes" {
  let d : Document = {
    objects: [
      DataObject::new(ObjectPath::channel("g", "a"), kind=I16, values=[
        Signed(1L),
      ]),
    ],
  }
  let m = Writer::new(false, Limits::default())
  m.uint(1UL, 4)
  m.string("/'g'/'a'")
  m.uint(0UL, 4)
  m.uint(1UL, 4)
  write_property(m, { name: "unit_string", kind: Text, value: Textual("mV"), })
  let out = Writer::new(false, Limits::default())
  out.append(write(d))
  out.append(test_segment(m.finish(), decode_hex("0200"), 10U))
  let obj = read(out.finish()).objects[0]
  assert_eq(obj.values, [Signed(1L), Signed(2L)])
  assert_eq(obj.property("unit_string"), Some(Textual("mV")))
}

///|
test "new object lists reorder channels and preserve global channel identity" {
  let a = DataObject::new(ObjectPath::channel("g", "a"), kind=I32, values=[
    Signed(1L),
  ])
  let b = DataObject::new(ObjectPath::channel("g", "b"), kind=I32, values=[
    Signed(2L),
  ])
  let d = read(write_segments([{ objects: [a, b], }, { objects: [b, a], }]))
  assert_eq(d.objects[0].values, [Signed(1L), Signed(1L)])
  assert_eq(d.objects[1].values, [Signed(2L), Signed(2L)])
}
