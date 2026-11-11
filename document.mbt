///|
pub(all) struct DataObject {
  path : ObjectPath
  properties : Array[Property]
  mut kind : DataType?
  values : Array[Value]
} derive(Eq, Debug)

///|
pub(all) struct Document {
  objects : Array[DataObject]
} derive(Eq, Debug)

///|
pub fn Document::new() -> Document {
  { objects: [], }
}

///|
pub fn DataObject::new(
  path : ObjectPath,
  kind? : DataType,
  values~ : Array[Value] = [],
  properties~ : Array[Property] = [],
) -> DataObject {
  { path, kind, values, properties, }
}

///|
pub fn Document::find(self : Document, path : ObjectPath) -> DataObject? {
  for o in self.objects {
    if o.path == path {
      return Some(o)
    }
  }
  None
}

///|
pub fn DataObject::property(self : DataObject, name : String) -> Value? {
  for p in self.properties {
    if p.name == name {
      return Some(p.value)
    }
  }
  None
}

///|
fn set_property(obj : DataObject, p : Property) -> Unit {
  for i = 0; i < obj.properties.length(); i = i + 1 {
    if obj.properties[i].name == p.name {
      obj.properties[i] = p
      return
    }
  }
  obj.properties.push(p)
}

///|
fn Document::validate(self : Document, limits : Limits) -> Unit raise TdmsError {
  limits.validate()
  if self.objects.length() > limits.max_objects {
    raise Budget("objects")
  }
  let paths : Map[String, Bool] = Map([])
  let mut properties = 0
  let mut samples = 0
  for obj in self.objects {
    let path = obj.path.text()
    demand(!paths.contains(path), "duplicate object path")
    paths[path] = true
    demand(
      obj.path.parts.length() == 2 || obj.kind is None,
      "only channels may have data types",
    )
    demand(
      obj.kind is Some(_) || obj.values.is_empty(),
      "untyped channel samples",
    )
    let names : Map[String, Bool] = Map([])
    for p in obj.properties {
      demand(
        !p.name.is_empty() && !names.contains(p.name),
        "empty or duplicate property name",
      )
      names[p.name] = true
      p.value.validate(p.kind)
      if properties >= limits.max_properties {
        raise Budget("properties")
      }
      properties += 1
    }
    if obj.values.length() > limits.max_samples - samples {
      raise Budget("samples")
    }
    samples += obj.values.length()
    if obj.kind is Some(kind) {
      for v in obj.values {
        v.validate(kind)
      }
    }
  }
}

///|
pub extend DataObject with Eq::{equal, not_equal}

///|
pub extend DataObject with @debug.Debug::{to_repr}

///|
pub extend Document with Eq::{equal, not_equal}

///|
pub extend Document with @debug.Debug::{to_repr}
