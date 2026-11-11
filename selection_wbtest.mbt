///|
test "selection crops data preserves metadata and detaches mutable arrays" {
  let d = trial_document()
  let path = ObjectPath::channel("g", "volts")
  let original = d.find(path).unwrap()
  set_property(original, { name: "wf_increment", kind: F64, value: Real(0.25), })
  let selected = d.select([path], start=1, end=2)
  assert_eq(selected.objects.length(), 3)
  let ch = selected.find(path).unwrap()
  assert_eq(ch.values, [Real(2.0)])
  assert_eq(ch.property("wf_start_offset"), Some(Real(0.25)))
  ch.values.clear()
  assert_eq(original.values.length(), 2)
  assert_eq(original.property("wf_start_offset"), None)
}
