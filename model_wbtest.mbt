///|
test "types preserve exact integers and reject narrowing" {
  assert_eq(data_type(68U), Time)
  assert_eq(DataType::Time.width(), Some(16))
  Value::Unsigned(18446744073709551615UL).validate(U64)
  match (Ok(Value::Signed(128L).validate(I8)) catch { e => Err(e) }) {
    Err(_) => ()
    Ok(_) => fail("narrowing accepted")
  }
  Limits::default().validate()
}
