`define SEG_SEL_NULL  4'b0000
`define SEG_SEL_0     4'b0001
`define SEG_SEL_1     4'b0010
`define SEG_SEL_2     4'b0100
`define SEG_SEL_3     4'b1000

module SegWrapper #(
        parameter CLK_FREQ = 50_000_000,
        parameter SEG_FLASH_DUR = 49_999,
        parameter ROW_ADDR_WIDTH = 5,
        parameter COL_ADDR_WIDTH = 5
    ) (
        input                            clk,
        input                            rstn,
        input      [1:0]                 disp_mode,
        input      [12:0]                detect_time,
        input      [2:0]                 disp_peak_idx,
        input      [ROW_ADDR_WIDTH-1:0]  disp_peak_row,
        input      [COL_ADDR_WIDTH-1:0]  disp_peak_col,
        input      [7:0]                 disp_peak_val,
        output     [3:0]                 seg_sel,
        output     [7:0]                 seg_data
    );

    // 时钟
    reg [15:0] clk_cnt = 16'b0;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            clk_cnt <= 0;
        end else if (clk_cnt == SEG_FLASH_DUR) begin
            clk_cnt <= 0;
        end else begin
            clk_cnt <= clk_cnt + 1;
        end
    end
    wire flash_en = (clk_cnt == SEG_FLASH_DUR) ? 1'b1 : 1'b0;

    // 状态转移
    reg [3:0] seg_sel_r = `SEG_SEL_NULL;
    assign seg_sel = seg_sel_r;
    always @(posedge clk) begin
        if (!rstn || disp_mode == 2'b00) begin
            seg_sel_r <= `SEG_SEL_NULL; // 如果disp_mode=2'b00,则seg_sel_r=`SEG_SEL_NULL且disp_num_0~3=4'b1111，双保险不显示任何内容
        end else if (flash_en) begin
            case (seg_sel_r)
                `SEG_SEL_NULL: seg_sel_r <= `SEG_SEL_0;
                `SEG_SEL_0: seg_sel_r <= `SEG_SEL_1;
                `SEG_SEL_1: seg_sel_r <= `SEG_SEL_2;
                `SEG_SEL_2: seg_sel_r <= `SEG_SEL_3;
                `SEG_SEL_3: seg_sel_r <= `SEG_SEL_0;
                default: seg_sel_r <= `SEG_SEL_NULL;
            endcase
        end
    end

    reg [3:0] disp_num_0;
    reg [3:0] disp_num_1;
    reg [3:0] disp_num_2;
    reg [3:0] disp_num_3;
    always @(*) begin
        case(disp_mode)
            2'b01: begin
                disp_num_0 = detect_time % 10;
                disp_num_1 = (detect_time / 10) % 10;
                disp_num_2 = (detect_time / 100) % 10;
                disp_num_3 = (detect_time / 1000) % 10;
            end
            2'b10: begin
                disp_num_0 = disp_peak_row % 10;
                disp_num_1 = (disp_peak_row / 10) % 10;
                disp_num_2 = disp_peak_col % 10;
                disp_num_3 = (disp_peak_col / 10) % 10;
            end
            2'b11: begin
                disp_num_0 = disp_peak_val % 10;
                disp_num_1 = (disp_peak_val / 10) % 10;
                disp_num_2 = (disp_peak_val / 100) % 10;
                disp_num_3 = (disp_peak_val / 1000) % 10;
            end
            default: begin
                disp_num_0 = 4'b1111;
                disp_num_1 = 4'b1111;
                disp_num_2 = 4'b1111;
                disp_num_3 = 4'b1111;
            end
        endcase
    end

    reg [3:0] sel_num;
    always @(*) begin
        case (seg_sel_r)
            `SEG_SEL_0: begin
                sel_num = disp_num_0;
            end
            `SEG_SEL_1: begin
                sel_num = disp_num_1;
            end
            `SEG_SEL_2: begin
                sel_num = disp_num_2;
            end
            `SEG_SEL_3: begin
                sel_num = disp_num_3;
            end
            default: begin
                sel_num = 4'b1111;
            end
        endcase
    end

    reg [7:0] seg_data_r;
    assign seg_data = seg_data_r;
    always @(*) begin
        case (sel_num)
            4'b0000: seg_data_r = 8'b11000000; // 0
            4'b0001: seg_data_r = 8'b11111001; // 1
            4'b0010: seg_data_r = 8'b10100100; // 2
            4'b0011: seg_data_r = 8'b10110000; // 3
            4'b0100: seg_data_r = 8'b10011001; // 4
            4'b0101: seg_data_r = 8'b10010010; // 5
            4'b0110: seg_data_r = 8'b10000010; // 6
            4'b0111: seg_data_r = 8'b11111000; // 7
            4'b1000: seg_data_r = 8'b10000000; // 8
            4'b1001: seg_data_r = 8'b10010000; // 9
            default: seg_data_r = 8'b11111111; // 给sel_num传入4'b1111即可什么都不显示
        endcase
    end
endmodule
