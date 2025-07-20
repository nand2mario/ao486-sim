VERILATOR = verilator
CFLAGS_SDL=$(shell sdl2-config --cflags) -g -O2 -std=c++17
LIBS_SDL=$(shell sdl2-config --libs) -g
VERILATOR_FLAGS = +1800-2017ext+sv --trace-fst --trace-structs --top-module system --cc --exe --threads 2 --build -CFLAGS "$(CFLAGS_SDL)" -LDFLAGS "$(LIBS_SDL)" -j 0 -Wno-WIDTH -Wno-PINMISSING
VERILATOR_INCLUDE = -I../src/ao486
VERILATOR_OPT = -O2
D=../src

# Source files
SOURCES = $D/system.sv $D/sdram_sim.sv $D/ao486/ao486.v $D/ao486/exception.v $D/ao486/global_regs.v \
		  $D/ao486/memory/avalon_mem.v $D/ao486/memory/icache.v $D/ao486/memory/link_dcacheread.v $D/ao486/memory/link_dcachewrite.v \
		  $D/ao486/memory/memory_read.v $D/ao486/memory/memory_write.v $D/ao486/memory/memory.v \
		  $D/ao486/memory/prefetch_control.v $D/ao486/memory/prefetch_fifo.v $D/ao486/memory/prefetch.v \
		  $D/ao486/memory/tlb.v $D/ao486/memory/tlb_memtype.v $D/ao486/memory/tlb_regs.v \
		  $D/ao486/pipeline/condition.v $D/ao486/pipeline/decode_commands.v $D/ao486/pipeline/decode_prefix.v \
		  $D/ao486/pipeline/decode_ready.v $D/ao486/pipeline/decode_regs.v $D/ao486/pipeline/decode.v \
		  $D/ao486/pipeline/execute_commands.v $D/ao486/pipeline/execute_divide.v $D/ao486/pipeline/execute_multiply.v \
		  $D/ao486/pipeline/execute_offset.v $D/ao486/pipeline/execute_shift.v $D/ao486/pipeline/execute.v \
		  $D/ao486/pipeline/fetch.v $D/ao486/pipeline/microcode_commands.v $D/ao486/pipeline/microcode.v \
		  $D/ao486/pipeline/pipeline.v $D/ao486/pipeline/read_commands.v $D/ao486/pipeline/read_debug.v \
		  $D/ao486/pipeline/read_effective_address.v $D/ao486/pipeline/read_mutex.v $D/ao486/pipeline/read.v $D/ao486/pipeline/read_segment.v \
		  $D/ao486/pipeline/write_commands.v $D/ao486/pipeline/write_debug.v $D/ao486/pipeline/write_register.v \
		  $D/ao486/pipeline/write_stack.v $D/ao486/pipeline/write_string.v $D/ao486/pipeline/write.v \
		  $D/soc/dma.v $D/soc/floppy.v $D/soc/ide.v $D/soc/driver_sd_sim.v $D/soc/iobus.v $D/soc/pic.v $D/soc/pit_counter.v \
		  $D/soc/pit.v $D/soc/ps2.v $D/soc/rtc.v $D/soc/vga.v $D/common/dpram.v $D/common/simple_ram.v \
		  $D/common/simple_fifo.v $D/common/ps2_device.v $D/common/simple_mult.v $D/cache/l1_icache.v
CPP_SOURCES = main.cpp ide.cpp

# Default target
all: obj_dir/Vsystem dos6.vhd

# Generate Verilator files and build
obj_dir/Vsystem: $(SOURCES) $(CPP_SOURCES)
	$(VERILATOR) $(VERILATOR_FLAGS) $(VERILATOR_INCLUDE) $(VERILATOR_OPT) $(SOURCES) $(CPP_SOURCES) 

dos6.vhd: dos6.vhd.gz
	gunzip -k dos6.vhd.gz

# Clean generated filesx2
clean:
	rm -rf obj_dir
	rm -f *.o *.d sim_cache

# msdos622.vhd is hard-coded in driver_sd_sim.v
# ./obj_dir/Vsystem -s 235000000 -e 240000000 boot0.rom boot1.rom
trace: obj_dir/Vsystem dos6.vhd
	./obj_dir/Vsystem --trace -s 0 -e 10000000 boot0.rom boot1.rom dos6.vhd

sim: obj_dir/Vsystem dos6.vhd
	./obj_dir/Vsystem boot0.rom boot1.rom dos6.vhd

.PHONY: all sim run clean
