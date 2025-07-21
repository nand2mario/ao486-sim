// ao486-sim: x86 whole-system simulator
//
// This is a Verilator-based simulator for the ao486 CPU core.
// It simulates the entire x86 system, including the CPU, memory,
// and peripherals.
//
// nand2mario, 7/2025
//
#include "verilated.h"
#include "verilated_fst_c.h"
#include "Vsystem.h"
#include "Vsystem_ao486.h"
#include "Vsystem_system.h"
#include "Vsystem_pipeline.h"
#include "Vsystem_sdram_sim.h"
#include "Vsystem_driver_sd.h"
#include <svdpi.h>
#include <fstream>
#include <iostream>
#include <set>
#include <map>
#include <vector>
#include <sys/stat.h>
#include <SDL.h>

#include "ide.h"

using namespace std;

const int H_RES = 720;    // VGA text mode is 720x400
const int V_RES = 480;    // graphics mode is max 640x480
int resolution_x = 720;
int resolution_y = 400;
int x_cnt, y_cnt;
int frame_count = 0;
string disk_file;
typedef struct Pixel
{			   // for SDL texture
	uint8_t a; // transparency
	uint8_t b; // blue
	uint8_t g; // green
	uint8_t r; // red
} Pixel;

Pixel screenbuffer[H_RES * V_RES];

bool trace_toggle = false;
void set_trace(bool toggle);
bool trace_vga = false;
bool trace_ide = false;
bool trace_post = false;
uint64_t sim_time = 0;
uint64_t last_time;
uint64_t start_time = UINT64_MAX;
uint64_t stop_time = UINT64_MAX;
Vsystem tb;
VerilatedFstC* trace;
int failure = -1;
uint16_t ignore_mask = 0xf400;      // 15:12 
int ignore_memory = 0;
set<uint32_t> watch_memory;         // dword addresses
bool mem_write_r = 0;
uint32_t eip_r = 0;

// FPS tracking variables (wall clock time)
uint32_t fps_start_time = 0;
uint32_t fps_frame_count = 0;

#include "scancode.h"

void step() {
    tb.clk_sys = !tb.clk_sys;
    tb.clk_vga = tb.clk_sys;
    tb.eval();
    sim_time++;
    if (trace_toggle) {
        trace->dump(sim_time);
    }
}

void load_program(uint32_t start_addr, std::vector<uint8_t> &program) {
    if (!tb.clk_sys) step(); 
    
    for (int i = 0; i < program.size(); i++) {
        tb.dbg_mem_wr = 1;
        tb.dbg_mem_addr = start_addr + i;
        tb.dbg_mem_din = program[i];
        step(); step();
    }
    tb.dbg_mem_wr = 0;
    step(); step();
}

inline void set_cmos(uint8_t addr, uint8_t data) {
    tb.mgmt_write = 1;
    tb.mgmt_address = 0xF400 + addr;
    tb.mgmt_writedata = data;
    step(); step();
    tb.mgmt_write = 0;
}

void init_cmos() {
    if (!tb.clk_sys) step();      // make sure clk=0

    int XMS_KB = 1024;     // 2MB of total memory
    set_cmos(0x30, XMS_KB & 0xff);
    set_cmos(0x31, (XMS_KB >> 8) & 0xff);

    set_cmos(0x14, 0x01);  // EQUIP byte: diskette exists
    set_cmos(0x10, 0x20);  // 1.2MB 5.25 drive

    set_cmos(0x09, 0x24);  // year in BCD
    set_cmos(0x08, 0x01);  // month
    set_cmos(0x07, 0x01);  // day of month
    set_cmos(0x32, 0x20);  // century

    step(); step();
}

bool cpu_io_write_do_r = 0;
bool cpu_io_read_do_r = 0;
uint16_t int10h_ip_r = 0;
uint8_t crtc_reg = 0;
bool blank_n_r = 0;

void print_ide_trace() {
    // print IDE I/O writes and reads
    if (trace_ide && tb.system->cpu_io_write_do && !cpu_io_write_do_r && 
        (tb.system->cpu_io_write_address >= 0x1f0 && tb.system->cpu_io_write_address <= 0x1f7 ||
         tb.system->cpu_io_write_address >= 0x170 && tb.system->cpu_io_write_address <= 0x177)) {
        printf("%8lld: IDE [%04x]=%02x, EIP=%08x\n", sim_time, tb.system->cpu_io_write_address, tb.system->cpu_io_write_data & 0xff,
                tb.system->ao486->eip);
    }
    // if (trace_ide && tb.system->cpu_io_read_do && !cpu_io_read_do_r && 
    //     (tb.system->cpu_io_read_address >= 0x1f0 && tb.system->cpu_io_read_address <= 0x1f7 ||
    //      tb.system->cpu_io_read_address >= 0x170 && tb.system->cpu_io_read_address <= 0x177)) {
    //     printf("%8lld: IDE read %04x, EIP=%08x\n", sim_time, tb.system->cpu_io_read_address,
    //             tb.system->ao486->eip);
    // }
}

void print_vga_trace() {
    // print video I/O writes
    if (trace_vga && tb.system->cpu_io_write_do && !cpu_io_write_do_r && 
        // tb.system->cpu_io_write_address >= 0x3b0 && tb.system->cpu_io_write_address <= 0x3df) {
        (tb.system->cpu_io_write_address == 0x3c9 || tb.system->cpu_io_write_address == 0x3c8)) {
        printf("%8lld: VIDEO [%04x]=%02x, EIP=%08x\n", sim_time, tb.system->cpu_io_write_address, tb.system->cpu_io_write_data & 0xff,
                tb.system->ao486->eip);
    }
    // print CRTC reg writes
    uint32_t eax = tb.system->ao486->pipeline_inst->eax;
    if (trace_vga && tb.system->cpu_io_write_do && !cpu_io_write_do_r && tb.system->cpu_io_write_address == 0x3d4 ) {
        crtc_reg = tb.system->cpu_io_write_data & 0xff;
        if ((tb.system->cpu_io_write_data & 0xff) == 6 || (tb.system->cpu_io_write_data & 0xff) == 7) {
            printf("%8lld: CRTC [%04x]=%02x, EIP=%08x, EAX=%08x\n", sim_time, tb.system->cpu_io_write_address, tb.system->cpu_io_write_data & 0xff, tb.system->ao486->eip, eax);    
        }
    }
    if (trace_vga && tb.system->cpu_io_write_do && !cpu_io_write_do_r && tb.system->cpu_io_write_address == 0x3d5 &&
        (crtc_reg == 6 || crtc_reg == 7)) {
        printf("%8lld: CRTC [%04x]=%02x, EIP=%08x, EAX=%08x\n", sim_time, tb.system->cpu_io_write_address, tb.system->cpu_io_write_data & 0xff, 
                tb.system->ao486->eip, eax);
    }

    // print int 10h calls
    // if (trace_vga && tb.system->ao486->pipeline_inst->ex_opcode == 0xCD && tb.system->ao486->pipeline_inst->ex_imm == 0x10 &&
    //     tb.system->ao486->pipeline_inst->ex_valid && tb.system->ao486->pipeline_inst->ex_ready &&
    //     tb.system->ao486->pipeline_inst->ex_ip_after != int10h_ip_r) {
    //     int10h_ip_r = tb.system->ao486->pipeline_inst->
    //     printf("%8lld: INT 10h, EIP=%08x\n", sim_time, tb.system->ao486->eip);
    // }
    // if (tb.system->u_z86->ex_ip_after != int10h_ip_r) {
    //     int10h_ip_r = 0;   // clear int10 IP when CPU moves on to new instruction
    // }
}

uint8_t read_byte(uint32_t addr) {
    uint8_t r = (tb.system->sdram->mem[addr >> 2] >> (8*(addr & 3))) & 0xff;
    // printf("read_byte(%08x)=%02x, mem[%08x] = %08x\n", addr, r, addr >> 2, tb.system->sdram->mem[addr >> 2]);
    return r;
}

uint16_t read_word(uint32_t addr) {
    return  read_byte(addr) + 
            ((uint16_t)read_byte(addr+1) << 8);
}

uint32_t read_dword(uint32_t addr) {
    return  read_byte(addr) + 
            ((uint32_t)read_byte(addr+1) << 8) + 
            ((uint32_t)read_byte(addr+2) << 16) + 
            ((uint32_t)read_byte(addr+3) << 24);
}

string read_string(uint32_t addr) {
    string r;
    for (;;) {
        char c = read_byte(addr++);
        if (!c) return r;
        r += c;
    }
}

// sp points to 1st argument after format string
void bios_printf(const string fmt, uint32_t sp, uint32_t ds, uint32_t ss) {
    for (int i = 0; i < fmt.size(); i++) {
        uint16_t arg;
        uint16_t argu;
        string str;
        char c = fmt[i];
        if (c == '%' && i+1 < fmt.size()) {
            int j = i + 1;
            // Parse width and zero-padding, e.g. %02x, %04x
            char fmtbuf[16] = "%";
            int fmtlen = 1;
            // Parse flags (only '0' supported)
            bool has_zero = false;
            if (fmt[j] == '0') {
                has_zero = true;
                fmtbuf[fmtlen++] = '0';
                j++;
            }
            // Parse width (1 or 2 digits)
            int width = 0;
            while (j < fmt.size() && isdigit(fmt[j])) {
                width = width * 10 + (fmt[j] - '0');
                fmtbuf[fmtlen++] = fmt[j];
                j++;
            }
            // Parse type
            if (j < fmt.size()) {
                char type = fmt[j];
                fmtbuf[fmtlen++] = type;
                fmtbuf[fmtlen] = 0;
                switch (type) {
                    case 's':
                    case 'S':
                        arg = read_word(ss*16+sp);
                        sp+=2;
                        str = read_string(ds*16+arg);
                        printf("%s", str.c_str());
                        break;
                    case 'c':
                        c = read_byte(ss*16+sp);
                        sp++;
                        printf("%c", c);
                        break;
                    case 'x':
                    case 'X':
                    case 'u':
                    case 'd':
                    {
                        argu = read_word(ss*16+sp);
                        sp+=2;
                        // For 'd', cast to int for signed printing
                        if (type == 'd')
                            printf(fmtbuf, argu & 0x8000 ? argu - 0x10000 : argu);
                        else
                            printf(fmtbuf, argu);
                        break;
                    }
                    default:
                        // Print unknown format as literal
                        printf("%%%c", type);
                }
                i = j;
            } else {
                // Malformed format, print as literal
                printf("%%");
            }
        } else
            printf("%c", c);
    }
}

void usage() {
    printf("\nUsage: Vsystem [--trace] [-s T0] [-e T1] <boot0.rom> <boot1.rom> <disk.vhd>\n");
    printf("  -s T0     start tracing at time T0\n");
    printf("  -e T1     stop simulation at time T1\n");
    printf("  --trace   start trace immediately\n");
    printf("  --vga     print VGA related operations\n");
    printf("  --ide     print ATA/IDE related operations\n");
    printf("  --post    print POST codes\n");
    printf("  --mem <addr> watch memory location\n");
}

void load_disk();
void persist_disk();

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    if (argc < 3+1) {
        usage();
        return 1;
    }

    int off = 1;
    std::string bios_name;
    std::string video_bios_name;
    for (int i = 1; i < argc; i++) {
        string arg(argv[i]);
        if (arg == "-s") {
            start_time = atoi(argv[++i]);
        } else if (arg == "-e") {
            stop_time = atoi(argv[++i]);
        } else if (arg == "--trace") {
            set_trace(true);
        } else if (arg == "--vga") {
            trace_vga = true;
        } else if (arg == "--post") {
            trace_post = true;
        } else if (arg == "--ide") {
            trace_ide = true;
        } else if (arg == "--mem") {
            // Support decimal or hex (0x...) addresses
            watch_memory.insert(strtol(argv[++i], nullptr, 0) >> 2);
        } else if (arg[0] == '-') {
            printf("Unknown option: %s\n", argv[i]);
            return 1;
        } else {
            if (i+3 > argc) {
                usage();
                return 1;
            }
            bios_name = argv[i];
            video_bios_name = argv[++i];
            disk_file = argv[++i];
            break;
        }
    }

	if (SDL_Init(SDL_INIT_VIDEO) < 0)
	{
		printf("SDL init failed.\n");
		return 1;
	}

	SDL_Window *sdl_window = NULL;
	SDL_Renderer *sdl_renderer = NULL;
	SDL_Texture *sdl_texture = NULL;

	sdl_window = SDL_CreateWindow("z86 sim", SDL_WINDOWPOS_CENTERED,
								  SDL_WINDOWPOS_CENTERED, 800, 600, SDL_WINDOW_SHOWN);
	if (!sdl_window)
	{
		printf("Window creation failed: %s\n", SDL_GetError());
		return 1;
	}
	sdl_renderer = SDL_CreateRenderer(sdl_window, -1,
									  SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
	if (!sdl_renderer)
	{
		printf("Renderer creation failed: %s\n", SDL_GetError());
		return 1;
	}

	sdl_texture = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_RGBA8888,
									SDL_TEXTUREACCESS_TARGET, H_RES, V_RES);
	if (!sdl_texture)
	{
		printf("Texture creation failed: %s\n", SDL_GetError());
		return 1;
	}

	SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, H_RES * sizeof(Pixel));
	SDL_RenderClear(sdl_renderer);
	SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL);
	SDL_RenderPresent(sdl_renderer);
	SDL_StopTextInput(); // for SDL_KEYDOWN

    printf("Starting simulation\n");

    tb.clock_rate = 40000000;            // for time keeping of timer, RTC and floppy
    tb.clock_rate_vga = 57000000;        // at least 2x VGA pixel clock (25.2Mhz and 28.3Mhz)
    if (!tb.clk_sys) step();             // make sure clk_sys is 1
    // reset whole system
    tb.reset = 1;
    // tb.cpu_reset = 1;
    step(); step();
    // release system reset
    step(); step();
    // load BIOS into F0000-FFFFF
    std::ifstream bios_file(bios_name, std::ios::binary);
    std::vector<uint8_t> bios(std::istreambuf_iterator<char>(bios_file), {});
    bios_file.close();
    if (bios.size() != 0x10000) {
        printf("Cannot open BIOS file %s, or wrong size(%zu), expected 64K\n", bios_name.c_str(), bios.size());
        return 1;
    }
    load_program(0xF0000, bios);
    // Load video BIOS into C0000-C7FFF
    std::ifstream video_bios_file(video_bios_name, std::ios::binary);
    std::vector<uint8_t> video_bios(std::istreambuf_iterator<char>(video_bios_file), {});
    video_bios_file.close();
    load_program(0xC0000, video_bios);

    // set CMOS_DISKETTE (0x10) to one 1.2MB 5.25 drive.
    // and amount of extended memory
    init_cmos();

    // set HDD geometry and other parameters
    init_ide("dos6.vhd");

    // load disk image into drive_sd_sim.sv
    load_disk();  

    // now start cpu
    tb.reset = 0;
    // tb.cpu_reset = 0;

    bool vsync_r = 0;
    int x = 0;
    int y = 0;
    bool speaker_out_r = 0;
    bool speaker_active = false;

    bool post_need_newline = false;
    int pix_cnt = 0;
	vector<uint8_t> scancode;   // scancode
	uint64_t last_scancode_time;
    SDL_Keycode last_key = 0;

    while (sim_time < stop_time) {
        step();

        // watch memory locations
        if (watch_memory.size() > 0) {
            if (tb.clk_sys && tb.system->mem_write && !mem_write_r && watch_memory.find(tb.system->mem_address) != watch_memory.end()) {
                printf("%8lld: WRITE [%08x]=%08x, BE=%1x, EIP=%08x\n", sim_time, tb.system->mem_address << 2, tb.system->mem_writedata,
                        tb.system->mem_byteenable, tb.system->ao486->eip);
            }
            mem_write_r = tb.system->mem_write;
        }

        if (trace_ide)
            print_ide_trace();

        if (trace_vga)
            print_vga_trace();

        // detect speaker output
        if (tb.speaker_out != speaker_out_r) {
            speaker_active = true;
        }
        speaker_out_r = tb.speaker_out;

        cpu_io_write_do_r = tb.system->cpu_io_write_do;

        // Trace int 10h (Eh) to print character
        if (tb.system->ao486->eip == 0xA58 && eip_r != 0xA58 && tb.system->ao486->pipeline_inst->cs == 0xC000) {
            uint32_t eax = tb.system->ao486->pipeline_inst->eax;
            if ((eax >> 8 & 0xFF) == 0xE) {
                if (sim_time - last_time > 1e5) {
                    printf("%8lld: PRINT: ", sim_time);
                }
                printf("\033[32m%c\033[0m", eax & 0xFF);
                last_time = sim_time;
            }
        }
        // Trace bios_printf debug messages in BIOS (boot0.rom)
        if (tb.system->ao486->eip == 0x0907 && eip_r != 0x0907 && tb.system->ao486->pipeline_inst->cs == 0xF000) {
            uint32_t esp  = tb.system->ao486->pipeline_inst->esp;
            uint32_t ss = tb.system->ao486->pipeline_inst->ss;
            uint16_t caller = read_word(ss*16+esp);
            uint16_t action = read_word(ss*16+esp+2);
            uint16_t arg_fmt = read_word(ss*16+esp+4);
            uint16_t cs = tb.system->ao486->pipeline_inst->cs;   // bios_printf uses CS:arg_fmt as format string
            string fmt_str = read_string(arg_fmt+cs*16);

            // printf("%8lld: printf: SP=%04x, SS=%04x, action=%04x, arg_fmt=%04x, cs=%04x\n", sim_time, esp, ss, action, arg_fmt, cs);
            if ((action&2) == 0) {  // do not capture SCREEN output, as it will be captured by int10h 
                if (sim_time - last_time > 1e5) {
                    const char *t = "PRINT";
                    if (action & 4) t = "INFO";
                    if (action & 8) t = "DEBUG";
                    if (action & 1) t = "HALT";
                    if (action & 2) t = "SCREEN";
                    printf("%8lld: %s from %04x:%04x, SP=%04x, SS=%04x, action=%04x, arg_fmt=%04x\n", sim_time, t, cs, caller, esp, ss, action, arg_fmt);
                }
                if (action & 4 || action & 8)
                    printf("\033[33m");
                else if (action & 1)
                    printf("\033[31m");
                else if (action & 2)
                    printf("\033[32m");
                bios_printf(fmt_str, esp+6, cs, ss);
                printf("\033[0m");
                last_time = sim_time;
            }
        }
        // Trace int 13h disk accesses
        if (tb.system->ao486->eip == 0x85d3 && eip_r != 0x85d3 && tb.system->ao486->pipeline_inst->cs == 0xF000) {
            uint32_t eax = tb.system->ao486->pipeline_inst->eax;
            uint32_t ecx = tb.system->ao486->pipeline_inst->ecx;
            uint32_t edx = tb.system->ao486->pipeline_inst->edx;
            int cylinder = (ecx >> 8 & 0xFF) + ((ecx & 0xC0) << 2);
            int head = edx >> 8 & 0xFF;
            int sector = ecx & 0x3F;
            int count = eax & 0xFF;
            printf("%8lld: INT 13h: AX=%04x, CX=%04x, DX=%04x", sim_time, eax & 0xFFFF, ecx & 0xFFFF, edx & 0xFFFF);
            printf(", C/H/S = %d/%d/%d, count=%d\n", cylinder, head, sector, count);
        }
        eip_r = tb.system->ao486->eip;

        // Capture video frame
        if (tb.clk_sys && tb.video_ce) {
            if (tb.video_vsync && !vsync_r) {
                x = 0; y = 0;
                x_cnt++; y_cnt++;
                printf("%8lld: VSYNC: pix_cnt=%d, width=%d, height=%d, speaker=%s, CS:IP=%04x:%04x\n", sim_time, pix_cnt, x_cnt, y_cnt, speaker_active ? "ON" : "OFF", 
                        tb.system->ao486->pipeline_inst->cs, tb.system->ao486->eip);

                // detect video resolution change
                const vector<pair<int,int>> resolutions = 
                    {{720,400}, {360,400}, {640,344},                                    // text modes
                     {640,480}, {640,400}, {640,200}, {640,350}, {320,200}, {320,240}};  // graphics modes
                if ((x_cnt != resolution_x || y_cnt != resolution_y) && 
                       find(resolutions.begin(), resolutions.end(), pair<int,int>{x_cnt, y_cnt}) != resolutions.end()) {
                    printf("New video resolution: %d x %d\n", x_cnt, y_cnt);
                    resolution_x = x_cnt;
                    resolution_y = y_cnt;
                }

                pix_cnt = 0; x_cnt = 0; y_cnt = 0;
                speaker_active = false;
                
                // FPS calculation using wall clock time
                if (fps_frame_count == 0) {
                    fps_start_time = SDL_GetTicks();
                }
                fps_frame_count++;
                
                // Display FPS every 10 frames
                if (fps_frame_count % 10 == 0) {
                    uint32_t current_time = SDL_GetTicks();
                    uint32_t elapsed_ms = current_time - fps_start_time;
                    double fps = (double)fps_frame_count / (elapsed_ms / 1000.0);
                    printf("%8lld: FPS: %.2f (frames=%d, time=%.3fs)\n", sim_time, fps, fps_frame_count, elapsed_ms / 1000.0);
                }
                
                // update texture once per frame (in blanking)
                SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, H_RES * sizeof(Pixel));
                SDL_RenderClear(sdl_renderer);
                const SDL_Rect srcRect = {0, 0, resolution_x, resolution_y};
                SDL_RenderCopy(sdl_renderer, sdl_texture, &srcRect, NULL);
                SDL_RenderPresent(sdl_renderer);
                frame_count++;
                SDL_SetWindowTitle(sdl_window, ("ao486 sim - frame " + to_string(frame_count) + (trace_toggle ? " tracing" : "") + (speaker_active ? " speaker" : "")).c_str());
            } else if (!tb.video_blank_n) {
                x=0;
                if (blank_n_r) y++;
            } else {
                if (y < V_RES && x < H_RES) {
                    Pixel *p = &screenbuffer[y * H_RES + x];
                    p->a = 0xff;
                    p->r = tb.video_r;
                    p->g = tb.video_g;
                    p->b = tb.video_b;
                    if (p->r || p->g || p->b) {
                        // printf("Pixel at %d,%d\n", x, y);
                        pix_cnt++;
                    }
                    x_cnt = max(x_cnt, x);
                    y_cnt = max(y_cnt, y);
                }
                x++;
            }
            blank_n_r = tb.video_blank_n;
            vsync_r = tb.video_vsync;
        }

        // start / stop tracing
        if (sim_time == start_time) {
            set_trace(true);
        }
        if (sim_time == stop_time) {
            set_trace(false);
        }

        // process SDL events
        if (sim_time % 100 == 0) {
            SDL_Event e;
            if (SDL_PollEvent(&e)) {
                if (e.type == SDL_QUIT) {
                    break;
                }
                if (e.type == SDL_WINDOWEVENT) {
                    if (e.window.event == SDL_WINDOWEVENT_CLOSE) {
                        if (e.window.windowID == SDL_GetWindowID(sdl_window))
                            break;
                    }
                }
				if (e.type == SDL_KEYDOWN && e.key.keysym.sym != last_key) {
                    if (e.key.keysym.mod & KMOD_LGUI) {
                        if (e.key.keysym.sym == SDLK_t) {
    	    				// press WIN-T to toggle trace
                            set_trace(!trace_toggle);
                        } else if (e.key.keysym.sym == SDLK_s) {
                            // press WIN-S to backup disk content
                            persist_disk();
                        }
                    } else {
                        last_key = e.key.keysym.sym;
                        printf("Key pressed: %d\n", e.key.keysym.sym);
                        if (ps2scancodes.find(e.key.keysym.sym) != ps2scancodes.end()) {
                            scancode.insert(scancode.end(), ps2scancodes[e.key.keysym.sym].first.begin(), ps2scancodes[e.key.keysym.sym].first.end());
                        }
                    }
                }
				if (e.type == SDL_KEYUP) {
                    if (e.key.keysym.mod & KMOD_LGUI) {
                        // nothing
                    } else {
                        last_key = 0;
                        printf("Key up: %d\n", e.key.keysym.sym);
	    				if (ps2scancodes.find(e.key.keysym.sym) != ps2scancodes.end()) {
		    				scancode.insert(scancode.end(), ps2scancodes[e.key.keysym.sym].second.begin(), ps2scancodes[e.key.keysym.sym].second.end());
			    		}
                    }
                }
            }
        }

		// send scancode to ps2_device, one scancode takes about 1ms (we'll wait 2ms)
        if (tb.clk_sys) {
            if (sim_time - last_scancode_time > 1e5  && !scancode.empty()) {
                printf("%8lld: Sending scancode %d\n", sim_time, scancode.front());
                last_scancode_time = sim_time;
                tb.kbd_data = scancode.front();
                tb.kbd_data_valid = 1;
                scancode.erase(scancode.begin());
            } else {
                tb.kbd_data_valid = 0;
            }

            if (tb.kbd_host_data & 0x100) {
                uint8_t cmd = tb.kbd_host_data & 0xff;
                printf("%8lld: Received keyboard command %d\n", sim_time, cmd);
                tb.kbd_host_data_clear = 1;
                if (cmd == 0xFF) {
                    printf("%8lld: Keyboard reset\n", sim_time);
                    scancode.push_back(0xFA);
                    scancode.push_back(0xAA);
                    last_scancode_time = sim_time;    // 0xFA is sent 1ms later
                } else if (cmd >= 0xF0) {
                    // respond to all commands with an ACK
                    scancode.push_back(0xFA);
                    last_scancode_time = sim_time;    // 0xFA is sent 1ms later
                }
            } else if (tb.kbd_host_data_clear) {
                tb.kbd_host_data_clear = 0;
            }

        }
    }
    printf("Simulation stopped at time %lld\n", sim_time);

    // Cleanup
    if (trace) {
        trace->close();
        delete trace;
    }
    return 0;
}

void set_trace(bool toggle) {
    printf("Tracing %s\n", toggle ? "on" : "off");
    if (toggle) {
        if (!trace) {
            trace = new VerilatedFstC;
            tb.trace(trace, 5);
            Verilated::traceEverOn(true);
            // printf("Tracing to waveform.fst\n");
            trace->open("waveform.fst");    
        }
    }
    trace_toggle = toggle;
}

int disk_size;
// Prototypes generated by Verilator from the exports
extern "C" {
    void sd_write(unsigned addr, const uint8_t data);
}


static svScope sd_scope = nullptr;

// DPI-C call from verilog to load disk image
void load_disk() {
    const char *fname = disk_file.c_str();
    unsigned blk_sz = 1024;
    struct stat st;
    printf("Loading disk image from %s.\n", fname);
    sd_scope = svGetScopeFromName("TOP.system.driver_sd");
    if (!sd_scope) {
        fprintf(stderr,
                "ERROR: scope TOP.tb.driver_sd_sim not found\n");
        exit(1);
    }    
    svSetScope(sd_scope);

    if (stat(fname, &st) != 0) { perror(fname); return; }
    disk_size = st.st_size;

    FILE* f = fopen(fname, "rb");
    if (!f) { perror(fname); return; }

    std::vector<uint8_t> buf(blk_sz);
    unsigned addr = 0;
    while (addr < disk_size) {
        size_t n = fread(buf.data(), 1,
                         std::min<unsigned>(blk_sz, disk_size - addr), f);
        if (!n) break;
        for (int i = 0; i < n; i++) {
            sd_write(addr + i, buf[i]);
        }
        addr += n;
    }
    fclose(f);
    printf("Disk image loaded.\n");
}

void persist_disk() {
    uint8_t buf[1024];
    printf("Persisting disk image to %s.\n", disk_file.c_str());
    svSetScope(sd_scope);

    if (rename(disk_file.c_str(), (disk_file + ".bak").c_str()) != 0) {
        printf("Failed to rename existing disk image to %s.bak\n", disk_file.c_str());
        return;
    }
    printf("Existing disk image renamed to %s.bak\n", disk_file.c_str());

    // write new disk image
    FILE* f = fopen(disk_file.c_str(), "wb");
    if (!f) {
        printf("Failed to open disk image for writing\n");
        return;
    }
    for (int i = 0; i < disk_size; i += 1024) {
        int n = std::min(1024, disk_size - i);
        for (int j = 0; j < n; j++) {
            buf[j] = tb.system->driver_sd->sd_buf[i+j];
        }
        if (fwrite(buf, 1, n, f) != (size_t)n) {
            printf("Failed to write disk image\n");
            fclose(f);
            return;
        }
    }
    fclose(f);
    printf("Disk image persisted to %s\n", disk_file.c_str());
}