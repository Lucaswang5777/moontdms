///|
test "waveform timing separates relative axis from exact epoch fields" {
  let ch = DataObject::new(
    ObjectPath::channel("g", "v"),
    kind=F64,
    values=[Real(1.0), Real(2.0)],
    properties=[
      { name: "wf_increment", kind: F64, value: Real(0.5), },
      { name: "wf_start_offset", kind: F64, value: Real(-1.0), },
      {
        name: "wf_start_time",
        kind: Time,
        value: Instant({
          seconds: 2082844800L,
          fractions: 9223372036854775808UL,
        }),
      },
    ],
  )
  let axis = ch.waveform()
  assert_eq(axis.values(), [-1.0, -0.5])
  assert_eq(axis.start_time.unwrap().unix_seconds(), 0.5)
  assert_eq(
    Timestamp::{ seconds: -1L, fractions: 5UL, }.compare({
      seconds: -1L,
      fractions: 6UL,
    }),
    -1,
  )
}
