package chipyard

import org.chipsalliance.cde.config.Config

import gemmini._
import gemmini.Arithmetic.SIntArithmetic

// Gemmini sized for the PYNQ-Z2 (XC7Z020): 8x8 array, 64 KB scratchpad, 32 KB
// accumulator (docs/plan.md section 3.2). Everything else is the upstream
// defaultConfig, so differences against GemminiRocketConfig come only from the
// array and SRAM sizes.
object Gemmini8x8 {
  val arrayConfig = GemminiConfigs.defaultConfig.copy(
    meshRows = 8,
    meshColumns = 8,
    sp_capacity = CapacityInKilobytes(64),
    acc_capacity = CapacityInKilobytes(32))
}

// Same SoC as GemminiRocketConfig (one huge Rocket core, 128-bit system bus).
class Gemmini8x8RocketConfig extends Config(
  new gemmini.DefaultGemminiConfig(Gemmini8x8.arrayConfig) ++
  new freechips.rocketchip.rocket.WithNHugeCores(1) ++
  new chipyard.config.WithSystemBusWidth(128) ++
  new chipyard.config.AbstractConfig)
