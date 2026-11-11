///|
test "caller constructed values honor string byte budgets" {
  let lim = { ..Limits::default(), max_string_bytes: 10, }
  let d : Document = {
    objects: [
      DataObject::new(ObjectPath::channel("g", "c"), kind=Text, values=[
        Textual("abcdefghijk"),
      ]),
    ],
  }
  let rejected = try {
    d.validate(lim)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let d2 : Document = {
    objects: [
      DataObject::new(ObjectPath::root(), properties=[
        { name: "p", kind: Text, value: Textual("abcdefghijk"), },
      ]),
    ],
  }
  assert_true(
    try {
      d2.validate(lim)
      false
    } catch {
      _ => true
    },
  )
  let d3 : Document = {
    objects: [DataObject::new(ObjectPath::group("abcdefghijk"))],
  }
  assert_true(
    try {
      d3.validate(lim)
      false
    } catch {
      _ => true
    },
  )
}

///|
test "public waveform axis and summary reject invalid caller data" {
  let axis : WaveformAxis = {
    increment: -1.0,
    offset: 0.0,
    count: 2,
    start_time: None,
  }
  assert_true(
    try {
      ignore(axis.at(0))
      false
    } catch {
      _ => true
    },
  )
  let obj = DataObject::new(ObjectPath::channel("g", "c"), kind=I8, values=[
    Unsigned(255UL),
  ])
  assert_true(
    try {
      ignore(obj.summary())
      false
    } catch {
      _ => true
    },
  )
}

///|
test "cropping inserted timing property also obeys output metadata budget" {
  let obj = DataObject::new(
    ObjectPath::channel("g", "c"),
    kind=F64,
    values=[Real(1.0), Real(2.0)],
    properties=[{ name: "wf_increment", kind: F64, value: Real(1.0), }],
  )
  let d : Document = { objects: [obj], }
  let lim = { ..Limits::default(), max_properties: 1, }
  assert_true(
    try {
      ignore(d.select([obj.path], start=1, limits=lim))
      false
    } catch {
      _ => true
    },
  )
}
