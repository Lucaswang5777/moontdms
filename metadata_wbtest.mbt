///|
test "raw index sizes are validated before allocation" {
  let w = Writer::new(false, Limits::default())
  w.uint(3UL, 4)
  w.uint(1UL, 4)
  w.uint(7UL, 8)
  let b = w.finish()
  let r = Reader::new(b, 0, b.length(), false, Limits::default())
  let idx = read_index(r, 20U)
  assert_eq(idx.count, 7)
  assert_eq(idx.size, 28)
  let state = ReadState::new()
  assert_eq(state.object(ObjectPath::channel("g", "a"), Limits::default()), 0)
  assert_eq(state.object(ObjectPath::channel("g", "a"), Limits::default()), 0)
  assert_eq(state.doc.objects.length(), 1)
}
