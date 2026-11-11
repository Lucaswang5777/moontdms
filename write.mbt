///|
fn string_payload(obj : DataObject, limits : Limits) -> Bytes raise TdmsError {
  let offsets = Writer::new(false, limits)
  let payload = Writer::new(false, limits)
  for v in obj.values {
    match v {
      Textual(s) => {
        let b = @utf8.encode(s)
        if b.length() > limits.max_string_bytes {
          raise Budget("string value bytes")
        }
        payload.append(b)
        offsets.uint(payload.bytes.length().to_uint64(), 4)
      }
      _ => raise Invalid("non-string in string channel")
    }
  }
  offsets.append(payload.finish())
  offsets.finish()
}

///|
pub fn write(
  doc : Document,
  big_endian~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> Bytes raise TdmsError {
  doc.validate(limits)
  let meta = Writer::new(big_endian, limits)
  let raw = Writer::new(big_endian, limits)
  meta.uint(doc.objects.length().to_uint64(), 4)
  for obj in doc.objects {
    meta.string(obj.path.text())
    match obj.kind {
      None => meta.uint(0xffffffffUL, 4)
      Some(kind) => {
        meta.uint(if kind == Text { 28UL } else { 20UL }, 4)
        meta.uint(kind.code().to_uint64(), 4)
        meta.uint(1UL, 4)
        meta.uint(obj.values.length().to_uint64(), 8)
        if kind == Text {
          let payload = string_payload(obj, limits)
          meta.uint(payload.length().to_uint64(), 8)
          // The offset table has the same endianness as the segment.
          if big_endian {
            let r = Reader::new(payload, 0, payload.length(), false, limits)
            for n = 0; n < obj.values.length(); n = n + 1 {
              raw.uint(r.uint(4), 4)
            }
            raw.append(r.take(r.end - r.pos))
          } else {
            raw.append(payload)
          }
        } else {
          for v in obj.values {
            raw.scalar(kind, v)
          }
        }
      }
    }
    meta.uint(obj.properties.length().to_uint64(), 4)
    for p in obj.properties {
      write_property(meta, p)
    }
  }
  let m = meta.finish()
  let data = raw.finish()
  let out = Writer::new(false, limits)
  out.append(b"TDSm")
  out.uint(if big_endian { 78UL } else { 14UL }, 4)
  let header = Writer::new(big_endian, limits)
  header.uint(4713UL, 4)
  demand(
    m.length() <= limits.max_bytes - data.length(),
    "segment size overflow",
  )
  header.uint((m.length() + data.length()).to_uint64(), 8)
  header.uint(m.length().to_uint64(), 8)
  out.append(header.finish())
  out.append(m)
  out.append(data)
  out.finish()
}
