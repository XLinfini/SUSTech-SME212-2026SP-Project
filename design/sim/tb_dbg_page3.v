`timescale 1ns/1ns
module tb_dbg_page3();
    reg clk = 0;
    reg rstn = 0;
    reg detect_start = 0;
    reg [2:0] disp_peak_idx = 0;
    wire [11:0] bram_rd_addr;
    reg [7:0] bram_rd_data;
    wire detect_finish;
    wire [2:0] detect_peak_num;
    wire [5:0] disp_peak_row;
    wire [5:0] disp_peak_col;
    wire [7:0] disp_peak_val;
    reg [7:0] mem [0:4095];
    reg [7:0] data_d;
    integer i;

    Core u_Core(
        .clk(clk), .rstn(rstn), .bram_rd_addr(bram_rd_addr), .bram_rd_data(bram_rd_data),
        .detect_start(detect_start), .detect_finish(detect_finish), .detect_peak_num(detect_peak_num),
        .disp_peak_idx(disp_peak_idx), .disp_peak_row(disp_peak_row), .disp_peak_col(disp_peak_col), .disp_peak_val(disp_peak_val)
    );

    always #10 clk = ~clk;

    always @(posedge clk) begin
        if (!rstn) begin
            data_d <= 0;
        end else begin
            data_d <= mem[bram_rd_addr];
        end
    end
    always @(*) bram_rd_data = data_d;

    always @(posedge clk) begin
        if (u_Core.eval_vld && u_Core.center_row == 6'd49 && u_Core.center_col == 6'd2) begin
            $display("EVAL 49,2 cand=%b local=%b center=%0d outer=%0d lhs=%0d rhs=%0d", u_Core.peak_candidate, u_Core.local_max, u_Core.w22, u_Core.outer_cnt, u_Core.peak_lhs, u_Core.peak_rhs);
            $display("W0 %0d %0d %0d %0d %0d", u_Core.w00,u_Core.w01,u_Core.w02,u_Core.w03,u_Core.w04);
            $display("W1 %0d %0d %0d %0d %0d", u_Core.w10,u_Core.w11,u_Core.w12,u_Core.w13,u_Core.w14);
            $display("W2 %0d %0d %0d %0d %0d", u_Core.w20,u_Core.w21,u_Core.w22,u_Core.w23,u_Core.w24);
            $display("W3 %0d %0d %0d %0d %0d", u_Core.w30,u_Core.w31,u_Core.w32,u_Core.w33,u_Core.w34);
            $display("W4 %0d %0d %0d %0d %0d", u_Core.w40,u_Core.w41,u_Core.w42,u_Core.w43,u_Core.w44);
            $display("V3 %b %b %b %b %b", u_Core.v30,u_Core.v31,u_Core.v32,u_Core.v33,u_Core.v34);
        end
        if (u_Core.eval_vld && u_Core.center_row == 6'd50 && u_Core.center_col == 6'd0) begin
            $display("EVAL 50,0 cand=%b local=%b center=%0d outer=%0d lhs=%0d rhs=%0d", u_Core.peak_candidate, u_Core.local_max, u_Core.w22, u_Core.outer_cnt, u_Core.peak_lhs, u_Core.peak_rhs);
            $display("W0 %0d %0d %0d %0d %0d", u_Core.w00,u_Core.w01,u_Core.w02,u_Core.w03,u_Core.w04);
            $display("W1 %0d %0d %0d %0d %0d", u_Core.w10,u_Core.w11,u_Core.w12,u_Core.w13,u_Core.w14);
            $display("W2 %0d %0d %0d %0d %0d", u_Core.w20,u_Core.w21,u_Core.w22,u_Core.w23,u_Core.w24);
            $display("W3 %0d %0d %0d %0d %0d", u_Core.w30,u_Core.w31,u_Core.w32,u_Core.w33,u_Core.w34);
            $display("W4 %0d %0d %0d %0d %0d", u_Core.w40,u_Core.w41,u_Core.w42,u_Core.w43,u_Core.w44);
            $display("V2 %b %b %b %b %b", u_Core.v20,u_Core.v21,u_Core.v22,u_Core.v23,u_Core.v24);
        end
    end

    initial begin
        $readmemh("bram_64x64_page3_tmp.dat", mem);
        #20 rstn = 1;
        #100 detect_start = 1;
        wait(detect_finish);
        #20 detect_start = 0;
        $display("num=%0d", detect_peak_num);
        for (i=0;i<detect_peak_num;i=i+1) begin
            disp_peak_idx=i; #20;
            $display("P%0d %0d %0d %0d", i, disp_peak_row, disp_peak_col, disp_peak_val);
        end
        $finish;
    end
endmodule
