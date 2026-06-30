# Kairos: 32-Core Programmable SIMD GPU

This repository contains the hardware-software co-design of a custom 32-core Single Instruction, Multiple Data (SIMD) General-Purpose Graphics Processing Unit (GPGPU) implemented on the Xilinx ZC706 Evaluation Board.

The architecture features a custom 32-bit Instruction Set Architecture (ISA), a 3072-bit L1 fabric register cache, hardware double-buffering, and a decoupled 48kHz audio/720p video pipeline orchestrated by the ARM Cortex-A9 Processing System (PS).

https://github.com/user-attachments/assets/b7488102-da05-4da7-b471-b0032c6120ac


## Repository Structure
```
.
├── assembler/      # Python script for translating custom ISA to machine code
├── bd/             # Tcl scripts to automatically regenerate the Zynq Block Design
├── bits/           # Pre-generated bitstream for quick deployment
├── block_design/   # Document showing Block diagram interconnections
├── constraints/    # Physical XDC constraints for the ZC706 board
├── data/           # Assembly source files (.asm) and compiled memory files (.mem)
├── demo/           # Demonstration video
├── docs/           # Technical documentation of the project
├── hdl/            # Custom SystemVerilog datapath, controller, and memory modules
├── scripts/        # Master build automation scripts (build.tcl)
├── sim/            # Behavioral simulation testbenches
└── sw/             # Bare-metal C code for the ARM PS and A/V synchronization
```
## Prerequisites
* Hardware: Xilinx ZC706 Evaluation Board, SD Card (FAT32)
* Software: Xilinx Vivado 2018.2 (Required for block diagram compatibility, minimal tweaking required for other versions) & Xilinx SDK, FFmpeg

---

## 1. Hardware Setup
This project uses a script-based version control flow.
In case you are using any version except 2018.2, the script will not work out of the box. You would have to see the block diagram in the block_design/ and make it manually via Vivado block designer.

1. Open Vivado 2018.2.
2. At the bottom of the welcome screen, open the Tcl Console.
3. Navigate to this cloned repository and source the master build script:
   cd C:/path/to/repo
   source scripts/build.tcl
4. Vivado will construct the workspace, import all HDL, constraints & memory files, and rebuild the block diagram hierarchy.
5. Once complete, click Generate Bitstream in the Vivado GUI.

---
## 2. Media Preparation
Because this GPU utilizes raw Direct Memory Access (DMA) without an operating system, it cannot decode standard `.mp4` or `.mkv` files. Thus, you have to use `ffmpeg` to extract the raw, headerless video and audio streams into `.BIN` files before placing them on the SD card.

Assuming input file is named `input.mp4`:

### 2.1 Generate VIDEO.BIN
The VDMA expects a continuous stream of raw 24-bit color pixels at 1280x720 resolution and exactly 25 FPS. 
Run the following command to extract the raw RGB stream:

ffmpeg -i input.mp4 -f rawvideo -pix_fmt rgb24 -s 1280x720 -r 25 VIDEO.BIN

*(Note: Depending on the specific color mapping of the ADV7511, the C-code `load_video_from_sd` function includes a software loop to automatically swap the Red and Blue bytes (RGB to BGR) during the SD card read process).*

### 2.2 Generate AUDIO.BIN
The custom `spdif_tx` hardware module is hardcoded (via the ADV7511 N-value of 6144) to accept exactly 48 kHz, 16-bit Stereo PCM audio.
Run the following command to extract the raw audio stream:

ffmpeg -i input.mp4 -f s16le -acodec pcm_s16le -ar 48000 -ac 2 AUDIO.BIN

Place both `VIDEO.BIN` and `AUDIO.BIN` on the root of your FAT32 formatted SD card.

## 3. Software Setup (Xilinx SDK)
The ARM Cortex-A9 manages the SD Card file system, AXI DMA transfers, and A/V synchronization. Once your bitstream is generated, compile the software:

1. In Vivado, go to File > Export > Export Hardware. Ensure the "Include Bitstream" checkbox is selected.
2. Launch the SDK via File > Launch SDK.
3. In the Xilinx SDK, create a new application: File > New > Application Project.
   * Target OS: standalone
   * Language: C
   * Select the Empty Application template.
4. Copy all .c and .h files from this repository's sw/ folder directly into your new SDK project's src/ directory.
5. Media Setup: Place your raw AUDIO.BIN and VIDEO.BIN files onto the root directory of a FAT32-formatted SD Card. Insert the SD Card into the ZC706.
6. Build the SDK project (Ctrl+B).
7. Right-click your project -> Run As > Launch on Hardware (System Debugger).

---

## 4. Compiling Assembly Code
This GPU executes a custom 32-bit ISA. To run custom algorithms (like the Mandelbrot set), you must compile your .asm code into .mem files for the Vivado Instruction BRAM.

1. Write your custom program and save it in the data/ directory (e.g., data/mandelbrot.asm).
2. Run the assembler script:
   python assembler/assembler.py data/mandelbrot.asm data/mandelbrot.mem
3. The scripts/build.tcl script will automatically load all generated .mem files into the BRAM during the Vivado hardware build.

---

## 5. Running Simulations
To verify Q8.24 fixed-point math or SIMD pipeline behavior without waiting for hardware synthesis, behavioral simulation testbenches are provided.

1. Generate the Vivado project using scripts/build.tcl.
2. In the Vivado GUI Flow Navigator, click Run Simulation > Run Behavioral Simulation.
3. Use the Waveform Viewer to monitor the 3072-bit internal memory bus and the 3-cycle MAC write buffers.

