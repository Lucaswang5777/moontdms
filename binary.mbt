///|
priv struct Reader {
  bytes : Bytes
  mut pos : Int32
  end : Int32
  big : Bool
  limits : Limits
}

///|
fn Reader::new(
  bytes : Bytes,
  start : Int32,
  end : Int32,
  big : Bool,
  limits : Limits,
) -> Reader raise TdmsError {
  demand(
    start >= 0 && start <= end && end <= bytes.length(),
    "invalid byte extent",
  )
  { bytes, pos: start, end, big, limits, }
}

///|
fn Reader::take(self : Reader, size : Int32) -> Bytes raise TdmsError {
  demand(size >= 0 && size <= self.end - self.pos, "truncated payload")
  let start = self.pos
  self.pos += size
  Bytes::makei(size, i => self.bytes[start + i])
}

///|
fn Reader::uint(self : Reader, width : Int32) -> UInt64 raise TdmsError {
  demand(
    width >= 1 && width <= 8 && width <= self.end - self.pos,
    "truncated integer",
  )
  let mut value = 0UL
  for i = 0; i < width; i = i + 1 {
    let shift = if self.big { (width - i - 1) * 8 } else { i * 8 }
    value = value | (self.bytes[self.pos + i].to_uint64() << shift)
  }
  self.pos += width
  value
}

///|
fn Reader::u32(self : Reader) -> UInt32 raise TdmsError {
  self.uint(4).to_uint()
}

///|
fn Reader::bounded(
  self : Reader,
  width : Int32,
  bound : Int32,
  label : String,
) -> Int32 raise TdmsError {
  let n = self.uint(width)
  if n > bound.to_uint64() {
    raise Budget(label)
  }
  n.to_int()
}

///|
fn Reader::signed(self : Reader, width : Int32) -> Int64 raise TdmsError {
  let n = self.uint(width)
  if width == 8 {
    return n.reinterpret_as_int64()
  }
  let sign = 1UL << (width * 8 - 1)
  if (n & sign) == 0UL {
    n.reinterpret_as_int64()
  } else {
    n.reinterpret_as_int64() - (1L << (width * 8))
  }
}

///|
fn Reader::string(self : Reader) -> String raise TdmsError {
  let size = self.bounded(4, self.limits.max_string_bytes, "string bytes")
  let b = self.take(size)
  @utf8.decode(b) catch {
    _ => raise Invalid("invalid UTF-8")
  }
}

///|
priv struct Writer {
  bytes : Array[Byte]
  big : Bool
  limits : Limits
}

///|
fn Writer::new(big : Bool, limits : Limits) -> Writer {
  { bytes: [], big, limits, }
}

///|
fn Writer::room(self : Writer, n : Int32) -> Unit raise TdmsError {
  if n < 0 || self.bytes.length() > self.limits.max_bytes - n {
    raise Budget("output bytes")
  }
}

///|
fn Writer::uint(
  self : Writer,
  value : UInt64,
  width : Int32,
) -> Unit raise TdmsError {
  self.room(width)
  for i = 0; i < width; i = i + 1 {
    let shift = if self.big { (width - i - 1) * 8 } else { i * 8 }
    self.bytes.push(((value >> shift) & 255UL).to_byte())
  }
}

///|
fn Writer::append(self : Writer, bytes : Bytes) -> Unit raise TdmsError {
  self.room(bytes.length())
  for b in bytes {
    self.bytes.push(b)
  }
}

///|
fn Writer::finish(self : Writer) -> Bytes {
  Bytes::makei(self.bytes.length(), i => self.bytes[i])
}

///|
fn Writer::string(self : Writer, value : String) -> Unit raise TdmsError {
  let bytes = @utf8.encode(value)
  if bytes.length() > self.limits.max_string_bytes {
    raise Budget("string bytes")
  }
  self.uint(bytes.length().to_uint64(), 4)
  self.append(bytes)
}

///|
fn checked_product(
  a : Int32,
  b : Int32,
  bound : Int32,
) -> Int32 raise TdmsError {
  demand(a >= 0 && b >= 0 && bound >= 0, "negative extent")
  if a > 0 && b > bound / a {
    raise Budget("extent product")
  }
  a * b
}

///|
pub fn decode_hex(
  text : String,
  limits~ : Limits = Limits::default(),
) -> Bytes raise TdmsError {
  limits.validate()
  demand(text.length() % 2 == 0, "odd hexadecimal length")
  if text.length() / 2 > limits.max_bytes {
    raise Budget("hexadecimal bytes")
  }
  let out : Array[Byte] = []
  let mut high = 0
  for i = 0; i < text.length(); i = i + 1 {
    let c = text.code_unit_at(i).to_int()
    let n = if c >= 48 && c <= 57 {
      c - 48
    } else if c >= 65 && c <= 70 {
      c - 55
    } else if c >= 97 && c <= 102 {
      c - 87
    } else {
      raise Invalid("invalid hexadecimal character")
    }
    if i % 2 == 0 {
      high = n
    } else {
      out.push((high * 16 + n).to_byte())
    }
  }
  Bytes::makei(out.length(), i => out[i])
}

///|
pub fn encode_hex(bytes : Bytes) -> String {
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let out : Array[Char] = []
  for b in bytes {
    out.push(digits[b.to_int() / 16])
    out.push(digits[b.to_int() % 16])
  }
  String::from_array(out)
}
