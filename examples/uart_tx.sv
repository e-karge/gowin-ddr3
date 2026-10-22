`ifndef module_uart_tx
`define module_uart_tx

// UART transmitter, 8N1. data is taken when valid and ready are both high.
module uart_tx #(
    parameter CLK_FREQ = 27_000_000,
    parameter BAUD     = 115_200
) (
    input            clk,
    input      [7:0] data,
    input            valid,
    output           ready,
    output reg       tx
);

initial tx = 1;

localparam DIV = CLK_FREQ / BAUD;

reg [$clog2(DIV)-1:0] cnt;
reg [3:0] bits;                 // bits left, 0 when idle
reg [8:0] shift;
initial begin
    cnt = 0;
    bits = 0;
    shift = '1;
end

assign ready = bits == 0;

always @(posedge clk) begin
    if (ready) begin
        if (valid) begin
            shift <= {data, 1'b0};
            bits <= 10;
            cnt <= 0;
        end
    end else if (cnt == $clog2(DIV)'(DIV - 1)) begin
        cnt <= 0;
        tx <= shift[0];
        shift <= {1'b1, shift[8:1]};
        bits <= bits - 1'd1;
    end else
        cnt <= cnt + 1'd1;
end

endmodule

`endif /* module_uart_tx */
