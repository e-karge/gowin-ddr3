`ifndef module_ddr3_clk_2to1_tang_primer_20k
`define module_ddr3_clk_2to1_tang_primer_20k

/* verilator lint_off PINCONNECTEMPTY */

// Clock for ddr3_phy_2to1 on the Tang Primer 20K: an rPLL, CK = clk = 108 MHz
// from the 27 MHz board clock (tCK 9.26ns, DLL-off mode needs at least 8ns;
// 121.5 MHz calibrated, but the reads after writes returned only ffff).
// fout = FCLKIN * (FBDIV + 1) / (IDIV + 1), VCO = fout * ODIV
module ddr3_clk_2to1_tang_primer_20k #(
    parameter FCLKIN = "27",
    parameter IDIV   = 0,
    parameter FBDIV  = 3,
    parameter ODIV   = 8
) (
    input  clkin,
    output clk,
    output lock
);

rPLL #(
    .FCLKIN(FCLKIN), .DEVICE("GW2A-18"), .IDIV_SEL(IDIV), .FBDIV_SEL(FBDIV), .ODIV_SEL(ODIV),
    .DYN_IDIV_SEL("false"), .DYN_FBDIV_SEL("false"), .DYN_ODIV_SEL("false"),
    .PSDA_SEL("0000"), .DUTYDA_SEL("1000"), .DYN_DA_EN("false"),
    .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
    .CLKFB_SEL("internal")
) pll (
    .CLKIN(clkin), .CLKFB(1'b0), .RESET(1'b0), .RESET_P(1'b0),
    .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0),
    .CLKOUT(clk), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(), .LOCK(lock)
);

endmodule

`endif /* module_ddr3_clk_2to1_tang_primer_20k */
