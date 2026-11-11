///|
pub(all) struct Summary {
  total : Int32
  finite_count : Int32
  nonfinite_count : Int32
  minimum : Double?
  maximum : Double?
  mean : Double?
  population_variance : Double?
  rms : Double?
} derive(Eq, Debug)

///|
pub fn DataObject::summary(self : DataObject) -> Summary raise TdmsError {
  demand(
    self.kind is Some(k) && k != Text && k != Time,
    "summary requires a numeric channel",
  )
  let mut n = 0
  let mut lo = 1.0 / 0.0
  let mut hi = -(1.0 / 0.0)
  let mut mean = 0.0
  let mut m2 = 0.0
  let mut scale = 0.0
  let mut squares = 0.0
  for value in self.values {
    let x = value.as_double()
    if !finite(x) {
      continue
    }
    n += 1
    if x < lo {
      lo = x
    }
    if x > hi {
      hi = x
    }
    let delta = x - mean
    mean += delta / n.to_double()
    m2 += delta * (x - mean)
    demand(finite(mean) && finite(m2), "numeric summary overflow")
    let magnitude = x.abs()
    if magnitude > 0.0 {
      if scale < magnitude {
        let ratio = scale / magnitude
        squares = 1.0 + squares * ratio * ratio
        scale = magnitude
      } else {
        let ratio = magnitude / scale
        squares += ratio * ratio
      }
    }
  }
  let has = n > 0
  {
    total: self.values.length(),
    finite_count: n,
    nonfinite_count: self.values.length() - n,
    minimum: if has {
      Some(lo)
    } else {
      None
    },
    maximum: if has {
      Some(hi)
    } else {
      None
    },
    mean: if has {
      Some(mean)
    } else {
      None
    },
    population_variance: if has {
      Some(m2 / n.to_double())
    } else {
      None
    },
    rms: if has {
      Some(scale * (squares / n.to_double()).sqrt())
    } else {
      None
    },
  }
}

///|
pub extend Summary with Eq::{equal, not_equal}

///|
pub extend Summary with @debug.Debug::{to_repr}
