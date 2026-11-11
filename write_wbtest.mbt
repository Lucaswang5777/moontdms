///|
fn trial_document() -> Document {
  {
    objects: [
      DataObject::new(ObjectPath::root(), properties=[
        { name: "title", kind: Text, value: Textual("测试"), },
      ]),
      DataObject::new(ObjectPath::group("g")),
      DataObject::new(ObjectPath::channel("g", "volts"), kind=F64, values=[
        Real(-1.5),
        Real(2.0),
      ]),
      DataObject::new(ObjectPath::channel("g", "labels"), kind=Text, values=[
        Textual("a"),
        Textual("测量😀"),
      ]),
      DataObject::new(ObjectPath::channel("g", "ticks"), kind=U64, values=[
        Unsigned(18446744073709551615UL),
      ]),
      DataObject::new(ObjectPath::channel("g", "time"), kind=Time, values=[
        Instant({ seconds: -1L, fractions: 5UL, }),
      ]),
    ],
  }
}

///|
test "canonical TDMS writer roundtrips mixed channels on both endians" {
  let doc = trial_document()
  for big in [false, true] {
    let bytes = write(doc, big_endian=big)
    assert_eq(read(bytes), doc)
    assert_eq(inspect(bytes)[0].big_endian, big)
  }
}
