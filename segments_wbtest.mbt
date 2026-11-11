///|
fn empty_segment(big : Bool) -> Bytes raise TdmsError {
  let w = Writer::new(false, Limits::default())
  w.append(b"TDSm")
  w.uint(if big { 64UL } else { 0UL }, 4)
  let h = Writer::new(big, Limits::default())
  h.uint(4713UL, 4)
  h.uint(0UL, 8)
  h.uint(0UL, 8)
  w.append(h.finish())
  w.finish()
}

///|
test "lead-ins validate version endianness and ranges" {
  for big in [false, true] {
    let b = empty_segment(big)
    let info = inspect(b)
    assert_eq(info.length(), 1)
    assert_eq(info[0].big_endian, big)
    assert_eq(info[0].end_offset, 28)
  }
  let bad = try {
    let _ = inspect(b"TDSm")
    false
  } catch {
    _ => true
  }
  assert_true(bad)
}
