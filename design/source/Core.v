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
    );

    parameter PADDING = 2;
    parameter EXT_ROWS = ROWS + 2 * PADDING;
    parameter EXT_COLS = COLS + 2 * PADDING;

    parameter S_IDLE = 2'b00;
    parameter S_ISSUING = 2'b01;
    parameter S_DRAIN = 2'b10;
    parameter S_DONE = 2'b11;
    reg [1:0] state = S_IDLE;

    reg [ROWS_ADDR_WIDTH:0] ext_row = 0;
    reg [COLS_ADDR_WIDTH:0] ext_col = 0;
    wire vld = (ext_row >= 2) && (ext_row <= 65) && (ext_col >= 2) && (ext_col <= 65);
    wire [ROWS_ADDR_WIDTH-1:0] real_row = ext_row - 2;
    wire [COLS_ADDR_WIDTH-1:0] real_col = ext_col - 2;

    // 发射系统
    wire [BRAM_ADDR_WIDTH-1:0] issue_addr = vld ? {real_row, real_col} : 0;
    assign bram_rd_addr = issue_addr;

    // 延迟量定义
    wire issue_a_value = state == S_ISSUING;
    reg issue_a_value_d1 = 0;
    reg issue_a_value_d2 = 0;
    reg eval_vld = 0;
    reg vld_d1 = 0;
    reg vld_d2 = 0;
    reg [ROWS_ADDR_WIDTH:0] ext_row_d1 = 0;
    reg [COLS_ADDR_WIDTH:0] ext_col_d2 = 0;
    reg [COLS_ADDR_WIDTH:0] ext_col_d1 = 0;
    reg [ROWS_ADDR_WIDTH:0] ext_row_d2 = 0;
    reg [ROWS_ADDR_WIDTH-1:0] center_row_d3 = 0;
    reg [COLS_ADDR_WIDTH-1:0] center_col_d3 = 0;

    // 行缓存定义
    reg [7:0] line_buf0 [0:EXT_COLS-1]; // 不需要初始化，因为只要对应的line_vld_buf是0，win的值就不影响结果
    reg [7:0] line_buf1 [0:EXT_COLS-1];
    reg [7:0] line_buf2 [0:EXT_COLS-1];
    reg [7:0] line_buf3 [0:EXT_COLS-1];
    reg line_vld_buf0 [0:EXT_COLS-1];
    reg line_vld_buf1 [0:EXT_COLS-1];
    reg line_vld_buf2 [0:EXT_COLS-1];
    reg line_vld_buf3 [0:EXT_COLS-1];

    // 窗口定义
    reg [7:0] win [0:4][0:4]; // 不需要初始化，因为只要对应的win_vld是0，win的值就不影响结果
    reg win_vld [0:4][0:4];

    // 判断是否是峰值
    reg is_peak = 0;
    reg [11:0] outer_sum;
    reg [4:0] outer_vld_cnt;
    reg [31:0] lhs;
    reg [31:0] rhs;
    integer i, j;
    always @(*) begin
        is_peak = 1;
        outer_sum = 0;
        outer_vld_cnt = 0;
        lhs = 0;
        rhs = 0;

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

        // lhs和rhs是必须的，因为直接比较会溢出
        lhs = outer_vld_cnt * win[2][2];
        rhs = 2 * outer_sum;
        if (outer_vld_cnt > 0 && lhs <= rhs) begin
            is_peak = 0;
        end
    end
    wire is_peak_real = is_peak && win_vld[2][2] && eval_vld; // 只有当中心值有效、满足峰值条件、曾经没被算过是不是峰值时，才认为是一个真正的峰值

    // 判断插入位置
    reg [2:0] peak_num = 0;
    assign detect_peak_num = peak_num;
    reg [7:0] peak_vals [0:5];
    reg [ROWS_ADDR_WIDTH-1:0] peak_rows [0:5];
    reg [COLS_ADDR_WIDTH-1:0] peak_cols [0:5];
    reg do_insert = 0;
    reg [2:0] insert_pos = 3'd7; // 不插入时默认为7
    always @(*) begin
        do_insert = 0;
        insert_pos = 3'd7; // 默认不插入

        if (is_peak_real) begin
            if (win[2][2] > peak_vals[0]) begin
                do_insert = 1;
                insert_pos = 0;
            end
            else if (win[2][2] > peak_vals[1]) begin
                do_insert = 1;
                insert_pos = 1;
            end
            else if (win[2][2] > peak_vals[2]) begin
                do_insert = 1;
                insert_pos = 2;
            end
            else if (win[2][2] > peak_vals[3]) begin
                do_insert = 1;
                insert_pos = 3;
            end
            else if (win[2][2] > peak_vals[4]) begin
                do_insert = 1;
                insert_pos = 4;
            end
            else if (win[2][2] > peak_vals[5]) begin
                do_insert = 1;
                insert_pos = 5;
            end
            else begin
                do_insert = 0;
                insert_pos = 7;
            end
        end
    end

    // 时序逻辑：延、进、移、插、迭
    /*
        状态机只管“发不发地址”和“什么时候结束”
        延迟管道只管“地址/valid 和 BRAM data 对齐”
        pix_cycle 只管“窗口何时移动”
        eval_valid 只管“何时检测窗口”
        do_insert 只管“何时更新 Top-6”
    */
    integer m, n;
    integer k;
    always @(posedge clk) begin
        // 延迟管道更新
        if (state == S_ISSUING || state == S_DRAIN) begin
            issue_a_value_d1 <= issue_a_value;
            issue_a_value_d2 <= issue_a_value_d1;
            eval_vld <= issue_a_value_d2;
            vld_d1 <= vld;
            vld_d2 <= vld_d1;
            ext_row_d1 <= ext_row;
            ext_row_d2 <= ext_row_d1;
            center_row_d3 <= ext_row_d2 - 4;
            ext_col_d1 <= ext_col;
            ext_col_d2 <= ext_col_d1;
            center_col_d3 <= ext_col_d2 - 4;
        end

        // 数据流动
        if (issue_a_value_d2) begin
            // 新的数据进入窗口
            win[4][4] <= vld_d2 ? bram_rd_data : 0;
            win_vld[4][4] <= vld_d2;

            // 窗口和行缓存移动
            line_buf0[ext_col_d2] <= vld_d2 ? bram_rd_data : 0;
            line_buf1[ext_col_d2] <= line_buf0[ext_col_d2];
            line_buf2[ext_col_d2] <= line_buf1[ext_col_d2];
            line_buf3[ext_col_d2] <= line_buf2[ext_col_d2];

            line_vld_buf0[ext_col_d2] <= vld_d2;
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

        // 峰值插入
        if (do_insert) begin
            if (peak_num < 6) begin // 这个判断是必须的，万一peak_num已经满了但新来的值又比第6大的话，peak_num还在加，就爆了
                peak_num <= peak_num + 1;
            end

            for (k = 5; k > 0; k = k - 1) begin
                if (k > insert_pos) begin
                    peak_vals[k] <= peak_vals[k-1];
                    peak_rows[k] <= peak_rows[k-1];
                    peak_cols[k] <= peak_cols[k-1];
                end
            end
            peak_vals[insert_pos] <= win[2][2];
            peak_rows[insert_pos] <= center_row_d3;
            peak_cols[insert_pos] <= center_col_d3;
        end

        // 状态机
        case (state)
            S_ISSUING: begin
                // 坐标迭代（只在S_ISSUING状态下进行）
                if (ext_row == EXT_ROWS - 1 && ext_col == EXT_COLS - 1) begin
                    state <= S_DRAIN;
                end
                else begin
                    if (ext_col == EXT_COLS - 1) begin
                        ext_row <= ext_row + 1;
                        ext_col <= 0;
                    end
                    else begin
                        ext_col <= ext_col + 1;
                    end
                end
            end

            S_DRAIN: begin
                // 如果是在S_DRAIN状态，不迭代坐标，等待缓冲区数据排空即可
                if (state == S_DRAIN) begin
                    if (issue_a_value_d1 == 0 && issue_a_value_d2 == 0 && eval_vld == 0) begin
                        state <= S_DONE;
                    end
                end
            end

            S_DONE: begin
                // 检测完成，在S_DONE停留直到detect_start拉低，之后回到S_IDLE展示结果及等待下一次检测
                if (detect_start == 0) begin
                    state <= S_IDLE;
                end
            end

            S_IDLE: begin
                // S_IDLE状态下，清空虚拟坐标 延迟量
                ext_row <= 0;
                ext_col <= 0;
                issue_a_value_d1 <= 0;
                issue_a_value_d2 <= 0;
                eval_vld <= 0;
                vld_d1 <= 0;
                vld_d2 <= 0;
                ext_row_d1 <= 0;
                ext_row_d2 <= 0;
                ext_col_d1 <= 0;
                ext_col_d2 <= 0;

                if (detect_start) begin
                    // 下一次检测开始前，清空peak_num peak_vals peak_rows peak_cols line_vld_buf win_vld
                    // TODO: 复用m可能有bug，需要验证
                    for (m = 0; m <= EXT_COLS-1; m = m + 1) begin
                        line_vld_buf0[m] <= 0;
                        line_vld_buf1[m] <= 0;
                        line_vld_buf2[m] <= 0;
                        line_vld_buf3[m] <= 0;
                    end
                    for (m = 0; m <= 4; m = m + 1) begin
                        for (n = 0; n <= 4; n = n + 1) begin
                            win_vld[m][n] <= 0;
                        end
                    end

                    peak_num <= 0;
                    for (m = 0; m <= 5; m = m + 1) begin
                        peak_vals[m] <= 0;
                        peak_rows[m] <= 0;
                        peak_cols[m] <= 0;
                    end

                    state <= S_ISSUING;
                end
            end
        endcase

        if (rstn == 0) begin
            // rstn触发时，回到S_IDLE状态，并清空虚拟坐标 延迟量 peak_num peak_vals peak_rows peak_cols line_vld_buf win_vld
            state <= S_IDLE;

            ext_row <= 0;
            ext_col <= 0;
            issue_a_value_d1 <= 0;
            issue_a_value_d2 <= 0;
            eval_vld <= 0;
            vld_d1 <= 0;
            vld_d2 <= 0;
            ext_row_d1 <= 0;
            ext_row_d2 <= 0;
            ext_col_d1 <= 0;
            ext_col_d2 <= 0;

            for (m = 0; m <= EXT_COLS-1; m = m + 1) begin
                line_vld_buf0[m] <= 0;
                line_vld_buf1[m] <= 0;
                line_vld_buf2[m] <= 0;
                line_vld_buf3[m] <= 0;
            end
            for (m = 0; m <= 4; m = m + 1) begin
                for (n = 0; n <= 4; n = n + 1) begin
                    win_vld[m][n] <= 0;
                end
            end

            peak_num <= 0;
            for (m = 0; m <= 5; m = m + 1) begin
                peak_vals[m] <= 0;
                peak_rows[m] <= 0;
                peak_cols[m] <= 0;
            end
        end
    end

    assign detect_finish = (state == S_DONE);

    // 输出系统
    reg [ROWS_ADDR_WIDTH-1:0] disp_peak_row_reg;
    reg [COLS_ADDR_WIDTH-1:0] disp_peak_col_reg;
    reg [7:0] disp_peak_val_reg;
    assign disp_peak_col = disp_peak_col_reg;
    assign disp_peak_row = disp_peak_row_reg;
    assign disp_peak_val = disp_peak_val_reg;
    always @(*) begin
        if (disp_peak_idx < peak_num) begin
            disp_peak_row_reg = peak_rows[disp_peak_idx];
            disp_peak_col_reg = peak_cols[disp_peak_idx];
            disp_peak_val_reg = peak_vals[disp_peak_idx];
        end
        else begin
            disp_peak_row_reg = 0;
            disp_peak_col_reg = 0;
            disp_peak_val_reg = 0;
        end
    end
endmodule
