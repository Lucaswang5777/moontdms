///|
fn main raise {
  // Independently assembled fixture, identical to fixtures/daqmx/voltage.tdms.
  let bytes = @tdms.decode_hex(
    "5444536d8e0000006912000073010000000000006b0100000000000001000000100000002f27616371272f27766f6c746167652769120000ffffffff010000000400000000000000010000000300000000000000000000000000000000000000010000000200000008000000130000004e495f4e756d6265725f4f665f5363616c65730700000002000000160000004e495f5363616c655b315d5f5363616c655f5479706520000000060000004c696e6561721f0000004e495f5363616c655b315d5f4c696e6561725f496e7075745f536f757263650700000000000000180000004e495f5363616c655b315d5f4c696e6561725f536c6f70650a000000000000000000d03f1e0000004e495f5363616c655b315d5f4c696e6561725f595f496e746572636570740a000000000000000000f83f0b000000756e69745f737472696e672000000001000000560c00000077665f696e6372656d656e740a0000007b14ae47e17a843f0f00000077665f73746172745f6f66667365740a000000000000000000e03f9cff00006400c800",
  )
  let path = @tdms.ObjectPath::channel("acq", "voltage")
  let source = @tdms.read_acquisition(bytes)
  let raw = source.raw_channel(path).unwrap().scalers[0].values
  if raw !=
    [
      @tdms.Signed(-100L),
      @tdms.Signed(0L),
      @tdms.Signed(100L),
      @tdms.Signed(200L),
    ] {
    fail("raw counts changed")
  }
  let physical = source.physical().find(path).unwrap()
  if physical.values !=
    [@tdms.Real(-23.5), @tdms.Real(1.5), @tdms.Real(26.5), @tdms.Real(51.5)] {
    fail("physical conversion failed")
  }
  let selected = source.select([path], start=1, end=3)
  let rewritten = @tdms.read_acquisition(selected.write())
  if rewritten.raw_channel(path).unwrap().scalers[0].values !=
    [@tdms.Signed(0L), @tdms.Signed(100L)] {
    fail("crop lost raw counts")
  }
  let cropped = rewritten.physical().find(path).unwrap()
  if cropped.values != [@tdms.Real(1.5), @tdms.Real(26.5)] ||
    cropped.waveform().at(0) != 0.51 {
    fail("crop lost physical values or timing")
  }
  let normalized = @tdms.read_acquisition(@tdms.write(rewritten.physical())).physical()
  if normalized.find(path).unwrap().values != cropped.values {
    fail("physical output scaled twice")
  }
  println(
    "daqmx: raw [-100,0,100,200] -> [-23.5,1.5,26.5,51.5] V; crop [1,3) -> raw [0,100], [1.5,26.5] V, offset 0.51",
  )
}
