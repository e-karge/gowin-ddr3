`ifndef module_ddr3_test
`define module_ddr3_test

`include "uart_tx.sv"

// Memory test of the examples: after the calibration, write WORDS words from
// address 0 on, read them back and compare, forever. led toggles after every
// pass and stays on after a read error or a failed calibration. uart_tx (8N1,
// BAUD) reports the calibration with the read delay of each byte lane, and
// every pass with its errors and the first of them:
//   calib ok   delays 1b 1b
//   pass 0001 errors 00000000 first 0000000 got 0000 want 0000
module ddr3_test #(
    parameter DQ_W     = 16,
    parameter ADDR_W   = 26,
    parameter DW       = 3,             // read delay bits per lane
    parameter SYS_FREQ = 27_000_000,
    parameter WORDS    = 1 << 20,
    parameter BAUD     = 115_200
) (
    input                    clk,
    input                    rst,
    input                    calib_done,
    input                    calib_fail,
    input  [DQ_W/8*DW-1:0]   rd_delay,

    // to the controller
    output reg               rd,
    output reg               wr,
    output reg               refresh,
    output reg  [ADDR_W-1:0] addr,
    output reg    [DQ_W-1:0] din,
    input         [DQ_W-1:0] dout,
    input                    data_ready,
    input                    busy,

    output                   led,
    output                   uart_tx
);

initial begin
    rd = 0;
    wr = 0;
    refresh = 0;
    addr = 0;
    din = 0;
end

localparam LANES = DQ_W / 8;

// the data of a word: its address scrambled with the pass number, so that
// every address bit and every pass changes the pattern
function automatic [31:0] pattern(input [ADDR_W-1:0] a, input [15:0] p);
    logic [31:0] x;
    x = 32'(a) ^ {p, 16'h0};
    x = x ^ (x << 13);
    x = x ^ (x >> 17);
    x = x ^ (x << 5);
    pattern = x;
endfunction

// a refresh every 7.8us, issued in between the accesses
localparam REFRESH_COUNT = SYS_FREQ / 1000 * 78 / 10000;
reg [15:0] refresh_time;
reg refresh_due;
initial begin
    refresh_time = 0;
    refresh_due = 0;
end
always @(posedge clk) begin
    if (refresh_time == 16'(REFRESH_COUNT - 1)) begin
        refresh_time <= 0;
        refresh_due <= 1;
    end else
        refresh_time <= refresh_time + 1'd1;
    if (refresh) refresh_due <= 0;
end

localparam [2:0] S_CALIB = 0, S_WRITE = 1, S_WRITE_NEXT = 2, S_READ = 3, S_READ_WAIT = 4, S_FAILED = 5;
reg [2:0] state;
reg [15:0] pass;
reg error, toggle;
// the pattern of addr, a cycle late: moved holds back a write meanwhile
reg [DQ_W-1:0] want;
reg moved;
// a read word, checked in the cycle after it came
reg chk, chk_bad, chk_last;
reg [ADDR_W-1:0] chk_addr;
reg [DQ_W-1:0] chk_got, chk_want;
// the errors of the current pass and the first of them
reg [31:0] errors;
reg [ADDR_W-1:0] first_addr;
reg [DQ_W-1:0] first_got, first_want;
// the report of the last pass
reg [15:0] rep_pass;
reg [31:0] rep_errors;
reg [ADDR_W-1:0] rep_addr;
reg [DQ_W-1:0] rep_got, rep_want;
reg say_calib, say_pass;
initial begin
    state = S_CALIB;
    pass = 0;
    error = 0;
    toggle = 0;
    want = 0;
    moved = 0;
    chk = 0;
    chk_bad = 0;
    chk_last = 0;
    chk_addr = 0;
    chk_got = 0;
    chk_want = 0;
    errors = 0;
    first_addr = 0;
    first_got = 0;
    first_want = 0;
    rep_pass = 0;
    rep_errors = 0;
    rep_addr = 0;
    rep_got = 0;
    rep_want = 0;
    say_calib = 0;
    say_pass = 0;
end

assign led = error || calib_fail || toggle;

wire idle = !busy && !rd && !wr && !refresh;
always @(posedge clk) want <= DQ_W'(pattern(addr, pass));

always @(posedge clk) begin
    rd <= 0;
    wr <= 0;
    refresh <= 0;
    moved <= 0;
    chk <= 0;
    if (rst) begin
        state <= S_CALIB;
    end else case (state)
        S_CALIB: if (calib_done) begin
            addr <= 0;
            moved <= 1;
            state <= calib_fail ? S_FAILED : S_WRITE;
        end
        S_WRITE: if (idle && !moved) begin
            if (refresh_due) refresh <= 1;
            else begin
                wr <= 1;
                din <= want;
                state <= S_WRITE_NEXT;
            end
        end
        // addr stays while wr is high
        S_WRITE_NEXT: begin
            addr <= addr + 1'd1;
            moved <= 1;
            state <= S_WRITE;
            if (addr == ADDR_W'(WORDS - 1)) begin
                addr <= 0;
                state <= S_READ;
            end
        end
        S_READ: if (idle) begin
            if (refresh_due) refresh <= 1;
            else begin
                rd <= 1;
                state <= S_READ_WAIT;
            end
        end
        S_READ_WAIT: if (data_ready) begin
            chk <= 1;
            chk_bad <= dout != want;
            chk_last <= addr == ADDR_W'(WORDS - 1);
            {chk_addr, chk_got, chk_want} <= {addr, dout, want};
            addr <= addr + 1'd1;
            moved <= 1;
            state <= S_READ;
            if (addr == ADDR_W'(WORDS - 1)) begin
                addr <= 0;
                pass <= pass + 1'd1;
                toggle <= !toggle;
                state <= S_WRITE;
            end
        end
        S_FAILED: ;
        default: state <= S_CALIB;
    endcase
end

// the check of the read words, the report of the calibration and the passes
wire first = errors == 0;
always @(posedge clk) begin
    say_calib <= 0;
    say_pass <= 0;
    if (rst) begin
        error <= 0;
        errors <= 0;
    end else begin
        if (state == S_CALIB && calib_done) say_calib <= 1;
        if (chk) begin
            if (chk_bad) begin
                error <= 1;
                errors <= errors + 1'd1;
                if (first) {first_addr, first_got, first_want} <= {chk_addr, chk_got, chk_want};
            end
            if (chk_last) begin
                rep_pass <= pass;
                rep_errors <= errors + 32'(chk_bad);
                {rep_addr, rep_got, rep_want} <= first && chk_bad ? {chk_addr, chk_got, chk_want}
                                                                  : {first_addr, first_got, first_want};
                say_pass <= 1;
                errors <= 0;
            end
        end
    end
end

// the report lines, left aligned in line, which shifts out from the top
function automatic [7:0] hexc(input [3:0] n);
    hexc = n < 4'd10 ? 8'd48 + 8'(n) : 8'd87 + 8'(n);
endfunction
function automatic [63:0] hex32(input [31:0] v);
    for (int i = 0; i < 8; i++) hex32[8*i +: 8] = hexc(v[4*i +: 4]);
endfunction

localparam AH = (ADDR_W + 3) / 4, DH = DQ_W / 4;
localparam CALIB_LEN = 17 + 3 * LANES + 2, PASS_LEN = 45 + AH + 2 * DH;
localparam LINE_MAX = CALIB_LEN > PASS_LEN ? CALIB_LEN : PASS_LEN;
localparam [15:0] CRLF = 16'h0d0a;

wire [24*LANES-1:0] delays;
for (genvar l = 0; l < LANES; l++) begin : g_delay
    wire [63:0] h = hex32(32'(rd_delay[l*DW +: DW]));
    assign delays[24*(LANES-1-l) +: 24] = {" ", h[15:0]};
end
wire [8*CALIB_LEN-1:0] calib_line = {calib_fail ? "calib FAIL delays" : "calib ok   delays", delays, CRLF};

wire [63:0] h_pass = hex32(32'(rep_pass)), h_errors = hex32(rep_errors), h_addr = hex32(32'(rep_addr));
wire [63:0] h_got = hex32(32'(rep_got)), h_want = hex32(32'(rep_want));
wire [8*PASS_LEN-1:0] pass_line = {"pass ", h_pass[31:0], " errors ", h_errors, " first ", h_addr[8*AH-1:0],
                                   " got ", h_got[8*DH-1:0], " want ", h_want[8*DH-1:0], CRLF};

reg [8*LINE_MAX-1:0] line;
reg [$clog2(LINE_MAX+1)-1:0] line_len;
initial begin
    line = 0;
    line_len = 0;
end
wire tx_ready;

// a pass report while the line is still busy is left out
always @(posedge clk) begin
    if (say_calib && line_len == 0) begin
        line <= (8*LINE_MAX)'(calib_line) << 8 * (LINE_MAX - CALIB_LEN);
        line_len <= CALIB_LEN[$bits(line_len)-1:0];
    end else if (say_pass && line_len == 0) begin
        line <= (8*LINE_MAX)'(pass_line) << 8 * (LINE_MAX - PASS_LEN);
        line_len <= PASS_LEN[$bits(line_len)-1:0];
    end else if (line_len != 0 && tx_ready) begin
        line <= line << 8;
        line_len <= line_len - 1'd1;
    end
end

uart_tx #(.CLK_FREQ(SYS_FREQ), .BAUD(BAUD)) uart(
    .clk(clk), .data(line[8*LINE_MAX-1 -: 8]), .valid(line_len != 0), .ready(tx_ready), .tx(uart_tx)
);

endmodule

`endif /* module_ddr3_test */
