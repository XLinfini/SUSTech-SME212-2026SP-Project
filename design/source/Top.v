module Top #(
    parameter CLK_FREQ = 32'd50_000_000,
    parameter DATA_COLS = 64, 
    parameter DATA_ROWS = 64, 
    parameter COLS_ADDR_WIDTH = 6, 
    parameter ROWS_ADDR_WIDTH = 6  
) (
    input             clk,
    input             rstn,
    input      [7:0]  sw,
    input      [6:0]  keys, 
    // UART interface
    input             uart_rx,
    output            uart_tx,
    // LED indicators
    output     [7:0]  led,
    // 7-segment display tubes
    output     [3:0]  seg_sel,
    output     [7:0]  seg_data
);


//==========================================================================
// PLL, generate core clock signals: 
//          - core_clk, 50MHz, which is used for core logic, can be changed
//==========================================================================

wire pll_lock;
wire core_clk;

pll u_pll (
  .pll_rst(~rstn),        // input
  .clkin1(clk),           // input
  .pll_lock(pll_lock),    // output
  .clkout0(core_clk)      // output
);

wire sys_rstn;
assign sys_rstn = pll_lock & rstn;


//==========================================================================
// Control signals
//==========================================================================

wire detect_start;
wire detect_finish;
wire [2:0] detect_peak_num;
wire [12:0] detect_time;

wire [1:0] disp_mode;
wire [2:0] disp_peak_idx;
wire [ROWS_ADDR_WIDTH-1:0] disp_peak_row;
wire [COLS_ADDR_WIDTH-1:0] disp_peak_col;
wire [7:0] disp_peak_val;

wire bram_wr_start;


Control #(
    .CLK_FREQ(CLK_FREQ)
) u_control (
    // clock input
    .clk    (clk),
    // system reset, low active
    .rstn   (sys_rstn),
    // switch & key pins, raw input
    .sw     (sw[7]),
    .keys   (keys),
    // LED indicators outputs
    .led    (led),
    // core detection related signals 
    .detect_start   (detect_start),
    .detect_finish  (detect_finish),
    .detect_peak_num(detect_peak_num),
    .detect_time    (detect_time), // us
    // 7-segment display mode control
    .disp_mode      (disp_mode), 
    .disp_peak_idx  (disp_peak_idx),
    // BRAM control signals
    .bram_wr_start  (bram_wr_start)
);


//==========================================================================
// BRAM - stored image data
//          which write from UART, and read by core logic 
//==========================================================================

wire bram_wr_en;
wire [7:0] bram_wr_data;
wire [15:0] bram_wr_addr;
wire [7:0] bram_rd_data;
wire [15:0] bram_rd_addr;

BRAM u_bram (
  .wr_data(bram_wr_data),    // input [7:0]
  .wr_addr(bram_wr_addr),    // input [15:0]
  .wr_en(bram_wr_en),        // input
  .wr_clk(clk),          // input
  .wr_rst(~rstn),        // input
  .rd_addr(bram_rd_addr),    // input [15:0]
  .rd_data(bram_rd_data),    // output [7:0]
  .rd_clk(core_clk),         // input
  .rd_rst(~rstn)         // input
);


//==========================================================================
// 7-segment display wrapper
//==========================================================================

SegWrapper #(
  .CLK_FREQ (CLK_FREQ),
  .ROW_ADDR_WIDTH(ROWS_ADDR_WIDTH),
  .COL_ADDR_WIDTH(COLS_ADDR_WIDTH)
) u_seg (
    .clk            (clk),
    .rstn           (sys_rstn),
    .disp_mode      (disp_mode), 
    .detect_time    (detect_time),
    .disp_peak_idx  (disp_peak_idx),
    .disp_peak_row  (disp_peak_row),
    .disp_peak_col  (disp_peak_col),
    .disp_peak_val  (disp_peak_val),
    .seg_sel        (seg_sel),
    .seg_data       (seg_data)
);


//==========================================================================
// Uart wrapper
//          which read image data by UART from PC host,
//          and write to BRAM
//==========================================================================

wire [ROWS_ADDR_WIDTH+COLS_ADDR_WIDTH-1:0] bram_wr_addr_from_uart;

UartWrapper #(
   .CLK_FREQ (CLK_FREQ),
   .BRAM_ADDR_WIDTH(ROWS_ADDR_WIDTH+COLS_ADDR_WIDTH)
) u_uart_wrapper (
   .clk            (clk),
   .rstn           (sys_rstn),
   .uart_rx        (uart_rx),
   .uart_tx        (uart_tx),
   .bram_wr_start  (bram_wr_start),
   // w/ BRAM: data path and control signals
   .bram_wr_en     (bram_wr_en),
   .bram_wr_addr   (bram_wr_addr_from_uart),
   .bram_wr_data   (bram_wr_data)
);

assign bram_wr_addr = {sw, bram_wr_addr_from_uart};


//==========================================================================
// Core logic
//          - image data read from BRAM
//          - do peak detection
//          - output detection result
//          - NOTE: cross-clock domain signals synchronization
//==========================================================================

reg [1:0] detect_start_d;
always @(posedge core_clk) begin
    if (~sys_rstn) begin
        detect_start_d <= 2'b0;
    end 
    else begin
        detect_start_d <= {detect_start_d[0], detect_start};
    end 
end

wire detect_finish_w;
reg [1:0] detect_finish_d;
assign detect_finish = detect_finish_d[1];
always @(posedge clk) begin
    if (~sys_rstn) begin
        detect_finish_d <= 2'b0;
    end 
    else begin
        detect_finish_d <= {detect_finish_d[0], detect_finish_w};
    end 
end

reg [2:0] detect_peak_num_d0;
reg [2:0] detect_peak_num_d1;
wire [2:0] detect_peak_num_w;
assign detect_peak_num = detect_peak_num_d1;
always @(posedge clk) begin
    if (~sys_rstn) begin
        detect_peak_num_d0 <= 3'b0;
        detect_peak_num_d1 <= 3'b0;
    end 
    else begin
        detect_peak_num_d0 <= detect_peak_num_w;
        detect_peak_num_d1 <= detect_peak_num_d0;
    end
end

reg [2:0] disp_peak_idx_d0;
reg [2:0] disp_peak_idx_d1;
always @(posedge core_clk) begin
    if (~sys_rstn) begin
        disp_peak_idx_d0 <= 3'b0;
        disp_peak_idx_d1 <= 3'b0;
    end 
    else begin
        disp_peak_idx_d0 <= disp_peak_idx;
        disp_peak_idx_d1 <= disp_peak_idx_d0;
    end
end

wire [ROWS_ADDR_WIDTH-1:0] disp_peak_row_w;
wire [COLS_ADDR_WIDTH-1:0] disp_peak_col_w;
wire [7:0] disp_peak_val_w;
reg [ROWS_ADDR_WIDTH-1:0] disp_peak_row_d0;
reg [COLS_ADDR_WIDTH-1:0] disp_peak_col_d0;
reg [7:0] disp_peak_val_d0;
reg [ROWS_ADDR_WIDTH-1:0] disp_peak_row_d1;
reg [COLS_ADDR_WIDTH-1:0] disp_peak_col_d1;
reg [7:0] disp_peak_val_d1;
assign disp_peak_row = disp_peak_row_d1;
assign disp_peak_col = disp_peak_col_d1;
assign disp_peak_val = disp_peak_val_d1;
always @(posedge clk) begin
    if (~sys_rstn) begin
        disp_peak_row_d0 <= {ROWS_ADDR_WIDTH{1'b0}};
        disp_peak_col_d0 <= {COLS_ADDR_WIDTH{1'b0}};
        disp_peak_val_d0 <= 8'b0;
        disp_peak_row_d1 <= {ROWS_ADDR_WIDTH{1'b0}};
        disp_peak_col_d1 <= {COLS_ADDR_WIDTH{1'b0}};
        disp_peak_val_d1 <= 8'b0;
    end 
    else begin
        disp_peak_row_d0 <= disp_peak_row_w;
        disp_peak_col_d0 <= disp_peak_col_w;
        disp_peak_val_d0 <= disp_peak_val_w;
        disp_peak_row_d1 <= disp_peak_row_d0;
        disp_peak_col_d1 <= disp_peak_col_d0;
        disp_peak_val_d1 <= disp_peak_val_d0;
    end
end

wire [ROWS_ADDR_WIDTH+COLS_ADDR_WIDTH-1:0] bram_rd_addr_from_core;

Core #(
    .COLS(DATA_COLS),
    .ROWS(DATA_ROWS),
    .COLS_ADDR_WIDTH(COLS_ADDR_WIDTH),
    .ROWS_ADDR_WIDTH(ROWS_ADDR_WIDTH)
) u_core (
   .clk               (core_clk),
   .rstn              (sys_rstn),
   // BRAM read interface
   .bram_rd_addr      (bram_rd_addr_from_core),
   .bram_rd_data      (bram_rd_data),
   // detection control signals
   .detect_start      (detect_start_d[1]),
   .detect_finish     (detect_finish_w),
   // detection result related signals
   .detect_peak_num   (detect_peak_num_w),
   .disp_peak_idx     (disp_peak_idx_d1),
   .disp_peak_row     (disp_peak_row_w),
   .disp_peak_col     (disp_peak_col_w),  
   .disp_peak_val     (disp_peak_val_w)
);

assign bram_rd_addr = {sw, bram_rd_addr_from_core};

endmodule