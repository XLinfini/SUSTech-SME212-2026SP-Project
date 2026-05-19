module Core #(
        parameter ROWS = 64,
        parameter COLS = 64,
        parameter ROWS_ADDR_WIDTH = 6, // log2(ROWS)
        parameter COLS_ADDR_WIDTH = 6, // log2(COLS)
        parameter BRAM_ADDR_WIDTH = ROWS_ADDR_WIDTH + COLS_ADDR_WIDTH
    ) (
        input                         clk, // clock input
        input                         rstn, // system reset, low active
        output  [BRAM_ADDR_WIDTH-1:0] bram_rd_addr, // BRAM read interface
        input   [7:0]                 bram_rd_data,
        input                         detect_start, // detection control signals
        output                        detect_finish,
        output  [2:0]                 detect_peak_num, // detection result related signals
        input   [2:0]                 disp_peak_idx,
        output  [ROWS_ADDR_WIDTH-1:0] disp_peak_row,
        output  [COLS_ADDR_WIDTH-1:0] disp_peak_col,
        output  [7:0]                 disp_peak_val
    );

    // TODO - implement core detection logic here
    //      -  following code NEED TO REMOVE IN YOUR CODE
    localparam PADDING = 2;
    localparam EXTENDED_ROWS = ROWS + 2*PADDING;
    localparam EXTENDED_COLS = COLS + 2*PADDING;

    localparam CORE_IDLE = 2'd0;
    localparam CORE_ISSUING = 2'd1;
    localparam CORE_DRAINED = 2'd2;
    localparam CORE_DONE = 2'd3;
    reg [1:0] core_state = CORE_IDLE;
    assign detect_finish = (core_state == CORE_DONE);

    reg [ROWS_ADDR_WIDTH:0] extended_row_coordinate;
    reg [COLS_ADDR_WIDTH:0] extended_col_coordinate;

    wire is_extended_coordinate_valid;
    assign is_extended_coordinate_valid = (extended_row_coordinate >= PADDING) && (extended_row_coordinate < ROWS + PADDING) && (extended_col_coordinate >= PADDING) && (extended_col_coordinate < COLS + PADDING);

    wire issue_row;
    assign issue_row = (extended_row_coordinate - PADDING)[ROWS_ADDR_WIDTH-1:0];
    wire issue_col;
    assign issue_col = (extended_col_coordinate - PADDING)[COLS_ADDR_WIDTH-1:0];
    wire issue_addr;
    assign issue_addr = {issue_row, issue_col};

    reg issue_a_pixel; // TODO: 一定要把默认值设成0,不然前两拍会出bug
    reg issue_a_pixel_1before;
    reg issue_a_pixel_2before; // 两个周期之前是否请求了一个像素？也就是说，现在窗口要不要移动？
    reg is_issued_pixel_valid_delayed1; // 其实是延迟1个周期的is_extended_coordinate_valid
    reg is_issued_pixel_valid_delayed2;
    reg [ROWS_ADDR_WIDTH:0] extended_row_coordinate_delayed1;
    reg [ROWS_ADDR_WIDTH:0] extended_row_coordinate_delayed2;
    reg [COLS_ADDR_WIDTH:0] extended_col_coordinate_delayed1;
    reg [COLS_ADDR_WIDTH:0] extended_col_coordinate_delayed2;

    wire do_window_move;
    assign do_window_move = issue_a_pixel_2before; // 窗口要不要移动？
    wire is_received_pixel_valid;
    assign is_received_pixel_valid = is_issued_pixel_valid_delayed2;
    wire [ROWS_ADDR_WIDTH:0] received_pixel_row_coordinate;
    assign received_pixel_row_coordinate = extended_row_coordinate_delayed2;
    wire [COLS_ADDR_WIDTH:0] received_pixel_col_coordinate;
    assign received_pixel_col_coordinate = extended_col_coordinate_delayed2;
    wire [7:0] received_pixel_value;
    assign received_pixel_value = is_received_pixel_valid ? bram_rd_data : 8'b0;

    reg window_valid_strobe;

    reg [7:0] line_buffer [0:3][0:EXTENDED_COLS-1];
    reg line_valid_buffer [0:3][0:EXTENDED_COLS-1];

    reg [7:0] window [0:4][0:4];
    reg window_valid [0:4][0:4];
    wire [7:0] center_value;
    assign center_value = window[2][2];
    wire is_center_value_valid;
    assign is_center_value_valid = window_valid[2][2];
    wire [ROWS_ADDR_WIDTH-1:0] center_real_row_coordinate;
    assign center_real_row_coordinate = received_pixel_row_coordinate - 4;
    wire [COLS_ADDR_WIDTH-1:0] center_real_col_coordinate;
    assign center_real_col_coordinate = received_pixel_col_coordinate - 4;
    wire center_real_addr;
    assign center_real_addr = {center_real_row_coordinate, center_real_col_coordinate};

    integer i;
    integer j;

    always @(posedge clk) begin
        if (!rstn) begin
            // TODO: reset logic
        end

        issue_a_pixel_1before <= (core_state == CORE_ISSUING);
        issue_a_pixel_2before <= issue_a_pixel_1before;
        is_issued_pixel_valid_delayed1 <= is_extended_coordinate_valid;
        is_issued_pixel_valid_delayed2 <= is_issued_pixel_valid_delayed1;
        extended_row_coordinate_delayed1 <= extended_row_coordinate;
        extended_row_coordinate_delayed2 <= extended_row_coordinate_delayed1;
        extended_col_coordinate_delayed1 <= extended_col_coordinate;
        extended_col_coordinate_delayed2 <= extended_col_coordinate_delayed1;
        window_valid_strobe <= do_window_move;

        case(core_state)
            CORE_IDLE: begin
                bram_rd_addr <= {BRAM_ADDR_WIDTH{1'b0}};
                issue
            end
            CORE_ISSUING: begin
                bram_rd_addr <= is_extended_coordinate_valid ? issue_addr : {BRAM_ADDR_WIDTH{1'b0}};

                if (extended_row_coordinate == EXTENDED_ROWS - 1 && extended_col_coordinate == EXTENDED_COLS - 1) begin
                    core_state <= CORE_DRAINED;
                end

                if (extended_col_coordinate == EXTENDED_COLS - 1) begin
                    extended_col_coordinate <= 0;
                    extended_row_coordinate <= extended_row_coordinate + 1;
                end else begin
                    extended_col_coordinate <= extended_col_coordinate + 1;
                end
            end
            CORE_DRAINED: begin
            end
            CORE_DONE: begin
            end
        endcase

        if (do_window_move) begin
            line_buffer[3][received_pixel_col_coordinate] <= line_buffer[2][received_pixel_col_coordinate];
            line_buffer[2][received_pixel_col_coordinate] <= line_buffer[1][received_pixel_col_coordinate];
            line_buffer[1][received_pixel_col_coordinate] <= line_buffer[0][received_pixel_col_coordinate];
            line_buffer[0][received_pixel_col_coordinate] <= received_pixel_value;

            line_valid_buffer[3][received_pixel_col_coordinate] <= line_valid_buffer[2][received_pixel_col_coordinate];
            line_valid_buffer[2][received_pixel_col_coordinate] <= line_valid_buffer[1][received_pixel_col_coordinate];
            line_valid_buffer[1][received_pixel_col_coordinate] <= line_valid_buffer[0][received_pixel_col_coordinate];
            line_valid_buffer[0][received_pixel_col_coordinate] <= is_received_pixel_valid;

            for (i = 0; i < 5; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    window[i][j] <= window[i][j+1];
                    window_valid[i][j] <= window_valid[i][j+1];
                end
            end

            window[0][4] <= line_buffer[3][received_pixel_col_coordinate];
            window[1][4] <= line_buffer[2][received_pixel_col_coordinate];
            window[2][4] <= line_buffer[1][received_pixel_col_coordinate];
            window[3][4] <= line_buffer[0][received_pixel_col_coordinate];
            window[4][4] <= received_pixel_value;

            window_valid[0][4] <= line_valid_buffer[3][received_pixel_col_coordinate];
            window_valid[1][4] <= line_valid_buffer[2][received_pixel_col_coordinate];
            window_valid[2][4] <= line_valid_buffer[1][received_pixel_col_coordinate];
            window_valid[3][4] <= line_valid_buffer[0][received_pixel_col_coordinate];
            window_valid[4][4] <= is_received_pixel_valid;
        end

        if (do_insert) begin
            for (i = 5; i > insert_position; i = i - 1) begin
                peak_values[i] <= peak_values[i-1];
                peaks_real_row_coordinate[i] <= peaks_real_row_coordinate[i-1];
                peaks_real_col_coordinate[i] <= peaks_real_col_coordinate[i-1];
                peak_slot_occupied[i] <= peak_slot_occupied[i-1];
            end

            peak_values[insert_position] <= center_value;
            peaks_real_row_coordinate[insert_position] <= center_real_row_coordinate;
            peaks_real_col_coordinate[insert_position] <= center_real_col_coordinate;
            peak_slot_occupied[insert_position] <= 1'b1;

            if (peak_num < 3'd6) begin
                peak_num <= peak_num + 1;
            end
        end
    end

    // 峰值检测
    reg [11:0] outer_sum;
    reg [4:0] outer_valid_count;
    reg is_peak;
    integer rr;
    integer cc;
    always @(*) begin
        outer_sum = 12'b0;
        outer_valid_count = 5'b0;

        is_peak = window_valid_strobe && is_center_value_valid;

        for (rr = 0; rr < 5; rr = rr + 1) begin
            for (cc = 0; cc < 5; cc = cc + 1) begin
                if (rr != 2 && cc != 2) begin
                    if (window_valid[rr][cc] && (window[rr][cc] >= center_value)) begin
                        is_peak = 0;
                    end 
                end

                if (rr == 0 || rr == 4 || cc == 0 || cc == 4) begin
                    if (window_valid[rr][cc]) begin
                        outer_sum = outer_sum + window[rr][cc];
                        outer_valid_count = outer_valid_count + 1;
                    end
                end
            end
        end

        if (!(center_value * outer_valid_count > 2 * outer_sum) || outer_valid_count == 0) begin
            is_peak = 0;
        end
    end

    reg [7:0] peak_values [0:5];
    reg [ROWS_ADDR_WIDTH-1:0] peaks_real_row_coordinate [0:5];
    reg [COLS_ADDR_WIDTH-1:0] peaks_real_col_coordinate [0:5];
    reg peak_slot_occupied [0:5];
    reg [2:0] peak_num;
    function better;
        input [7:0] value1;
        input [BRAM_ADDR_WIDTH-1:0] addr_a;
        input a_slot_occupied;
        input [7:0] value2;
        input [BRAM_ADDR_WIDTH-1:0] addr_b;
        input b_slot_occupied;
        begin
            if (!a_slot_occupied) begin
                better = 0;
            end else if (!b_slot_occupied) begin
                better = 1;
            end else if (value1 > value2) begin
                better = 1;
            end else if (value1 < value2) begin
                better = 0;
            end else if (addr_a < addr_b) begin
                better = 1;
            end else begin
                better = 0;
            end
        end
    endfunction

    wire [BRAM_ADDR_WIDTH-1:0] peak_addr0;
    assign peak_addr0 = {peaks_real_row_coordinate[0], peaks_real_col_coordinate[0]};
    wire [BRAM_ADDR_WIDTH-1:0] peak_addr1;
    assign peak_addr1 = {peaks_real_row_coordinate[1], peaks_real_col_coordinate[1]};
    wire [BRAM_ADDR_WIDTH-1:0] peak_addr2;
    assign peak_addr2 = {peaks_real_row_coordinate[2], peaks_real_col_coordinate[2]};
    wire [BRAM_ADDR_WIDTH-1:0] peak_addr3;
    assign peak_addr3 = {peaks_real_row_coordinate[3], peaks_real_col_coordinate[3]};
    wire [BRAM_ADDR_WIDTH-1:0] peak_addr4;
    assign peak_addr4 = {peaks_real_row_coordinate[4], peaks_real_col_coordinate[4]};
    wire [BRAM_ADDR_WIDTH-1:0] peak_addr5;
    assign peak_addr5 = {peaks_real_row_coordinate[5], peaks_real_col_coordinate[5]};

    wire better0;
    assign better0 = better(center_value, center_real_addr, is_peak, peak_values[0], peak_addr0, peak_slot_occupied[0]);
    wire better1;
    assign better1 = better(center_value, center_real_addr, is_peak, peak_values[1], peak_addr1, peak_slot_occupied[1]);
    wire better2;
    assign better2 = better(center_value, center_real_addr, is_peak, peak_values[2], peak_addr2, peak_slot_occupied[2]);
    wire better3;
    assign better3 = better(center_value, center_real_addr, is_peak, peak_values[3], peak_addr3, peak_slot_occupied[3]);
    wire better4;
    assign better4 = better(center_value, center_real_addr, is_peak, peak_values[4], peak_addr4, peak_slot_occupied[4]);
    wire better5;
    assign better5 = better(center_value, center_real_addr, is_peak, peak_values[5], peak_addr5, peak_slot_occupied[5]);

    reg do_insert;
    reg [2:0] insert_position;

    always @(*) begin
        do_insert = 1'b0;
        insert_position = 3'b0;

        if (better0) begin
            do_insert = 1;
            insert_position = 0;
        end else if (better1) begin
            do_insert = 1;
            insert_position = 1;
        end else if (better2) begin
            do_insert = 1;
            insert_position = 2;
        end else if (better3) begin
            do_insert = 1;
            insert_position = 3;
        end else if (better4) begin
            do_insert = 1;
            insert_position = 4;
        end else if (better5) begin
            do_insert = 1;
            insert_position = 5;
        end
    end


    //////////////// check detect_start rising edge ////////////////
    reg detect_start_d1 = 1'b0; // detect_start with 1 clock delay

    always @(posedge clk) begin
        if (~rstn) begin
            detect_start_d1 <= 1'b0;
        end
        else begin
            detect_start_d1 <= detect_start;
        end
    end

    wire detect_new_request;
    assign detect_new_request = detect_start & (~detect_start_d1);
    ////////////////////////////////////////////////////////////////

    // TODO - remove wait_cnt related code, which for simulate detection process only
    //       and replace with actual detection logic
    reg [15:0] wait_cnt = 16'd0;

    always @(posedge clk) begin
        if (~rstn || detect_new_request) begin
            wait_cnt <= 16'b0;
        end
        else if (detect_start && wait_cnt != 16'hff_ff) begin
            wait_cnt <= wait_cnt + 16'd1;
        end
    end
    ////////////////////////////////////////////////////////////////

    // TODO - set to actual finish signal
    assign detect_finish = (wait_cnt == 16'hff_ff);
    ////////////////////////////////////////////////////////////////

    // TODO - set to actual detected peak number
    assign detect_peak_num = detect_finish ? 3'd6 : 3'b0;
    ////////////////////////////////////////////////////////////////

    // TODO - set to actual detected peak data
    reg  [ROWS_ADDR_WIDTH-1:0]       disp_peak_row_r = 0;
    reg  [COLS_ADDR_WIDTH-1:0]       disp_peak_col_r = 0;
    reg  [7:0]                       disp_peak_val_r = 0;

    assign disp_peak_row = disp_peak_row_r;
    assign disp_peak_col = disp_peak_col_r;
    assign disp_peak_val = disp_peak_val_r;

    always @(*) begin
        if (~rstn || ~detect_finish) begin
            disp_peak_row_r <= {ROWS_ADDR_WIDTH{1'b0}};
            disp_peak_col_r <= {COLS_ADDR_WIDTH{1'b0}};
            disp_peak_val_r <= 8'b0;
        end
        else begin
            case (disp_peak_idx)
                3'd0: begin
                    disp_peak_row_r <= 6'd10;
                    disp_peak_col_r <= 6'd15;
                    disp_peak_val_r <= 8'd120;
                end
                3'd1: begin
                    disp_peak_row_r <= 6'd12;
                    disp_peak_col_r <= 6'd18;
                    disp_peak_val_r <= 8'd100;
                end
                3'd2: begin
                    disp_peak_row_r <= 6'd14;
                    disp_peak_col_r <= 6'd20;
                    disp_peak_val_r <= 8'd80;
                end
                3'd3: begin
                    disp_peak_row_r <= 6'd16;
                    disp_peak_col_r <= 6'd25;
                    disp_peak_val_r <= 8'd60;
                end
                3'd4: begin
                    disp_peak_row_r <= 6'd18;
                    disp_peak_col_r <= 6'd30;
                    disp_peak_val_r <= 8'd40;
                end
                3'd5: begin
                    disp_peak_row_r <= 6'd10;
                    disp_peak_col_r <= 6'd31;
                    disp_peak_val_r <= 8'd99;
                end
                default: begin
                    disp_peak_row_r <= {ROWS_ADDR_WIDTH{1'b0}};
                    disp_peak_col_r <= {COLS_ADDR_WIDTH{1'b0}};
                    disp_peak_val_r <= 8'b0;
                end
            endcase
        end
    end
    ////////////////////////////////////////////////////////////////

    // TODO - set to actual read address
    assign bram_rd_addr = {BRAM_ADDR_WIDTH{1'b0}};
    ////////////////////////////////////////////////////////////////

endmodule
