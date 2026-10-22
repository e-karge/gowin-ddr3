# gowin-ddr3

A small, low-latency DDR3 controller for Gowin FPGAs, built with the open
toolchain: [yosys](https://github.com/YosysHQ/yosys),
[nextpnr-himbaechel](https://github.com/YosysHQ/nextpnr) and
[apicula](https://github.com/YosysHQ/apicula). It runs on the Tang Primer 20K
(GW2A-18) and the Tang Console 138K (GW5AST-138C).

The controller core follows nand2mario's
[ddr3-tang-primer-20k](https://github.com/nand2mario/ddr3-tang-primer-20k):
single word accesses, closed page, refresh requested by the user. It keeps to
the primitives the open toolchain supports: the PHYs capture reads without DQS
and calibrate the read delay against a test pattern, and run the DRAM in
DLL-off mode.

## Files

| file | |
|---|---|
| `ddr3/ddr3_ctrl.sv` | controller core: user interface, init → calibration → user arbitration |
| `ddr3/ddr3_cmd.sv` | command sequencer: MRS, ZQCL, REF, ACT + RD/WR with auto-precharge, DRAM timings |
| `ddr3/ddr3_init.sv` | power-up sequence and mode registers |
| `ddr3/ddr3_calib.sv` | read calibration |
| `ddr3/ddr3_phy_slow.sv` | PHY from fabric or IO block registers: CK = clk/2, both families |
| `ddr3/ddr3_phy_2to1.sv` | PHY with ODDR/IDDR and IODELAY: CK = clk; GW2A, and GW5AST-138C with `GW5A=1` |
| `ddr3/clk/ddr3_clk_2to1_tang_primer_20k.sv` | rPLL for `ddr3_phy_2to1` on the Tang Primer 20K: 108 MHz from 27 MHz |
| `ddr3/clk/ddr3_clk_2to1_tang_mega_138k.sv` | PLL for `ddr3_phy_2to1` on the Tang Console 138K: 100 MHz from 50 MHz |
| `examples/` | a memory test per board and PHY |

The files include each other as `ddr3/...`, so the repository root goes on the
include path.

## Interface

`ddr3_ctrl` takes requests while `busy` is low: a one cycle pulse on `rd`, `wr`
or `refresh` with `addr` (a word address `{bank, row, column}`) and, for
writes, `din` and the byte enables `be`. `busy` rises in the next cycle and
drops when the access is done; a read pulses `data_ready` with `dout`, and
`dout_burst` holds the whole aligned BL8 burst. Refresh is up to the user: one
every 7.8 µs on average.

The controller works on the `ce` cycles of its clock, which the PHY provides;
each covers `NPH` DRAM clocks. `init_done`, `calib_done` and `calib_fail`
report the start-up. `examples/ddr3_test.sv` shows the request handshake and
a refresh timer.

## Boards and PHYs

| board | PHY | clock | CK | transfer rate | tested |
|---|---|---|---|---|---|
| Tang Primer 20K | `ddr3_phy_slow` | 27 MHz | 13.5 MHz | 27 MT/s, 54 MB/s | 8 MB |
| Tang Primer 20K | `ddr3_phy_2to1` | 108 MHz | 108 MHz | 216 MT/s, 432 MB/s | 8 MB |
| Tang Console 138K | `ddr3_phy_slow`, `IOBFF=1` | 50 MHz | 25 MHz | 50 MT/s, 200 MB/s | 16 MB |
| Tang Console 138K | `ddr3_phy_2to1`, `GW5A=1` | 50 MHz | 50 MHz | 100 MT/s, 400 MB/s | 4 MB |
| Tang Console 138K | `ddr3_phy_2to1`, `GW5A=1` | 100 MHz | 100 MHz | 200 MT/s, 800 MB/s | 4 MB |

The Tang Primer 20K has one 16 bit 1Gb chip, the Tang Console 138K two 16 bit
4Gb chips on a 32 bit bus. All combinations run the DRAM in DLL-off mode
(CK ≤ 125 MHz), which is outside the guaranteed operating range of some parts.
`ddr3_phy_2to1` on the Tang Console 138K also passed at 120 and 130 MHz; on
the Tang Primer 20K it fails from 114.75 MHz on, with the vendor toolchain as
well.

### Toolchain branches

Some combinations need changes to apicula and nextpnr from the forks
[e-karge/apicula](https://github.com/e-karge/apicula) and
[e-karge/nextpnr](https://github.com/e-karge/nextpnr). Each combination builds
with the branches in its row; the last column shows how a build without them
fails.

| board | PHY | apicula | nextpnr | without the branches |
|---|---|---|---|---|
| Tang Primer 20K | `ddr3_phy_slow` | [upstream master](https://github.com/YosysHQ/apicula/tree/master) | [upstream main](https://github.com/YosysHQ/nextpnr/tree/main) | |
| Tang Primer 20K | `ddr3_phy_2to1` | [segments-iologic](https://github.com/e-karge/apicula/tree/segments-iologic) | [upstream main](https://github.com/YosysHQ/nextpnr/tree/main) | nextpnr fails to route, or aborts with `w2n_entry == nullptr` |
| Tang Console 138K | `ddr3_phy_slow`, `IOBFF=1` | [gw5a-iob-regs](https://github.com/e-karge/apicula/tree/gw5a-iob-regs) | [gowin-gw5a-iob-regs](https://github.com/e-karge/nextpnr/tree/gowin-gw5a-iob-regs) | gowin_pack stops with `NameError: name 'av' is not defined` |
| Tang Console 138K | `ddr3_phy_2to1`, `GW5A=1`, 50 MHz | [gw5a-iodelay](https://github.com/e-karge/apicula/tree/gw5a-iodelay) | [gowin-gw5a-iodelay](https://github.com/e-karge/nextpnr/tree/gowin-gw5a-iodelay) | nextpnr crashes while packing the IODELAYs |
| Tang Console 138K | `ddr3_phy_2to1`, `GW5A=1`, 100 MHz | [gw5a-iodelay](https://github.com/e-karge/apicula/tree/gw5a-iodelay) | [gowin-gw5a-iodelay](https://github.com/e-karge/nextpnr/tree/gowin-gw5a-iodelay) | nextpnr crashes while packing the IODELAYs |

The branches carry:

* `segments-iologic`: the chip database keeps segment wires out of the IO logic
  cells, where nextpnr used IO logic input pins as gate wires and failed.
* `gw5a-iob-regs`, `gowin-gw5a-iob-regs`: registers in the IO blocks of the GW5A.
* `gw5a-iodelay`, `gowin-gw5a-iodelay`: the GW5A IODELAY with dynamic delay, on
  top of the GW5AST-138C PLL, the IO block registers and the IO logic fixes of
  the GW5AST-138C (IDDR outputs, IO logic of B pins, ODDR tristate).

apicula keeps its chip databases in the package: after switching branches,
rebuild them (`make` in apicula) and then nextpnr's, whose build doesn't notice
the change (delete the generated `chipdb-*.bba` and `chipdb-*.bin` in its build
directory).

## Examples

`examples/<board>-<phy>` builds a memory test: after the calibration it writes
1M words, reads them back and compares, forever. The LED toggles after every
pass and stays on after a read error or a failed calibration. The USB UART of
the dock (115200 8N1) reports the calibration with the read delay of each byte
lane, and every pass with its errors and the first of them:

```
calib ok   delays 1b 1b
pass 0001 errors 00000000 first 0000000 got 0000 want 0000
```

```
cd examples/tang-primer-20k-2to1
make            # build/top.fs
make flash      # openFPGALoader
```

The Makefiles take the tools from `PATH`; `YOSYS`, `NEXTPNR`, `GOWIN_PACK` and
`NEXTPNR_FLAGS` (e.g. `--chipdb`) override them.

## How the PHYs work

### ddr3_phy_slow

Every pin comes from a register clocked by the controller clock, CK is half
of it. DQS is ignored on reads: DQ is sampled on both edges of the
controller clock, and the calibration picks the sample per byte lane.

* CK and DQS need differential buffers. As separately routed single ended
  outputs, the skew within a pair depends on the placement and the DRAM sees
  extra clock and strobe edges. On the Tang Primer 20K they go through ELVDS
  buffers (`ELVDS=1`). The pairs of the Tang Console 138K are true LVDS pins,
  where apicula has no emulated LVDS: there each pin of the pairs comes from
  the register in its IO block (`IOBFF=1`).
* DQS is driven low whenever the DRAM doesn't drive it: without ODT nothing
  keeps the pair defined.

### ddr3_phy_2to1

Commands, CK, DQ, DM and DQS go through ODDRs, DQ comes back through an
IODELAY and an IDDR, two samples per clock cycle into a history. The read
delay of a lane picks the sample and the IODELAY setting within it.

* The fabric runs at CK: DLL-off mode, CL = CWL = 6, CK up to 125 MHz.
* CK and DQS are a quarter CK later than the commands and DQ, so that their
  edges sit in the middle of the bits, through output IODELAY. On the GW5A
  its 255 taps of 12.5 ps (3.2 ns) are less than a quarter CK below 80 MHz,
  still ample for the DRAM's setup and hold times at such clocks.
* The tristate of DQ and DQS comes from fabric registers: an ODDR with its
  tristate output in use held its data after the first beats of a burst.
* On the GW5A, CK# and DQS# have their own ODDRs (true LVDS pins), and RESET#
  comes from the fabric: the chip database has no clock for the IO logic of
  its pin. The GW5A IODELAY loads the read delay from `DLYSTEP` on an `SDTAP`
  pulse; its taps are 12.5 ps.

### DDR3 in DLL-off mode

Read data comes CL - 1 clocks after the READ (JESD79-3F 5.4), tDQSCK 1-10 ns
after the CK edge. The DDR pins are LVCMOS15 (CK and DQS on the Tang Primer
20K LVCMOS15D).

## License

Apache-2.0, see `LICENSE`. The controller core is derived from nand2mario's
[ddr3-tang-primer-20k](https://github.com/nand2mario/ddr3-tang-primer-20k)
(Apache-2.0).
