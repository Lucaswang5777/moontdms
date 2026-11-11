///|
pub fn write_segments(
  parts : Array[Document],
  big_endian~ : Bool = false,
  interleaved~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> Bytes raise TdmsError {
  limits.validate()
  demand(!parts.is_empty(), "no segments")
  if parts.length() > limits.max_segments {
    raise Budget("segments")
  }
  let types : Map[String, DataType] = Map([])
  let paths : Map[String, Bool] = Map([])
  let mut samples = 0
  let mut properties = 0
  let out = Writer::new(false, limits)
  for part in parts {
    part.validate(limits)
    for obj in part.objects {
      let key = obj.path.text()
      paths[key] = true
      if paths.size() > limits.max_objects {
        raise Budget("objects across segments")
      }
      if obj.values.length() > limits.max_samples - samples {
        raise Budget("samples across segments")
      }
      samples += obj.values.length()
      if obj.properties.length() > limits.max_properties - properties {
        raise Budget("property records across segments")
      }
      properties += obj.properties.length()
      if obj.kind is Some(kind) {
        if types.get(key) is Some(old) {
          demand(old == kind, "channel data type changed")
        }
        types[key] = kind
      }
    }
    out.append(
      if interleaved {
        write_interleaved(part, big_endian~, limits~)
      } else {
        write(part, big_endian~, limits~)
      },
    )
  }
  out.finish()
}
