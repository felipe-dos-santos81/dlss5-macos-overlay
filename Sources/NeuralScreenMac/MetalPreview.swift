import AppKit
import SwiftUI
import MetalKit
import CoreVideo

@MainActor
final class MetalPreviewRenderer: NSObject, MTKViewDelegate {
    let view: MTKView
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache
    private var pixels: CVPixelBuffer?

    override init() {
        let device = MTLCreateSystemDefaultDevice()!
        view = MTKView(frame: .zero, device: device)
        queue = device.makeCommandQueue()!
        let library = try! ShaderLibrary.make(device: device)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "screenVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "screenFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try! device.makeRenderPipelineState(descriptor: descriptor)
        var created: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &created); cache = created!
        super.init()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0.025, 0.03, 0.04, 1)
        view.isPaused = true; view.enableSetNeedsDisplay = true
        view.framebufferOnly = true; view.delegate = self
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    }

    func display(_ pixels: CVPixelBuffer?) { self.pixels = pixels; view.needsDisplay = true }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.needsDisplay = true }
    func draw(in view: MTKView) {
        guard let pixels, let drawable = view.currentDrawable,
            let pass = view.currentRenderPassDescriptor, let command = queue.makeCommandBuffer() else { return }
        var wrapper: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixels, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(pixels), CVPixelBufferGetHeight(pixels), 0, &wrapper) == kCVReturnSuccess,
            let wrapper, let texture = CVMetalTextureGetTexture(wrapper),
            let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let scale = min(view.drawableSize.width / Double(texture.width), view.drawableSize.height / Double(texture.height))
        let width = Double(texture.width) * scale, height = Double(texture.height) * scale
        encoder.setViewport(MTLViewport(originX: (view.drawableSize.width - width) / 2,
            originY: (view.drawableSize.height - height) / 2, width: width, height: height, znear: 0, zfar: 1))
        encoder.setRenderPipelineState(pipeline); encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding(); command.present(drawable)
        let retained = RetainedMetalResources(buffers: [pixels], textures: [wrapper])
        command.addCompletedHandler { _ in withExtendedLifetime(retained) {} }
        command.commit()
    }
}

struct MetalPreview: NSViewRepresentable {
    let frame: RenderedFrame?
    func makeCoordinator() -> MetalPreviewRenderer { MetalPreviewRenderer() }
    func makeNSView(context: Context) -> MTKView { context.coordinator.view }
    func updateNSView(_ view: MTKView, context: Context) { context.coordinator.display(frame?.pixels) }
}

@MainActor
final class DesktopOverlay {
    private let renderer = MetalPreviewRenderer()
    private let panel: NSPanel
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = renderer.view
        panel.level = .floating
        panel.isOpaque = true; panel.hasShadow = false; panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
    }
    func update(frame: RenderedFrame, bounds: CGRect) {
        let desktopTop = CGDisplayBounds(CGMainDisplayID()).height
        panel.setFrame(NSRect(x: bounds.minX, y: desktopTop - bounds.maxY,
                              width: bounds.width, height: bounds.height), display: true)
        renderer.display(frame.pixels); panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil); renderer.display(nil) }
}
