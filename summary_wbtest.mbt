///|
test "summary excludes nonfinite values and uses population variance" {
  let c = DataObject::new(ObjectPath::channel("g", "c"), kind=F64, values=[
    Real(1.0),
    Real(2.0),
    Real(3.0),
    Real(0.0 / 0.0),
    Real(1.0 / 0.0),
  ])
  let s = c.summary()
  assert_eq(s.finite_count, 3)
  assert_eq(s.nonfinite_count, 2)
  assert_eq(s.mean, Some(2.0))
  assert_eq(s.population_variance, Some(2.0 / 3.0))
  assert_true((s.rms.unwrap() - (14.0 / 3.0).sqrt()).abs() < 1.0e-14)
}
