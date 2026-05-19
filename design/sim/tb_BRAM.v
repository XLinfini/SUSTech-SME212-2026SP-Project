`timescale 1ns / 1ps

`define BOARD_CK 50000000 // 50 MHz clock frequency
`define BRAM_ADD_WIDTH  16

module tb_BRAM();

//###############################
//GTP_GRS
//###############################
   reg grs_n;
   GTP_GRS GRS_INST(
      .GRS_N (grs_n)
   );

   reg CLK = 0;

   reg RES = 1;

   always #(500e6/`BOARD_CK) CLK = !CLK; // clock generator

   reg  [`BRAM_ADD_WIDTH-1:0] RAM_ADDR = 0;
   reg  [7:0] RAM_DATAI = 8'h00;
   wire [7:0] RAM_DATAO;
   reg  RAM_WREN = 0;

   BRAM uut (
      .wr_data(RAM_DATAI),    // input [7:0]
      .wr_addr(RAM_ADDR),    // input [`BRAM_ADD_WIDTH-1:0]
      .wr_en(RAM_WREN),        // input
      .wr_clk(CLK),      // input
      .wr_rst(RES),      // input
      .rd_addr(RAM_ADDR),    // input [`BRAM_ADD_WIDTH-1:0]
      .rd_data(RAM_DATAO),    // output [7:0]
      .rd_clk(CLK),      // input
      .rd_rst(RES)       // input
   );

   // 复位 任务
	task task_reset;
	begin
      grs_n = 1'b0;
		RES = 1'b1;
      #5000;
		grs_n = 1'b1;
		RES = 1'b0;
	end
	endtask

   reg [10:0] i; 

   initial begin 

      task_reset;
      #100;

      for (i = 0; i < 1024; i = i + 1) begin
         @(posedge CLK) begin
            RAM_ADDR = i; // address 0
         end 
         @(posedge CLK);
         @(posedge CLK);
      end

      #100 $finish;
   end

   initial
   begin
      $dumpfile("tb_bram.vcd");
      $dumpvars();
   end

endmodule