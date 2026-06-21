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

    // 
    localparam PADDING = 2;
    localparam EXT_ROWS = ROWS + 2 * PADDING;
    localparam EXT_COLS = COLS + 2 * PADDING;
    localparam SHIFT_BITS = EXT_COLS * 8;

    // 
    localparam S_IDLE = 2'd0;
    localparam S_ISSUING = 2'd1;
    localparam S_DRAIN = 2'd2;
    localparam S_DONE = 2'd3;
    reg [1:0] state = S_IDLE;

    reg [ROWS_ADDR_WIDTH:0] ext_row = 0;
    reg [COLS_ADDR_WIDTH:0] ext_col = 0;
    wire real_valid = (ext_row >= 7'd2) && (ext_row <= 7'd65) && (ext_col >= 7'd2) && (ext_col <= 7'd65);
    wire [ROWS_ADDR_WIDTH-1:0] real_row = ext_row - 7'd2;
    wire [COLS_ADDR_WIDTH-1:0] real_col = ext_col - 7'd2;

    // 
    assign bram_rd_addr = real_valid ? {real_row, real_col} : {BRAM_ADDR_WIDTH{1'b0}};

    // 
    wire issue_valid = (state == S_ISSUING);
    reg issue_d1 = 0;
    reg issue_d2 = 0;
    reg issue_d3 = 0;
    reg eval_vld = 0;
    reg valid_d1 = 0;
    reg valid_d2 = 0;
    reg valid_d3 = 0;
    reg [ROWS_ADDR_WIDTH:0] row_d1 = 0;
    reg [ROWS_ADDR_WIDTH:0] row_d2 = 0;
    reg [ROWS_ADDR_WIDTH:0] row_d3 = 0;
    reg [COLS_ADDR_WIDTH:0] col_d1 = 0;
    reg [COLS_ADDR_WIDTH:0] col_d2 = 0;
    reg [COLS_ADDR_WIDTH:0] col_d3 = 0;
    reg [ROWS_ADDR_WIDTH-1:0] center_row = 0;
    reg [COLS_ADDR_WIDTH-1:0] center_col = 0;
    reg [7:0] pixel_data = 0;

    // 
    reg [SHIFT_BITS-1:0] line0 = 0;
    reg [SHIFT_BITS-1:0] line1 = 0;
    reg [SHIFT_BITS-1:0] line2 = 0;
    reg [SHIFT_BITS-1:0] line3 = 0;
    reg [EXT_COLS-1:0] line0_v = 0; // 
    reg [EXT_COLS-1:0] line1_v = 0;
    reg [EXT_COLS-1:0] line2_v = 0;
    reg [EXT_COLS-1:0] line3_v = 0;
    wire [7:0] line0_out = line0[SHIFT_BITS-1 -: 8];
    wire [7:0] line1_out = line1[SHIFT_BITS-1 -: 8];
    wire [7:0] line2_out = line2[SHIFT_BITS-1 -: 8];
    wire [7:0] line3_out = line3[SHIFT_BITS-1 -: 8];
    wire line0_v_out = line0_v[EXT_COLS-1];
    wire line1_v_out = line1_v[EXT_COLS-1];
    wire line2_v_out = line2_v[EXT_COLS-1];
    wire line3_v_out = line3_v[EXT_COLS-1];

    // 
    reg [7:0] w00 = 0, w01 = 0, w02 = 0, w03 = 0, w04 = 0;
    reg [7:0] w10 = 0, w11 = 0, w12 = 0, w13 = 0, w14 = 0;
    reg [7:0] w20 = 0, w21 = 0, w22 = 0, w23 = 0, w24 = 0;
    reg [7:0] w30 = 0, w31 = 0, w32 = 0, w33 = 0, w34 = 0;
    reg [7:0] w40 = 0, w41 = 0, w42 = 0, w43 = 0, w44 = 0;
    reg v00 = 0, v01 = 0, v02 = 0, v03 = 0, v04 = 0;
    reg v10 = 0, v11 = 0, v12 = 0, v13 = 0, v14 = 0;
    reg v20 = 0, v21 = 0, v22 = 0, v23 = 0, v24 = 0;
    reg v30 = 0, v31 = 0, v32 = 0, v33 = 0, v34 = 0;
    reg v40 = 0, v41 = 0, v42 = 0, v43 = 0, v44 = 0;

    // 
    wire local_max =
        (!v00 || w22 > w00) && (!v01 || w22 > w01) && (!v02 || w22 > w02) && (!v03 || w22 > w03) && (!v04 || w22 > w04) &&
        (!v10 || w22 > w10) && (!v11 || w22 > w11) && (!v12 || w22 > w12) && (!v13 || w22 > w13) && (!v14 || w22 > w14) &&
        (!v20 || w22 > w20) && (!v21 || w22 > w21) &&                         (!v23 || w22 > w23) && (!v24 || w22 > w24) &&
        (!v30 || w22 > w30) && (!v31 || w22 > w31) && (!v32 || w22 > w32) && (!v33 || w22 > w33) && (!v34 || w22 > w34) &&
        (!v40 || w22 > w40) && (!v41 || w22 > w41) && (!v42 || w22 > w42) && (!v43 || w22 > w43) && (!v44 || w22 > w44);
    wire [11:0] outer_sum =
        (v00 ? w00 : 0) + (v01 ? w01 : 0) + (v02 ? w02 : 0) + (v03 ? w03 : 0) + (v04 ? w04 : 0) +
        (v10 ? w10 : 0) +                                                           (v14 ? w14 : 0) +
        (v20 ? w20 : 0) +                                                           (v24 ? w24 : 0) +
        (v30 ? w30 : 0) +                                                           (v34 ? w34 : 0) +
        (v40 ? w40 : 0) + (v41 ? w41 : 0) + (v42 ? w42 : 0) + (v43 ? w43 : 0) + (v44 ? w44 : 0);
    wire [4:0] outer_cnt =
        v00 + v01 + v02 + v03 + v04 + v10 + v14 + v20 + v24 + v30 + v34 + v40 + v41 + v42 + v43 + v44;
    wire [15:0] peak_lhs = w22 * outer_cnt;
    wire [15:0] peak_rhs = {3'b000, outer_sum, 1'b0};
    wire peak_candidate = eval_vld && v22 && local_max && (outer_cnt != 0) && (peak_lhs > peak_rhs);

    reg [2:0] peak_num = 0;
    assign detect_peak_num = peak_num;
    reg [7:0] peak_vals [0:5];
    reg [ROWS_ADDR_WIDTH-1:0] peak_rows [0:5];
    reg [COLS_ADDR_WIDTH-1:0] peak_cols [0:5];

    // 
    reg do_insert;
    reg [2:0] insert_pos;
    always @(*) begin
        do_insert = 0;
        insert_pos = 0;
        if (peak_candidate) begin
            if ((peak_num == 0) || (w22 > peak_vals[0])) begin
                do_insert = 1; insert_pos = 0;
            end else if ((peak_num < 2) || (w22 > peak_vals[1])) begin
                do_insert = 1; insert_pos = 1;
            end else if ((peak_num < 3) || (w22 > peak_vals[2])) begin
                do_insert = 1; insert_pos = 2;
            end else if ((peak_num < 4) || (w22 > peak_vals[3])) begin
                do_insert = 1; insert_pos = 3;
            end else if ((peak_num < 5) || (w22 > peak_vals[4])) begin
                do_insert = 1; insert_pos = 4;
            end else if ((peak_num < 6) || (w22 > peak_vals[5])) begin
                do_insert = 1; insert_pos = 5;
            end
        end
    end

    /*
        
    */
    integer k;
    always @(posedge clk) begin
        if (~rstn) begin
            // 
            state <= S_IDLE;
            ext_row <= 0; ext_col <= 0;
            issue_d1 <= 0; issue_d2 <= 0; issue_d3 <= 0; eval_vld <= 0;
            valid_d1 <= 0; valid_d2 <= 0; valid_d3 <= 0;
            row_d1 <= 0; row_d2 <= 0; row_d3 <= 0;
            col_d1 <= 0; col_d2 <= 0; col_d3 <= 0;
            center_row <= 0; center_col <= 0;
            pixel_data <= 0;
            peak_num <= 0;
            line0 <= 0; line1 <= 0; line2 <= 0; line3 <= 0;
            line0_v <= 0; line1_v <= 0; line2_v <= 0; line3_v <= 0;
            for (k = 0; k < 6; k = k + 1) begin
                peak_vals[k] <= 0; peak_rows[k] <= 0; peak_cols[k] <= 0;
            end
        end else begin
            // 
            if (state == S_ISSUING || state == S_DRAIN) begin
                issue_d1 <= issue_valid;
                issue_d2 <= issue_d1;
                issue_d3 <= issue_d2;
                eval_vld <= issue_d3;
                valid_d1 <= real_valid;
                valid_d2 <= valid_d1;
                valid_d3 <= valid_d2;
                row_d1 <= ext_row;
                row_d2 <= row_d1;
                row_d3 <= row_d2;
                col_d1 <= ext_col;
                col_d2 <= col_d1;
                col_d3 <= col_d2;
                center_row <= row_d3 - 7'd4;
                center_col <= col_d3 - 7'd3;
                pixel_data <= bram_rd_data;
            end

            // 
            if (issue_d3) begin
                w00 <= w01; w01 <= w02; w02 <= w03; w03 <= w04; w04 <= line3_out;
                w10 <= w11; w11 <= w12; w12 <= w13; w13 <= w14; w14 <= line2_out;
                w20 <= w21; w21 <= w22; w22 <= w23; w23 <= w24; w24 <= line1_out;
                w30 <= w31; w31 <= w32; w32 <= w33; w33 <= w34; w34 <= line0_out;
                w40 <= w41; w41 <= w42; w42 <= w43; w43 <= w44; w44 <= valid_d3 ? pixel_data : 0;
                v00 <= v01; v01 <= v02; v02 <= v03; v03 <= v04; v04 <= line3_v_out;
                v10 <= v11; v11 <= v12; v12 <= v13; v13 <= v14; v14 <= line2_v_out;
                v20 <= v21; v21 <= v22; v22 <= v23; v23 <= v24; v24 <= line1_v_out;
                v30 <= v31; v31 <= v32; v32 <= v33; v33 <= v34; v34 <= line0_v_out;
                v40 <= v41; v41 <= v42; v42 <= v43; v43 <= v44; v44 <= valid_d3;

                line0 <= {line0[SHIFT_BITS-9:0], valid_d3 ? pixel_data : 8'b0};
                line1 <= {line1[SHIFT_BITS-9:0], line0_out};
                line2 <= {line2[SHIFT_BITS-9:0], line1_out};
                line3 <= {line3[SHIFT_BITS-9:0], line2_out};
                line0_v <= {line0_v[EXT_COLS-2:0], valid_d3};
                line1_v <= {line1_v[EXT_COLS-2:0], line0_v_out};
                line2_v <= {line2_v[EXT_COLS-2:0], line1_v_out};
                line3_v <= {line3_v[EXT_COLS-2:0], line2_v_out};
            end

            // 
            if (do_insert) begin
                if (peak_num < 6) begin
                    peak_num <= peak_num + 1'b1;
                end
                for (k = 5; k > 0; k = k - 1) begin
                    if (k > insert_pos) begin
                        peak_vals[k] <= peak_vals[k-1];
                        peak_rows[k] <= peak_rows[k-1];
                        peak_cols[k] <= peak_cols[k-1];
                    end
                end
                peak_vals[insert_pos] <= w22;
                peak_rows[insert_pos] <= center_row;
                peak_cols[insert_pos] <= center_col;
            end

            // 
            case (state)
                S_IDLE: begin
                    // 
                    ext_row <= 0; ext_col <= 0;
                    issue_d1 <= 0; issue_d2 <= 0; issue_d3 <= 0; eval_vld <= 0;
                    valid_d1 <= 0; valid_d2 <= 0; valid_d3 <= 0;
                    row_d1 <= 0; row_d2 <= 0; row_d3 <= 0;
                    col_d1 <= 0; col_d2 <= 0; col_d3 <= 0;
                    pixel_data <= 0;

                    // 
                    if (detect_start) begin
                        peak_num <= 0;

                        line0 <= 0; line1 <= 0; line2 <= 0; line3 <= 0;
                        line0_v <= 0; line1_v <= 0; line2_v <= 0; line3_v <= 0;
                        
                        v00 <= 0; v01 <= 0; v02 <= 0; v03 <= 0; v04 <= 0;
                        v10 <= 0; v11 <= 0; v12 <= 0; v13 <= 0; v14 <= 0;
                        v20 <= 0; v21 <= 0; v22 <= 0; v23 <= 0; v24 <= 0;
                        v30 <= 0; v31 <= 0; v32 <= 0; v33 <= 0; v34 <= 0;
                        v40 <= 0; v41 <= 0; v42 <= 0; v43 <= 0; v44 <= 0;
                        
                        for (k = 0; k < 6; k = k + 1) begin
                            peak_vals[k] <= 0;
                            peak_rows[k] <= 0;
                            peak_cols[k] <= 0;
                        end
                        state <= S_ISSUING;
                    end
                end
                
                // 
                S_ISSUING: begin
                    if (ext_row == EXT_ROWS - 1 && ext_col == EXT_COLS - 1) begin
                        state <= S_DRAIN;
                    end else if (ext_col == EXT_COLS - 1) begin
                        ext_col <= 0;
                        ext_row <= ext_row + 1'b1;
                    end else begin
                        ext_col <= ext_col + 1'b1;
                    end
                end

                // 
                S_DRAIN: begin
                    if (!issue_d1 && !issue_d2 && !issue_d3 && !eval_vld) begin
                        state <= S_DONE;
                    end
                end

                // 
                S_DONE: begin
                    if (!detect_start) begin
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    // 
    assign detect_finish = (state == S_DONE);
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
        end else begin
            disp_peak_row_reg = 0;
            disp_peak_col_reg = 0;
            disp_peak_val_reg = 0;
        end
    end
endmodule
