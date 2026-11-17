///|
priv enum ScaleOp {
  Scaler(UInt32)
  Pass(UInt32)
  Linear(UInt32, Double, Double)
  Polynomial(UInt32, Array[Double])
  Table(UInt32, Array[Double], Array[Double])
  Add(UInt32, UInt32)
  Subtract(UInt32, UInt32)
}

///|
fn scale_number(obj : DataObject, key : String) -> Double raise TdmsError {
  let v = match obj.property(key) {
    Some(v) => v.as_double()
    None => raise Invalid("missing scale property: " + key)
  }
  demand(finite(v), "nonfinite scale coefficient")
  v
}

///|
fn scale_uint(
  obj : DataObject,
  key : String,
  fallback : UInt32?,
) -> UInt32 raise TdmsError {
  let v = match obj.property(key) {
    Some(v) => v.as_double()
    None =>
      match fallback {
        Some(n) => return n
        None => raise Invalid("missing scale property: " + key)
      }
  }
  demand(
    finite(v) && v >= 0.0 && v <= 4294967295.0 && v == v.trunc(),
    "invalid scale index or size",
  )
  v.to_uint()
}

///|
fn scale_count(obj : DataObject) -> Int32 raise TdmsError {
  if obj.property("NI_Scaling_Status") == Some(Textual("scaled")) {
    return 0
  }
  let mut inferred = 0
  for p in obj.properties {
    if p.name.has_prefix("NI_Scale[") && p.name.has_suffix("]_Scale_Type") {
      let pieces = p.name.split("[").to_array()
      let pieces = pieces[1].split("]").to_array()
      let n = @string.parse_int(pieces[0]) catch {
        _ => raise Invalid("invalid scale property index")
      }
      demand(n >= 0 && n < 128, "scale index exceeds graph bound")
      inferred = if inferred > n { inferred } else { n + 1 }
    }
  }
  let n = scale_uint(
    obj,
    "NI_Number_Of_Scales",
    Some(inferred.reinterpret_as_uint()),
  )
  demand(
    n <= 128U && n >= inferred.reinterpret_as_uint(),
    "scale graph size mismatch or exceeds 128 nodes",
  )
  n.reinterpret_as_int()
}

///|
fn scale_owner(
  doc : Document,
  channel : DataObject,
) -> DataObject? raise TdmsError {
  if scale_count(channel) > 0 {
    return Some(channel)
  }
  if channel.property("NI_Scaling_Status") == Some(Textual("scaled")) {
    return None
  }
  if channel.path.parts.length() == 2 {
    let group : ObjectPath = { parts: [channel.path.parts[0]], }
    if doc.find(group) is Some(g) {
      if scale_count(g) > 0 {
        return Some(g)
      }
    }
  }
  if doc.find({ parts: [], }) is Some(root) {
    if scale_count(root) > 0 {
      return Some(root)
    }
  }
  None
}

///|
fn scale_plan(owner : DataObject) -> Array[ScaleOp] raise TdmsError {
  let plan : Array[ScaleOp] = []
  for i = 0; i < scale_count(owner); i = i + 1 {
    let prefix = "NI_Scale[\{i}]_"
    let kind = owner.property(prefix + "Scale_Type")
    let op : ScaleOp = match kind {
      None => Scaler(i.reinterpret_as_uint())
      Some(Textual(t)) => {
        let input = if t == "Add" || t == "Subtract" {
          0U
        } else {
          scale_uint(owner, prefix + t + "_Input_Source", Some(0xffffffffU))
        }
        match t {
          "Linear" =>
            Linear(
              input,
              scale_number(owner, prefix + "Linear_Slope"),
              scale_number(owner, prefix + "Linear_Y_Intercept"),
            )
          "AdvancedAPI" => Pass(input)
          "Polynomial" => {
            let n = scale_uint(
              owner,
              prefix + "Polynomial_Coefficients_Size",
              Some(4U),
            )
            demand(n > 0U && n <= 128U, "polynomial coefficient count")
            let coefficients : Array[Double] = []
            for j = 0; j < n.reinterpret_as_int(); j = j + 1 {
              coefficients.push(
                scale_number(owner, prefix + "Polynomial_Coefficients[\{j}]"),
              )
            }
            Polynomial(input, coefficients)
          }
          "Table" => {
            let n = scale_uint(owner, prefix + "Table_Scaled_Values_Size", None)
            demand(
              n >= 2U &&
              n <= 4096U &&
              n ==
              scale_uint(owner, prefix + "Table_Pre_Scaled_Values_Size", None),
              "invalid table size",
            )
            let xs : Array[Double] = []
            let ys : Array[Double] = []
            for j = 0; j < n.reinterpret_as_int(); j = j + 1 {
              xs.push(scale_number(owner, prefix + "Table_Scaled_Values[\{j}]"))
              ys.push(
                scale_number(owner, prefix + "Table_Pre_Scaled_Values[\{j}]"),
              )
            }
            if xs[0] > xs[1] {
              for j = 0; j < xs.length() / 2; j = j + 1 {
                let k = xs.length() - 1 - j
                let x = xs[j]
                let y = ys[j]
                xs[j] = xs[k]
                xs[k] = x
                ys[j] = ys[k]
                ys[k] = y
              }
            }
            for j = 1; j < xs.length(); j = j + 1 {
              demand(xs[j] > xs[j - 1], "nonmonotone scale table")
            }
            Table(input, xs, ys)
          }
          "Add" | "Subtract" => {
            let left = scale_uint(
              owner,
              prefix + t + "_Left_Operand_Input_Source",
              None,
            )
            let right = scale_uint(
              owner,
              prefix + t + "_Right_Operand_Input_Source",
              None,
            )
            if t == "Add" {
              Add(left, right)
            } else {
              Subtract(left, right)
            }
          }
          _ => raise Unsupported("NI scale type: " + t)
        }
      }
      _ => raise Invalid("scale type must be text")
    }
    plan.push(op)
  }
  plan
}

///|
fn ScaleOp::inputs(self : ScaleOp) -> Array[UInt32] {
  match self {
    Scaler(_) => []
    Pass(i) | Linear(i, _, _) | Polynomial(i, _) | Table(i, _, _) => [i]
    Add(l, r) | Subtract(l, r) => [l, r]
  }
}

///|
fn table_value(x : Double, xs : Array[Double], ys : Array[Double]) -> Double {
  if x.is_nan() {
    return x
  }
  if x <= xs[0] {
    return ys[0]
  }
  let last = xs.length() - 1
  if x >= xs[last] {
    return ys[last]
  }
  let mut lo = 0
  let mut hi = last
  while hi - lo > 1 {
    let mid = (lo + hi) / 2
    if x < xs[mid] {
      hi = mid
    } else {
      lo = mid
    }
  }
  ys[lo] + (x - xs[lo]) / (xs[hi] - xs[lo]) * (ys[hi] - ys[lo])
}

///|
fn compute_scales(
  obj : DataObject,
  daq : DaqChannel?,
  plan : Array[ScaleOp],
  limits : Limits,
) -> (DataType?, Array[Value]) raise TdmsError {
  if plan.is_empty() {
    if daq is Some(d) {
      demand(
        d.native_type is Some(_),
        "raw DAQmx samples require explicit scaling metadata",
      )
      demand(
        d.scalers.length() == 1,
        "multiple DAQmx scalers require a scale graph",
      )
      return (Some(d.scalers[0].kind), d.scalers[0].values.map(v => v))
    }
    return (obj.kind, obj.values.map(v => v))
  }
  let ordinary = match daq {
    Some(d) => if d.native_type is Some(_) { d.scalers[0].values } else { [] }
    None => obj.values
  }
  let cache : Array[Array[Value]?] = Array::make(plan.length(), None)
  let mut remaining = plan.length()
  let mut allocated = 0
  while remaining > 0 {
    let before = remaining
    for i = 0; i < plan.length(); i = i + 1 {
      if cache[i] is Some(_) {
        continue
      }
      let op = plan[i]
      let mut ready = true
      for source in op.inputs() {
        if source == 0xffffffffU {
          demand(
            daq is None || daq.unwrap().native_type is Some(_),
            "raw sentinel is not a DAQmx scaler",
          )
        } else {
          demand(
            source < plan.length().reinterpret_as_uint(),
            "scale source out of range",
          )
          if cache[source.reinterpret_as_int()] is None {
            ready = false
          }
        }
      }
      if !ready {
        continue
      }
      let source = fn(id : UInt32) -> Array[Value] {
        if id == 0xffffffffU {
          ordinary
        } else {
          cache[id.reinterpret_as_int()].unwrap()
        }
      }
      let values = match op {
        Scaler(id) => {
          let d = match daq {
            Some(d) => d
            None => raise Invalid("scaler reference on ordinary channel")
          }
          match d.scalers.iter().find_first(s => s.id == id) {
            Some(s) => s.values
            None => raise Invalid("missing DAQmx scaler")
          }
        }
        Pass(id) => source(id)
        Linear(id, slope, intercept) =>
          source(id).map(v => Real(v.as_double() * slope + intercept))
        Polynomial(id, coefficients) =>
          source(id).map(v => {
            let x = v.as_double()
            let mut y = 0.0
            for j = coefficients.length() - 1; j >= 0; j = j - 1 {
              y = y * x + coefficients[j]
            }
            Real(y)
          })
        Table(id, xs, ys) =>
          source(id).map(v => Real(table_value(v.as_double(), xs, ys)))
        Add(l, r) | Subtract(l, r) => {
          let a = source(l)
          let b = source(r)
          demand(
            a.length() == b.length(),
            "unequal scale operand sample counts",
          )
          Array::makei(a.length(), j => {
            let x = a[j].as_double()
            let y = b[j].as_double()
            Real(if op is Add(_, _) { x + y } else { y - x })
          })
        }
      }
      demand(
        values.length() <= limits.max_samples - allocated,
        "scale graph intermediate sample budget",
      )
      allocated += values.length()
      cache[i] = Some(values)
      remaining -= 1
    }
    demand(remaining < before, "cyclic scale graph")
  }
  let values = cache[plan.length() - 1].unwrap().map(v => v)
  let kind = match plan[plan.length() - 1] {
    Scaler(id) =>
      Some(
        daq.unwrap().scalers.iter().find_first(s => s.id == id).unwrap().kind,
      )
    Pass(_) =>
      if values.is_empty() {
        obj.kind
      } else {
        match values[0] {
          Signed(_) => Some(I64)
          Unsigned(_) => Some(U64)
          Real(_) => Some(F64)
          Instant(_) => Some(Time)
          _ => obj.kind
        }
      }
    _ => Some(F64)
  }
  (kind, values)
}

///|
/// Interpret NI scaling explicitly and mark the output as already scaled.
/// Floating point calculations may round integers larger than 2^53; raw streams are retained by the Acquisition.
pub fn Acquisition::physical(
  self : Acquisition,
  limits~ : Limits = Limits::default(),
) -> Document raise TdmsError {
  self.validate(limits)
  let result = Document::new()
  for obj in self.metadata.objects {
    let copy = copy_object(obj, 0, obj.values.length())
    if obj.path.parts.length() == 2 {
      let owner = scale_owner(self.metadata, obj)
      let plan = match owner {
        Some(o) => scale_plan(o)
        None => []
      }
      let (kind, values) = compute_scales(
        obj,
        self.raw_channel(obj.path),
        plan,
        limits,
      )
      copy.kind = kind
      copy.values.clear()
      for v in values {
        copy.values.push(v)
      }
      if !plan.is_empty() || self.raw_channel(obj.path) is Some(_) {
        set_property(copy, {
          name: "NI_Scaling_Status",
          kind: Text,
          value: Textual("scaled"),
        })
      }
    }
    result.objects.push(copy)
  }
  result.validate(limits)
  result
}
