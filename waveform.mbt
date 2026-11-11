///|
pub(all) struct WaveformAxis {
  increment : Double
  offset : Double
  start_time : Timestamp?
  count : Int32
} derive(Eq, Debug)

///|
pub fn DataObject::waveform(self : DataObject) -> WaveformAxis raise TdmsError {
  demand(self.path.parts.length() == 2, "waveform requires a channel")
  let increment = match self.property("wf_increment") {
    Some(v) => v.as_double()
    None => raise Invalid("waveform increment is missing")
  }
  let offset = match self.property("wf_start_offset") {
    Some(v) => v.as_double()
    None => 0.0
  }
  let start_time = match self.property("wf_start_time") {
    Some(Instant(t)) => Some(t)
    Some(_) => raise Invalid("wf_start_time must be a TDMS timestamp")
    None => None
  }
  demand(
    finite(increment) && increment > 0.0 && finite(offset),
    "invalid waveform timing",
  )
  { increment, offset, start_time, count: self.values.length(), }
}

///|
pub fn WaveformAxis::at(
  self : WaveformAxis,
  index : Int32,
) -> Double raise TdmsError {
  demand(
    self.count >= 0 &&
    finite(self.offset) &&
    finite(self.increment) &&
    self.increment > 0.0,
    "invalid waveform axis",
  )
  demand(index >= 0 && index < self.count, "waveform index outside channel")
  let x = self.offset + self.increment * index.to_double()
  demand(finite(x), "waveform axis overflow")
  x
}

///|
pub fn WaveformAxis::values(
  self : WaveformAxis,
  max_samples~ : Int32 = 4000000,
) -> Array[Double] raise TdmsError {
  demand(
    self.count >= 0 &&
    max_samples >= 0 &&
    finite(self.offset) &&
    finite(self.increment) &&
    self.increment > 0.0,
    "invalid waveform axis",
  )
  if self.count > max_samples {
    raise Budget("waveform axis samples")
  }
  let values : Array[Double] = []
  for i = 0; i < self.count; i = i + 1 {
    values.push(self.at(i))
  }
  values
}

///|
pub fn Timestamp::unix_seconds(self : Timestamp) -> Double {
  // Approximate conversion only; the original integer fields remain exact.
  self.seconds.to_double() -
  2082844800.0 +
  self.fractions.to_double() / 18446744073709551616.0
}

///|
pub fn Timestamp::compare(self : Timestamp, other : Timestamp) -> Int32 {
  if self.seconds < other.seconds {
    -1
  } else if self.seconds > other.seconds {
    1
  } else if self.fractions < other.fractions {
    -1
  } else if self.fractions > other.fractions {
    1
  } else {
    0
  }
}

///|
pub extend WaveformAxis with Eq::{equal, not_equal}

///|
pub extend WaveformAxis with @debug.Debug::{to_repr}
