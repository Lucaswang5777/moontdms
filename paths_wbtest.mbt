///|
test "path quoting is reversible for Unicode slashes and apostrophes" {
  for name in ["a", "a'b", "a/b", "测量 😀"] {
    let p = ObjectPath::channel(name, "volts' /")
    assert_eq(parse_path(p.text()), p)
  }
  for bad in ["", "a", "/''", "/'a", "/'a'junk", "/'a'/'b'/'c'"] {
    let ok = try {
      let _ = parse_path(bad)
      true
    } catch {
      _ => false
    }
    assert_false(ok)
  }
}
