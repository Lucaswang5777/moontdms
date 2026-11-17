///|
fn independent_daqmx_fixture() -> Bytes raise TdmsError {
  decode_hex(
    "5444536d8e0000006912000073010000000000006b0100000000000001000000100000002f27616371272f27766f6c746167652769120000ffffffff010000000400000000000000010000000300000000000000000000000000000000000000010000000200000008000000130000004e495f4e756d6265725f4f665f5363616c65730700000002000000160000004e495f5363616c655b315d5f5363616c655f5479706520000000060000004c696e6561721f0000004e495f5363616c655b315d5f4c696e6561725f496e7075745f536f757263650700000000000000180000004e495f5363616c655b315d5f4c696e6561725f536c6f70650a000000000000000000d03f1e0000004e495f5363616c655b315d5f4c696e6561725f595f496e746572636570740a000000000000000000f83f0b000000756e69745f737472696e672000000001000000560c00000077665f696e6372656d656e740a0000007b14ae47e17a843f0f00000077665f73746172745f6f66667365740a000000000000000000e03f9cff00006400c800",
  )
}

///|
test "DAQmx independently assembled fixture preserves raw and physical crop" {
  let path = ObjectPath::channel("acq", "voltage")
  let source = read_acquisition(independent_daqmx_fixture())
  assert_eq(source.raw_channel(path).unwrap().scalers[0].values, [
    Signed(-100L),
    Signed(0L),
    Signed(100L),
    Signed(200L),
  ])
  assert_eq(source.physical().find(path).unwrap().values, [
    Real(-23.5),
    Real(1.5),
    Real(26.5),
    Real(51.5),
  ])
  let crop = source.select([path], start=1, end=3)
  for big in [false, true] {
    let after = read_acquisition(crop.write(big_endian=big))
    assert_eq(after.raw_channel(path).unwrap().scalers[0].values, [
      Signed(0L),
      Signed(100L),
    ])
    let c = after.physical().find(path).unwrap()
    assert_eq(c.values, [Real(1.5), Real(26.5)])
    assert_eq(c.waveform().at(0), 0.51)
  }
  assert_eq(source.raw_channel(path).unwrap().scalers[0].values.length(), 4)
}

///|
test "physical rewrite explicitly suppresses a second NI scale" {
  let source = read_acquisition(independent_daqmx_fixture()).physical()
  let after = read_acquisition(write(source)).physical()
  assert_eq(after, source)
}

///|
test "DAQmx prefixes are bounded and empty sample streams remain typed" {
  let b = independent_daqmx_fixture()
  for n = 0; n < b.length(); n = n + 1 {
    assert_true(
      try {
        ignore(read_acquisition(Bytes::makei(n, i => b[i])))
        false
      } catch {
        _ => true
      },
    )
  }
  let source = read_acquisition(b).select(
    [ObjectPath::channel("acq", "voltage")],
    start=0,
    end=0,
  )
  let after = read_acquisition(source.write())
  assert_eq(after.daqmx.length(), 1)
  assert_eq(
    after.physical().find(ObjectPath::channel("acq", "voltage")).unwrap().kind,
    Some(F64),
  )
}

///|
test "DAQmx raw sample and scale graph intermediate budgets" {
  let b = independent_daqmx_fixture()
  assert_true(
    try {
      ignore(
        read_acquisition(b, limits={ ..Limits::default(), max_samples: 3, }),
      )
      false
    } catch {
      _ => true
    },
  )
  let source = read_acquisition(b)
  assert_true(
    try {
      ignore(source.physical(limits={ ..Limits::default(), max_samples: 7, }))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    source.physical(limits={ ..Limits::default(), max_samples: 8, }).objects.length(),
    1,
  )
}

///|
test "caller constructed raw channels validate type ids samples and metadata" {
  let source = read_acquisition(independent_daqmx_fixture())
  let d = source.daqmx[0]
  let duplicate : Acquisition = { metadata: source.metadata, daqmx: [d, d], }
  assert_true(
    try {
      ignore(duplicate.write())
      false
    } catch {
      _ => true
    },
  )
  let missing : Acquisition = { metadata: Document::new(), daqmx: [d], }
  assert_true(
    try {
      ignore(missing.physical())
      false
    } catch {
      _ => true
    },
  )
  let mismatched : Acquisition = {
    metadata: source.metadata,
    daqmx: [{ ..d, native_type: Some(U8), }],
  }
  assert_true(
    try {
      ignore(mismatched.write())
      false
    } catch {
      _ => true
    },
  )
}

///|
test "scaling cycles unknown sensors and out of range sources never become physical values" {
  let source = read_acquisition(independent_daqmx_fixture())
  let c = source.metadata.objects[0]
  set_property(c, {
    name: "NI_Scale[1]_Linear_Input_Source",
    kind: U32,
    value: Unsigned(1UL),
  })
  assert_true(
    try {
      ignore(source.physical())
      false
    } catch {
      _ => true
    },
  )
  set_property(c, {
    name: "NI_Scale[1]_Linear_Input_Source",
    kind: U32,
    value: Unsigned(99UL),
  })
  assert_true(
    try {
      ignore(source.physical())
      false
    } catch {
      _ => true
    },
  )
  set_property(c, {
    name: "NI_Scale[1]_Scale_Type",
    kind: Text,
    value: Textual("Thermocouple"),
  })
  assert_true(
    try {
      ignore(source.physical())
      false
    } catch {
      _ => true
    },
  )
  let after = read_acquisition(source.write())
  assert_eq(
    after.metadata.objects[0].property("NI_Scale[1]_Scale_Type"),
    Some(Textual("Thermocouple")),
  )
  assert_eq(after.daqmx[0].scalers[0].values, source.daqmx[0].scalers[0].values)
}

///|
test "inherited scale is applied once and channel scaled marker takes precedence" {
  let source = read_acquisition(independent_daqmx_fixture())
  let c = source.metadata.objects[0]
  let group = DataObject::new(
    ObjectPath::group("acq"),
    properties=c.properties.map(p => p),
  )
  c.properties.clear()
  source.metadata.objects.push(group)
  let p = source.physical()
  assert_eq(p.find(c.path).unwrap().values, [
    Real(-23.5),
    Real(1.5),
    Real(26.5),
    Real(51.5),
  ])
  assert_eq(read_acquisition(write(p)).physical(), p)
}

///|
test "empty AdvancedAPI output keeps its raw scalar data type" {
  let source = read_acquisition(independent_daqmx_fixture()).select(
    [ObjectPath::channel("acq", "voltage")],
    start=0,
    end=0,
  )
  set_property(source.metadata.objects[0], {
    name: "NI_Scale[1]_Scale_Type",
    kind: Text,
    value: Textual("AdvancedAPI"),
  })
  set_property(source.metadata.objects[0], {
    name: "NI_Scale[1]_AdvancedAPI_Input_Source",
    kind: U32,
    value: Unsigned(0UL),
  })
  assert_eq(source.physical().objects[0].kind, Some(I16))
}
