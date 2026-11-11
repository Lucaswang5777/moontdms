///|
test "CSV escapes commas quotes newlines and exact unsigned values" {
  let d : Document = {
    objects: [
      DataObject::new(ObjectPath::channel("g,1", "a\"b"), kind=Text, values=[
        Textual("line\nnext"),
      ]),
    ],
  }
  let csv = d.csv()
  assert_eq(
    csv, "group,channel,index,value,unit,relative_time\r\n\"g,1\",\"a\"\"b\",0,\"line\nnext\",\"\",\r\n",
  )
  assert_eq(
    Value::Unsigned(18446744073709551615UL).text(),
    "18446744073709551615",
  )
}
