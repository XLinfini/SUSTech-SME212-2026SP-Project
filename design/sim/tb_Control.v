`timescale 1ns/1ns

module tb_Control();
    parameter CLK_FREQ = 1_000_000;
    parameter CLK_PERIOD = 1000;

    reg clk = 0;
    reg rstn = 1;
    reg sw = 0;
    reg [6:0] keys = 7'h7f;
    wire [7:0] led;
    wire detect_start;
    reg detect_finish = 0;
    reg [2:0] detect_peak_num = 0;
    wire [12:0] detect_time;
    wire [1:0] disp_mode;
    wire [2:0] disp_peak_idx;
    wire bram_wr_start;

    Control #(
        .CLK_FREQ(CLK_FREQ)
    ) u_Control (
        .clk            (clk),
        .rstn           (rstn),
        .sw             (sw),
        .keys           (keys),
        .led            (led),
        .detect_start   (detect_start),
        .detect_finish  (detect_finish),
        .detect_peak_num(detect_peak_num),
        .detect_time    (detect_time),
        .disp_mode      (disp_mode),
        .disp_peak_idx  (disp_peak_idx),
        .bram_wr_start  (bram_wr_start)
    );

    /*
        需要测试的有：
        1. 默认状态下，led0是否为暗；STATE_RUNNING状态下，led0是否闪烁；STATE_DONE状态下，led0是否常亮
        2. STATE_DONE状态下，亮起的led数量是否等于detect_peak_num，且闪烁的led对应正显示的峰值编号
        3. 按下对应按键，disp_mode能否在3种显示模式间切换，或在不同峰值间切换
    */

    always #(CLK_PERIOD/2) clk = ~clk;

    integer error_count = 0;

    localparam STATE_INITED  = 3'b000;
    localparam STATE_PENDING = 3'b010;
    localparam STATE_RUNNING = 3'b011;
    localparam STATE_DONE    = 3'b100;

    localparam SEG_MODE_NONE = 2'b00;
    localparam SEG_MODE_TIME = 2'b01;
    localparam SEG_MODE_POS  = 2'b10;
    localparam SEG_MODE_VAL  = 2'b11;

    task report_error;
        input [255:0] msg;
        begin
            error_count = error_count + 1;
            $display("[ERROR] %0t: %0s", $time, msg);
        end
    endtask

    task reset_system;
        begin
            sw = 0;
            keys = 7'h7f;
            detect_finish = 0;
            detect_peak_num = 0;
            rstn = 0;
            repeat (5) @(posedge clk);
            rstn = 1;
            repeat (5) @(posedge clk);
        end
    endtask

    task force_state;
        input [2:0] state;
        begin
            force u_Control.current_state = state;
            repeat (2) @(posedge clk);
        end
    endtask

    task press_key;
        input integer key_idx;
        begin
            keys[key_idx] = 1'b0;
            repeat (CLK_FREQ/50 + 10) @(posedge clk);
            keys[key_idx] = 1'b1;
            repeat (CLK_FREQ/50 + 10) @(posedge clk);
        end
    endtask

    task wait_blink_edge;
        output reg before_value;
        output reg after_value;
        begin
            before_value = led[0];
            repeat (CLK_FREQ/2 + CLK_FREQ/100) @(posedge clk);
            after_value = led[0];
        end
    endtask

    function integer count_peak_led_on;
        input [5:0] value;
        integer k;
        begin
            count_peak_led_on = 0;
            for (k = 0; k < 6; k = k + 1) begin
                if (value[k]) begin
                    count_peak_led_on = count_peak_led_on + 1;
                end
            end
        end
    endfunction

    task test_led0_state_behavior;
        reg led0_before;
        reg led0_after;
        begin
            $display("Test 1: led0 state behavior");

            force_state(STATE_PENDING);
            if (led[0] !== 1'b0) begin
                report_error("led0 should be off in default/PENDING state");
            end

            force_state(STATE_RUNNING);
            wait_blink_edge(led0_before, led0_after);
            if (led0_before === led0_after) begin
                report_error("led0 should blink in STATE_RUNNING");
            end

            force_state(STATE_DONE);
            repeat (3) @(posedge clk);
            if (led[0] !== 1'b1) begin
                report_error("led0 should stay on in STATE_DONE");
            end
        end
    endtask

    task test_peak_led_count_and_selected_blink;
        reg selected_before;
        reg selected_after;
        integer led_count;
        begin
            $display("Test 2: peak led count and selected peak blinking");

            detect_peak_num = 3'd4;
            force_state(STATE_DONE);
            press_key(3);
            repeat (5) @(posedge clk);

            led_count = count_peak_led_on(led[6:1]);
            if (led_count !== detect_peak_num) begin
                report_error("number of on peak leds should equal detect_peak_num");
            end
            if (disp_peak_idx !== 3'd2) begin
                report_error("disp_peak_idx should select key3/peak2");
            end

            selected_before = led[1 + disp_peak_idx];
            repeat (CLK_FREQ/2 + CLK_FREQ/100) @(posedge clk);
            selected_after = led[1 + disp_peak_idx];
            if (selected_before === selected_after) begin
                report_error("selected peak led should blink");
            end
            if (led[1] !== 1'b1 || led[2] !== 1'b1 || led[4] !== 1'b1) begin
                report_error("non-selected valid peak leds should stay on");
            end
            if (led[5] !== 1'b0 || led[6] !== 1'b0) begin
                report_error("peak leds beyond detect_peak_num should stay off");
            end
        end
    endtask

    task test_display_mode_and_peak_switch;
        begin
            $display("Test 3: display mode and peak index switch");

            detect_peak_num = 3'd6;
            force_state(STATE_DONE);

            force u_Control.disp_mode_r = SEG_MODE_NONE;
            force u_Control.disp_peak_idx_r = 3'b111;
            repeat (2) @(posedge clk);
            release u_Control.disp_mode_r;
            release u_Control.disp_peak_idx_r;

            press_key(2);
            if (disp_peak_idx !== 3'd1 || disp_mode !== SEG_MODE_TIME) begin
                report_error("first key2 press should select peak1 and TIME mode");
            end

            press_key(2);
            if (disp_peak_idx !== 3'd1 || disp_mode !== SEG_MODE_POS) begin
                report_error("second key2 press should switch to POS mode");
            end

            press_key(2);
            if (disp_peak_idx !== 3'd1 || disp_mode !== SEG_MODE_VAL) begin
                report_error("third key2 press should switch to VAL mode");
            end

            press_key(2);
            if (disp_peak_idx !== 3'd1 || disp_mode !== SEG_MODE_TIME) begin
                report_error("fourth key2 press should switch back to TIME mode");
            end

            press_key(5);
            if (disp_peak_idx !== 3'd4 || disp_mode !== SEG_MODE_TIME) begin
                report_error("key5 press should switch to peak4 and keep current display mode");
            end
        end
    endtask

    initial begin
        $dumpfile("tb_Control.vcd");
        $dumpvars;

        reset_system();
        test_led0_state_behavior();
        test_peak_led_count_and_selected_blink();
        test_display_mode_and_peak_switch();

        if (error_count == 0) begin
            $display("All Control tests passed!");
        end
        else begin
            $display("Control tests failed, error_count = %0d", error_count);
        end

        $finish;
    end

    initial begin
        #(64'd10 * CLK_PERIOD * CLK_FREQ) $display("Test timeout!");
        $finish;
    end
endmodule
