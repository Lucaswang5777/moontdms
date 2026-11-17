///|
/// Crop raw scalers together, retaining NI scale metadata and waveform timing.
pub fn Acquisition::select(
  self : Acquisition,
  paths : Array[ObjectPath],
  start~ : Int32 = 0,
  end? : Int32,
  limits~ : Limits = Limits::default(),
) -> Acquisition raise TdmsError {
  self.validate(limits)
  // Ordinary selection validates existence and carries root/group properties.
  let shadow = Document::new()
  for o in self.metadata.objects {
    if self.raw_channel(o.path) is Some(d) {
      demand(!d.scalers.is_empty(), "empty DAQmx scaler set")
      shadow.objects.push(
        DataObject::new(
          o.path,
          kind=d.scalers[0].kind,
          values=d.scalers[0].values,
          properties=o.properties,
        ),
      )
    } else {
      shadow.objects.push(o)
    }
  }
  let selected = shadow.select(paths, start~, end?, limits~)
  let streams : Array[DaqChannel] = []
  for o in selected.objects {
    if self.raw_channel(o.path) is Some(d) {
      let stop = end.unwrap_or(d.scalers[0].values.length())
      let scalers : Array[ScalerData] = []
      for s in d.scalers {
        demand(
          s.values.length() == d.scalers[0].values.length(),
          "unequal DAQmx scaler lengths",
        )
        scalers.push({
          id: s.id,
          kind: s.kind,
          values: Array::makei(stop - start, i => s.values[start + i]),
        })
      }
      streams.push({ path: o.path, scalers, native_type: d.native_type, })
      o.kind = None
      o.values.clear()
    }
  }
  { metadata: selected, daqmx: streams, }
}

///|
fn daq_segment(
  meta : Bytes,
  raw : Bytes,
  big : Bool,
  limits : Limits,
) -> Bytes raise TdmsError {
  let out = Writer::new(false, limits)
  out.append(b"TDSm")
  out.uint(if big { 206UL } else { 142UL }, 4)
  let header = Writer::new(big, limits)
  header.uint(4713UL, 4)
  demand(
    meta.length() <= limits.max_bytes - raw.length(),
    "DAQmx segment size budget",
  )
  header.uint((meta.length() + raw.length()).to_uint64(), 8)
  header.uint(meta.length().to_uint64(), 8)
  out.append(header.finish())
  out.append(meta)
  out.append(raw)
  out.finish()
}

///|
/// Write exact scaler samples and original scale properties. Buffer padding and
/// digital bit packing are canonicalized to byte-aligned format-changing scalers.
pub fn Acquisition::write(
  self : Acquisition,
  big_endian~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> Bytes raise TdmsError {
  self.validate(limits)
  let base = Document::new()
  let seen : Map[String, Bool] = Map([])
  let mut samples = 0
  for d in self.daqmx {
    demand(!seen.contains(d.path.text()), "duplicate DAQmx channel")
    seen[d.path.text()] = true
    demand(
      d.path.parts.length() == 2 && self.metadata.find(d.path) is Some(_),
      "DAQmx channel missing metadata",
    )
    demand(
      !d.scalers.is_empty() && d.scalers.length() <= limits.max_objects,
      "DAQmx scaler count",
    )
    let ids : Map[UInt32, Bool] = Map([])
    for s in d.scalers {
      demand(!ids.contains(s.id), "duplicate DAQmx scaler id")
      ids[s.id] = true
      demand(
        s.values.length() == d.scalers[0].values.length(),
        "unequal DAQmx scaler lengths",
      )
      if s.values.length() > limits.max_samples - samples {
        raise Budget("DAQmx output samples")
      }
      samples += s.values.length()
    }
  }
  for o in self.metadata.objects {
    if self.raw_channel(o.path) is None {
      base.objects.push(o)
    } else {
      demand(
        o.kind is None && o.values.is_empty(),
        "DAQmx metadata contains ordinary samples",
      )
      base.objects.push(DataObject::new(o.path, properties=o.properties))
    }
  }
  let out = Writer::new(false, limits)
  out.append(write(base, big_endian~, limits~))
  for d in self.daqmx {
    let meta = Writer::new(big_endian, limits)
    let raw = Writer::new(big_endian, limits)
    meta.uint(1UL, 4)
    meta.string(d.path.text())
    meta.uint(0x1269UL, 4)
    meta.uint(
      match d.native_type {
        Some(k) => k.code().to_uint64()
        None => 0xffffffffUL
      },
      4,
    )
    meta.uint(1UL, 4)
    meta.uint(d.scalers[0].values.length().to_uint64(), 8)
    meta.uint(d.scalers.length().to_uint64(), 4)
    let mut width = 0
    for s in d.scalers {
      meta.uint(daq_code(s.kind).to_uint64(), 4)
      meta.uint(0UL, 4)
      meta.uint(width.to_uint64(), 4)
      meta.uint(0UL, 4)
      meta.uint(s.id.to_uint64(), 4)
      width += s.kind.width().unwrap()
    }
    demand(width <= limits.max_bytes, "DAQmx output buffer width")
    meta.uint(1UL, 4)
    meta.uint(width.to_uint64(), 4)
    meta.uint(0UL, 4)
    for i = 0; i < d.scalers[0].values.length(); i = i + 1 {
      for s in d.scalers {
        raw.scalar(s.kind, s.values[i])
      }
    }
    out.append(daq_segment(meta.finish(), raw.finish(), big_endian, limits))
  }
  out.finish()
}
