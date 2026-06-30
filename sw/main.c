/*
 * main.c
 *
 *  Created on: May 6, 2026
 *      Author: Shawaiz Haider
 */

#include "xparameters.h"
#include "xil_printf.h"
#include "xaxivdma.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "sleep.h"
#include "ff.h"
#include <string.h>

// ═══════════════════════════════════════════════════════════════════════════
// Constants & Memory Map
// ═══════════════════════════════════════════════════════════════════════════
#define VDMA_ID           XPAR_AXIVDMA_0_DEVICE_ID
#define AUDIO_DMA_ID      XPAR_AXIDMA_0_DEVICE_ID

#define FRAME_WIDTH       1280u
#define FRAME_HEIGHT      720u
#define PIXEL_BYTES       3u
#define FRAME_STRIDE      (FRAME_WIDTH  * PIXEL_BYTES)
#define FRAME_SIZE        (FRAME_STRIDE * FRAME_HEIGHT)

#define VIDEO_FPS         25u

#define DISPLAY_BUF_A     0x01000000u
#define AUDIO_BUFFER      0x03000000u
#define STORAGE_BUFFER    0x04000000u

#define SD_READ_CHUNK     (FRAME_SIZE * 5u)

XAxiVdma Vdma;
XAxiDma  AudioDma;
FATFS FatFs;

u32 audio_file_size = 0u;

// ═══════════════════════════════════════════════════════════════════════════
// Init Functions
// ═══════════════════════════════════════════════════════════════════════════
static int init_vdma(void) {
    XAxiVdma_Config *Cfg = XAxiVdma_LookupConfig(VDMA_ID);
    if (!Cfg) return XST_FAILURE;
    if (XAxiVdma_CfgInitialize(&Vdma, Cfg, Cfg->BaseAddress) != XST_SUCCESS) return XST_FAILURE;

    XAxiVdma_Reset(&Vdma, XAXIVDMA_READ);
    int polls = 200000;
    while (polls-- && XAxiVdma_ResetNotDone(&Vdma, XAXIVDMA_READ));

    XAxiVdma_DmaSetup R;
    memset(&R, 0, sizeof(R));
    R.VertSizeInput      = FRAME_HEIGHT;
    R.HoriSizeInput      = FRAME_STRIDE;
    R.Stride             = FRAME_STRIDE;
    R.FrameDelay         = 0;
    R.EnableCircularBuf  = 1;
    R.EnableSync         = 0;
    R.PointNum           = 0;
    R.EnableFrameCounter = 0;
    R.FixedFrameStoreAddr = 0;

    if (XAxiVdma_DmaConfig(&Vdma, XAXIVDMA_READ, &R) != XST_SUCCESS) return XST_FAILURE;

    UINTPTR Addr[1] = {(UINTPTR)DISPLAY_BUF_A};
    if (XAxiVdma_DmaSetBufferAddr(&Vdma, XAXIVDMA_READ, Addr) != XST_SUCCESS) return XST_FAILURE;
    if (XAxiVdma_DmaStart(&Vdma, XAXIVDMA_READ) != XST_SUCCESS) return XST_FAILURE;

    return XST_SUCCESS;
}

static int init_audio_dma(void) {
    XAxiDma_Config *Cfg = XAxiDma_LookupConfig(AUDIO_DMA_ID);
    if (!Cfg) return XST_FAILURE;
    if (XAxiDma_CfgInitialize(&AudioDma, Cfg) != XST_SUCCESS) return XST_FAILURE;
    XAxiDma_IntrDisable(&AudioDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    return XST_SUCCESS;
}

// ═══════════════════════════════════════════════════════════════════════════
// Media Loaders
// ═══════════════════════════════════════════════════════════════════════════
static int load_audio_from_sd(void) {
    FIL fil; FILINFO finfo; UINT bytes_read;
    if (f_stat("0:/AUDIO.BIN", &finfo) != FR_OK) return XST_FAILURE;
    audio_file_size = (u32)finfo.fsize;
    if (f_open(&fil, "0:/AUDIO.BIN", FA_READ) != FR_OK) return XST_FAILURE;
    if (f_read(&fil, (void*)AUDIO_BUFFER, audio_file_size, &bytes_read) != FR_OK) return XST_FAILURE;
    f_close(&fil);
    Xil_DCacheFlushRange((INTPTR)AUDIO_BUFFER, audio_file_size);
    return XST_SUCCESS;
}

static int load_video_from_sd(u32 *total_frames_out) {
    FIL fil; FILINFO finfo; UINT bytes_read;
    if (f_stat("0:/VIDEO.BIN", &finfo) != FR_OK) return XST_FAILURE;

    u32 nframes = (u32)(finfo.fsize / FRAME_SIZE);
    u32 required = nframes * FRAME_SIZE;
    if (f_open(&fil, "0:/VIDEO.BIN", FA_READ) != FR_OK) return XST_FAILURE;

    u8 *dst = (u8*)STORAGE_BUFFER;
    u32 remaining = required;

    while (remaining > 0u) {
        u32 chunk = (remaining < SD_READ_CHUNK) ? remaining : SD_READ_CHUNK;
        if (f_read(&fil, dst, (UINT)chunk, &bytes_read) != FR_OK) return XST_FAILURE;

        u8 *p = dst, *end = dst + chunk;
        while (p < end) {
            u8 tmp = p[0]; p[0] = p[2]; p[2] = tmp; p += 3;
        }

        Xil_DCacheFlushRange((INTPTR)dst, chunk);
        dst += chunk; remaining -= chunk;
    }
    f_close(&fil);
    *total_frames_out = nframes;
    return XST_SUCCESS;
}

static inline void present_frame(u32 frame_idx) {
    const u8 *src = (const u8*)(STORAGE_BUFFER + frame_idx * FRAME_SIZE);
    u8       *dst = (u8*)DISPLAY_BUF_A;
    memcpy(dst, src, FRAME_SIZE);
    Xil_DCacheFlushRange((INTPTR)dst, FRAME_SIZE);
}

// ═══════════════════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════════════════
int main(void) {
    u32 total_frames = 0u;

    xil_printf("\r\n--- SYSTEM BOOT ---\r\n");
    if (f_mount(&FatFs, "0:/", 1) != FR_OK) { xil_printf("SD Mount FAIL\r\n"); while(1); }

    xil_printf("Loading AUDIO.BIN...\r\n");
    if (load_audio_from_sd() != XST_SUCCESS) { xil_printf("Audio Load FAIL\r\n"); while(1); }

    xil_printf("Loading VIDEO.BIN (This takes 15 seconds)...\r\n");
    if (load_video_from_sd(&total_frames) != XST_SUCCESS) { xil_printf("Video Load FAIL\r\n"); while(1); }

    present_frame(0u);

    // ── HARDWARE INITIALIZATION ──────────────────────────────────────────
    // Because the hardware payload mute prevents clock dropping, you can flip
    // the switch freely at any time. The VDMA can be initialized immediately.
    xil_printf("\r\nInitializing Hardware Pipelines...\r\n");
    if (init_vdma() != XST_SUCCESS) { xil_printf("VDMA FAIL\r\n"); while(1); }
    if (init_audio_dma() != XST_SUCCESS) { xil_printf("Audio DMA FAIL\r\n"); while(1); }

    // ── PRE-FILL TEST ────────────────────────────────────────────────────
    xil_printf("[AUDIO] Pre-filling audio pipeline...\r\n");
    int test_status = XAxiDma_SimpleTransfer(&AudioDma, (UINTPTR)AUDIO_BUFFER, 3840u, XAXIDMA_DMA_TO_DEVICE);

    if (test_status == 0) {
        int wt = 500;
        while (XAxiDma_Busy(&AudioDma, XAXIDMA_DMA_TO_DEVICE) && wt-- > 0) usleep(1000u);
        u32 sr = Xil_In32(XPAR_AXIDMA_0_BASEADDR + 0x04);
        if ((sr >> 1) & 1u) xil_printf("[AUDIO] PASS: DMA idle, FIFO populated.\r\n");
    }

    // ── PLAYBACK LOOP TRACKERS ───────────────────────────────────────────
    static u32 audio_xfer_ok   = 0u;
    static u32 audio_xfer_fail = 0u;
    static u32 audio_busy_skip = 0u;
    static u32 dbg_print_ctr   = 0u;

    u32 audio_chunk_idx = 0u;
    u32 video_frame_idx = 0u;

    u32 time_acc = 0u;
    u32 expected_frame = 0u;

    xil_printf("\r\n[PLAY] Running Audio-Master AV Sync...\r\n");
    xil_printf(">>> YOU MAY FLIP THE VIDEO SWITCH AT ANY TIME <<<\r\n\r\n");

    while (1) {
        // 1. AUDIO FEED (Master Clock)
        // Drains at exactly 48kHz. 3840 bytes = exactly 20ms of audio.
        if (!XAxiDma_Busy(&AudioDma, XAXIDMA_DMA_TO_DEVICE)) {
            u32 audio_offset = audio_chunk_idx * 3840u;

            // Handle track looping seamlessly
            if (audio_offset + 3840u > audio_file_size) {
                audio_chunk_idx = 0u;
                audio_offset    = 0u;
                video_frame_idx = 0u;
                expected_frame  = 0u;
            }

            int ast = XAxiDma_SimpleTransfer(&AudioDma, (UINTPTR)(AUDIO_BUFFER + audio_offset), 3840u, XAXIDMA_DMA_TO_DEVICE);

            if (ast == XST_SUCCESS) {
                audio_xfer_ok++;
                audio_chunk_idx++;

                // 2 Audio Chunks = exactly 1 Video Frame (25 FPS)
                expected_frame = audio_chunk_idx / 2;
            } else {
                audio_xfer_fail++;
            }
        } else {
            audio_busy_skip++;
        }

        // 2. VIDEO PACING (The AXI Shield)
        // time_acc guarantees a minimum 30ms gap between heavy memory reads.
        if (time_acc >= 30u) {

            // Only update the screen if the hardware audio clock indicates it is time.
            if (video_frame_idx < expected_frame) {
                present_frame(video_frame_idx % total_frames);
                video_frame_idx++;

                // Reset the shield
                time_acc = 0u;
            }
        }

        // 3. THROTTLE
        usleep(1000u);
        time_acc++;

        // 4. DIAGNOSTICS
        dbg_print_ctr++;
        if (dbg_print_ctr >= 2000u) {
            dbg_print_ctr = 0u;
            u32 dma_sr = Xil_In32(XPAR_AXIDMA_0_BASEADDR + 0x04);
            xil_printf("[DIAG] OK:%u | FAIL:%u | BUSY:%u | V_FRAME:%u\r\n", audio_xfer_ok, audio_xfer_fail, audio_busy_skip, video_frame_idx);
            xil_printf("[DIAG] DMA_SR=0x%08X | Halted=%u | Idle=%u\r\n\r\n", dma_sr, dma_sr & 1u, (dma_sr >> 1) & 1u);
        }
    }

    return 0;
}