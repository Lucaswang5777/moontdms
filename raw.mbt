///|
fn read_strings(
  r : Reader,
  index : RawIndex,
  target : Array[Value],
) -> Unit raise TdmsError {
  demand(index.size <= r.end - r.pos, "truncated string chunk")
  let offset_bytes = checked_product(index.count, 4, index.size)
  let payload_bytes = index.size - offset_bytes
  let ends : Array[Int32] = []
  let mut previous = 0
  for i = 0; i < index.count; i = i + 1 {
    let end = r.bounded(4, payload_bytes, "string offset")
    demand(
      end >= previous && end - previous <= r.limits.max_string_bytes,
      "invalid string offsets",
    )
    ends.push(end)
    previous = end
  }
  demand(previous == payload_bytes, "string offsets do not cover payload")
  previous = 0
  for end in ends {
    let b = r.take(end - previous)
    let text = @utf8.decode(b) catch {
      _ => raise Invalid("invalid UTF-8 channel value")
    }
    target.push(Textual(text))
    previous = end
  }
}

///|
fn read_contiguous(
  bytes : Bytes,
  seg : SegmentInfo,
  state : ReadState,
  limits : Limits,
) -> Unit raise TdmsError {
  if !flag(seg.toc, 8U) {
    return
  }

  let r = Reader::new(
    bytes,
    seg.raw_offset,
    seg.end_offset,
    seg.big_endian,
    limits,
  )
  let channels : Array[(Int32, RawIndex)] = []
  let mut chunk_size = 0
  let mut sample_count = 0
  for i in state.active {
    if !state.enabled[i] {
      continue
    }
    let idx = state.cache[i].unwrap()
    demand(idx.size <= limits.max_bytes - chunk_size, "chunk byte overflow")
    demand(
      idx.count <= limits.max_samples - sample_count,
      "chunk sample overflow",
    )
    chunk_size += idx.size
    sample_count += idx.count
    channels.push((i, idx))
    match state.endian[i] {
      Some(big) => demand(big == seg.big_endian, "channel endianness changed")
      None => state.endian[i] = Some(seg.big_endian)
    }
  }
  let raw_size = r.end - r.pos
  if chunk_size == 0 {
    demand(raw_size == 0, "raw bytes without nonempty indexes")
    return
  }
  demand(raw_size % chunk_size == 0, "incomplete trailing raw chunk")
  let chunks = raw_size / chunk_size
  let total = checked_product(
    chunks,
    sample_count,
    limits.max_samples - state.samples,
  )
  state.samples += total
  for chunk = 0; chunk < chunks; chunk = chunk + 1 {
    if flag(seg.toc, 32U) {
      read_interleaved(r, channels, state)
      continue
    }
    for (i, idx) in channels {
      let target = state.doc.objects[i].values
      if idx.kind == Text {
        read_strings(r, idx, target)
      } else {
        for sample = 0; sample < idx.count; sample = sample + 1 {
          target.push(r.scalar(idx.kind))
        }
      }
    }
  }
  demand(r.pos == r.end, "unconsumed raw bytes")
}

///|
pub fn read(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> Document raise TdmsError {
  let segments = inspect(bytes, limits~)
  let state = ReadState::new()
  for seg in segments {
    read_metadata(bytes, seg, state, limits)
    read_contiguous(bytes, seg, state, limits)
  }
  state.doc
}
