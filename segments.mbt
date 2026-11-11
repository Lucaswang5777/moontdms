///|
pub(all) struct SegmentInfo {
  offset : Int32
  raw_offset : Int32
  end_offset : Int32
  toc : UInt32
  big_endian : Bool
} derive(Eq, Debug)

///|
fn flag(toc : UInt32, bit : UInt32) -> Bool {
  (toc & bit) != 0U
}

///|
fn segment_header(
  bytes : Bytes,
  pos : Int32,
  limits : Limits,
) -> SegmentInfo raise TdmsError {
  demand(pos >= 0 && bytes.length() - pos >= 28, "truncated TDMS lead-in")
  let tag = Reader::new(bytes, pos, pos + 8, false, limits)
  demand(tag.take(4) == b"TDSm", "expected TDSm segment tag")
  let toc = tag.u32()
  if (toc & 0xffffff11U) != 0U {
    raise Unsupported("unknown table-of-contents flags")
  }
  if flag(toc, 128U) {
    raise Unsupported("DAQmx raw data")
  }
  let big = flag(toc, 64U)
  let r = Reader::new(bytes, pos + 8, pos + 28, big, limits)
  let version = r.u32()
  if version != 4713U {
    raise Unsupported("only TDMS 2.0 version 4713 is supported")
  }
  let size = r.uint(8)
  if size == 18446744073709551615UL {
    raise Unsupported("unfinished segment sentinel")
  }
  let raw = r.uint(8)
  demand(
    size <= (bytes.length() - pos - 28).to_uint64(),
    "segment extends beyond input",
  )
  demand(raw <= size, "raw offset exceeds segment")
  demand(flag(toc, 2U) || raw == 0UL, "metadata bytes without metadata flag")
  demand(!flag(toc, 4U) || flag(toc, 2U), "new object list without metadata")
  demand(flag(toc, 8U) || raw == size, "raw bytes without raw-data flag")
  {
    offset: pos,
    raw_offset: pos + 28 + raw.to_int(),
    end_offset: pos + 28 + size.to_int(),
    toc,
    big_endian: big,
  }
}

///|
pub fn inspect(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> Array[SegmentInfo] raise TdmsError {
  limits.validate()
  if bytes.length() > limits.max_bytes {
    raise Budget("input bytes")
  }
  demand(bytes.length() > 0, "empty TDMS input")
  let result : Array[SegmentInfo] = []
  let mut pos = 0
  while pos < bytes.length() {
    if result.length() >= limits.max_segments {
      raise Budget("segments")
    }
    let s = segment_header(bytes, pos, limits)
    result.push(s)
    pos = s.end_offset
  }
  result
}

///|
pub extend SegmentInfo with Eq::{equal, not_equal}

///|
pub extend SegmentInfo with @debug.Debug::{to_repr}
