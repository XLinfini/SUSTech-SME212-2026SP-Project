`define SEG_SEL_NULL  4'b0000
`define SEG_SEL_0     4'b0001
`define SEG_SEL_1     4'b0010
`define SEG_SEL_2     4'b0100
`define SEG_SEL_3     4'b1000

module SegWrapper #(
   parameter CLK_FREQ = 50_000_000,
   parameter SEG_FLASH_DUR = 49_999,
   parameter ROW_ADDR_WIDTH = 5,
   parameter COL_ADDR_WIDTH = 5
) (
   input                            clk,
   input                            rstn,
   input      [1:0]                 disp_mode, 
   input      [12:0]                detect_time,
   input      [2:0]                 disp_peak_idx,
   input      [ROW_ADDR_WIDTH-1:0]  disp_peak_row,
   input      [COL_ADDR_WIDTH-1:0]  disp_peak_col,
   input      [7:0]                 disp_peak_val,
   output     [3:0]                 seg_sel,
   output     [7:0]                 seg_data
);

// TODO - implement 7-segments tube display logic here
//      -  following code NEED TO REMOVE IN YOUR CODE
assign seg_sel = `SEG_SEL_NULL;
assign seg_data = 8'hff;

endmodule