module Control #(
        // clock frequency(Mhz), 50 MHz
        parameter CLK_FREQ = 50_000_000
    ) (
        input               clk, // clock input
        input               rstn, // system reset, low active
        input               sw, // switch, raw input
        input   [6:0]       keys, // key pins, raw input
        output  [7:0]       led,// LED indicators
        output              detect_start,
        input               detect_finish,
        input   [2:0]       detect_peak_num,
        output  [12:0]      detect_time, // ms
        output  [1:0]       disp_mode,
        output  [2:0]       disp_peak_idx,
        output              bram_wr_start // BRAM control signals
    );


    //==========================================================================
    // 1ms timer - DONT MODIFY THIS CODE
    //==========================================================================

    reg  [15:0] ms_cnt;        // count 1ms
    wire        ms_tick;       // 1ms tick

    assign ms_tick = (ms_cnt == (CLK_FREQ/1000 - 1));

    always @(posedge clk) begin
        if (~rstn) begin
            ms_cnt <= 16'b0;
        end
        else if (ms_tick) begin
            ms_cnt <= 16'b0;
        end
        else begin
            ms_cnt <= ms_cnt + 16'b1;
        end
    end
    ////////////////////////////////////////////////////////////////////////////

    //==========================================================================
    // 1us timer - DONT MODIFY THIS CODE
    //==========================================================================
    reg  [5:0]  us_cnt;         // count 1us
    wire        us_tick;        // 1us tick

    assign us_tick = (us_cnt == (CLK_FREQ/1000000 - 1));

    always @(posedge clk) begin
        if (~rstn) begin
            us_cnt <= 6'b0;
        end
        else if (us_tick) begin
            us_cnt <= 6'b0;
        end
        else begin
            us_cnt <= us_cnt + 6'b1;
        end
    end
    ////////////////////////////////////////////////////////////////////////////


    //==========================================================================
    // Key debounce & events - DONT MODIFY THIS CODE
    //==========================================================================

    wire [7:0] keys_stable;

    reg  [7:0] keys_d1 = 8'hff; // keys_stable with 1 clock delay
    always @(posedge clk) begin
        keys_d1 <= keys_stable;
    end

    wire pressed_dw_key0      = keys_d1[0] & (~keys_stable[0]);
    wire pressed_dw_key1      = keys_d1[1] & (~keys_stable[1]);
    wire pressed_dw_key2      = keys_d1[2] & (~keys_stable[2]);
    wire pressed_dw_key3      = keys_d1[3] & (~keys_stable[3]);
    wire pressed_dw_key4      = keys_d1[4] & (~keys_stable[4]);
    wire pressed_dw_key5      = keys_d1[5] & (~keys_stable[5]);
    wire pressed_dw_key6      = keys_d1[6] & (~keys_stable[6]);

    wire switch_on_loading;
    assign switch_on_loading = ~keys_stable[7];

    KeyDebounce #(
                    .CLK_FREQ(CLK_FREQ),
                    .KEY_CNT(8)
                ) u_key (
                    .clk(clk),
                    .keys({~sw, keys}),
                    .keys_stable(keys_stable)
                );
    ////////////////////////////////////////////////////////////////////////////


    //==========================================================================
    // System state machine - DONT MODIFY THIS CODE
    //==========================================================================

    localparam STATE_INITED     = 3'b000;
    localparam STATE_LOADING    = 3'b001;
    localparam STATE_PENDING    = 3'b010;
    localparam STATE_RUNNING    = 3'b011;
    localparam STATE_DONE       = 3'b100;

    reg [2:0] current_state = STATE_INITED;
    reg [2:0] next_state = STATE_INITED;

    always @(posedge clk) begin
        if (~rstn) begin
            current_state <= STATE_INITED;
        end
        else begin
            current_state <= next_state;
        end
    end

    always @(*) begin
        if (~rstn)
            next_state = STATE_INITED;
        else begin
            case (current_state)
                STATE_INITED: begin
                    next_state = STATE_PENDING;
                end
                STATE_LOADING: begin
                    next_state = switch_on_loading ? STATE_LOADING : STATE_PENDING;
                end
                STATE_PENDING: begin
                    if (switch_on_loading)
                        next_state = STATE_LOADING;
                    else
                        next_state = pressed_dw_key0 ? STATE_RUNNING : STATE_PENDING;
                end
                STATE_RUNNING: begin
                    next_state = detect_finish ? STATE_DONE : STATE_RUNNING;
                end
                STATE_DONE: begin
                    if (pressed_dw_key0)
                        next_state = STATE_PENDING;
                    else
                        next_state = STATE_DONE;
                end
                default: begin
                    next_state = STATE_INITED;
                end
            endcase
        end
    end
    ////////////////////////////////////////////////////////////////////////////


    //==========================================================================
    // BRAM control signals - DONT MODIFY THIS CODE
    //==========================================================================

    assign bram_wr_start = (current_state == STATE_LOADING);

    ////////////////////////////////////////////////////////////////////////////


    //==========================================================================
    // Detect control signals - DONT MODIFY THIS CODE
    //==========================================================================
    assign detect_start = (current_state == STATE_RUNNING);


    reg [12:0] detect_time_us;

    always @(posedge clk) begin
        if (~rstn || (current_state <= STATE_PENDING)) begin
            detect_time_us <= 13'b0;
        end
        else if (us_tick && (current_state == STATE_RUNNING)) begin
            detect_time_us <= (detect_time_us < 13'h1fff)
                           ? detect_time_us + 13'b1 : detect_time_us;
        end
    end

    assign detect_time = detect_time_us;
    //////////////////////////////////////////////////////////////////////////////


    //==========================================================================
    // 7-segment display control
    //==========================================================================

    localparam SEG_MODE_NONE      = 2'b00;
    localparam SEG_MODE_TIME      = 2'b01;
    localparam SEG_MODE_POS       = 2'b10;
    localparam SEG_MODE_VAL       = 2'b11;

    reg [1:0] disp_mode_r;
    reg [2:0] disp_peak_idx_r;
    assign disp_mode = disp_mode_r;
    assign disp_peak_idx = disp_peak_idx_r;

    always @(posedge clk) begin
        if (~rstn) begin
            disp_mode_r <= SEG_MODE_NONE;
            disp_peak_idx_r <= 3'b111;
        end
        // TODO - control 7-segments tube display mode here
    end
    //////////////////////////////////////////////////////////////////////////////

    //==========================================================================
    // LED indicators output
    //==========================================================================

    ////////////////////////////// DONT MODIFY THIS CODE ////////////////////////
    reg [8:0] blink_ms = 9'd0; // count 500ms

    always @(posedge clk) begin
        if (~rstn) begin
            blink_ms <= 9'b0;
        end
        else if (ms_tick) begin
            blink_ms <= (blink_ms < 9'd500)
                     ? blink_ms + 9'b1 : 9'b0;
        end
    end

    reg led7 = 1'b0;
    always @(posedge clk) begin
        if (~rstn) begin
            led7 <= 1'b0;
        end
        else if (current_state == STATE_LOADING) begin
            led7 <= ((blink_ms == 9'd500) && ms_tick) ? ~led7 : led7;
        end
        else begin
            led7 <= 1'b1;
        end
    end
    //////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////////////////////
    reg led0 = 1'b0;
    always @(posedge clk) begin
        if (~rstn) begin
            led0 <= 1'b0;
        end
        else if (current_state == STATE_RUNNING) begin
            led0 <= ((blink_ms == 9'd500) && ms_tick) ? ~led0 : led0;
        end
        else if (current_state == STATE_DONE) begin
            led0 <= 1'b1;
        end
        else begin
            led0 <= 1'b0;
        end
    end
    //////////////////////////////////////////////////////////////////////////////


    //////////////////////////////////////////////////////////////////////////////
    reg [5:0] peak_led = 6'b0; // peak number indicator
    // TODO - implement peak-1~6 indicators logic here
    //////////////////////////////////////////////////////////////////////////////


    ////////////////////////////// DONT MODIFY THIS CODE ////////////////////////
    // assign LED output
    assign led = {led7, peak_led, led0};
    //////////////////////////////////////////////////////////////////////////////

endmodule
