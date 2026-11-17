///|
/// Raw samples from one DAQmx scaler. Integer samples remain exact.
pub(all) struct ScalerData {
  id : UInt32
  kind : DataType
  values : Array[Value]
} derive(Eq, Debug)

///|
/// A DAQmx channel can have several independent scaler streams.
pub(all) struct DaqChannel {
  path : ObjectPath
  scalers : Array[ScalerData]
  native_type : DataType?
} derive(Eq, Debug)

///|
/// Metadata and ordinary raw samples; DAQmx streams live in daqmx.
/// Call physical explicitly before exporting engineering values.
pub(all) struct Acquisition {
  metadata : Document
  daqmx : Array[DaqChannel]
} derive(Eq, Debug)

///|
pub fn Acquisition::raw_channel(
  self : Acquisition,
  path : ObjectPath,
) -> DaqChannel? {
  self.daqmx.iter().find_first(c => c.path == path)
}

///|
priv struct DaqScaler {
  id : UInt32
  kind : DataType
  buffer : Int32
  offset : Int32
  bit : Int32?
}

///|
priv struct DaqIndex {
  raw_type : Bool
  scalers : Array[DaqScaler]
  widths : Array[Int32]
}

///|
fn daq_kind(code : UInt32) -> DataType raise TdmsError {
  match code {
    0U => U8
    1U => I8
    2U => U16
    3U => I16
    4U => U32
    5U => I32
    6U => U64
    7U => I64
    8U => F32
    9U => F64
    0xffffffffU => Time
    _ => raise Unsupported("DAQmx scaler type \{code}")
  }
}

///|
fn daq_code(kind : DataType) -> UInt32 raise TdmsError {
  match kind {
    U8 => 0U
    I8 => 1U
    U16 => 2U
    I16 => 3U
    U32 => 4U
    I32 => 5U
    U64 => 6U
    I64 => 7U
    F32 => 8U
    F64 => 9U
    Time => 0xffffffffU
    _ => raise Unsupported("non-DAQmx scaler type")
  }
}

///|
fn read_daq_index(r : Reader, marker : UInt32) -> RawIndex raise TdmsError {
  let code = r.u32()
  let raw_type = code == 0xffffffffU
  let kind = if raw_type { F64 } else { data_type(code) }
  demand(r.u32() == 1U, "DAQmx array dimension must be one")
  let count = r.bounded(8, r.limits.max_samples, "DAQmx chunk samples")
  let n = r.bounded(4, r.limits.max_objects, "DAQmx scalers")
  demand(n > 0, "DAQmx index without scalers")
  let scalers : Array[DaqScaler] = []
  let ids : Map[UInt32, Bool] = Map([])
  for i = 0; i < n; i = i + 1 {
    let k = daq_kind(r.u32())
    let buffer = r.bounded(4, r.limits.max_objects, "DAQmx buffer index")
    let offset = r.bounded(4, r.limits.max_bytes, "DAQmx offset")
    let digital = marker != 0x1269U
    let bitmap = r.uint(if digital { 1 } else { 4 })
    if bitmap != 0UL {
      raise Unsupported("DAQmx sample format bitmap")
    }
    let id = r.u32()
    demand(!ids.contains(id), "duplicate DAQmx scaler id")
    ids[id] = true
    if digital {
      demand(k == U8, "digital line scaler must be Uint8")
    }
    scalers.push({
      id,
      kind: k,
      buffer,
      offset: if digital {
        offset / 8
      } else {
        offset
      },
      bit: if digital {
        Some(offset % 8)
      } else {
        None
      },
    })
  }
  if !raw_type {
    demand(
      n == 1 && scalers[0].kind == kind,
      "DAQmx channel/scaler type mismatch",
    )
  }
  let nbuf = r.bounded(4, r.limits.max_objects, "DAQmx buffers")
  demand(nbuf > 0, "DAQmx index without buffers")
  let widths : Array[Int32] = []
  for i = 0; i < nbuf; i = i + 1 {
    let width = r.bounded(4, r.limits.max_bytes, "DAQmx buffer width")
    demand(width > 0, "zero DAQmx buffer width")
    widths.push(width)
  }
  for s in scalers {
    demand(s.buffer < nbuf, "DAQmx buffer index out of range")
    let width = s.kind.width().unwrap()
    demand(
      s.offset <= widths[s.buffer] && width <= widths[s.buffer] - s.offset,
      "DAQmx scaler outside record",
    )
  }
  { kind, count, size: 0, daq: Some({ raw_type, scalers, widths, }), }
}

///|
fn read_daq_raw(
  bytes : Bytes,
  seg : SegmentInfo,
  state : ReadState,
  limits : Limits,
) -> Unit raise TdmsError {
  let channels : Array[(Int32, RawIndex)] = []
  let mut widths : Array[Int32] = []
  for i in state.active {
    if !state.enabled[i] {
      continue
    }
    let idx = state.cache[i].unwrap()
    let layout = idx.daq.unwrap()
    if widths.is_empty() {
      widths = layout.widths
    } else {
      demand(widths == layout.widths, "inconsistent DAQmx buffer widths")
    }
    channels.push((i, idx))
  }
  let counts = Array::make(widths.length(), 0)
  for (_, idx) in channels {
    for s in idx.daq.unwrap().scalers {
      if counts[s.buffer] != 0 {
        demand(
          counts[s.buffer] == idx.count,
          "inconsistent DAQmx buffer sample counts",
        )
      }
      counts[s.buffer] = idx.count
    }
  }
  let starts : Array[Int32] = []
  let mut chunk_bytes = 0
  for b = 0; b < widths.length(); b = b + 1 {
    starts.push(chunk_bytes)
    let n = checked_product(
      counts[b],
      widths[b],
      limits.max_bytes - chunk_bytes,
    )
    chunk_bytes += n
  }
  let size = seg.end_offset - seg.raw_offset
  let chunks = if chunk_bytes == 0 {
    demand(size == 0, "DAQmx bytes without samples")
    0
  } else {
    demand(size % chunk_bytes == 0, "incomplete DAQmx raw chunk")
    size / chunk_bytes
  }
  for (i, idx) in channels {
    let layout = idx.daq.unwrap()
    let path = state.doc.objects[i].path
    let target = match state.daqmx[i] {
      Some(c) => c
      None => {
        let c : DaqChannel = {
          path,
          native_type: if layout.raw_type {
            None
          } else {
            Some(idx.kind)
          },
          scalers: layout.scalers.map(s => {
            id: s.id,
            kind: s.kind,
            values: [],
          }),
        }
        state.daqmx[i] = Some(c)
        c
      }
    }
    demand(
      target.native_type ==
      (if layout.raw_type { None } else { Some(idx.kind) }),
      "DAQmx channel type changed",
    )
    demand(
      target.scalers.length() == layout.scalers.length(),
      "DAQmx scaler set changed",
    )
    for s in layout.scalers {
      let stream = match target.scalers.iter().find_first(t => t.id == s.id) {
        Some(t) => t
        None => raise Invalid("DAQmx scaler id changed")
      }
      demand(stream.kind == s.kind, "DAQmx scaler type changed")
      let n = checked_product(
        chunks,
        idx.count,
        limits.max_samples - state.samples,
      )
      state.samples += n
      for ch = 0; ch < chunks; ch = ch + 1 {
        for row = 0; row < idx.count; row = row + 1 {
          let pos = seg.raw_offset +
            ch * chunk_bytes +
            starts[s.buffer] +
            row * widths[s.buffer] +
            s.offset
          let r = Reader::new(
            bytes,
            pos,
            pos + s.kind.width().unwrap(),
            seg.big_endian,
            limits,
          )
          let v = match s.bit {
            None => r.scalar(s.kind)
            Some(bit) => Unsigned((r.uint(1) >> bit) & 1UL)
          }
          stream.values.push(v)
        }
      }
    }
  }
}

///|
pub fn read_acquisition(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> Acquisition raise TdmsError {
  let state = ReadState::new()
  for seg in inspect(bytes, limits~) {
    read_metadata(bytes, seg, state, limits)
    if flag(seg.toc, 8U) {
      for i in state.active {
        if state.enabled[i] {
          demand(
            (state.cache[i].unwrap().daq is Some(_)) == flag(seg.toc, 128U),
            "mixed ordinary/DAQmx raw indexes",
          )
        }
      }
      if flag(seg.toc, 128U) {
        read_daq_raw(bytes, seg, state, limits)
      } else {
        read_contiguous(bytes, seg, state, limits)
      }
    }
  }
  { metadata: state.doc, daqmx: state.daqmx.filter_map(x => x), }
}

///|
pub extend ScalerData with Eq::{equal, not_equal}

///|
pub extend ScalerData with @debug.Debug::{to_repr}

///|
pub extend DaqChannel with Eq::{equal, not_equal}

///|
pub extend DaqChannel with @debug.Debug::{to_repr}

///|
pub extend Acquisition with Eq::{equal, not_equal}

///|
pub extend Acquisition with @debug.Debug::{to_repr}

///|
fn Acquisition::validate(
  self : Acquisition,
  limits : Limits,
) -> Unit raise TdmsError {
  self.metadata.validate(limits)
  let mut samples = 0
  for o in self.metadata.objects {
    samples += o.values.length()
  }
  let paths : Map[String, Bool] = Map([])
  for d in self.daqmx {
    demand(!paths.contains(d.path.text()), "duplicate DAQmx channel")
    paths[d.path.text()] = true
    let obj = match self.metadata.find(d.path) {
      Some(o) => o
      None => raise Invalid("DAQmx metadata missing")
    }
    demand(
      d.path.parts.length() == 2 && obj.kind is None && obj.values.is_empty(),
      "invalid DAQmx metadata placeholder",
    )
    demand(
      !d.scalers.is_empty() && d.scalers.length() <= limits.max_objects,
      "DAQmx scaler count",
    )
    if d.native_type is Some(kind) {
      demand(
        d.scalers.length() == 1 && d.scalers[0].kind == kind,
        "DAQmx channel/scaler type mismatch",
      )
    }
    let ids : Map[UInt32, Bool] = Map([])
    for s in d.scalers {
      demand(!ids.contains(s.id), "duplicate DAQmx scaler id")
      ids[s.id] = true
      let _ = daq_code(s.kind)
      demand(
        s.values.length() == d.scalers[0].values.length(),
        "unequal DAQmx scaler lengths",
      )
      if s.values.length() > limits.max_samples - samples {
        raise Budget("acquisition samples")
      }
      samples += s.values.length()
      for v in s.values {
        v.validate(s.kind)
      }
    }
  }
}
