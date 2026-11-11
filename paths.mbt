///|
pub(all) struct ObjectPath {
  parts : Array[String]
} derive(Eq, Debug)

///|
pub fn ObjectPath::root() -> ObjectPath {
  { parts: [], }
}

///|
pub fn ObjectPath::group(name : String) -> ObjectPath {
  { parts: [name], }
}

///|
pub fn ObjectPath::channel(group : String, name : String) -> ObjectPath {
  { parts: [group, name], }
}

///|
pub fn ObjectPath::text(self : ObjectPath) -> String raise TdmsError {
  demand(self.parts.length() <= 2, "path exceeds three-level hierarchy")
  if self.parts.is_empty() {
    return "/"
  }
  let mut result = ""
  for part in self.parts {
    demand(!part.is_empty(), "empty object name")
    let escaped = part.replace_all(old="'", new="''")
    result += "/'" + escaped + "'"
  }
  result
}

///|
pub fn parse_path(text : String) -> ObjectPath raise TdmsError {
  if text == "/" {
    return ObjectPath::root()
  }
  let chars = text.iter().to_array()
  let parts : Array[String] = []
  let mut pos = 0
  while pos < chars.length() {
    demand(
      parts.length() < 2 &&
      pos + 1 < chars.length() &&
      chars[pos] == '/' &&
      chars[pos + 1] == '\'',
      "invalid quoted object path",
    )
    pos += 2
    let name : Array[Char] = []
    let mut closed = false
    while pos < chars.length() {
      let c = chars[pos]
      pos += 1
      if c == '\'' {
        if pos < chars.length() && chars[pos] == '\'' {
          name.push('\'')
          pos += 1
        } else {
          closed = true
          break
        }
      } else {
        name.push(c)
      }
    }
    demand(closed && !name.is_empty(), "unterminated or empty object name")
    parts.push(String::from_array(name))
  }
  demand(!parts.is_empty(), "empty object path")
  { parts, }
}

///|
pub extend ObjectPath with Eq::{equal, not_equal}

///|
pub extend ObjectPath with @debug.Debug::{to_repr}
