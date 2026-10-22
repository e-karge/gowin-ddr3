`ifndef module_ddr3_clk_2to1_tang_mega_138k
`define module_ddr3_clk_2to1_tang_mega_138k

/* verilator lint_off PINCONNECTEMPTY */

// Clocks for ddr3_phy_2to1 with GW5A = 1 on the Tang Mega 138K: a PLL, clk =
// 100 MHz from the 50 MHz board clock and clk270, clk delayed by 3/4 of its
// period.
// VCO = FCLKIN * FBDIV * MDIV / IDIV (800 MHz), clk = VCO / ODIV
module ddr3_clk_2to1_tang_mega_138k #(
    parameter FCLKIN = "50",
    parameter IDIV   = 1,
    parameter FBDIV  = 1,
    parameter MDIV   = 16,
    parameter ODIV   = 8
) (
    input  clkin,
    output clk,
    output clk270,
    output lock
);

// 3/4 of a clk period is 3 * ODIV / 4 VCO periods, the fine steps are 1/8
localparam PE270_COARSE = 3 * ODIV / 4;
localparam PE270_FINE = (3 * ODIV * 2) % 8;

PLL #(
    .FCLKIN(FCLKIN), .IDIV_SEL(IDIV), .FBDIV_SEL(FBDIV), .MDIV_SEL(MDIV),
    .ODIV0_SEL(ODIV), .ODIV1_SEL(ODIV),
    .CLKOUT0_EN("TRUE"), .CLKOUT1_EN("TRUE"),
    .CLKOUT1_PE_COARSE(PE270_COARSE), .CLKOUT1_PE_FINE(PE270_FINE)
) pll (
    .CLKIN(clkin), .CLKFB(1'b0), .RESET(1'b0), .PLLPWD(1'b0), .RESET_I(1'b0), .RESET_O(1'b0),
    .PSSEL(3'b0), .PSDIR(1'b0), .PSPULSE(1'b0),
    .SSCPOL(1'b0), .SSCON(1'b0), .SSCMDSEL(7'b0), .SSCMDSEL_FRAC(3'b0),
    .FBDSEL(6'b0), .IDSEL(6'b0), .MDSEL(7'b0), .MDSEL_FRAC(3'b0),
    .ODSEL0(7'b0), .ODSEL0_FRAC(3'b0), .ODSEL1(7'b0), .ODSEL2(7'b0), .ODSEL3(7'b0),
    .ODSEL4(7'b0), .ODSEL5(7'b0), .ODSEL6(7'b0),
    .DT0(4'b0), .DT1(4'b0), .DT2(4'b0), .DT3(4'b0),
    .ICPSEL(6'b0), .LPFRES(3'b0), .LPFCAP(2'b0),
    .ENCLK0(1'b1), .ENCLK1(1'b1), .ENCLK2(1'b0),
    .ENCLK3(1'b0), .ENCLK4(1'b0), .ENCLK5(1'b0), .ENCLK6(1'b0),
    .LOCK(lock), .CLKOUT0(clk), .CLKOUT1(clk270), .CLKOUT2(),
    .CLKOUT3(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUT()
);

endmodule

`endif /* module_ddr3_clk_2to1_tang_mega_138k */
