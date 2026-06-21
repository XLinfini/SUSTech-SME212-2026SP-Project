module uart_rx #(
    // clock frequency
    parameter  CLK_FREQ  = 50_000_000,   // clk frequency, Unit : Hz
    // UART format
    parameter  BAUD_RATE = 115200,       // Unit : Hz
    parameter  PARITY    = "NONE"        // "NONE", "ODD", or "EVEN"
)
(
      //input ports
      input             clk     ,
      input             rstn    ,        // reset
      input             uart_rx ,
    
      //output ports
      output [7:0]      rx_data ,
      output            rx_en   ,
      output            rx_busy
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// Generate fractional precise upper limit for counter
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
localparam  BAUD_CYCLES      = ( (CLK_FREQ*10*2 + BAUD_RATE) / (BAUD_RATE*2) ) / 10 ;
localparam  BAUD_CYCLES_FRAC = ( (CLK_FREQ*10*2 + BAUD_RATE) / (BAUD_RATE*2) ) % 10 ;

localparam           HALF_BAUD_CYCLES =  BAUD_CYCLES    / 2;
localparam  THREE_QUARTER_BAUD_CYCLES = (BAUD_CYCLES*3) / 4;

localparam [9:0] ADDITION_CYCLES = (BAUD_CYCLES_FRAC == 0) ? 10'b0000000000 :
                                   (BAUD_CYCLES_FRAC == 1) ? 10'b0000010000 :
                                   (BAUD_CYCLES_FRAC == 2) ? 10'b0010000100 :
                                   (BAUD_CYCLES_FRAC == 3) ? 10'b0010010010 :
                                   (BAUD_CYCLES_FRAC == 4) ? 10'b0101001010 :
                                   (BAUD_CYCLES_FRAC == 5) ? 10'b0101010101 :
                                   (BAUD_CYCLES_FRAC == 6) ? 10'b1010110101 :
                                   (BAUD_CYCLES_FRAC == 7) ? 10'b1101101101 :
                                   (BAUD_CYCLES_FRAC == 8) ? 10'b1101111011 :
                                  /*BAUD_CYCLES_FRAC == 9)*/ 10'b1111101111 ;

wire [31:0] cycles [9:0];

assign cycles[0] = BAUD_CYCLES + (ADDITION_CYCLES[0] ? 1 : 0);
assign cycles[1] = BAUD_CYCLES + (ADDITION_CYCLES[1] ? 1 : 0);
assign cycles[2] = BAUD_CYCLES + (ADDITION_CYCLES[2] ? 1 : 0);
assign cycles[3] = BAUD_CYCLES + (ADDITION_CYCLES[3] ? 1 : 0);
assign cycles[4] = BAUD_CYCLES + (ADDITION_CYCLES[4] ? 1 : 0);
assign cycles[5] = BAUD_CYCLES + (ADDITION_CYCLES[5] ? 1 : 0);
assign cycles[6] = BAUD_CYCLES + (ADDITION_CYCLES[6] ? 1 : 0);
assign cycles[7] = BAUD_CYCLES + (ADDITION_CYCLES[7] ? 1 : 0);
assign cycles[8] = BAUD_CYCLES + (ADDITION_CYCLES[8] ? 1 : 0);
assign cycles[9] = BAUD_CYCLES + (ADDITION_CYCLES[9] ? 1 : 0);



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// Input beat
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
reg        rx_d1 = 1'b0;

always @ (posedge clk)
    if (~rstn)
        rx_d1 <= 1'b0;
    else
        rx_d1 <= uart_rx;



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// count continuous '1'
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
reg [31:0] count1 = 0;

always @ (posedge clk)
    if (~rstn) begin
        count1 <= 0;
    end else begin
        if (rx_d1)
            count1 <= (count1 < 'hFFFFFFFF) ? (count1 + 1) : count1;
        else
            count1 <= 0;
    end



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// main FSM
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
localparam [ 3:0] TOTAL_BITS_MINUS1 = (PARITY == "ODD" || PARITY == "EVEN") ? 4'd9 : 4'd8;

localparam [ 1:0] S_IDLE     = 2'd0 ,
                  S_RX       = 2'd1 ,
                  S_STOP_BIT = 2'd2 ;

reg        [ 1:0] state   = S_IDLE;
reg        [ 8:0] rxbits  = 9'b0;
reg        [ 3:0] rxcnt   = 4'd0;
reg        [31:0] cycle   = 1;
reg        [32:0] countp  = 33'h1_0000_0000;       // countp>=0x100000000 means '1' is majority       , countp<0x100000000 means '0' is majority
wire              rxbit   = countp[32];            // countp>=0x100000000 corresponds to countp[32]==1, countp<0x100000000 corresponds to countp[32]==0

wire [ 7:0] rbyte   = (PARITY == "ODD" ) ? rxbits[7:0] : 
                      (PARITY == "EVEN") ? rxbits[7:0] : 
                    /*(PARITY == "NONE")*/ rxbits[8:1] ;

wire parity_correct = (PARITY == "ODD" ) ? ((~(^(rbyte))) == rxbits[8]) : 
                      (PARITY == "EVEN") ? (  (^(rbyte))  == rxbits[8]) : 
                    /*(PARITY == "NONE")*/      1'b1                    ;


always @ (posedge clk)
    if (~rstn) begin
        state    <= S_IDLE;
        rxbits   <= 9'b0;
        rxcnt    <= 4'd0;
        cycle    <= 1;
        countp   <= 33'h1_0000_0000;
    end else begin
        case (state)
            S_IDLE : begin
                if ((count1 >= THREE_QUARTER_BAUD_CYCLES) && (rx_d1 == 1'b0))  // receive a '0' which is followed by continuous '1' for half baud cycles
                    state <= S_RX;
                rxcnt  <= 4'd0;
                cycle  <= 2;                                                   // we've already receive a '0', so here cycle  = 2
                countp <= (33'h1_0000_0000 - 33'd1);                           // we've already receive a '0', so here countp = initial_value - 1
            end
            
            S_RX :
                if ( cycle < cycles[rxcnt] ) begin                             // cycle loop from 1 to cycles[rxcnt]
                    cycle  <= cycle + 1;
                    countp <= rx_d1 ? (countp + 33'd1) : (countp - 33'd1);
                end else begin
                    cycle  <= 1;                                               // reset counter
                    countp <= 33'h1_0000_0000;                                 // reset counter
                    
                    if ( rxcnt < TOTAL_BITS_MINUS1 ) begin                     // rxcnt loop from 0 to TOTAL_BITS_MINUS1
                        rxcnt <= rxcnt + 4'd1;
                        if ((rxcnt == 4'd0) && (rxbit == 1'b1))                // except start bit, but get '1'
                            state <= S_IDLE;                                   // RX failed, back to IDLE
                    end else begin
                        rxcnt <= 4'd0;
                        state <= S_STOP_BIT;
                    end
                    
                    rxbits <= {rxbit, rxbits[8:1]};                            // put current rxbit to MSB of rxbits, and right shift other bits
                end
            
            default :  // S_STOP_BIT
                if ( cycle < THREE_QUARTER_BAUD_CYCLES) begin                  // cycle loop from 1 to THREE_QUARTER_BAUD_CYCLES
                    cycle <= cycle + 1;
                end else begin
                    cycle <= 1;                                                // reset counter
                    state <= S_IDLE;                                           // back to IDLE
                end
        endcase
    end



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// RX result byte
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
reg       f_tvalid = 1'b0;
reg [7:0] f_tdata  = 8'h0;

always @ (posedge clk)
    if (~rstn) begin
        f_tvalid <= 1'b0;
        f_tdata  <= 8'h0;
    end else begin
        if (state == S_IDLE) begin
            f_tvalid <= 1'b0;
        end 
        else if (state == S_RX) begin
            f_tvalid <= 1'b0;
            f_tdata  <= 8'h0;
        end 
        else if (state == S_STOP_BIT) begin
            if ( cycle < THREE_QUARTER_BAUD_CYCLES) begin
            end else begin
                if ((count1 >= HALF_BAUD_CYCLES) && parity_correct) begin  // stop bit have enough '1', and parity correct
                    f_tvalid <= 1'b1;
                    f_tdata  <= rbyte;                                     // received a correct byte, output it
                end
            end
        end
    end


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// Adapter
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
assign rx_en   = f_tvalid;
assign rx_data = f_tdata;
assign rx_busy = (state == S_IDLE) ? 1'b0 : 1'b1;

endmodule
