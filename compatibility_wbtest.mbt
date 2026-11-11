///|
test "npTDMS short string index marker remains bounded and readable" {
  let doc : Document = {
    objects: [
      DataObject::new(ObjectPath::channel("g", "a"), kind=Text, values=[
        Textual("µV"),
        Textual(""),
      ]),
    ],
  }
  let canonical = write(doc)
  // Object count, path byte length, then eleven ASCII path bytes.
  let marker = 28 + 4 + 4 + 8
  let legacy = Bytes::makei(canonical.length(), i => {
    if i == marker {
      (20).to_byte()
    } else {
      canonical[i]
    }
  })
  assert_eq(canonical[marker], (28).to_byte())
  assert_eq(read(legacy), doc)
}
