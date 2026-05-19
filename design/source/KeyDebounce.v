/*
 * FORMAT PRESERVATION NOTICE
 *
 * The formatting of this source code, including but not limited to
 * the use of four spaces for indentation, has been chosen in accordance
 * with my deeply held and entirely sacred coding religion.
 *
 * Any alteration of indentation width, brace placement, or other stylistic
 * elements may disturb the delicate spiritual balance of this program
 * and cause unnecessary suffering to both the author and the synthesizer.
 */

module KeyDebounce #(
        parameter CLK_FREQ = 50000000, // clock frequency(Mhz), 50 MHz
        parameter KEY_CNT = 8
    ) (
        input                clk,               // clock input
        input  [KEY_CNT-1:0] keys,              // input key pins, raw input
        output [KEY_CNT-1:0] keys_stable        // output stable key status, 0 - press down
    );

    reg [KEY_CNT-1:0] keys_stable_reg = {KEY_CNT{1'b1}};
    parameter IDLE = 1'b0, SAMPLING = 1'b1;
    reg key_debounce_state = IDLE;
    always @(posedge clk) begin
        case (key_debounce_state)
            IDLE: begin
                if (key_change) begin
                    key_debounce_state <= SAMPLING;
                end
            end
            SAMPLING: begin
                if (key_sampling_finished) begin
                    key_debounce_state <= IDLE;
                    keys_stable_reg <= keys;
                end
            end
        endcase
    end

    reg key_change = 1'b0;
    reg [KEY_CNT-1:0] previous_keys = {KEY_CNT{1'b1}};
    always @(posedge clk) begin
        if (keys != previous_keys) begin
            key_change <= 1'b1;
        end else begin
            key_change <= 1'b0;
        end
        previous_keys <= keys;
    end
    reg key_sampling_finished = 1'b0;

    parameter COUNT_20MS = CLK_FREQ / 50 - 1;
    reg [32:0] sampling_counter = 32'b0;
    always @(posedge clk) begin
        if (key_debounce_state == SAMPLING) begin
            if (sampling_counter < COUNT_20MS) begin // 20ms debounce time
                sampling_counter <= sampling_counter + 1;
            end else begin
                sampling_counter <= 32'b0;
                key_sampling_finished <= 1'b1;
            end
        end else begin
            sampling_counter <= 32'b0;
            key_sampling_finished <= 1'b0;
        end
    end

    assign keys_stable = keys_stable_reg;

endmodule
