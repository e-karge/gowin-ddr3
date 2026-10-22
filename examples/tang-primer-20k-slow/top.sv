/* verilator lint_off PINCONNECTEMPTY */
`include "ddr3/ddr3_ctrl.sv"
`include "ddr3/ddr3_phy_slow.sv"
`include "ddr3_test.sv"

// ddr3_phy_slow on the Tang Primer 20K: the controller runs on the 27 MHz
// board clock, CK = 13.5 MHz (27 MT/s) in DLL-off mode, CK and DQS through
// ELVDS buffers.
module top (
    input         clk,
    output        led,
    output        uart_tx,
    output        ddr_ck,
    output        ddr_ck_n,
    output        ddr_reset_n,
    output        ddr_cke,
    output        ddr_cs_n,
    output        ddr_ras_n,
    output        ddr_cas_n,
    output        ddr_we_n,
    output        ddr_odt,
    output  [2:0] ddr_ba,
    output [13:0] ddr_addr,
    output  [1:0] ddr_dm,
    inout   [1:0] ddr_dqs,
    inout   [1:0] ddr_dqs_n,
    inout  [15:0] ddr_dq
);

localparam DQ_W = 16, ROW_W = 13, COL_W = 10, BA_W = 3, DW = 3;
localparam ADDR_W = BA_W + ROW_W + COL_W, LANES = DQ_W / 8;
localparam SYS_FREQ = 27_000_000;

reg [7:0] reset_cnt;
initial reset_cnt = 0;
wire reset = !reset_cnt[7];
always @(posedge clk) if (reset) reset_cnt <= reset_cnt + 1'd1;

wire rd, wr, refresh, data_ready, busy, calib_done, calib_fail;
wire [ADDR_W-1:0] addr;
wire [DQ_W-1:0] din, dout;

wire ce, phy_reset_n, phy_cke, phy_odt, phy_wr, phy_rd, phy_rvalid, phy_ready;
wire [2:0] phy_cmd;
wire [ROW_W-1:0] phy_addr;
wire [BA_W-1:0] phy_ba;
wire [1:0] phy_wr_ph, phy_rd_ph, phy_wr_shift;
wire [8*DQ_W-1:0] phy_wdata, phy_rdata;
wire [DQ_W-1:0] phy_wmask;
wire [LANES*DW-1:0] phy_rd_delay;

ddr3_ctrl #(
    .DQ_W(DQ_W), .ROW_W(ROW_W), .COL_W(COL_W), .BA_W(BA_W),
    .NPH(1), .TCK_PS(2_000_000_000 / (SYS_FREQ / 1000)), .CL(6), .CWL(6), .NWR(5), .DLL_OFF(1),
    .T_RFC_PS(110_000), .CAL_DW(DW), .CAL_STEPS(2 ** DW), .CAL_PER_LANE(1)
) ctrl (
    .clk(clk), .ce(ce), .rst(reset),
    .rd(rd), .wr(wr), .refresh(refresh), .addr(addr), .din(din), .be('1),
    .dout(dout), .dout_burst(), .data_ready(data_ready), .busy(busy),
    .init_done(), .calib_done(calib_done), .calib_fail(calib_fail),
    .phy_reset_n(phy_reset_n), .phy_cke(phy_cke), .phy_odt(phy_odt),
    .phy_cmd(phy_cmd), .phy_addr(phy_addr), .phy_ba(phy_ba),
    .phy_wr(phy_wr), .phy_wr_ph(phy_wr_ph), .phy_wdata(phy_wdata), .phy_wmask(phy_wmask),
    .phy_rd(phy_rd), .phy_rd_ph(phy_rd_ph), .phy_rd_delay(phy_rd_delay), .phy_wr_shift(phy_wr_shift),
    .phy_rvalid(phy_rvalid), .phy_rdata(phy_rdata), .phy_ready(phy_ready)
);

// the 1Gb chip has 13 row bits, A13 stays low
wire [ROW_W-1:0] ddr_row_addr;
assign ddr_addr = 14'(ddr_row_addr);

ddr3_phy_slow #(.DQ_W(DQ_W), .ROW_W(ROW_W), .BA_W(BA_W), .CL(6), .CWL(6), .DW(DW), .ELVDS(1)) phy (
    .clk(clk), .ce(ce), .dqs_in(),
    .phy_reset_n(phy_reset_n), .phy_cke(phy_cke), .phy_odt(phy_odt),
    .phy_cmd(phy_cmd), .phy_addr(phy_addr), .phy_ba(phy_ba),
    .phy_wr(phy_wr), .phy_wr_ph(phy_wr_ph), .phy_wdata(phy_wdata), .phy_wmask(phy_wmask),
    .phy_rd(phy_rd), .phy_rd_ph(phy_rd_ph), .phy_rd_delay(phy_rd_delay), .phy_wr_shift(phy_wr_shift),
    .phy_rvalid(phy_rvalid), .phy_rdata(phy_rdata), .phy_ready(phy_ready),
    .ddr_ck(ddr_ck), .ddr_ck_n(ddr_ck_n), .ddr_reset_n(ddr_reset_n), .ddr_cke(ddr_cke),
    .ddr_cs_n(ddr_cs_n), .ddr_ras_n(ddr_ras_n), .ddr_cas_n(ddr_cas_n), .ddr_we_n(ddr_we_n),
    .ddr_odt(ddr_odt), .ddr_ba(ddr_ba), .ddr_addr(ddr_row_addr), .ddr_dm(ddr_dm),
    .ddr_dqs(ddr_dqs), .ddr_dqs_n(ddr_dqs_n), .ddr_dq(ddr_dq)
);

wire test_led;
assign led = !test_led;

ddr3_test #(.DQ_W(DQ_W), .ADDR_W(ADDR_W), .DW(DW), .SYS_FREQ(SYS_FREQ)) test (
    .clk(clk), .rst(reset), .calib_done(calib_done), .calib_fail(calib_fail), .rd_delay(phy_rd_delay),
    .rd(rd), .wr(wr), .refresh(refresh), .addr(addr), .din(din),
    .dout(dout), .data_ready(data_ready), .busy(busy), .led(test_led), .uart_tx(uart_tx)
);

endmodule
