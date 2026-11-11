///|
pub suberror TdmsError {
  Invalid(String)
  Unsupported(String)
  Budget(String)
} derive(Debug)

///|
fn demand(ok : Bool, message : String) -> Unit raise TdmsError {
  if !ok {
    raise Invalid(message)
  }
}

///|
pub(all) enum DataType {
  I8
  I16
  I32
  I64
  U8
  U16
  U32
  U64
  F32
  F64
  Text
  Boolean
  Time
} derive(Eq, Debug)

///|
pub(all) struct Timestamp {
  seconds : Int64
  fractions : UInt64
} derive(Eq, Debug)

///|
pub(all) enum Value {
  Signed(Int64)
  Unsigned(UInt64)
  Real(Double)
  Textual(String)
  Logical(Bool)
  Instant(Timestamp)
} derive(Eq, Debug)

///|
pub(all) struct Property {
  name : String
  kind : DataType
  value : Value
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_bytes : Int32
  max_segments : Int32
  max_objects : Int32
  max_properties : Int32
  max_string_bytes : Int32
  max_samples : Int32
} derive(Eq, Debug)

///|
pub fn Limits::default() -> Limits {
  {
    max_bytes: 64 * 1024 * 1024,
    max_segments: 10000,
    max_objects: 10000,
    max_properties: 100000,
    max_string_bytes: 1024 * 1024,
    max_samples: 4000000,
  }
}

///|
fn Limits::validate(self : Limits) -> Unit raise TdmsError {
  demand(
    self.max_bytes >= 28 &&
    self.max_segments > 0 &&
    self.max_objects > 0 &&
    self.max_properties >= 0 &&
    self.max_string_bytes >= 0 &&
    self.max_samples >= 0,
    "invalid resource limits",
  )
}

///|
pub fn DataType::code(self : DataType) -> UInt32 {
  match self {
    I8 => 1U
    I16 => 2U
    I32 => 3U
    I64 => 4U
    U8 => 5U
    U16 => 6U
    U32 => 7U
    U64 => 8U
    F32 => 9U
    F64 => 10U
    Text => 32U
    Boolean => 33U
    Time => 68U
  }
}

///|
pub fn data_type(code : UInt32) -> DataType raise TdmsError {
  match code {
    1U => I8
    2U => I16
    3U => I32
    4U => I64
    5U => U8
    6U => U16
    7U => U32
    8U => U64
    9U | 0x19U => F32
    10U | 0x1AU => F64
    32U => Text
    33U => Boolean
    68U => Time
    _ => raise Unsupported("TDMS data type \{code}")
  }
}

///|
pub fn DataType::width(self : DataType) -> Int32? {
  match self {
    I8 | U8 | Boolean => Some(1)
    I16 | U16 => Some(2)
    I32 | U32 | F32 => Some(4)
    I64 | U64 | F64 => Some(8)
    Time => Some(16)
    Text => None
  }
}

///|
fn Value::validate(self : Value, kind : DataType) -> Unit raise TdmsError {
  let ok = match (kind, self) {
    (I8, Signed(n)) => n >= -128L && n <= 127L
    (I16, Signed(n)) => n >= -32768L && n <= 32767L
    (I32, Signed(n)) => n >= -2147483648L && n <= 2147483647L
    (I64, Signed(_)) => true
    (U8, Unsigned(n)) => n <= 255UL
    (U16, Unsigned(n)) => n <= 65535UL
    (U32, Unsigned(n)) => n <= 4294967295UL
    (U64, Unsigned(_)) => true
    (F32, Real(n)) =>
      n.is_nan() || n.is_inf() || !Float::from_double(n).is_inf()
    (F64, Real(_)) => true
    (Text, Textual(_)) | (Boolean, Logical(_)) | (Time, Instant(_)) => true
    _ => false
  }
  demand(ok, "value does not fit declared type")
}

///|
pub fn Value::as_double(self : Value) -> Double raise TdmsError {
  match self {
    Signed(n) => n.to_double()
    Unsigned(n) => n.to_double()
    Real(n) => n
    Logical(b) => if b { 1.0 } else { 0.0 }
    _ => raise Invalid("channel is not numeric")
  }
}

///|
pub extend DataType with @debug.Debug::{to_repr}

///|
pub extend DataType with Eq::{equal, not_equal}

///|
pub extend Timestamp with @debug.Debug::{to_repr}

///|
pub extend Timestamp with Eq::{equal, not_equal}

///|
pub extend Value with @debug.Debug::{to_repr}

///|
pub extend Value with Eq::{equal, not_equal}

///|
pub extend Property with @debug.Debug::{to_repr}

///|
pub extend Property with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend TdmsError with @debug.Debug::{to_repr}
