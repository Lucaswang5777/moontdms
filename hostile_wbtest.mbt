///|
fn rejected(bytes : Bytes, limits~ : Limits = Limits::default()) -> Bool {
  try {
    ignore(read(bytes, limits~))
    false
  } catch {
    _ => true
  }
}

///|
fn patch_uint(
  bytes : Bytes,
  offset : Int32,
  value : UInt64,
  width : Int32,
) -> Bytes {
  Bytes::makei(bytes.length(), i => {
    if i >= offset && i < offset + width {
      ((value >> ((i - offset) * 8)) & 255UL).to_byte()
    } else {
      bytes[i]
    }
  })
}

///|
fn hostile_fixture() -> Bytes raise TdmsError {
  write({
    objects: [
      DataObject::new(ObjectPath::channel("g", "a"), kind=I16, values=[
        Signed(1L),
        Signed(2L),
      ]),
    ],
  })
}

///|
test "all strict prefixes of complete segment fail safely" {
  let b = hostile_fixture()
  for n = 0; n < b.length(); n = n + 1 {
    assert_true(rejected(Bytes::makei(n, i => b[i])))
  }
  assert_eq(read(b).objects[0].values.length(), 2)
}

///|
test "lead-in flags extents versions and unfinished sentinel are rejected" {
  let b = hostile_fixture()
  for
    pair in [
      (4, 128UL, 4),
      (4, 1UL, 4),
      (8, 4712UL, 4),
      (12, 18446744073709551615UL, 8),
      (12, 1000000UL, 8),
      (20, 1000000UL, 8),
    ] {
    assert_true(rejected(patch_uint(b, pair.0, pair.1, pair.2)))
  }
  assert_true(rejected(patch_uint(b, 4, 8UL, 4)))
  assert_true(rejected(patch_uint(b, 4, 4UL, 4)))
}

///|
test "raw index unknown types dimensions sizes and DAQmx are rejected" {
  let b = hostile_fixture()
  // count(4), length(4), eight path bytes -> raw index starts at 44.
  for
    pair in [
      (44, 0UL, 4),
      (44, 21UL, 4),
      (44, 0x1269UL, 4),
      (48, 0xffffUL, 4),
      (52, 2UL, 4),
      (56, 18446744073709551615UL, 8),
    ] {
    assert_true(rejected(patch_uint(b, pair.0, pair.1, pair.2)))
  }
}

///|
test "sample byte object segment and property budgets reject bounded inputs" {
  let b = hostile_fixture()
  assert_true(rejected(b, limits={ ..Limits::default(), max_samples: 1, }))
  assert_true(rejected(b, limits={ ..Limits::default(), max_bytes: 28, }))
  let pair = Writer::new(false, Limits::default())
  pair.append(b)
  pair.append(b)
  assert_true(
    rejected(pair.finish(), limits={ ..Limits::default(), max_segments: 1, }),
  )
  let doc : Document = {
    objects: [
      DataObject::new(ObjectPath::group("g")),
      DataObject::new(ObjectPath::channel("g", "a"), kind=I16, values=[
        Signed(1L),
      ]),
    ],
  }
  assert_true(
    rejected(write(doc), limits={ ..Limits::default(), max_objects: 1, }),
  )
  let prop : Document = {
    objects: [
      DataObject::new(ObjectPath::root(), properties=[
        { name: "p", kind: Text, value: Textual("v"), },
      ]),
    ],
  }
  assert_true(
    rejected(write(prop), limits={ ..Limits::default(), max_properties: 0, }),
  )
}

///|
test "string cumulative offsets coverage and UTF8 are strictly validated" {
  let b = write({
    objects: [
      DataObject::new(ObjectPath::channel("g", "a"), kind=Text, values=[
        Textual("a"),
        Textual("b"),
      ]),
    ],
  })
  let raw = inspect(b)[0].raw_offset
  assert_true(rejected(patch_uint(b, raw, 3UL, 4)))
  assert_true(rejected(patch_uint(b, raw + 4, 0UL, 4)))
  assert_true(rejected(patch_uint(b, raw + 4, 1UL, 4)))
  assert_true(rejected(patch_uint(b, raw + 8, 255UL, 1)))
  // Invalid path UTF8 must also fail before metadata interpretation.
  assert_true(rejected(patch_uint(b, 36, 255UL, 1)))
}

///|
test "disable then reuse re-enables cached index without reading disabled channel" {
  let b = hostile_fixture()
  let m = Writer::new(false, Limits::default())
  m.uint(1UL, 4)
  m.string("/'g'/'a'")
  m.uint(0xffffffffUL, 4)
  m.uint(0UL, 4)
  let disabled = test_segment(m.finish(), b"", 6U)
  let n = Writer::new(false, Limits::default())
  n.uint(1UL, 4)
  n.string("/'g'/'a'")
  n.uint(0UL, 4)
  n.uint(0UL, 4)
  let resumed = test_segment(n.finish(), decode_hex("03000400"), 14U)
  let out = Writer::new(false, Limits::default())
  out.append(b)
  out.append(disabled)
  out.append(resumed)
  assert_eq(read(out.finish()).objects[0].values, [
    Signed(1L),
    Signed(2L),
    Signed(3L),
    Signed(4L),
  ])
}

///|
test "type changes endian changes duplicate metadata and reserved names fail" {
  let b = hostile_fixture()
  let d : Document = {
    objects: [
      DataObject::new(ObjectPath::channel("g", "a"), kind=I32, values=[
        Signed(1L),
      ]),
    ],
  }
  let o = Writer::new(false, Limits::default())
  o.append(b)
  o.append(write(d))
  assert_true(rejected(o.finish()))
  let p = Writer::new(false, Limits::default())
  p.append(b)
  p.append(
    write(
      {
        objects: [
          DataObject::new(ObjectPath::channel("g", "a"), kind=I16, values=[
            Signed(1L),
          ]),
        ],
      },
      big_endian=true,
    ),
  )
  assert_true(rejected(p.finish()))
  let m = Writer::new(false, Limits::default())
  m.uint(2UL, 4)
  for _i in 0..<2 {
    m.string("/'g'")
    m.uint(0xffffffffUL, 4)
    m.uint(0UL, 4)
  }
  assert_true(rejected(test_segment(m.finish(), b"", 6U)))
  let r = Writer::new(false, Limits::default())
  r.uint(1UL, 4)
  r.string("/'g'")
  r.uint(0xffffffffUL, 4)
  r.uint(1UL, 4)
  write_property(r, { name: "name", kind: Text, value: Textual("rename"), })
  assert_true(rejected(test_segment(r.finish(), b"", 6U)))
}

///|
test "partial raw frames invalid booleans and unequal interleaving fail" {
  let b = hostile_fixture()
  let short = Bytes::makei(b.length() - 1, i => b[i])
  assert_true(
    rejected(patch_uint(short, 12, (short.length() - 28).to_uint64(), 8)),
  )
  let boolean = write({
    objects: [
      DataObject::new(ObjectPath::channel("g", "a"), kind=Boolean, values=[
        Logical(true),
      ]),
    ],
  })
  assert_true(
    rejected(patch_uint(boolean, inspect(boolean)[0].raw_offset, 2UL, 1)),
  )
  let doc : Document = {
    objects: [
      DataObject::new(ObjectPath::channel("g", "a"), kind=I8, values=[
        Signed(1L),
      ]),
      DataObject::new(ObjectPath::channel("g", "b"), kind=I16, values=[
        Signed(2L),
        Signed(3L),
      ]),
    ],
  }
  assert_true(
    try {
      ignore(write_interleaved(doc))
      false
    } catch {
      _ => true
    },
  )
  let blob = write(doc)
  assert_true(rejected(patch_uint(blob, 4, 46UL, 4)))
}
