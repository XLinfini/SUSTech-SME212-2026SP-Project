module UartWrapper #(
   parameter CLK_FREQ = 50_000_000,
   parameter BRAM_ADDR_WIDTH = 10,
   parameter BAUD_RATE = 115200,
   parameter BPS_NUM = 16'd434 // CLK_FREQ/BAUD_RATE
) (
   input                            clk,
   input                            rstn,
   // hardware interface of UART
   input                            uart_rx,
   output                           uart_tx,
   // system control signals
   input                            bram_wr_start,
   // w/ BRAM: data path and control signals
   output                            bram_wr_en,
   output      [BRAM_ADDR_WIDTH-1:0] bram_wr_addr,
   output      [7:0]                 bram_wr_data
);


//==========================================================================
// internal signals
//==========================================================================

reg bram_wr_start_d1 = 1'b0;

always @(posedge clk) begin
   bram_wr_start_d1 <= (~rstn) ? 1'b0 : bram_wr_start; 
end

wire bram_wr_new_request;
assign bram_wr_new_request = (~bram_wr_start_d1) & bram_wr_start;


reg [BRAM_ADDR_WIDTH-1:0] uart_tx_data_idx = {BRAM_ADDR_WIDTH{1'b0}};

wire [BRAM_ADDR_WIDTH/2-1:0] uart_tx_data_row;
wire [BRAM_ADDR_WIDTH/2-1:0] uart_tx_data_col;
assign uart_tx_data_row = uart_tx_data_idx[BRAM_ADDR_WIDTH-1:BRAM_ADDR_WIDTH/2];
assign uart_tx_data_col = uart_tx_data_idx[BRAM_ADDR_WIDTH/2-1:0];


wire uart_tx_packet_end;
assign uart_tx_packet_end = (uart_tx_data_idx == {BRAM_ADDR_WIDTH{1'b1}}) ? 1'b1 : 1'b0;


//==========================================================================
// UART receive, for 1 byte data receive 
//==========================================================================
wire [7:0]     rx_data;        // data received
wire           rx_en;          // data received flag, high active    
reg            rx_en_d1;       //             : delay 1 clock
wire           rx_busy;        // receiver is busy

uart_rx #(
   .CLK_FREQ            (  CLK_FREQ      ),
   .BAUD_RATE           (  BAUD_RATE     )
)
u_uart_rx (                        
   .clk                 (  clk           ),// input             clk,
   .rstn                (  rstn          ),// input             rstn,                        
   .uart_rx             (  uart_rx       ),// input             uart_rx,            
   .rx_data             (  rx_data       ),// output reg [7:0]  rx_data,                                   
   .rx_en               (  rx_en         ),// output reg        rx_en,                          
   .rx_busy             (  rx_busy       ) // output            rx_busy           
);

always @(posedge clk) begin
   rx_en_d1 <= (~rstn) ? 1'b0 : rx_en;
end 

wire uart_new_received;
assign uart_new_received = (~rx_en_d1) & rx_en;


//==========================================================================
// UART transmit, for 1 byte data send 
//==========================================================================

wire           tx_busy;         // transmitter is free  
reg            tx_busy_d1;      //             : delay 1 clock
reg     [7:0]  tx_data;         // data need to send out                                    
reg            tx_en = 1'b0;    // enable transmit.

uart_tx #(
   .CLK_FREQ            (  CLK_FREQ       ),
   .BPS_NUM             (  BPS_NUM        )
) 
u_uart_tx(
   .clk                 (  clk           ),  // input            clk,     
   .rstn                (  rstn          ),  // input            rstn,          
   .tx_data             (  tx_data       ),  // input [7:0]      tx_data,           
   .tx_pluse            (  tx_en         ),  // input            tx_pluse,          
   .uart_tx             (  uart_tx       ),  // output reg       uart_tx,                                  
   .tx_busy             (  tx_busy       )   // output           tx_busy            
);   

always @(posedge clk) begin
   tx_busy_d1 <= (~rstn) ? 1'b0 : tx_busy;
end 

wire uart_tx_finished;
assign uart_tx_finished = (~tx_busy) & tx_busy_d1;


//==========================================================================
// UART Encode, for 1 packet data (many bytes inside) to send
//==========================================================================
parameter UART_ENCODE_TX_ROW = 3'b000;
parameter UART_ENCODE_TX_COL = 3'b100;
parameter UART_ENCODE_TX_WAIT = 3'b111;

reg [2:0] uart_tx_cur_state = UART_ENCODE_TX_ROW;
reg [2:0] uart_tx_nxt_state = UART_ENCODE_TX_ROW;

always @(posedge clk) begin
   if (~rstn) begin
      uart_tx_cur_state <= UART_ENCODE_TX_WAIT;
   end 
   else begin
      uart_tx_cur_state <= uart_tx_nxt_state;
   end 
end 

always @(*) begin
   if (~rstn) begin
      uart_tx_nxt_state = UART_ENCODE_TX_WAIT;
   end 
   else begin
      case (uart_tx_cur_state)
         UART_ENCODE_TX_ROW: begin
            uart_tx_nxt_state = uart_tx_finished ? UART_ENCODE_TX_COL : UART_ENCODE_TX_ROW;
         end 
         UART_ENCODE_TX_COL: begin
            uart_tx_nxt_state = uart_tx_finished ? UART_ENCODE_TX_WAIT : UART_ENCODE_TX_COL;
         end 
         UART_ENCODE_TX_WAIT: begin
            if (bram_wr_new_request) uart_tx_nxt_state = UART_ENCODE_TX_ROW;
            else if (uart_new_received && (~uart_tx_packet_end)) uart_tx_nxt_state = UART_ENCODE_TX_ROW;
            else uart_tx_nxt_state = UART_ENCODE_TX_WAIT;
         end
         default: begin
            uart_tx_nxt_state = UART_ENCODE_TX_WAIT;
         end 
      endcase 
   end 
end 
//////////////////////////////////////////////////////////////////////

///// update uart_tx_data_idx, that requesting data row/col to PC ////
always @(posedge clk) begin
   if (~rstn || bram_wr_new_request) begin
      uart_tx_data_idx <= {BRAM_ADDR_WIDTH{1'b0}};
   end 
   else if (uart_new_received && (~uart_tx_packet_end)) begin 
      // has received response for last transmited, request next data
      uart_tx_data_idx <= uart_tx_data_idx + 1;
   end 
end 
//////////////////////////////////////////////////////////////////////

///////////////// udpate tx_data, based on current state /////////////
always @(posedge clk) begin
   if ((~rstn) || (~bram_wr_start)) begin
      tx_data <= 8'b0;
   end 
   // following case is under bram_wr_start
   else if (uart_tx_cur_state == UART_ENCODE_TX_ROW) begin
      if (BRAM_ADDR_WIDTH/2 == 6) begin
         tx_data <= {UART_ENCODE_TX_ROW[2:1], uart_tx_data_row};
      end 
      else begin 
         tx_data <= {UART_ENCODE_TX_ROW, uart_tx_data_row};
      end 
   end 
   else if (uart_tx_cur_state == UART_ENCODE_TX_COL) begin 
      if (BRAM_ADDR_WIDTH/2 == 6) begin
         tx_data <= {UART_ENCODE_TX_COL[2:1], uart_tx_data_col};
      end 
      else begin 
         tx_data <= {UART_ENCODE_TX_COL, uart_tx_data_col};
      end 
   end
end 
//////////////////////////////////////////////////////////////////////

////////////// control tx_en signal, with speed control //////////////
reg [7:0] uart_wait_cnt = 1;

always @(posedge clk) begin
   if (~rstn) begin
      tx_en <= 1'b0;
      uart_wait_cnt <= 8'b1;
   end  
   else if (bram_wr_new_request || uart_tx_finished) begin
      tx_en <= 1'b0;
      uart_wait_cnt <= 8'b1;
   end 
   else begin
      if (uart_wait_cnt != 8'b0) begin
         tx_en <= 1'b0;
         uart_wait_cnt <= uart_wait_cnt + 8'b1;
      end  
      else begin
         tx_en <= (uart_tx_cur_state != UART_ENCODE_TX_WAIT) ? 1'b1 : 1'b0;
         uart_wait_cnt <= 8'b0;
      end 
   end
end 
//////////////////////////////////////////////////////////////////////


//==========================================================================
// UART Decode, for 1 packet data (1 bytes inside) received
//==========================================================================

reg         bram_wr_en_r = 1'b0;
reg [BRAM_ADDR_WIDTH-1:0]   bram_wr_addr_r = 0;
reg [7:0]   bram_wr_data_r = 8'b0;

always @(posedge clk) begin
   if ((~rstn) || (~bram_wr_start)) begin
      bram_wr_en_r <= 1'b0;
      bram_wr_addr_r <= {BRAM_ADDR_WIDTH{1'b0}};
      bram_wr_data_r <= 8'b0;
   end 
   else begin
      if (uart_new_received && bram_wr_start) begin
         bram_wr_en_r <= 1'b1;
         bram_wr_addr_r <= {uart_tx_data_row, uart_tx_data_col};
         bram_wr_data_r <= rx_data;
      end 
   end 
end

assign bram_wr_en = bram_wr_en_r;
assign bram_wr_data = bram_wr_data_r;
assign bram_wr_addr = bram_wr_addr_r;

endmodule
