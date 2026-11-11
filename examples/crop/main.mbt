///|
fn main raise {
  let channel = @tdms.DataObject::new(
    @tdms.ObjectPath::channel("run", "temperature"),
    kind=@tdms.F64,
    values=[
      @tdms.Real(20.0),
      @tdms.Real(20.5),
      @tdms.Real(21.0),
      @tdms.Real(21.5),
    ],
    properties=[
      @tdms.Property::{
        name: "wf_increment",
        kind: @tdms.F64,
        value: @tdms.Real(0.25),
      },
      @tdms.Property::{
        name: "wf_start_offset",
        kind: @tdms.F64,
        value: @tdms.Real(10.0),
      },
    ],
  )
  let source : @tdms.Document = {
    objects: [@tdms.DataObject::new(@tdms.ObjectPath::group("run")), channel],
  }
  let selected = source.select(
    [@tdms.ObjectPath::channel("run", "temperature")],
    start=1,
    end=3,
  )
  let cropped = selected
    .find(@tdms.ObjectPath::channel("run", "temperature"))
    .unwrap()
  let axis = cropped.waveform()
  if cropped.values.length() != 2 || axis.at(0) != 10.25 || axis.at(1) != 10.5 {
    fail("crop did not preserve waveform time")
  }
  let restored = @tdms.read(@tdms.write(selected))
  if restored.find(@tdms.ObjectPath::channel("run", "temperature")).unwrap().values.length() !=
    2 {
    fail("cropped TDMS rewrite changed sample count")
  }
  println("crop: selected samples 1..3 and shifted waveform offset")
}
