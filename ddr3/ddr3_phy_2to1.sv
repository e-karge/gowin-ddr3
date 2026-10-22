`ifndef module_ddr3_phy_2to1
`define module_ddr3_phy_2to1

/* verilator lint_off PINCONNECTEMPTY */

// 2:1 DDR3 PHY for the GW2A with ODDR/IDDR: CK = clk (up to 125 MHz), DLL-off mode.
// With GW5A = 1 for the GW5AST-138C of the Tang Mega 138K.
//
// nextpnr/apicula only support input and output IO logic on one pin as the
// ODDR+IDDR pair, so DQ can't use OSER8/IDES8. With 2:1 IO logic the fabric
// runs at CK, below the 300 MHz the DRAM's DLL needs: DLL-off mode, CL=CWL=6,
// CK at most 125 MHz.
//
// The controller runs on every clk cycle (ce is always 1, NPH=1).
//   commands, addresses  ODDR with D0=D1, change at clk rising edges
//   CK                   ODDR, rises at clk rising edges, plus WR_DLY taps
//                        (GW2A 25ps, GW5A 12.5ps) of output IODELAY, about a
//                        quarter of a CK:
//                        it rises in the middle of the commands' setup/hold
//   DQ, DM               ODDR, beat 2k in the high and 2k+1 in the low phase
//   DQS                  ODDR, high in the high phases of the burst, with the
//                        same delay as CK: tDQSS = 0, edges in the middle of
//                        the DQ bits; driven low whenever the DRAM doesn't
//                        drive it (there's no ODT in DLL-off mode)
//   CK#, DQS#            the B pins of emulated LVDS buffers (ELVDS_OBUF,
//                        ELVDS_IOBUF), so a pair can't be skewed by routing
// The tristate of DQ and DQS comes from fabric registers: on the hardware an
// ODDR with its tristate output (TX/Q1) in use sent the first beats of a
// burst and then held its data. DQ is driven from a cycle before the burst
// until a cycle after it.
// Reads ignore DQS: DQ goes through an IODELAY and IDDR, two samples per clk
// cycle into a history. The read delay t of a lane picks the sample
// RD_BASE + t / NF of beat 0 in the history and the position f = t % NF
// within the sample, set as (NF-1-f)*TAPS IODELAY taps: more delay samples
// the data earlier. In DLL-off mode the DRAM starts beat 0 tDQSCK (1-10ns)
// after the (CL-1)-th CK edge.
// GW5A: CK# and DQS# have their own ODDR and output IODELAY: apicula has no
// emulated LVDS on the true LVDS pins of the Mega's CK and DQS. The 255 taps
// of the output delay (3.2ns) are less than a quarter CK below 80 MHz, which
// leaves the DRAM's setup and hold times ample margin at such clocks. RESET#
// comes from the fabric: the 138C chip database has no clock for the IO logic
// of its pin. The GW5A IODELAY loads the read delay from DLYSTEP on an SDTAP
// pulse; its 255 taps span less than half a clk cycle at 100 MHz.
module ddr3_phy_2to1 #(
    parameter DQ_W  = 32,
    parameter ROW_W = 15,
    parameter BA_W  = 3,
    parameter CL    = 6,
    parameter CWL   = 6,
    parameter DW    = 6,                // read delay bits per lane
    parameter TCK_PS = 9259,            // clk period
    parameter NF    = 8,                // read delay steps per sample
    parameter GW5A  = 0,                // the GW5AST-138C PHY
    // IODELAY taps (GW2A 25ps, GW5A 12.5ps) per step: the steps of a sample,
    // up to all taps (GW2A 127, GW5A 255)
    parameter TAPS  = TCK_PS * 10 / 2 / NF / (GW5A ? 125 : 250) < (GW5A ? 255 : 127) / (NF - 1)
                    ? TCK_PS * 10 / 2 / NF / (GW5A ? 125 : 250) : (GW5A ? 255 : 127) / (NF - 1),
    // CK and DQS output delay in IODELAY taps, a quarter of a CK, up to all taps
    parameter WR_DLY = GW5A ? (TCK_PS * 10 / 4 / 125 < 255 ? TCK_PS * 10 / 4 / 125 : 255) : TCK_PS / 4 / 25,
    // history index of beat 0 at read delay 0: the CK edge CL-1 after the
    // READ, the two ODDR and three IDDR/register cycles
    parameter RD_BASE = 2 * (CL + 1) + 6,
    localparam LANES = DQ_W / 8
) (
    input                       clk,
    input                       lock,
    output                      ce,

    // controller side
    input                       phy_reset_n,
    input                       phy_cke,
    input                       phy_odt,
    input                 [2:0] phy_cmd,
    input           [ROW_W-1:0] phy_addr,
    input            [BA_W-1:0] phy_ba,
    input                       phy_wr,
    input                 [1:0] phy_wr_ph,
    input          [8*DQ_W-1:0] phy_wdata,
    input            [DQ_W-1:0] phy_wmask,
    input                       phy_rd,
    input                 [1:0] phy_rd_ph,
    input      [LANES*DW-1:0]   phy_rd_delay,
    input                 [1:0] phy_wr_shift,   // unused, writes are always aligned
    output reg                  phy_rvalid,
    output reg   [8*DQ_W-1:0]   phy_rdata,
    output                      phy_ready,
    output       [2*DQ_W-1:0]   dbg_rx,         // the DQ samples of the last clk cycle, 2 bits per pin

    // DRAM side
    output                      ddr_ck,
    output                      ddr_ck_n,
    output                      ddr_reset_n,
    output                      ddr_cke,
    output                      ddr_cs_n,
    output                      ddr_ras_n,
    output                      ddr_cas_n,
    output                      ddr_we_n,
    output                      ddr_odt,
    output          [BA_W-1:0]  ddr_ba,
    output         [ROW_W-1:0]  ddr_addr,
    output         [LANES-1:0]  ddr_dm,
    inout          [LANES-1:0]  ddr_dqs,
    inout          [LANES-1:0]  ddr_dqs_n,
    inout           [DQ_W-1:0]  ddr_dq
);

initial begin
    phy_rvalid = 0;
    phy_rdata = '0;
end

localparam FW = $clog2(NF);
localparam NB = 2 ** (DW - FW);         // sample offsets
localparam RD_WAIT = (RD_BASE + NB + 8 + 1) / 2;    // cycles from the READ until all samples are in
localparam HIST = 2 * RD_WAIT;

assign ce = 1'b1;
assign ddr_cs_n = 1'b0;

// an output for a whole clk cycle, 2 cycles after the input
`define ODDR1(name, d, q) ODDR name(.D0(d), .D1(d), .TX(1'b0), .CLK(clk), .Q0(q), .Q1());
// The GW2A and GW5A IODELAY have different pins, and Verilator checks the
// instances of both families against the simulation models of one: they
// waive PINNOTFOUND and PINMISSING.
// a static output delay
`define OUT_DLY(name, i, o) \
    IODELAY #(.C_STATIC_DLY(WR_DLY)) name(.DI(i), .SDTAP(1'b0), .SETN(1'b0), .VALUE(1'b0), .DF(), .DO(o));
`define OUT_DLY5(name, i, o) \
    IODELAY #(.C_STATIC_DLY(WR_DLY)) name(.DI(i), .DLYSTEP(8'd0), .SDTAP(1'b0), .VALUE(1'b0), .DF(), .DO(o));

if (GW5A) begin : g_reset
    assign ddr_reset_n = phy_reset_n;
end else begin : g_reset_oddr
    `ODDR1(oddr_reset_n, phy_reset_n, ddr_reset_n)
end
`ODDR1(oddr_cke, phy_cke, ddr_cke)
`ODDR1(oddr_odt, phy_odt, ddr_odt)
`ODDR1(oddr_ras, phy_cmd[2], ddr_ras_n)
`ODDR1(oddr_cas, phy_cmd[1], ddr_cas_n)
`ODDR1(oddr_we, phy_cmd[0], ddr_we_n)
for (genvar i = 0; i < ROW_W; i++) begin : g_addr
    `ODDR1(oddr, phy_addr[i], ddr_addr[i])
end
for (genvar i = 0; i < BA_W; i++) begin : g_ba
    `ODDR1(oddr, phy_ba[i], ddr_ba[i])
end

// CK: high from a quarter to three quarters of the clk cycle
if (GW5A) begin : g_ck_dly5
    wire ck_q, ck_n_q;
    ODDR oddr_ck(.D0(1'b1), .D1(1'b0), .TX(1'b0), .CLK(clk), .Q0(ck_q), .Q1());
    ODDR oddr_ck_n(.D0(1'b0), .D1(1'b1), .TX(1'b0), .CLK(clk), .Q0(ck_n_q), .Q1());
    /* verilator lint_off PINNOTFOUND */ /* verilator lint_off PINMISSING */
    `OUT_DLY5(dly_ck, ck_q, ddr_ck)
    `OUT_DLY5(dly_ck_n, ck_n_q, ddr_ck_n)
    /* verilator lint_on PINMISSING */ /* verilator lint_on PINNOTFOUND */
end else begin : g_ck_dly
    wire ck_q, ck_d;
    ODDR oddr_ck(.D0(1'b1), .D1(1'b0), .TX(1'b0), .CLK(clk), .Q0(ck_q), .Q1());
    /* verilator lint_off PINNOTFOUND */ /* verilator lint_off PINMISSING */
    `OUT_DLY(dly_ck, ck_q, ck_d)
    /* verilator lint_on PINMISSING */ /* verilator lint_on PINNOTFOUND */
    ELVDS_OBUF buf_ck(.I(ck_d), .O(ddr_ck), .OB(ddr_ck_n));
end

// Writes: the WRITE goes out with the cycle's command, its first DQS rising
// edge is due at the CWL-th CK edge after it, so the ODDRs take DQS and beats
// 0 and 1 CWL cycles after the WRITE, the other beats in the 3 cycles after.
localparam W = CWL + 3;
reg [W-1:0] w_act;
initial w_act = '0;
reg [8*DQ_W-1:0] w_data [W];
reg [DQ_W-1:0] w_mask [W];
always @(posedge clk) begin
    w_act <= {w_act[W-2:0], phy_wr};
    w_data[0] <= phy_wdata;
    w_mask[0] <= phy_wmask;
    for (int i = 1; i < W; i++) begin
        w_data[i] <= w_data[i-1];
        w_mask[i] <= w_mask[i-1];
    end
end
// beat pair k (0..3) of the burst whose WRITE was CWL+k cycles ago
wire [3:0] w_on = w_act[CWL-1 +: 4];
wire w_burst = |w_on;
reg [2*DQ_W-1:0] w_pair;
reg [2*LANES-1:0] w_pair_mask;
always @* begin
    w_pair = '0;
    w_pair_mask = '1;
    for (int k = 0; k < 4; k++)
        if (w_on[k]) begin
            w_pair = w_data[CWL-1+k][2*DQ_W*k +: 2*DQ_W];
            w_pair_mask = w_mask[CWL-1+k][2*LANES*k +: 2*LANES];
        end
end

// a read in progress, from the READ until all samples are in: the DRAM
// drives DQS meanwhile
reg [5:0] r_cnt;
reg r_act;
initial begin
    r_cnt = 0;
    r_act = 0;
end

reg dqs_oen;
initial dqs_oen = 0;
always @(posedge clk) dqs_oen <= r_act;

for (genvar l = 0; l < LANES; l++) begin : g_lane
    if (GW5A) begin : g_dqs_dly5
        wire q, qn, qd, qnd;
        ODDR oddr_dqs(.D0(w_burst), .D1(1'b0), .TX(1'b0), .CLK(clk), .Q0(q), .Q1());
        ODDR oddr_dqs_n(.D0(!w_burst), .D1(1'b1), .TX(1'b0), .CLK(clk), .Q0(qn), .Q1());
        /* verilator lint_off PINNOTFOUND */ /* verilator lint_off PINMISSING */
        `OUT_DLY5(dly_dqs, q, qd)
        `OUT_DLY5(dly_dqs_n, qn, qnd)
        /* verilator lint_on PINMISSING */ /* verilator lint_on PINNOTFOUND */
        IOBUF buf_dqs(.I(qd), .OEN(dqs_oen), .O(), .IO(ddr_dqs[l]));
        IOBUF buf_dqs_n(.I(qnd), .OEN(dqs_oen), .O(), .IO(ddr_dqs_n[l]));
    end else begin : g_dqs_dly
        wire q, qd;
        ODDR oddr_dqs(.D0(w_burst), .D1(1'b0), .TX(1'b0), .CLK(clk), .Q0(q), .Q1());
        /* verilator lint_off PINNOTFOUND */ /* verilator lint_off PINMISSING */
        `OUT_DLY(dly_dqs, q, qd)
        /* verilator lint_on PINMISSING */ /* verilator lint_on PINNOTFOUND */
        ELVDS_IOBUF buf_dqs(.I(qd), .OEN(dqs_oen), .O(), .IO(ddr_dqs[l]), .IOB(ddr_dqs_n[l]));
    end
    ODDR oddr_dm(.D0(w_pair_mask[l]), .D1(w_pair_mask[LANES+l]), .TX(1'b0), .CLK(clk), .Q0(ddr_dm[l]), .Q1());
end

// Read delay of each lane: sample offset and IODELAY taps. The GW2A IODELAY
// steps on falling edges of VALUE, which is the same IO logic input as the clock
// enable of the ODDR on the pin: VALUE is high but for a cycle per step.
localparam TW = GW5A ? 8 : 7;
reg [TW-1:0] taps [LANES];              // current IODELAY setting
reg [LANES-1:0] dly_step, dly_pulse, dly_dec;
reg dly_dyn;                        // SDTAP: 0 loads the static delay 0
reg [1:0] dly_phase;
initial begin
    dly_step = '0;
    dly_pulse = '0;
    dly_dec = '0;
    dly_dyn = 0;
    dly_phase = 0;
end
wire [TW-1:0] want_taps [LANES];
wire [LANES-1:0] dly_done;
for (genvar l = 0; l < LANES; l++) begin : g_want
    assign want_taps[l] = TW'((NF - 1 - 32'(phy_rd_delay[DW*l +: FW])) * TAPS);
    assign dly_done[l] = taps[l] == want_taps[l];
end
reg dly_sdtap, dly_load;         // GW5A: SDTAP 1 -> 0 loads DLYSTEP
initial begin
    dly_sdtap = 0;
    dly_load = 0;
end
if (GW5A) begin : g_load
assign phy_ready = lock && dly_dyn && &dly_done && !dly_load;
// all lanes together: the new delays, then a pulse on SDTAP
always @(posedge clk) begin
    if (!lock) begin
        dly_dyn <= 0;
        dly_load <= 1;
        dly_sdtap <= 0;
        dly_phase <= 0;
        for (int l = 0; l < LANES; l++) taps[l] <= 0;
    end else begin
        dly_phase <= dly_phase + 1'd1;
        case (dly_phase)
        2'd0: if (!(&dly_done)) begin
            for (int l = 0; l < LANES; l++) taps[l] <= want_taps[l];
            dly_load <= 1;
        end
        2'd1: dly_sdtap <= dly_load;
        2'd2: dly_sdtap <= 0;
        default: begin
            dly_load <= 0;
            dly_dyn <= dly_dyn | dly_load;
        end
        endcase
    end
end
end else begin : g_step
assign phy_ready = lock && dly_dyn && &dly_done && !(|dly_step);

// one tap at a time, all lanes together: direction (SETN), then VALUE low
always @(posedge clk) begin
    if (!lock) begin
        dly_dyn <= 0;
        dly_step <= '0;
        dly_pulse <= '0;
        dly_phase <= 0;
        for (int l = 0; l < LANES; l++) taps[l] <= 0;
    end else begin
        dly_dyn <= 1;
        dly_phase <= dly_phase + 1'd1;
        case (dly_phase)
        2'd0: for (int l = 0; l < LANES; l++) begin
            dly_dec[l] <= want_taps[l] < taps[l];
            dly_step[l] <= dly_dyn && !dly_done[l];
        end
        2'd1: dly_pulse <= dly_step;
        2'd2: dly_pulse <= '0;
        default: for (int l = 0; l < LANES; l++)
            if (dly_step[l]) begin
                dly_step[l] <= 0;
                taps[l] <= dly_dec[l] ? taps[l] - 1'd1 : taps[l] + 1'd1;
            end
        endcase
    end
end
end

// DQ: out through ODDR, in through IODELAY and IDDR. hist has the last HIST
// samples of each pin, the oldest in bit 0.
reg [1:0] rx [DQ_W];
reg [HIST-1:0] hist [DQ_W];
// DQ tristate: on while the ODDRs send the burst (2 cycles after w_burst)
// and a cycle before and after
reg [2:0] w_burst_d;
reg dq_oen;
initial begin
    w_burst_d = '0;
    dq_oen = 1;
end
always @(posedge clk) begin
    w_burst_d <= {w_burst_d[1:0], w_burst};
    dq_oen <= !(|w_burst_d);
end

for (genvar b = 0; b < DQ_W; b++) begin : g_dq
    wire q, di, dd, r0, r1;
    ODDR oddr(.D0(w_pair[b]), .D1(w_pair[DQ_W+b]), .TX(1'b0), .CLK(clk), .Q0(q), .Q1());
    IOBUF buf_dq(.I(q), .OEN(dq_oen), .O(di), .IO(ddr_dq[b]));
    if (GW5A) begin : g_dly5
        /* verilator lint_off PINNOTFOUND */ /* verilator lint_off PINMISSING */
        IODELAY #(.C_STATIC_DLY(0), .DYN_DLY_EN("TRUE")) dly(.DI(di), .DLYSTEP(taps[b / 8]), .SDTAP(dly_sdtap),
            .VALUE(1'b0), .DF(), .DO(dd));
        /* verilator lint_on PINMISSING */ /* verilator lint_on PINNOTFOUND */
    end else begin : g_dly
        /* verilator lint_off PINNOTFOUND */ /* verilator lint_off PINMISSING */
        IODELAY #(.C_STATIC_DLY(0)) dly(.DI(di), .SDTAP(dly_dyn), .SETN(dly_dec[b / 8]), .VALUE(!dly_pulse[b / 8]),
            .DF(), .DO(dd));
        /* verilator lint_on PINMISSING */ /* verilator lint_on PINNOTFOUND */
    end
    IDDR iddr(.D(dd), .CLK(clk), .Q0(r0), .Q1(r1));
    always @(posedge clk) begin
        rx[b] <= {r1, r0};
        hist[b] <= {rx[b], hist[b][HIST-1:2]};
    end
    assign dbg_rx[2*b +: 2] = rx[b];
end

// read capture: RD_WAIT cycles after the READ, beat j of a lane is at
// RD_BASE + t / NF + j in the history
always @(posedge clk) begin
    phy_rvalid <= 0;
    if (phy_rd) begin
        r_act <= 1;
        r_cnt <= 0;
    end else if (r_act) begin
        r_cnt <= r_cnt + 1'd1;
        if (r_cnt == 6'(RD_WAIT - 1)) begin
            r_act <= 0;
            phy_rvalid <= 1;
            for (int b = 0; b < DQ_W; b++)
                for (int j = 0; j < 8; j++)
                    phy_rdata[DQ_W*j + b] <= hist[b][RD_BASE + 32'(phy_rd_delay[DW*(b / 8) + FW +: DW - FW]) + j];
        end
    end
end

`undef ODDR1
`undef OUT_DLY
`undef OUT_DLY5

endmodule

`endif /* module_ddr3_phy_2to1 */
