// ao486 SoC for whole-system Verilator simulation
// nand2mario, 7/2025
module system (
    input         clk_sys,
    input         reset,
	input  [27:0] clock_rate,

	output [1:0]  fdd_request,
	output [2:0]  ide0_request,
	output [2:0]  ide1_request,
	input  [1:0]  floppy_wp,

	input  [15:0] mgmt_address,
	input         mgmt_read,
	output [31:0] mgmt_readdata,
	input         mgmt_write,
	input  [31:0] mgmt_writedata,

`ifdef VERILATOR
	input   [7:0] kbd_data,             // PS2 codes to send to PC
	input         kbd_data_valid,       // 1: kbd_data is valid
	output  [8:0] kbd_host_data,        // Data from PC to PS2. [8] has_data, [7:0] data
	input         kbd_host_data_clear,  // 1: clear kbd_rdata
`else
	input         ps2_kbclk_in,
	input         ps2_kbdat_in,
	output        ps2_kbclk_out,
	output        ps2_kbdat_out,
`endif

	input         ps2_mouseclk_in,
	input         ps2_mousedat_in,
	output        ps2_mouseclk_out,
	output        ps2_mousedat_out,
	output        ps2_reset_n,

	input   [5:0] bootcfg,
    input         uma_ram,
	output  [7:0] syscfg,

	input         clk_vga,
	input  [27:0] clock_rate_vga,

	output        video_ce,
	output        video_blank_n,
	output        video_hsync,
	output        video_vsync,
	output [7:0]  video_r,
	output [7:0]  video_g,
	output [7:0]  video_b,
	input         video_f60,
	output [7:0]  video_pal_a,
	output [17:0] video_pal_d,
	output        video_pal_we,
	output [19:0] video_start_addr,
	output [8:0]  video_width,
	output [10:0] video_height,
	output [3:0]  video_flags,
	output [8:0]  video_stride,
	output        video_off,
	input         video_fb_en,
	input         video_lores,
	input         video_border,

	output        speaker_out,

	input         dbg_mem_wr,
	input  [31:0] dbg_mem_addr,    // byte address
	input  [7:0]  dbg_mem_din,
	input         dbg_mem_rd,
	output [7:0]  dbg_mem_dout,

	input         dbg_reg_wr,
	input  [3:0]  dbg_reg_addr,
	input  [15:0] dbg_reg_din,
	input         dbg_reg_rd,
	output [15:0] dbg_reg_dout
);

wire        a20_enable;
wire  [7:0] dma_floppy_readdata;
wire        dma_floppy_tc;
wire  [7:0] dma_floppy_writedata;
wire        dma_floppy_req;
wire        dma_floppy_ack;
wire        dma_sb_req_8;
wire        dma_sb_req_16;
wire        dma_sb_ack_8;
wire        dma_sb_ack_16;
wire  [7:0] dma_sb_readdata_8;
wire [15:0] dma_sb_readdata_16;
wire [15:0] dma_sb_writedata;
wire [15:0] dma_readdata;
wire        dma_waitrequest;
wire [23:0] dma_address;
wire        dma_read;
wire        dma_readdatavalid;
wire        dma_write;
wire [15:0] dma_writedata;
wire        dma_16bit;

wire [15:0] mgmt_fdd_readdata;
wire [15:0] mgmt_ide0_readdata;
wire [15:0] mgmt_ide1_readdata;
wire        mgmt_ide0_cs;
wire        mgmt_ide1_cs;
wire        mgmt_fdd_cs;
wire        mgmt_rtc_cs;

wire        interrupt_done;
wire        interrupt_do;
wire  [7:0] interrupt_vector;
reg  [15:0] interrupt;
wire        irq_0, irq_1, irq_2, irq_3, irq_4, irq_5, irq_6, irq_7, irq_8, irq_9, irq_10, irq_12, irq_14, irq_15;

wire        cpu_io_read_do /* verilator public */;
wire [15:0] cpu_io_read_address /* verilator public */;
wire  [2:0] cpu_io_read_length;
wire [31:0] cpu_io_read_data;
wire        cpu_io_read_done;
wire        cpu_io_write_do        /* verilator public */;
wire [15:0] cpu_io_write_address   /* verilator public */;
wire  [2:0] cpu_io_write_length    /* verilator public */;
wire [31:0] cpu_io_write_data      /* verilator public */;
wire        cpu_io_write_done      /* verilator public */;
wire [15:0] iobus_address;
wire        iobus_write;
wire        iobus_read;
wire  [2:0] iobus_datasize;
wire [31:0] iobus_writedata;

reg         ide0_cs;
reg         ide1_cs;
reg         floppy0_cs;
reg         dma_master_cs;
reg         dma_page_cs;
reg         dma_slave_cs;
reg         pic_master_cs;
reg         pic_slave_cs;
reg         pit_cs;
reg         ps2_io_cs;
reg         ps2_ctl_cs;
reg         joy_cs;
reg         rtc_cs;
reg         fm_cs;
reg         sb_cs;
reg         uart1_cs;
reg         uart2_cs;
reg         mpu_cs;
reg         vga_b_cs;
reg         vga_c_cs;
reg         vga_d_cs;
reg         sysctl_cs;

wire        fdd0_inserted;

wire  [7:0] sound_readdata;
wire  [7:0] floppy0_readdata;
wire [31:0] ide0_readdata;
wire [31:0] ide1_readdata;
wire  [7:0] joystick_readdata;
wire  [7:0] pit_readdata;
wire  [7:0] ps2_readdata;
wire  [7:0] rtc_readdata;
wire  [7:0] uart1_readdata;
wire  [7:0] uart2_readdata;
wire  [7:0] mpu_readdata;
wire  [7:0] dma_io_readdata;
wire  [7:0] pic_readdata;
wire  [7:0] vga_io_readdata;

wire [29:0] mem_address /* verilator public */;      // dword address
wire [31:0] mem_writedata /* verilator public */;
wire [31:0] mem_readdata /* verilator public */;
wire  [3:0] mem_byteenable /* verilator public */;
wire  [3:0] mem_burstcount;
wire        mem_write /* verilator public */;
wire        mem_read;
wire        mem_waitrequest;
wire        mem_readdatavalid;

wire [16:0] vga_address;
wire  [7:0] vga_readdata;
wire  [7:0] vga_writedata;
wire        vga_read;
wire        vga_write;
wire  [2:0] vga_memmode;
wire  [5:0] video_wr_seg;
wire  [5:0] video_rd_seg;

// reg mgmt_read_req_r, mgmt_write_req_r;
// wire mgmt_read = mgmt_read_req ^ mgmt_read_req_r;
// wire mgmt_write = mgmt_write_req ^ mgmt_write_req_r;
// always @(posedge clk_sys) begin
// 	mgmt_read_req_r <= mgmt_read_req;
// 	mgmt_write_req_r <= mgmt_write_req;
// end

sdram_sim sdram (
    .clk               (clk_sys),
    .reset             (1'b0),
   
    .cpu_addr          (dbg_mem_wr ? dbg_mem_addr : {mem_address, 2'b00}),
    .cpu_din           (dbg_mem_wr ? {4{dbg_mem_din}} : mem_writedata),
    .cpu_dout          (mem_readdata),
    .cpu_dout_ready    (mem_readdatavalid),
    .cpu_be            (dbg_mem_wr ? (1 << dbg_mem_addr[1:0]) : mem_byteenable),
    .cpu_burstcount    (mem_burstcount),
    .cpu_busy          (mem_waitrequest),
    .cpu_rd            (mem_read),
    .cpu_we            (dbg_mem_wr ? 1'b1 : mem_write),

	.protect_rom       (~reset),    // when cpu is running, make ROM readonly

	.vga_address       (vga_address),
	.vga_readdata      (vga_readdata),
	.vga_writedata     (vga_writedata),
	.vga_read          (vga_read),
	.vga_write         (vga_write),
	.vga_memmode       (vga_memmode),
	.vga_wr_seg        (video_wr_seg),
	.vga_rd_seg        (video_rd_seg),
	.vga_fb_en         (video_fb_en)
);


ao486 ao486 (
    .clk               (clk_sys),
    .rst_n             (~reset),
	// .cpu_reset         (cpu_reset),

	.cache_disable     (1'b0),

	.avm_address       (mem_address),
	.avm_writedata     (mem_writedata),
	.avm_byteenable    (mem_byteenable),
	.avm_burstcount    (mem_burstcount),
	.avm_write         (mem_write),
	.avm_read          (mem_read),

	.avm_waitrequest   (mem_waitrequest),
	.avm_readdatavalid (mem_readdatavalid),
	.avm_readdata      (mem_readdata),

	.interrupt_do      (interrupt_do),
	.interrupt_vector  (interrupt_vector),
	.interrupt_done    (interrupt_done),

	.io_read_do        (cpu_io_read_do),
	.io_read_address   (cpu_io_read_address),
	.io_read_length    (cpu_io_read_length),
	.io_read_data      (cpu_io_read_data),
	.io_read_done      (cpu_io_read_done),

	.io_write_do       (cpu_io_write_do),
	.io_write_address  (cpu_io_write_address),
	.io_write_length   (cpu_io_write_length),
	.io_write_data     (cpu_io_write_data),
	.io_write_done     (cpu_io_write_done),

	.a20_enable        (a20_enable),

	.dma_address       (dma_address),
	.dma_16bit         (dma_16bit),
	.dma_write         (dma_write),
	.dma_writedata     (dma_writedata),
	.dma_read          (dma_read),
	.dma_readdata      (dma_readdata),
	.dma_readdatavalid (dma_readdatavalid),
	.dma_waitrequest   (dma_waitrequest)

	// .dbg_reg_wr        (dbg_reg_wr),
	// .dbg_reg_addr      (dbg_reg_addr),
	// .dbg_reg_din       (dbg_reg_din),
	// .dbg_reg_rd        (dbg_reg_rd),
	// .dbg_reg_dout      (dbg_reg_dout)
);

always @(posedge clk_sys) begin
	ide0_cs       <= ({iobus_address[15:3], 3'd0} == 16'h01F0) || ({iobus_address[15:0]} == 16'h03F6);
	ide1_cs       <= ({iobus_address[15:3], 3'd0} == 16'h0170) || ({iobus_address[15:0]} == 16'h0376);
	floppy0_cs    <= ({iobus_address[15:2], 2'd0} == 16'h03F0) || ({iobus_address[15:1], 1'd0} == 16'h03F4) || ({iobus_address[15:0]} == 16'h03F7) ;
	dma_master_cs <= ({iobus_address[15:5], 5'd0} == 16'h00C0);
	dma_page_cs   <= ({iobus_address[15:4], 4'd0} == 16'h0080);
	dma_slave_cs  <= ({iobus_address[15:4], 4'd0} == 16'h0000);
	pic_master_cs <= ({iobus_address[15:1], 1'd0} == 16'h0020);
	pic_slave_cs  <= ({iobus_address[15:1], 1'd0} == 16'h00A0);
	pit_cs        <= ({iobus_address[15:2], 2'd0} == 16'h0040) || (iobus_address == 16'h0061);
	ps2_io_cs     <= ({iobus_address[15:3], 3'd0} == 16'h0060);
	ps2_ctl_cs    <= ({iobus_address[15:4], 4'd0} == 16'h0090);
	rtc_cs        <= ({iobus_address[15:1], 1'd0} == 16'h0070);
	vga_b_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03B0);
	vga_c_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03C0);
	vga_d_cs      <= ({iobus_address[15:4], 4'd0} == 16'h03D0);
	sysctl_cs     <= ({iobus_address[15:0]      } == 16'h8888);
end

reg [7:0] ctlport = 0;
reg in_reset = 1;
always @(posedge clk_sys) begin
	if(reset) begin
		ctlport <= 8'hA2;
		in_reset <= 1;
	end
	else if((ide0_cs|ide1_cs|floppy0_cs) && in_reset) begin
		ctlport <= 0;
		in_reset <= 0;
	end
	else if(iobus_write && sysctl_cs && iobus_datasize == 2 && iobus_writedata[15:8] == 8'hA1) begin
		ctlport <= iobus_writedata[7:0];
		in_reset <= 0;
	end
end

assign syscfg = ctlport;

wire [7:0] iobus_readdata8 =
	( floppy0_cs                             ) ? floppy0_readdata  :
	( dma_master_cs|dma_slave_cs|dma_page_cs ) ? dma_io_readdata   :
	( pic_master_cs|pic_slave_cs             ) ? pic_readdata      :
	( pit_cs                                 ) ? pit_readdata      :
	( ps2_io_cs|ps2_ctl_cs                   ) ? ps2_readdata      :
	( rtc_cs                                 ) ? rtc_readdata      :
	( vga_b_cs|vga_c_cs|vga_d_cs             ) ? vga_io_readdata   :
	                                             8'hFF;

iobus iobus
(
	.clk               (clk_sys),
	.reset             (reset),

	.cpu_read_do       (cpu_io_read_do),
	.cpu_read_address  (cpu_io_read_address),
	.cpu_read_length   (cpu_io_read_length),
	.cpu_read_data     (cpu_io_read_data),
	.cpu_read_done     (cpu_io_read_done),
	.cpu_write_do      (cpu_io_write_do),
	.cpu_write_address (cpu_io_write_address),
	.cpu_write_length  (cpu_io_write_length),
	.cpu_write_data    (cpu_io_write_data),
	.cpu_write_done    (cpu_io_write_done),

	.bus_address       (iobus_address),
	.bus_write         (iobus_write),
	.bus_read          (iobus_read),
	.bus_io32          (((ide0_cs | ide1_cs) & ~iobus_address[9]) | sysctl_cs),
	.bus_datasize      (iobus_datasize),
	.bus_writedata     (iobus_writedata),
	.bus_readdata      (ide0_cs ? ide0_readdata : ide1_cs ? ide1_readdata : iobus_readdata8),
	.bus_wait          (ide0_wait | ide1_wait)
);

dma dma
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.mem_address       (dma_address),
	.mem_16bit         (dma_16bit),
	.mem_waitrequest   (dma_waitrequest),
	.mem_read          (dma_read),
	.mem_readdatavalid (dma_readdatavalid),
	.mem_readdata      (dma_readdata),
	.mem_write         (dma_write),
	.mem_writedata     (dma_writedata),

	.io_address        (iobus_address[4:0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read),
	.io_write          (iobus_write),
	.io_readdata       (dma_io_readdata),
	.io_master_cs      (dma_master_cs),
	.io_slave_cs       (dma_slave_cs),
	.io_page_cs        (dma_page_cs),

	.dma_2_req         (dma_floppy_req),
	.dma_2_ack         (dma_floppy_ack),
	.dma_2_tc          (dma_floppy_tc),
	.dma_2_readdata    (dma_floppy_readdata),
	.dma_2_writedata   (dma_floppy_writedata),

	.dma_1_req         (dma_sb_req_8),
	.dma_1_ack         (dma_sb_ack_8),
	.dma_1_readdata    (dma_sb_readdata_8),
	.dma_1_writedata   (dma_sb_writedata[7:0]),

	.dma_5_req         (dma_sb_req_16),
	.dma_5_ack         (dma_sb_ack_16),
	.dma_5_readdata    (dma_sb_readdata_16),
	.dma_5_writedata   (dma_sb_writedata)
);

floppy floppy
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.clock_rate        (clock_rate),

	.io_address        (iobus_address[2:0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read & floppy0_cs),
	.io_write          (iobus_write & floppy0_cs),
	.io_readdata       (floppy0_readdata),

	.fdd0_inserted     (fdd0_inserted),

	.dma_req           (dma_floppy_req),
	.dma_ack           (dma_floppy_ack),
	.dma_tc            (dma_floppy_tc),
	.dma_readdata      (dma_floppy_readdata),
	.dma_writedata     (dma_floppy_writedata),

	.mgmt_address      (mgmt_address[3:0]),
	.mgmt_fddn         (mgmt_address[7]),
	.mgmt_writedata    (mgmt_writedata),
	.mgmt_readdata     (mgmt_fdd_readdata),
	.mgmt_write        (mgmt_write & mgmt_fdd_cs),
	.mgmt_read         (mgmt_read & mgmt_fdd_cs),

	.wp                (floppy_wp),

	.request           (fdd_request),
	.irq               (irq_6)
);

wire [3:0] ide_address = {iobus_address[9],iobus_address[2:0]};

wire ide0_nodata;
reg  ide0_wait = 0;
always @(posedge clk_sys) begin
	if(iobus_read & ide0_cs & ide0_nodata & !ide_address) ide0_wait <= 1;
	if(~ide0_nodata) ide0_wait <= 0;
end

wire [3:0] sd_avs_address;
wire sd_avs_read;
wire sd_avs_write;
wire [31:0] sd_avs_writedata;
wire [31:0] sd_avs_readdata;
reg sd_avs_readdatavalid;
always @(posedge clk_sys) sd_avs_readdatavalid <= sd_avs_read;

wire [31:0] sd_avm_address;
wire sd_avm_read;
reg sd_avm_readdatavalid;
wire [31:0] sd_avm_readdata;
wire sd_avm_write;
wire [31:0] sd_avm_writedata;

always @(posedge clk_sys) sd_avm_readdatavalid <= sd_avm_read;

ide ide0
(
	.clk               (clk_sys),
	.rst_n             (1'b1 /*~reset*/),

	.io_address        (ide_address),
	.io_writedata      (iobus_writedata),
	.io_read           ((iobus_read & ide0_cs) | ide0_wait),
	.io_write          (iobus_write & ide0_cs),
	.io_readdata       (ide0_readdata),
	.io_32             (iobus_datasize[2]),

	// .use_fast          (1),
	// .no_data           (ide0_nodata),

	.mgmt_address      (mgmt_address[3:0]),
	.mgmt_writedata    (mgmt_writedata),
	.mgmt_write        (mgmt_write & mgmt_ide0_cs),
	// .mgmt_readdata     (mgmt_ide0_readdata),
	// .mgmt_read         (mgmt_read & mgmt_ide0_cs),

	// .request           (ide0_request),
	.irq               (irq_14),

	.sd_master_address (sd_avs_address),
	.sd_master_waitrequest (1'b0),
	.sd_master_read (sd_avs_read),
	.sd_master_readdatavalid (sd_avs_readdatavalid),
	.sd_master_readdata (sd_avs_readdata),
	.sd_master_write (sd_avs_write),
	.sd_master_writedata (sd_avs_writedata),

    .sd_slave_address (sd_avm_address),
    .sd_slave_read (sd_avm_read),
    .sd_slave_readdata (sd_avm_readdata),
    .sd_slave_write (sd_avm_write),
    .sd_slave_writedata (sd_avm_writedata)
);

driver_sd driver_sd
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.avs_address       (sd_avs_address[3:2]),
	.avs_read 		   (sd_avs_read),
	.avs_readdata      (sd_avs_readdata),
	.avs_write 	       (sd_avs_write),
	.avs_writedata     (sd_avs_writedata),

	.avm_address 	   (sd_avm_address),
	.avm_waitrequest   (1'b0),
	.avm_read 		   (sd_avm_read),
	.avm_readdatavalid (sd_avm_readdatavalid),
	.avm_readdata      (sd_avm_readdata),
	.avm_write         (sd_avm_write),
	.avm_writedata     (sd_avm_writedata)
);

wire ide1_nodata;
reg  ide1_wait = 0;
always @(posedge clk_sys) begin
	if(iobus_read & ide1_cs & ide1_nodata & !ide_address) ide1_wait <= 1;
	if(~ide1_nodata) ide1_wait <= 0;
end

ide ide1
(
	.clk               (clk_sys),
	.rst_n             (1'b1 /*~reset*/),

	.io_address        (ide_address),
	.io_writedata      (iobus_writedata),
	.io_read           ((iobus_read & ide1_cs) | ide1_wait),
	.io_write          (iobus_write & ide1_cs),
	.io_readdata       (ide1_readdata),
	.io_32             (iobus_datasize[2]),

	// .use_fast          (1),
	// .no_data           (ide1_nodata),

	.mgmt_address      (mgmt_address[3:0]),
	.mgmt_write        (mgmt_write & mgmt_ide1_cs),
	.mgmt_writedata    (mgmt_writedata),
	// .mgmt_readdata     (mgmt_ide1_readdata),
	// .mgmt_read         (mgmt_read & mgmt_ide1_cs),

	// .request           (ide1_request),
	.irq               (irq_15),

	.sd_master_address       (),
	.sd_master_waitrequest   (),
	.sd_master_read          (),
	.sd_master_readdatavalid (),
	.sd_master_readdata 	 (),
	.sd_master_write 	     (),
	.sd_master_writedata     (),

    .sd_slave_address        (),
    .sd_slave_read 			 (),
    .sd_slave_readdata 		 (),
    .sd_slave_write 		 (),
    .sd_slave_writedata      ()
);

// timers
pit pit
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.clock_rate        (clock_rate),

	.io_address        ({iobus_address[5],iobus_address[1:0]}),
	.io_writedata      (iobus_writedata[7:0]),
	.io_readdata       (pit_readdata),
	.io_read           (iobus_read & pit_cs),
	.io_write          (iobus_write & pit_cs),

	.speaker_out       (speaker_out),
	.irq               (irq_0)
);

`ifdef VERILATOR
wire ps2_kbclk_in;
wire ps2_kbdat_in;
wire ps2_kbclk_out;
wire ps2_kbdat_out;
`endif

ps2 ps2
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.io_address        (iobus_address[3:0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read),
	.io_write          (iobus_write),
	.io_readdata       (ps2_readdata),
	.io_cs             (ps2_io_cs),
	.ctl_cs            (ps2_ctl_cs),

	.ps2_kbclk         (ps2_kbclk_in),
	.ps2_kbdat         (ps2_kbdat_in),
	.ps2_kbclk_out     (ps2_kbclk_out),
	.ps2_kbdat_out     (ps2_kbdat_out),

	.ps2_mouseclk      (ps2_mouseclk_in),
	.ps2_mousedat      (ps2_mousedat_in),
	.ps2_mouseclk_out  (ps2_mouseclk_out),
	.ps2_mousedat_out  (ps2_mousedat_out),

	.output_a20_enable (),
	.output_reset_n    (ps2_reset_n),
	.a20_enable        (a20_enable),

	.irq_keyb          (irq_1),
	.irq_mouse         (irq_12)
);

rtc rtc
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.clock_rate        (clock_rate),

	.io_address        (iobus_address[0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read & rtc_cs),
	.io_write          (iobus_write & rtc_cs),
	.io_readdata       (rtc_readdata),

	.mgmt_address      (mgmt_address[7:0]),
	.mgmt_write        (mgmt_write & mgmt_rtc_cs),
	.mgmt_writedata    (mgmt_writedata[7:0]),

	.bootcfg           ({bootcfg[5:2], bootcfg[1:0] ? bootcfg[1:0] : {~fdd0_inserted, fdd0_inserted}}),

	.irq               (irq_8)
);

vga vga
(
	.clk_sys           (clk_sys),
	.rst_n             (~reset),

	.clk_vga           (clk_vga),
	.clock_rate_vga    (clock_rate_vga),

	.io_address        (iobus_address[3:0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read),
	.io_write          (iobus_write),
	.io_readdata       (vga_io_readdata),
	.io_b_cs           (vga_b_cs),
	.io_c_cs           (vga_c_cs),
	.io_d_cs           (vga_d_cs),

	.mem_address       (vga_address),
	.mem_read          (vga_read),
	.mem_readdata      (vga_readdata),
	.mem_write         (vga_write),
	.mem_writedata     (vga_writedata),

	.vga_ce            (video_ce),
	.vga_blank_n       (video_blank_n),
	.vga_horiz_sync    (video_hsync),
	.vga_vert_sync     (video_vsync),
	.vga_r             (video_r),
	.vga_g             (video_g),
	.vga_b             (video_b),
	.vga_f60           (video_f60),
	.vga_memmode       (vga_memmode),
	.vga_pal_a         (video_pal_a),
	.vga_pal_d         (video_pal_d),
	.vga_pal_we        (video_pal_we),
	.vga_start_addr    (video_start_addr),
	.vga_wr_seg        (video_wr_seg),
	.vga_rd_seg        (video_rd_seg),
	.vga_width         (video_width),
	.vga_height        (video_height),
	.vga_flags         (video_flags),
	.vga_stride        (video_stride),
	.vga_off           (video_off),
	.vga_lores         (video_lores),
	.vga_border        (video_border),

	.irq               (irq_2)
);

pic pic
(
	.clk               (clk_sys),
	.rst_n             (~reset),

	.io_address        (iobus_address[0]),
	.io_writedata      (iobus_writedata[7:0]),
	.io_read           (iobus_read),
	.io_write          (iobus_write),
	.io_readdata       (pic_readdata),
	.io_master_cs      (pic_master_cs),
	.io_slave_cs       (pic_slave_cs),

	.interrupt_vector  (interrupt_vector),
	.interrupt_done    (interrupt_done),
	.interrupt_do      (interrupt_do),
	.interrupt_input   (interrupt)
);

always @* begin
	interrupt = 0;

	interrupt[0]  = irq_0;
	interrupt[1]  = irq_1;
	interrupt[3]  = irq_3;
	interrupt[4]  = irq_4;
	interrupt[5]  = irq_5;
	interrupt[6]  = irq_6;
	interrupt[7]  = irq_7;
	interrupt[8]  = irq_8;
	interrupt[9]  = irq_9 | irq_2;
	interrupt[10] = irq_10;
	interrupt[12] = irq_12;
	interrupt[14] = irq_14;
	interrupt[15] = irq_15;
end

assign mgmt_ide0_cs  = (mgmt_address[15:8] == 8'hF0);
assign mgmt_ide1_cs  = (mgmt_address[15:8] == 8'hF1);
assign mgmt_fdd_cs   = (mgmt_address[15:8] == 8'hF2);
assign mgmt_rtc_cs   = (mgmt_address[15:8] == 8'hF4);
assign mgmt_readdata = mgmt_ide0_cs ? mgmt_ide0_readdata : mgmt_ide1_cs ? mgmt_ide1_readdata : mgmt_fdd_readdata;


//
// PS2 keyboard emulation for verilator simulation
//
`ifdef VERILATOR
logic clk_ps2;
localparam PS2DIV = 2000;       // 50M / 4000 = 12.5kHz

always_ff @(posedge clk_sys) begin
    integer cnt;
    cnt <= cnt + 1;
    if (cnt == PS2DIV) begin
        clk_ps2 <= ~clk_ps2;
        cnt <= 0;
    end
end

ps2_device ps2_kbd(
    .clk_sys(clk_sys),
    .ps2_clk(clk_ps2),

    .wdata(kbd_data),               // keyboard data byte
    .we(kbd_data_valid),

    .ps2_clk_out(ps2_kbclk_in),     // emulated PS2 interface to PC
    .ps2_dat_out(ps2_kbdat_in),
    .tx_empty(),
    .ps2_clk_in(ps2_kbclk_out),     // data from PC
    .ps2_dat_in(ps2_kbdat_out),

    .rdata(kbd_host_data),          // {valid, data_byte_from_PC}
    .rd(kbd_host_data_clear)        // clear the data
);

`endif



endmodule