///|
fn main raise {
  let channel = @tdms.DataObject::new(
    @tdms.ObjectPath::channel("run", "current"),
    kind=@tdms.F64,
    values=[@tdms.Real(2.0), @tdms.Real(4.0), @tdms.Real(6.0)],
    properties=[
      @tdms.Property::{
        name: "unit_string",
        kind: @tdms.Text,
        value: @tdms.Textual("A"),
      },
    ],
  )
  let doc : @tdms.Document = {
    objects: [@tdms.DataObject::new(@tdms.ObjectPath::group("run")), channel],
  }
  let summary = doc
    .find(@tdms.ObjectPath::channel("run", "current"))
    .unwrap()
    .summary()
  if summary.mean != Some(4.0) ||
    summary.minimum != Some(2.0) ||
    summary.maximum != Some(6.0) {
    fail("summary did not calculate expected current statistics")
  }
  let csv = doc.csv()
  if !csv.contains("current") || !csv.contains("2") || !csv.contains("A") {
    fail("CSV report omitted channel data")
  }
  println("report: mean=4, min=2, max=6; CSV rows exported")
}
