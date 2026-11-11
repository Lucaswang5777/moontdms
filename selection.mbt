///|
fn copy_object(
  obj : DataObject,
  start : Int32,
  end : Int32,
) -> DataObject raise TdmsError {
  demand(
    start >= 0 && end >= start && end <= obj.values.length(),
    "sample selection outside channel",
  )
  {
    path: { parts: obj.path.parts.map(x => x), },
    kind: obj.kind,
    properties: obj.properties.map(x => x),
    values: Array::makei(end - start, i => obj.values[start + i]),
  }
}

///|
pub fn Document::select(
  self : Document,
  channels : Array[ObjectPath],
  start~ : Int32 = 0,
  end? : Int32,
  limits~ : Limits = Limits::default(),
) -> Document raise TdmsError {
  self.validate(limits)
  demand(!channels.is_empty(), "no selected channels")
  let selected : Map[String, Bool] = Map([])
  let groups : Map[String, Bool] = Map([])
  for path in channels {
    demand(path.parts.length() == 2, "selection requires channel paths")
    let key = path.text()
    demand(!selected.contains(key), "duplicate selected channel")
    demand(self.find(path) is Some(_), "selected channel does not exist")
    selected[key] = true
    groups[path.parts[0]] = true
  }
  let result = Document::new()
  for obj in self.objects {
    if obj.path.parts.length() == 2 {
      if !selected.contains(obj.path.text()) {
        continue
      }
      let stop = end.unwrap_or(obj.values.length())
      let copy = copy_object(obj, start, stop)
      if start > 0 && obj.property("wf_increment") is Some(increment) {
        let dt = increment.as_double()
        demand(finite(dt) && dt > 0.0, "invalid waveform increment")
        let offset = match obj.property("wf_start_offset") {
          Some(v) => v.as_double()
          None => 0.0
        }
        let shifted = offset + start.to_double() * dt
        demand(finite(shifted), "waveform offset overflow")
        set_property(copy, {
          name: "wf_start_offset",
          kind: F64,
          value: Real(shifted),
        })
      }
      result.objects.push(copy)
    } else if obj.path.parts.is_empty() || groups.contains(obj.path.parts[0]) {
      result.objects.push(copy_object(obj, 0, 0))
    }
  }
  result.validate(limits)
  result
}

///|
pub fn Document::channel_paths(self : Document) -> Array[ObjectPath] {
  self.objects
  .filter(o => o.path.parts.length() == 2)
  .map(o => { parts: o.path.parts.map(x => x), })
}

///|
fn finite(x : Double) -> Bool {
  !x.is_nan() && !x.is_inf()
}
