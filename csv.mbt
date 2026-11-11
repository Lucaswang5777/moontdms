///|
fn csv_quote(text : String) -> String {
  "\"" + text.replace_all(old="\"", new="\"\"") + "\""
}

///|
pub fn Value::text(self : Value) -> String {
  match self {
    Signed(n) => n.to_string()
    Unsigned(n) => n.to_string()
    Real(n) => n.to_string()
    Textual(s) => s
    Logical(b) => if b { "true" } else { "false" }
    Instant(t) => t.seconds.to_string() + ":" + t.fractions.to_string()
  }
}

///|
pub fn Document::csv(
  self : Document,
  waveform_time~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> String raise TdmsError {
  self.validate(limits)
  let out = Writer::new(false, limits)
  out.append(b"group,channel,index,value,unit,relative_time\r\n")
  for obj in self.objects {
    if obj.path.parts.length() != 2 {
      continue
    }
    let group = csv_quote(obj.path.parts[0])
    let name = csv_quote(obj.path.parts[1])
    let unit = match obj.property("unit_string") {
      Some(Textual(s)) => csv_quote(s)
      Some(_) => raise Invalid("unit_string is not text")
      None => "\"\""
    }
    let axis = if waveform_time { Some(obj.waveform()) } else { None }
    for i = 0; i < obj.values.length(); i = i + 1 {
      let relative = match axis {
        Some(a) => a.at(i).to_string()
        None => ""
      }
      let row = group +
        "," +
        name +
        "," +
        i.to_string() +
        "," +
        csv_quote(obj.values[i].text()) +
        "," +
        unit +
        "," +
        relative +
        "\r\n"
      out.append(@utf8.encode(row))
    }
  }
  @utf8.decode(out.finish()) catch {
    _ => raise Invalid("internal CSV UTF-8 failure")
  }
}
