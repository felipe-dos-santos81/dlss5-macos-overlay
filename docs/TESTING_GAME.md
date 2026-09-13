# Testing with a game

Open `Launch.command` or `dist/DLSS_5_APPLE_SILICON.app`.
The NR.dlss model is included in the application and loads automatically.
Python installation is not required to run it.

1. Launch your game in windowed or borderless mode. Start with a scene containing
   a face and visible lighting, then test camera motion.
2. Select **Realtime** and wait for **NR.dlss · Ready** in the top bar.
3. Click **Refresh Screens and Windows**. If prompted, allow Screen Recording
   for **DLSS 5 — Apple Silicon** in macOS Settings and restart if needed.
   Microphone permission is not required.
4. Under **Source**, select the game window. CrossOver games may appear under a
   Wine or executable name. If the window is missing, select its display.
5. Start with **Natural**, **512 px**, capture at **30 FPS**, **Intensity: 1.00**
   and **Motion Awareness** enabled.
6. Click **Start**. The first frame can take several seconds. Check the preview.
   **Overlay On / Off is initially disabled.**
7. Enable **Overlay On / Off**, then switch to the game. The overlay passes mouse
   clicks through and does not take keyboard focus. The controls stop floating
   above the game when they lose focus.
8. Set **Before / After** to **0.50**: original on the left, processed on the right.
   Return it to **0.00** to show the full processed image.

## Controls during gameplay

- **⌥⌘1** immediately shows or hides the overlay, including on static scenes.
- **⌥⌘0** stops capture and processing and hides the overlay.
- **DLSS → Show Controls** in the menu bar returns to the settings.
- Turning off **Overlay On / Off** hides only the overlay. Preview and neural
  processing continue. Click **Stop** to release processing load.

If processing affects game smoothness, try **384 px**. With spare GPU capacity,
compare **640 px** or **768 px**. Disabling **Motion Awareness** removes optical-flow
work but may make the effect less stable. The panel's FPS counter measures
processed frames, not the game's frame rate.

Use **Screenshot** to save PNG or **Record Video** to save MP4. **System Audio**
enables the AAC track. Changing captured source dimensions stops the recording
with a message; start a new file for the new size.

If the overlay interferes with viewing menus or the cursor, hide it with ⌥⌘1
or stop with ⌥⌘0. Windowed/borderless mode is preferred for the first test.
Special fullscreen Spaces and protected surfaces are not verified for individual games.

Real inference, ScreenCaptureKit frames, Metal composition, PNG and MP4/H.264/AAC
have been checked. Specific games still require testing; 60 FPS and artifact-free
results in all games are not guaranteed.

## Screen Recording permission

If Refresh reports "The user declined TCCs" even though the permission switch is
on, fully quit the app with Command-Q and reopen the same app bundle. A running
process may still have the old permission state.

Development builds previously used an ad-hoc signature tied to the executable's
hash. Rebuilding could leave a visible permission entry that no longer matched
the app. The build now prefers an installed development certificate; keep the
same signing identity and bundle identifier across rebuilds.

If restarting does not help, quit the app and reset only its screen permission:

```sh
tccutil reset ScreenCapture local.dlss5.mlx.apple-silicon
./Launch.command
```

Click **Refresh Screens and Windows**, approve the system prompt, and enable the
app in **System Settings → Privacy & Security → Screen & System Audio Recording**
if requested. Quit and reopen once more if macOS asks. Do not run a global TCC
reset: other applications do not need their permissions changed.

This follows Apple's [permission reset instructions](https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos).
