///|
fn Reader::scalar(self : Reader, kind : DataType) -> Value raise TdmsError {
  match kind {
    I8 => Signed(self.signed(1))
    I16 => Signed(self.signed(2))
    I32 => Signed(self.signed(4))
    I64 => Signed(self.signed(8))
    U8 => Unsigned(self.uint(1))
    U16 => Unsigned(self.uint(2))
    U32 => Unsigned(self.uint(4))
    U64 => Unsigned(self.uint(8))
    F32 =>
      Real(
        Float::reinterpret_from_int(self.u32().reinterpret_as_int()).to_double(),
      )
    F64 => Real(self.uint(8).reinterpret_as_double())
    Text => Textual(self.string())
    Boolean => {
      let n = self.uint(1)
      demand(n <= 1UL, "invalid boolean value")
      Logical(n == 1UL)
    }
    Time => {
      let fractions = self.uint(8)
      let seconds = self.signed(8)
      Instant({ seconds, fractions, })
    }
  }
}

///|
fn Writer::scalar(
  self : Writer,
  kind : DataType,
  value : Value,
) -> Unit raise TdmsError {
  value.validate(kind)
  match value {
    Signed(n) => self.uint(n.reinterpret_as_uint64(), kind.width().unwrap())
    Unsigned(n) => self.uint(n, kind.width().unwrap())
    Real(n) =>
      if kind == F32 {
        self.uint(
          Float::from_double(n)
          .reinterpret_as_int()
          .reinterpret_as_uint()
          .to_uint64(),
          4,
        )
      } else {
        self.uint(n.reinterpret_as_uint64(), 8)
      }
    Textual(s) => self.string(s)
    Logical(b) => self.uint(if b { 1UL } else { 0UL }, 1)
    Instant(t) => {
      self.uint(t.fractions, 8)
      self.uint(t.seconds.reinterpret_as_uint64(), 8)
    }
  }
}

///|
fn read_property(r : Reader) -> Property raise TdmsError {
  let name = r.string()
  demand(!name.is_empty(), "empty property name")
  let kind = data_type(r.u32())
  let value = r.scalar(kind)
  { name, kind, value, }
}

///|
fn write_property(w : Writer, p : Property) -> Unit raise TdmsError {
  demand(!p.name.is_empty(), "empty property name")
  w.string(p.name)
  w.uint(p.kind.code().to_uint64(), 4)
  w.scalar(p.kind, p.value)
}
