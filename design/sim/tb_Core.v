`timescale 1ns/1ns

module tb_Core();

// BRAM大小（字节）
parameter BRAM_SIZE = 4096;
parameter BRAM_ADDR_WIDTH = 12;  // 2^12 = 4096
parameter ROWS = 64;
parameter COLS = 64;

// 时钟和复位信号
reg         clk;
reg         rstn;

// BRAM 接口
wire [BRAM_ADDR_WIDTH-1:0]  bram_rd_addr;
reg  [7:0]  bram_rd_data;

// 检测控制信号
reg         detect_start;
wire        detect_finish;

// 检测结果信号
wire [2:0]  detect_peak_num;
reg  [2:0]  disp_peak_idx;
wire [BRAM_ADDR_WIDTH/2-1:0]  disp_peak_row;
wire [BRAM_ADDR_WIDTH/2-1:0]  disp_peak_col;
wire [7:0]  disp_peak_val;

// 测试 BRAM
integer     i;
reg [7:0]   bram_mem [0:(BRAM_SIZE-1)];

// 实例化被测模块   
Core u_Core (
    .clk            (clk),
    .rstn           (rstn),
    .bram_rd_addr   (bram_rd_addr),
    .bram_rd_data   (bram_rd_data),
    .detect_start   (detect_start),
    .detect_finish  (detect_finish),
    .detect_peak_num(detect_peak_num),
    .disp_peak_idx  (disp_peak_idx),
    .disp_peak_row  (disp_peak_row),
    .disp_peak_col  (disp_peak_col),
    .disp_peak_val  (disp_peak_val)
);

// 时钟生成
always #10 clk = ~clk;  // 50MHz时钟
// always #1 clk = ~clk;  // 500MHz时钟

// BRAM读取模拟（1个时钟周期延迟）
reg [BRAM_ADDR_WIDTH-1:0] bram_addr_delayed;
reg [7:0] bram_data_delayed;

always @(posedge clk) begin
    if (~rstn) begin
        bram_addr_delayed <= {BRAM_ADDR_WIDTH{1'b0}};
        bram_data_delayed <= 8'b0;
    end else begin
        bram_addr_delayed <= bram_rd_addr;
        bram_data_delayed <= bram_mem[bram_rd_addr];
    end
end

always @(*) begin
    bram_rd_data = bram_data_delayed;
end

// 测试流程
initial begin
    // 初始化
    initialize();
    
    // 复位系统
    reset_system();
    
    // 加载BRAM数据
    load_bram_data();
    
    // 开始检测
    start_detection();
    
    // 显示检测结果
    display_results();
    
    // 结束测试
    #100;
    $display("Test completed successfully!");
    $finish;
end

// 初始化任务
task initialize;
begin
    clk = 0;
    rstn = 0;
    detect_start = 0;
    disp_peak_idx = 0;
    
    // 初始化BRAM内存为0
    for (i = 0; i < BRAM_SIZE; i = i + 1) begin
        bram_mem[i] = 8'h00;
    end
end
endtask

// 系统复位任务
task reset_system;
begin
    #20;
    rstn = 1;
    #50;
    $display("System reset completed at time %t", $time);
end
endtask

// 加载BRAM数据任务
task load_bram_data;
integer file, temp;
begin
    // 从hex文件读取数据
    if (BRAM_SIZE == 1024) begin
        $display("Loading BRAM data from bram_32x32.dat...");
        file = $fopen("bram_32x32.dat", "r");
    end 
    else if (BRAM_SIZE == 4096) begin
        $display("Loading BRAM data from bram_64x64.dat...");
        file = $fopen("bram_64x64.dat", "r");
    end
    else begin
        $display("Error: Unsupported BRAM_SIZE %d", BRAM_SIZE);
        $finish;
    end
    if (!file) begin
        $display("Error: Cannot open bram file!");
        $finish;
    end
    
    i = 0;
    while (!$feof(file) && i < BRAM_SIZE) begin
        temp = $fscanf(file, "%h", bram_mem[i]);
        // $display("BRAM LOAD =0x%h (%d, %d), data=0x%h (%d)", 
        //             i[BRAM_ADDR_WIDTH-1:0], i[BRAM_ADDR_WIDTH-1:BRAM_ADDR_WIDTH/2], i[BRAM_ADDR_WIDTH/2-1:0], bram_mem[i], bram_mem[i]);
        i = i + 1;
    end
    $fclose(file);
    
    $display("BRAM data loaded successfully, %0d bytes read", i);
end
endtask

// 开始检测任务
task start_detection;
begin
    #100;
    @(posedge clk) #1 detect_start = 1;
    $display("Detection started at time %t", $time);
    
    // 保持start信号为高直到检测完成
    while (!detect_finish) begin
        @(posedge clk);
    end
    @(posedge clk) #1 detect_start = 0;
    $display("Detection finished at time %t", $time);
    #100;
end
endtask

// 显示结果任务
task display_results;
integer j;
begin
    $display("\n=== Detection Results ===");
    $display("Number of peaks detected: %0d", detect_peak_num);
    
    if (detect_peak_num > 0) begin
        for (j = 0; j < detect_peak_num; j = j + 1) begin
            @(posedge clk) disp_peak_idx = j;
            #10;  // 等待输出稳定
            $display("Peak[%0d]: Row=%d, Col=%d, Value=%d", 
                     j, disp_peak_row, disp_peak_col, disp_peak_val);
        end
    end else begin
        $display("No peaks detected.");
    end
    
    $display("=== End of Results ===\n");
end
endtask

// 监控关键信号
always @(posedge clk) begin
    if (detect_start && !detect_finish) begin
        // 在检测过程中监控BRAM访问
        if (bram_rd_addr !== bram_addr_delayed) begin
            $display("Time %t: BRAM read address=0x%h (%d, %d), data=0x%h (%d)", 
                     $time, bram_rd_addr, bram_rd_addr[BRAM_ADDR_WIDTH-1:BRAM_ADDR_WIDTH/2], bram_rd_addr[BRAM_ADDR_WIDTH/2-1:0], bram_mem[bram_rd_addr], bram_mem[bram_rd_addr]);
        end
    end
end

// 断言检查
always @(posedge clk) begin
    if (rstn && detect_start) begin
        // 检查BRAM地址是否在有效范围内
        if (bram_rd_addr > (BRAM_SIZE-1)) begin
            $display("Warning: BRAM address out of range: 0x%h", bram_rd_addr);
        end
    end
end

initial begin
    $dumpfile("tb_Core.vcd");
    $dumpvars;
end

initial begin
    #100_000_000 $display("Test timeout!");
    $finish; // 超时保护
end 

endmodule