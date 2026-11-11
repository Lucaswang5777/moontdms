///|
#cfg(target="js")
fn argument_offset() -> Int32 {
  2
}

///|
#cfg(not(target="js"))
fn argument_offset() -> Int32 {
  1
}

///|
fn main raise {
  let args = @env.args()
  if args.length() != argument_offset() + 1 {
    fail("pass one moontdms/1 JSON argument")
  }
  println(@moontdms.process_json(args[argument_offset()])) catch {
    e => {
      println(
        Json::object({ "error": Json::string(@debug.to_string(e)) }).stringify(),
      )
      fail("MoonTDMS request failed")
    }
  }
}
