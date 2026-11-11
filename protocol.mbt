///|
fn json_field(j : Json, key : String) -> Json raise TdmsError {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(v) => v
        None => raise Invalid("missing JSON field: " + key)
      }
    _ => raise Invalid("expected JSON object")
  }
}

///|
fn json_optional(j : Json, key : String) -> Json? raise TdmsError {
  match j {
    Object(m) => m.get(key)
    _ => raise Invalid("expected JSON object")
  }
}

///|
fn json_text(j : Json) -> String raise TdmsError {
  match j {
    String(s) => s
    _ => raise Invalid("expected JSON string")
  }
}

///|
fn json_array(j : Json) -> Array[Json] raise TdmsError {
  match j {
    Array(a) => a
    _ => raise Invalid("expected JSON array")
  }
}

///|
fn json_integer(j : Json) -> Int32 raise TdmsError {
  match j {
    Number(n, ..) => {
      demand(
        finite(n) && n >= 0.0 && n <= 2147483647.0 && n == n.trunc(),
        "expected bounded nonnegative integer",
      )
      n.to_int()
    }
    _ => raise Invalid("expected JSON integer")
  }
}

///|
fn json_bool(j : Json) -> Bool raise TdmsError {
  match j {
    True => true
    False => false
    _ => raise Invalid("expected JSON boolean")
  }
}

///|
fn value_to_json(v : Value) -> Json {
  match v {
    Signed(n) => Json::string(n.to_string())
    Unsigned(n) => Json::string(n.to_string())
    Textual(s) => Json::string(s)
    Logical(b) => Json::boolean(b)
    Real(n) =>
      if n.is_nan() {
        Json::string("NaN")
      } else if n.is_inf() {
        Json::string(if n > 0.0 { "Infinity" } else { "-Infinity" })
      } else {
        Json::number(n)
      }
    Instant(t) =>
      Json::object({
        "seconds": Json::string(t.seconds.to_string()),
        "fractions": Json::string(t.fractions.to_string()),
      })
  }
}

///|
fn value_from_json(j : Json, kind : DataType) -> Value raise TdmsError {
  let value : Value = match kind {
    I8 | I16 | I32 | I64 => {
      let s = json_text(j)
      let n = @string.parse_int64(s) catch {
        _ => raise Invalid("invalid signed integer string")
      }
      Signed(n)
    }
    U8 | U16 | U32 | U64 => {
      let s = json_text(j)
      let n = @string.parse_uint64(s) catch {
        _ => raise Invalid("invalid unsigned integer string")
      }
      Unsigned(n)
    }
    F32 | F64 =>
      match j {
        Number(n, ..) => Real(n)
        String("NaN") => Real(0.0 / 0.0)
        String("Infinity") => Real(1.0 / 0.0)
        String("-Infinity") => Real(-1.0 / 0.0)
        _ => raise Invalid("expected float or named nonfinite value")
      }
    Text => Textual(json_text(j))
    Boolean => Logical(json_bool(j))
    Time => {
      let seconds_text = json_text(json_field(j, "seconds"))
      let fraction_text = json_text(json_field(j, "fractions"))
      let seconds = @string.parse_int64(seconds_text) catch {
        _ => raise Invalid("invalid timestamp seconds")
      }
      let fractions = @string.parse_uint64(fraction_text) catch {
        _ => raise Invalid("invalid timestamp fractions")
      }
      Instant({ seconds, fractions, })
    }
  }
  value.validate(kind)
  value
}

///|
fn object_to_json(obj : DataObject) -> Json raise TdmsError {
  let properties = obj.properties.map(p => {
    Json::object({
      "name": Json::string(p.name),
      "type": Json::number(p.kind.code().to_double()),
      "value": value_to_json(p.value),
    })
  })
  Json::object({
    "path": Json::string(obj.path.text()),
    "type": match obj.kind {
      Some(k) => Json::number(k.code().to_double())
      None => Json::null()
    },
    "values": Json::array(obj.values.map(value_to_json)),
    "properties": Json::array(properties),
  })
}

///|
fn document_to_json(doc : Document) -> Json raise TdmsError {
  let objects : Array[Json] = []
  for obj in doc.objects {
    objects.push(object_to_json(obj))
  }
  Json::array(objects)
}

///|
fn document_from_json(j : Json, limits : Limits) -> Document raise TdmsError {
  let objects = json_array(j)
  if objects.length() > limits.max_objects {
    raise Budget("JSON objects")
  }
  let doc = Document::new()
  let mut samples = 0
  let mut property_count = 0
  for o in objects {
    let path = parse_path(json_text(json_field(o, "path")))
    let kind = match json_optional(o, "type") {
      Some(Null) | None => None
      Some(v) => Some(data_type(json_integer(v).reinterpret_as_uint()))
    }
    let values_json = match json_optional(o, "values") {
      Some(v) => json_array(v)
      None => []
    }
    if values_json.length() > limits.max_samples - samples {
      raise Budget("JSON samples")
    }
    samples += values_json.length()
    let values : Array[Value] = []
    for v in values_json {
      match kind {
        Some(k) => values.push(value_from_json(v, k))
        None => raise Invalid("values without channel type")
      }
    }
    let properties_json = match json_optional(o, "properties") {
      Some(v) => json_array(v)
      None => []
    }
    if properties_json.length() > limits.max_properties - property_count {
      raise Budget("JSON properties")
    }
    property_count += properties_json.length()
    let properties : Array[Property] = []
    for p in properties_json {
      let name = json_text(json_field(p, "name"))
      let k = data_type(
        json_integer(json_field(p, "type")).reinterpret_as_uint(),
      )
      properties.push({
        name,
        kind: k,
        value: value_from_json(json_field(p, "value"), k),
      })
    }
    doc.objects.push({ path, kind, values, properties, })
  }
  doc.validate(limits)
  doc
}

///|
fn optional_bool(request : Json, key : String) -> Bool raise TdmsError {
  match json_optional(request, key) {
    Some(v) => json_bool(v)
    None => false
  }
}

///|
pub fn process_json(
  text : String,
  limits~ : Limits = Limits::default(),
) -> String raise TdmsError {
  limits.validate()
  if text.length() > limits.max_bytes {
    raise Budget("JSON request characters")
  }
  let request = @json.parse(
    text,
    max_nesting_depth=32,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise Invalid("invalid JSON request")
  }
  demand(
    json_text(json_field(request, "protocol")) == "moontdms/1",
    "unsupported protocol",
  )
  let op = json_text(json_field(request, "op"))
  let result = if op == "encode" {
    let doc = document_from_json(json_field(request, "objects"), limits)
    let big_endian = optional_bool(request, "big_endian")
    let bytes = if optional_bool(request, "interleaved") {
      write_interleaved(doc, big_endian~, limits~)
    } else {
      write(doc, big_endian~, limits~)
    }
    Json::object({ "hex": Json::string(encode_hex(bytes)) })
  } else {
    let bytes = decode_hex(json_text(json_field(request, "hex")), limits~)
    if op == "inspect" {
      let segments = inspect(bytes, limits~).map(s => {
        Json::object({
          "offset": Json::number(s.offset.to_double()),
          "raw_offset": Json::number(s.raw_offset.to_double()),
          "end_offset": Json::number(s.end_offset.to_double()),
          "toc": Json::number(s.toc.to_double()),
          "big_endian": Json::boolean(s.big_endian),
        })
      })
      Json::object({ "segments": Json::array(segments) })
    } else {
      let doc = read(bytes, limits~)
      if op == "decode" {
        Json::object({ "objects": document_to_json(doc) })
      } else if op == "csv" {
        Json::object({
          "csv": Json::string(
            doc.csv(
              waveform_time=optional_bool(request, "waveform_time"),
              limits~,
            ),
          ),
        })
      } else if op == "select" {
        let paths_json = json_array(json_field(request, "paths"))
        let paths : Array[ObjectPath] = []
        for p in paths_json {
          paths.push(parse_path(json_text(p)))
        }
        let start = match json_optional(request, "start") {
          Some(v) => json_integer(v)
          None => 0
        }
        let end = match json_optional(request, "end") {
          Some(v) => Some(json_integer(v))
          None => None
        }
        let selected = doc.select(paths, start~, end?, limits~)
        Json::object({
          "hex": Json::string(encode_hex(write(selected, limits~))),
        })
      } else {
        raise Invalid("unknown operation")
      }
    }
  }
  Json::object({ "protocol": Json::string("moontdms/1"), "result": result }).stringify()
}
