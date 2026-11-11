///|
fn read_interleaved(
  r : Reader,
  channels : Array[(Int32, RawIndex)],
  state : ReadState,
) -> Unit raise TdmsError {
  if channels.is_empty() {
    return
  }
  let count = channels[0].1.count
  for (_, idx) in channels {
    if idx.kind == Text {
      raise Unsupported("interleaved string channels")
    }
    demand(idx.count == count, "unequal interleaved channel lengths")
  }
  for row = 0; row < count; row = row + 1 {
    for (i, idx) in channels {
      state.doc.objects[i].values.push(r.scalar(idx.kind))
    }
  }
}

///|
pub fn write_interleaved(
  doc : Document,
  big_endian~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> Bytes raise TdmsError {
  doc.validate(limits)
  let channels = doc.objects.filter(o => o.kind is Some(_))
  let count = if channels.is_empty() { 0 } else { channels[0].values.length() }
  for obj in channels {
    if obj.kind == Some(Text) {
      raise Unsupported("interleaved string channels")
    }
    demand(obj.values.length() == count, "unequal interleaved channel lengths")
  }
  let ordinary = write(doc, big_endian~, limits~)
  let seg = inspect(ordinary, limits~)[0]
  let out = Writer::new(false, limits)
  out.append(b"TDSm")
  out.uint((seg.toc | 32U).to_uint64(), 4)
  out.append(Bytes::makei(seg.raw_offset - 8, i => ordinary[i + 8]))
  let raw = Writer::new(big_endian, limits)
  for row = 0; row < count; row = row + 1 {
    for obj in channels {
      raw.scalar(obj.kind.unwrap(), obj.values[row])
    }
  }
  out.append(raw.finish())
  out.finish()
}
