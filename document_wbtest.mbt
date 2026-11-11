///|
test "document validation rejects structural and type ambiguity" {
  let obj = DataObject::new(ObjectPath::channel("g", "c"), kind=I16, values=[
    Signed(7L),
  ])
  let doc : Document = { objects: [obj], }
  doc.validate(Limits::default())
  assert_eq(doc.find(obj.path), Some(obj))
  set_property(obj, { name: "unit_string", kind: Text, value: Textual("V"), })
  set_property(obj, { name: "unit_string", kind: Text, value: Textual("mV"), })
  assert_eq(obj.properties.length(), 1)
  assert_eq(obj.property("unit_string"), Some(Textual("mV")))
  obj.values.push(Signed(40000L))
  assert_true(
    try {
      doc.validate(Limits::default())
      false
    } catch {
      _ => true
    },
  )
}
