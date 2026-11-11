///|
fn main raise {
  let source : @tdms.Document = {
    objects: [
      @tdms.DataObject::new(@tdms.ObjectPath::root(), properties=[
        @tdms.Property::{
          name: "title",
          kind: @tdms.Text,
          value: @tdms.Textual("bench"),
        },
      ]),
      @tdms.DataObject::new(@tdms.ObjectPath::group("run")),
      @tdms.DataObject::new(
        @tdms.ObjectPath::channel("run", "voltage"),
        kind=@tdms.F64,
        values=[@tdms.Real(1.25), @tdms.Real(1.5), @tdms.Real(1.75)],
        properties=[
          @tdms.Property::{
            name: "unit_string",
            kind: @tdms.Text,
            value: @tdms.Textual("V"),
          },
        ],
      ),
    ],
  }
  let encoded = @tdms.write(source)
  let decoded = @tdms.read(encoded)
  let channel = decoded
    .find(@tdms.ObjectPath::channel("run", "voltage"))
    .unwrap()
  if channel.values.length() != 3 || channel.property("unit_string") is None {
    fail("ingest round trip lost typed channel data")
  }
  println("ingest: TDMS bytes decoded with 3 voltage samples")
}
