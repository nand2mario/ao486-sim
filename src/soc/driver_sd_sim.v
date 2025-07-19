// SD card module for ao486 simulation.
// nand2mario, 7/2024
module driver_sd (
    input               clk,
    input               rst_n,
    
    //
    input       [1:0]   avs_address,
    input               avs_read,
    output reg  [31:0]  avs_readdata,
    input               avs_write,
    input       [31:0]  avs_writedata,
    
    //
    output      [31:0]  avm_address,
    input               avm_waitrequest,
    output              avm_read,
    input       [31:0]  avm_readdata,
    input               avm_readdatavalid,
    output              avm_write,
    output      [31:0]  avm_writedata,
    
    //
    output reg          sd_clk,
    inout               sd_cmd,
    inout       [3:0]   sd_dat
);

reg [2:0] state;
localparam IDLE = 0;
localparam READ = 1;
localparam WRITE = 2;

reg [23:0] sd_sector;
reg [7:0] sd_sector_count;

localparam SD_BUF_SIZE = 33554432;       // max 1GB (2^30 bytes)
initial $readmemh("dos6.vhd.hex", sd_buf);

reg [7:0] sd_buf [0:SD_BUF_SIZE-1];
reg [29:0] sd_buf_ptr, sd_buf_ptr_end;

always @(posedge clk) begin
    if (!rst_n) begin
        state <= IDLE;
        avm_read <= 0;
        avm_write <= 0;
    end else begin
        avm_write <= 0;
        avm_read <= 0;
        case (state)
            IDLE: begin
                if (avs_read && avs_address == 2'd2) begin  // acquire mutex
                    avs_readdata <= 2;
                end else if (avs_write) begin
                    if (avs_address == 2'd0) begin
                        // write avalon base address, do nothing
                    end else if (avs_address == 2'd1) begin
                        sd_sector <= avs_writedata;
                    end else if (avs_address == 2'd2) begin
                        sd_sector_count <= avs_writedata;
                    end else if (avs_address == 2'd3) begin
                        sd_buf_ptr <= sd_sector * 512;
                        sd_buf_ptr_end <= (sd_sector + sd_sector_count) * 512;
                        if (avs_writedata == 32'd2) begin
                            state <= READ;
                        end else if (avs_writedata == 32'd3) begin
                            state <= WRITE;
                            avm_read <= 1;
                        end
                    end
                end
            end
            READ: begin
                avm_write <= 1;
                avm_writedata[7:0] <= sd_buf[sd_buf_ptr];
                avm_writedata[15:8] <= sd_buf[sd_buf_ptr+1];
                avm_writedata[23:16] <= sd_buf[sd_buf_ptr+2];
                avm_writedata[31:24] <= sd_buf[sd_buf_ptr+3];
                sd_buf_ptr <= sd_buf_ptr + 4;     // todo: check avm_waitrequest
                if (sd_buf_ptr + 4 == sd_buf_ptr_end) begin
                    state <= IDLE;
                end
            end
            WRITE: if (avm_readdatavalid) begin  // drive hdd-to-sd streaming with avm_read
                $display("WRITE: sd[%x]=%x", sd_buf_ptr, avm_readdata);
                sd_buf[sd_buf_ptr] <= avm_readdata[7:0];
                sd_buf[sd_buf_ptr+1] <= avm_readdata[15:8];
                sd_buf[sd_buf_ptr+2] <= avm_readdata[23:16];
                sd_buf[sd_buf_ptr+3] <= avm_readdata[31:24];
                sd_buf_ptr <= sd_buf_ptr + 4;
                if (sd_buf_ptr + 4 == sd_buf_ptr_end)
                    state <= IDLE;
                else
                    avm_read <= 1;
            end
        endcase
    end
end


endmodule