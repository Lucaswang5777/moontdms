///|
test "JSON protocol preserves UInt64 strings and rejects duplicate fields" {
  let result = @json.parse(
    process_json(
      "{\"protocol\":\"moontdms/1\",\"op\":\"encode\",\"objects\":[{\"path\":\"/'g'/'c'\",\"type\":8,\"values\":[\"18446744073709551615\"]}]}",
    ),
  )
  let hex = json_text(json_field(json_field(result, "result"), "hex"))
  let d = read(decode_hex(hex))
  assert_eq(d.objects[0].values, [Unsigned(18446744073709551615UL)])
  assert_true(
    try {
      let _ = process_json("{\"protocol\":\"moontdms/1\",\"protocol\":\"x\"}")
      false
    } catch {
      _ => true
    },
  )
}
