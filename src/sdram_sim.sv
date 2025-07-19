// SDRAM simulation that supports burst read, and VGA memory access
// nand2mario, 7/2025
module sdram_sim (
    input             clk,
    input             reset,
    input      [31:0] cpu_addr,
    input      [31:0] cpu_din,
    output reg [31:0] cpu_dout,
    output reg        cpu_dout_ready,
    input      [3:0]  cpu_be,            // byte enable for writes, assumed consecutive 1's
    input      [7:0]  cpu_burstcount,    // burst count for reads
    output reg        cpu_busy,
    input             cpu_rd,
    input             cpu_we,

    input             protect_rom,       // make 0xC0000 - 0xFFFFF write protected

    output reg [16:0] vga_address,
    input      [7:0]  vga_readdata,
    output reg [7:0]  vga_writedata,
    input      [2:0]  vga_memmode,
    output reg        vga_read,
    output reg        vga_write,

    input      [5:0]  vga_wr_seg,
    input      [5:0]  vga_rd_seg,
    input             vga_fb_en
);

localparam SIZE_MB = 4;
wire cpu_addr_region = cpu_addr < (SIZE_MB << 20);

// 2MB of main memory
localparam DWORD_CNT = SIZE_MB*1024*1024/4;

logic [31:0] mem [0:DWORD_CNT-1] /* verilator public */;

logic [2:0] state; 
localparam IDLE = 0;
localparam READ_BURST = 1;
localparam VGA_READ_WAIT = 2;
localparam VGA_READ = 3;
localparam VGA_WRITE = 4;

assign cpu_busy = (state != IDLE);

logic [7:0] burst_left;
logic [31:2] burst_addr;

reg   [1:0] vga_mask;
reg   [1:0] vga_cmp;
reg   [3:0] vga_be;
reg   [2:0] vga_bcnt;
reg   [1:0] vga_bank, vga_bank_t;
reg   [31:0] vga_data;
// reg   [1:0] boff_t, boff;

// = 0xA0000-0xBFFFF (VGA: exact region depends on VGA_MODE)
wire vga_rgn = (cpu_addr[31:17] == 'h5) && ((cpu_addr[16:15] & vga_mask) == vga_cmp); 

always @(posedge clk) begin
    if (reset) begin
        state <= IDLE;
        burst_left <= 0;
`ifdef VERILATOR
        for (int i = 0; i < DWORD_CNT; i++) begin
            mem[i] = {4{8'hF4}};     // HLT
        end
`endif
    end else begin
        cpu_dout_ready <= 0;
        vga_read <= 0;
        vga_write <= 0;
        case (state)
            IDLE: begin
                // set up vga access to point to 1st enabled byte
                vga_address[16:2] <= cpu_addr[16:2];
                if (cpu_be[0]) begin
                    vga_be <= cpu_be;
                    vga_bcnt <= 4;
                    vga_bank_t = 0;
                    vga_data <= cpu_din;
                end else if (cpu_be[1]) begin
                    vga_be <= cpu_be[3:1];
                    vga_bcnt <= 3;
                    vga_bank_t = 1;
                    vga_data <= cpu_din[31:8];
                end else if (cpu_be[2]) begin
                    vga_be <= cpu_be[3:2];
                    vga_bcnt <= 2;
                    vga_bank_t = 2;
                    vga_data <= cpu_din[31:16];
                end else begin
                    vga_be <= cpu_be[3:3];
                    vga_bcnt <= 1;
                    vga_bank_t = 3;
                    vga_data <= cpu_din[31:24];
                end
                vga_bank <= vga_bank_t;

                if (cpu_rd) begin
                    if (vga_rgn) begin
                        // VGA read, byte or word only
                        state <= VGA_READ_WAIT;
                        vga_read <= 1;
                        vga_address <= {cpu_addr[16:2], vga_bank_t};
                    end else begin
                        // Main memory read, supports burst
                        if (!cpu_addr_region)
                            cpu_dout <= 0;
                        else
                            cpu_dout <= mem[cpu_addr[31:2]];
                        cpu_dout_ready <= 1;
                        if (cpu_burstcount > 1) begin
                            state <= READ_BURST;
                            burst_left <= cpu_burstcount - 1;
                            burst_addr <= cpu_addr[31:2] + 1;
                        end
                    end
                end else if (cpu_we) begin
                    if (vga_rgn) begin
                        // VGA write
                        state <= VGA_WRITE;
                        // $display("VGA write: [%h]=%h, byteenable=%b", cpu_addr, cpu_din, cpu_be); 
                    end else begin
                        if ((!protect_rom || !is_rom_area(cpu_addr)) && cpu_addr_region) begin
                            // Main memory write, supports burst
                            if (cpu_be[0]) mem[cpu_addr[31:2]][7:0] <= cpu_din[7:0];
                            if (cpu_be[1]) mem[cpu_addr[31:2]][15:8] <= cpu_din[15:8];
                            if (cpu_be[2]) mem[cpu_addr[31:2]][23:16] <= cpu_din[23:16];
                            if (cpu_be[3]) mem[cpu_addr[31:2]][31:24] <= cpu_din[31:24];
                        end
                    end
                end
            end
            READ_BURST: begin
                if (burst_left == 0) begin
                    state <= IDLE;
                end else begin
                    if (!cpu_addr_region)
                        cpu_dout <= 0;
                    else
                        cpu_dout <= mem[burst_addr];
                    cpu_dout_ready <= 1;
                    burst_addr <= burst_addr + 1;
                    burst_left <= burst_left - 1;
                end
            end
            VGA_READ_WAIT: begin   // vga_read == 1
                state <= VGA_READ;
                vga_be <= vga_be[3:1];
                vga_bcnt <= vga_bcnt - 1;
                vga_bank <= vga_bank + 1;
            end
            VGA_READ: begin
                vga_read <= vga_be[0];
                vga_address[1:0] <= vga_bank;
                cpu_dout <= {vga_readdata, cpu_dout[31:8]};
                if (vga_bcnt == 0) begin
                    cpu_dout_ready <= 1;
                    state <= IDLE;
                end else
                    state <= VGA_READ_WAIT;
            end
            VGA_WRITE: begin
                vga_write <= vga_be[0];
                vga_be <= vga_be[3:1];
                vga_address[1:0] <= vga_bank;
                vga_bank <= vga_bank + 1;
                vga_writedata <= vga_data[7:0];
                vga_data <= {8'h00, vga_data[31:8]};
                if (!vga_be[3:1]) begin
                    state <= IDLE;
                end
            end
            default: ;
        endcase
    end
end

always @(posedge clk) begin
	case (vga_memmode)
		3'b100:		// 128K
			begin
				vga_mask <= 2'b00;
				vga_cmp  <= 2'b00;
			end
		
		3'b101:		// lower 64K
			begin
				vga_mask <= 2'b10;
				vga_cmp  <= 2'b00;
			end
		
		3'b110:		// 3rd 32K
			begin
				vga_mask <= 2'b11;
				vga_cmp  <= 2'b10;
			end
		
		3'b111:		// top 32K
			begin
				vga_mask <= 2'b11;
				vga_cmp  <= 2'b11;
			end
		
		default :	// disable VGA RAM
			begin
				vga_mask <= 2'b00;
				vga_cmp  <= 2'b11;
			end
	endcase
end

function automatic logic is_rom_area(input [31:0] addr);
    return (addr[31:16] == 16'h000F || addr[31:16] == 16'h000C || addr[31:16] == 16'h000D);
endfunction

endmodule