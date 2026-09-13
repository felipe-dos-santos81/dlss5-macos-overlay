# Process a video file

1. Open **DLSS 5 — Apple Silicon** and select the **Upload Video** tab.
2. Wait for **NR.dlss · Ready** in the top bar. The same built-in model loads
   automatically for both workspaces; there is nothing to select.
3. Click **Choose Video…** and select an SDR clip supported by macOS, such as an
   H.264/HEVC MP4 or MOV. You can play the original in the preview.
4. Start with **Natural**, **512 px**, **Intensity: 1.00** and **Motion Awareness**.
   Set **Before / After: 0.00** for the full effect. A value of 0.50 includes the
   comparison split in the exported file: original left, processed right.
5. Enable **Keep Original Audio** if wanted. Click **Export Video…** and choose
   a destination. The default filename ends in `-DLSS5.mp4`.
6. Watch the progress, frame count and estimated remaining time. After export,
   switch between **Original** and **Result** to play the clips. **Show in Finder**
   locates the finished MP4.

The processing size controls the neural network's working resolution, not the
exported frame size. Video output keeps the source dimensions and frame timing.
Every decoded frame is processed, even if the job is slower than playback.
Portrait rotation is applied to the pixels. Source audio tracks are mixed and
encoded as one stereo AAC track; audio from other apps is never captured.

**Cancel Export** or **⌥⌘0** stops the job after current GPU work settles.
The source is never overwritten, and an existing output is kept until the new
export succeeds. You can start another export after cancellation.

Realtime processing and file export use the same GPU engine, so finish or stop the
current job before switching tabs. Upload Video settings are independent from Realtime.
The first frame can take several seconds for kernel compilation. Processing
FPS and remaining time are estimates, not the output video's playback rate.

Currently supported: macOS-decodable SDR video with even frame dimensions,
MP4/H.264 output and optional stereo AAC audio. HDR, captions, chapters and
additional video tracks are not exported. Source audio is re-encoded, not copied
bit-for-bit. The app reports unsupported inputs before starting the neural work.

## Command-line use

```sh
dist/DLSS_5_APPLE_SILICON.app/Contents/MacOS/DLSS_5_APPLE_SILICON \
  --process-video /path/to/input.mp4 \
  --video-output /path/to/output-DLSS5.mp4 \
  --width 512
```

Add `--no-audio` for a silent export. The output must be a different local MP4
file. An existing output at that path is replaced only on success.
