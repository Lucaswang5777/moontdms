///|
priv struct RawIndex {
  kind : DataType
  count : Int32
  size : Int32
}

///|
priv struct ReadState {
  doc : Document
  by_path : Map[String, Int32]
  cache : Array[RawIndex?]
  enabled : Array[Bool]
  endian : Array[Bool?]
  active : Array[Int32]
  mut property_records : Int32
  mut samples : Int32
}

///|
fn ReadState::new() -> ReadState {
  {
    doc: Document::new(),
    by_path: Map([]),
    cache: [],
    enabled: [],
    endian: [],
    active: [],
    property_records: 0,
    samples: 0,
  }
}

///|
fn ReadState::object(
  self : ReadState,
  path : ObjectPath,
  limits : Limits,
) -> Int32 raise TdmsError {
  let key = path.text()
  if self.by_path.get(key) is Some(i) {
    return i
  }
  if self.doc.objects.length() >= limits.max_objects {
    raise Budget("objects")
  }
  let i = self.doc.objects.length()
  self.doc.objects.push(DataObject::new(path))
  self.by_path[key] = i
  self.cache.push(None)
  self.enabled.push(false)
  self.endian.push(None)
  i
}

///|
fn read_index(r : Reader, length : UInt32) -> RawIndex raise TdmsError {
  if length == 0x1269U || length == 0x126aU {
    raise Unsupported("DAQmx raw index")
  }
  let kind = data_type(r.u32())
  demand(r.u32() == 1U, "TDMS array dimension must be one")
  let count = r.bounded(8, r.limits.max_samples, "chunk samples")
  let size = match kind.width() {
    Some(width) => {
      demand(length == 20U, "invalid fixed raw index length")
      checked_product(count, width, r.limits.max_bytes)
    }
    None => {
      // npTDMS 1.10.0 emits marker 20 for strings but includes the size field.
      demand(length == 28U || length == 20U, "invalid string raw index length")
      let n = r.bounded(8, r.limits.max_bytes, "string chunk bytes")
      let offsets = checked_product(count, 4, r.limits.max_bytes)
      demand(n >= offsets, "string chunk smaller than offsets")
      n
    }
  }
  { kind, count, size, }
}

///|
fn read_metadata(
  bytes : Bytes,
  seg : SegmentInfo,
  state : ReadState,
  limits : Limits,
) -> Unit raise TdmsError {
  if !flag(seg.toc, 2U) {
    return
  }
  let r = Reader::new(
    bytes,
    seg.offset + 28,
    seg.raw_offset,
    seg.big_endian,
    limits,
  )
  let count = r.bounded(4, limits.max_objects, "metadata objects")
  let new_list = flag(seg.toc, 4U)
  if new_list {
    state.active.clear()
  }
  let seen : Map[Int32, Bool] = Map([])
  for record = 0; record < count; record = record + 1 {
    let path = parse_path(r.string())
    let i = state.object(path, limits)
    demand(!seen.contains(i), "object repeated in segment metadata")
    seen[i] = true
    if new_list || !state.active.contains(i) {
      state.active.push(i)
    }
    let marker = r.u32()
    if marker == 0xffffffffU {
      state.enabled[i] = false
    } else {
      let idx = if marker == 0U {
        match state.cache[i] {
          Some(previous) => previous
          None => raise Invalid("raw index reuse without previous index")
        }
      } else {
        read_index(r, marker)
      }
      demand(path.parts.length() == 2, "raw data on non-channel object")
      let obj = state.doc.objects[i]
      demand(
        obj.kind is None || obj.kind == Some(idx.kind),
        "channel data type changed",
      )
      obj.kind = Some(idx.kind)
      state.cache[i] = Some(idx)
      state.enabled[i] = true
    }
    let n = r.bounded(4, limits.max_properties, "properties per object")
    if n > limits.max_properties - state.property_records {
      raise Budget("property records")
    }
    state.property_records += n
    let names : Map[String, Bool] = Map([])
    for prop = 0; prop < n; prop = prop + 1 {
      let p = read_property(r)
      demand(!names.contains(p.name), "duplicate property in metadata record")
      names[p.name] = true
      if p.name == "name" {
        raise Unsupported("TDMS name-based object renaming")
      }
      set_property(state.doc.objects[i], p)
    }
  }
  demand(r.pos == r.end, "unconsumed metadata bytes")
}
