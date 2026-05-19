module Core #(
        parameter ROWS = 64,
        parameter COLS = 64,
        parameter ROWS_ADDR_WIDTH = 6,
        parameter COLS_ADDR_WIDTH = 6,
        parameter BRAM_ADDR_WIDTH = ROWS_ADDR_WIDTH + COLS_ADDR_WIDTH
    ) (
        input clk,
        input rstn,
        output [BRAM_ADDR_WIDTH-1:0] bram_rd_addr,
        input [7:0] bram_rd_data,
        input detect_start,
        output detect_finish,
        output [2:0] detect_peak_num,
        input [2:0] disp_peak_idx,
        output [ROWS_ADDR_WIDTH-1:0] disp_peak_row,
        output [COLS_ADDR_WIDTH-1:0] disp_peak_col,
        output [7:0] disp_peak_val
    )

    localparam PADDING = 2;
    localparam EXT_ROWS = ROWS + 2 * PADDING;
    localparam EXT_COLS = COLS + 2 * PADDING;

    localparam S_IDLE = 2'b00;
    localparam S_ISSUING = 2'b01;
    localparam S_DRAIN = 2'b10;
    localparam S_DONE = 2'b11;
    reg [1:0] state = S_IDLE;

    reg [ROWS_ADDR_WIDTH:0] ext_row = 0;
    reg [COLS_ADDR_WIDTH:0] ext_col = 0;
    wire vld = (ext_row >= 2) && (ext_row <= 65) && (ext_col >= 2) && (ext_col <= 65);
    wire [ROWS_ADDR_WIDTH-1:0] real_row = ext_row - 2;
    wire [COLS_ADDR_WIDTH-1:0] real_col = ext_col - 2;

    // 发射系统
    wire [BRAM_ADDR_WIDTH-1:0] issue_addr = vld ? {real_row, real_col} : 0;
    assign bram_rd_addr = issue_addr;

    // 延迟系统
    wire issue_a_value = state == S_ISSUING;
    reg issue_a_value_d1 = 0;
    reg issue_a_value_d2 = 0;
    reg do_win_mv = 0;
    reg vld_d1 = 0;
    reg vld_d2 = 0;
    reg [ROWS_ADDR_WIDTH:0] ext_row_d1 = 0;
    reg [COLS_ADDR_WIDTH:0] ext_col_d2 = 0;
    reg [COLS_ADDR_WIDTH:0] ext_col_d1 = 0;
    reg [ROWS_ADDR_WIDTH:0] ext_row_d2 = 0;
    always @(posedge clk) begin
        issue_a_value_d1 <= issue_a_value;
        issue_a_value_d2 <= issue_a_value_d1;
        do_win_mv <= issue_a_value_d2;
        vld_d1 <= vld;
        vld_d2 <= vld_d1;
        ext_row_d1 <= ext_row;
        ext_row_d2 <= ext_row_d1;
        ext_col_d1 <= ext_col;
        ext_col_d2 <= ext_col_d1;
    end
    wire [ROWS_ADDR_WIDTH-1:0] real_row_d2 = ext_row_d2 - 2;
    wire [COLS_ADDR_WIDTH-1:0] real_col_d2 = ext_col_d2 - 2;

    // 行缓存定义
    reg [7:0] line_buf0 [0:EXT_COLS-1]; // TODO: 需要初始化成0
    reg [7:0] line_buf1 [0:EXT_COLS-1]; // TODO: 需要初始化成0
    reg [7:0] line_buf2 [0:EXT_COLS-1]; // TODO: 需要初始化成0
    reg [7:0] line_buf3 [0:EXT_COLS-1]; // TODO: 需要初始化成0
    reg line_vld_buf0 [0:EXT_COLS-1]; // TODO: 需要初始化成0
    reg line_vld_buf1 [0:EXT_COLS-1]; // TODO: 需要初始化成0
    reg line_vld_buf2 [0:EXT_COLS-1]; // TODO: 需要初始化成0
    reg line_vld_buf3 [0:EXT_COLS-1]; // TODO: 需要初始化成0

    // 窗口定义
    reg [7:0] win [0:4][0:4]; // TODO: 需要初始化成0
    reg win_vld [0:4][0:4]; // TODO: 需要初始化成0

    // 判断系统
    reg [11:0] outer_sum = 0;
    reg [4:0] outer_vld_cnt = 0;
    function is_peak;
        input [7:0] win [0:4][0:4];
        input win_vld [0:4][0:4];
        integer i, j;
        begin
            is_peak = 1;

            for (i = 0; i <= 4; i = i + 1) begin
                for (j = 0; j <= 4; j = j + 1) begin
                    if ((i != 2) || (j != 2)) begin
                        if (win_vld[i][j] && (win[i][j] >= win[2][2])) begin
                            is_peak = 0;
                        end
                    end
                end
            end

            for (i = 0; i <= 4; i = i + 1) begin
                for (j = 0; j <= 4; j = j + 1) begin
                    if ((i == 0 || i == 4 || j == 0 || j == 4) && win_vld[i][j]) begin
                        outer_sum = outer_sum + win[i][j];
                        outer_vld_cnt = outer_vld_cnt + 1;
                    end
                end
            end

            if (outer_vld_cnt > 0 && outer_vld_cnt * win[2][2] <= 2 * outer_sum) begin
                is_peak = 0;
            end
        end
    endfunction
        
    // 插入系统
    reg [7:0] peak_vals [0:5]; // TODO: 需要初始化成0
    reg [ROWS_ADDR_WIDTH-1:0] peak_rows [0:5]; // TODO: 需要初始化成0
    reg [COLS_ADDR_WIDTH-1:0] peak_cols [0:5]; // TODO: 需要初始化成0
    reg [2:0] insert_pos = 3'd7; // 0-5有效，7表示不插入
    integer k;
    always @(win[4][4]) begin
        if (win_vld[2][2] && is_peak(win, win_vld)) begin
            if (win[2][2] > peak_vals[0]) begin
                insert_pos = 0;
            end else if (win[2][2] > peak_vals[1]) begin
                insert_pos = 1;
            end else if (win[2][2] > peak_vals[2]) begin
                insert_pos = 2;
            end else if (win[2][2] > peak_vals[3]) begin
                insert_pos = 3;
            end else if (win[2][2] > peak_vals[4]) begin
                insert_pos = 4;
            end else if (win[2][2] > peak_vals[5]) begin
                insert_pos = 5;
            end else begin
                insert_pos = 7;
            end
        end

        if (insert_pos >= 0 && insert_pos <= 5) begin
            for (k = 5; k > insert_pos; k = k - 1) begin
                peak_vals[k] = peak_vals[k-1];
                peak_rows[k] = peak_rows[k-1];
                peak_cols[k] = peak_cols[k-1];
            end
            peak_vals[insert_pos] = win[2][2];
            peak_rows[insert_pos] = real_row_d2 - 2;
            peak_cols[insert_pos] = real_col_d2 - 2;
        end
    end

    // 时序逻辑：进、移、迭
    integer m, n;
    always @(posedge clk) begin
        // 新的数据进入窗口
        if (vld_d2 == 0) begin
            win[4][4] <= 0;
        end else begin
            win[4][4] <= bram_rd_data;
        end
        win_vld[4][4] <= vld_d2;

        // 窗口和行缓存移动
        if (do_win_mv) begin
            line_buf0[ext_col_d2] <= win[4][4];
            line_buf1[ext_col_d2] <= line_buf0[ext_col_d2];
            line_buf2[ext_col_d2] <= line_buf1[ext_col_d2];
            line_buf3[ext_col_d2] <= line_buf2[ext_col_d2];

            line_vld_buf0[ext_col_d2] <= win_vld[4][4];
            line_vld_buf1[ext_col_d2] <= line_vld_buf0[ext_col_d2];
            line_vld_buf2[ext_col_d2] <= line_vld_buf1[ext_col_d2];
            line_vld_buf3[ext_col_d2] <= line_vld_buf2[ext_col_d2];

            for (m = 0; m <= 4; m = m + 1) begin
                for (n = 0; n <= 3; n = n + 1) begin
                    win[m][n] <= win[m][n+1];
                    win_vld[m][n] <= win_vld[m][n+1];
                end
            end

            win[0][4] <= line_buf3[ext_col_d2];
            win[1][4] <= line_buf2[ext_col_d2];
            win[2][4] <= line_buf1[ext_col_d2];
            win[3][4] <= line_buf0[ext_col_d2];

            win_vld[0][4] <= line_vld_buf3[ext_col_d2];
            win_vld[1][4] <= line_vld_buf2[ext_col_d2];
            win_vld[2][4] <= line_vld_buf1[ext_col_d2];
            win_vld[3][4] <= line_vld_buf0[ext_col_d2];
        end

        // 坐标迭代
        if (ext_row == EXT_ROWS - 1 && ext_col == EXT_COLS - 1) begin
            state <= S_DRAIN;
        end else begin
            if (ext_col == EXT_COLS - 1) begin
                ext_row <= ext_row + 1;
                ext_col <= 0;
            end else begin
                ext_col <= ext_col + 1;
            end
        end
    end
endmodule
