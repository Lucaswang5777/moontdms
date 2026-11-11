///|
test "metadata-only and empty segments have no invented channels" {
  let d = read(empty_segment(false))
  assert_eq(d.objects.length(), 0)
}

///|
test "string chunks use cumulative end offsets and UTF-8 byte lengths" {
  let w = Writer::new(false, Limits::default())
  w.uint(1UL, 4)
  w.uint(3UL, 4)
  w.append(b"abc")
  let b = w.finish()
  let r = Reader::new(b, 0, b.length(), false, Limits::default())
  let out : Array[Value] = []
  read_strings(r, { kind: Text, count: 2, size: 11, }, out)
  assert_eq(out, [Textual("a"), Textual("bc")])
}
