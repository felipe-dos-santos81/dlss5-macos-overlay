# Third-party sources

- NeuralScreen: https://github.com/perseval-BLR/DLSS5-NeuralScreen,
  analyzed at 8098ccf. MIT. Capture/NR/overlay architecture and matched residual
  composition inspired this native macOS adaptation. Original license retained
  in `Resources/NeuralScreen-LICENSE.txt`.
- MLX-DLSS: https://github.com/iamwavecut/MLX-DLSS,
  vendored source revision 0ca2dea (2026-09-11). Apache-2.0; the original LICENSE
  and NOTICE remain in `Vendor/MLX-DLSS`. Neural inference, temporal history and
  motion processing use its Swift library products. No source modifications.
- MLX Swift 0.31.6: https://github.com/ml-explore/mlx-swift, MIT.
  Transitive Swift Numerics and Argument Parser licenses are included in the
  built application. Exact revisions are recorded in Package.resolved.

The MIT license of this project's new code does not relicense vendor weights.
`Models/` and `local-runtime/` are local, ignored data and are not part of the
source distribution. Prepared local builds embed a copy as `Contents/Resources/NR.dlss`;
this does not change the weights' licensing. No NVIDIA runtime executes on this Mac: the DLL is used
only as an input to offline weight extraction. The application runs MLX/Metal.

DLSS is a trademark of NVIDIA. This experimental port is not an NVIDIA or Apple product.
