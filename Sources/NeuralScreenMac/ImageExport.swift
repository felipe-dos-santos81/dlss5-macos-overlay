import CoreImage
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

enum ImageExport {
    static func writePNG(_ buffer: CVPixelBuffer, to url: URL) throws {
        let image = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8,
                                             colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!),
              let target = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PortError.message("Could not prepare the PNG image.")
        }
        CGImageDestinationAddImage(target, cg, nil)
        guard CGImageDestinationFinalize(target) else { throw PortError.message("Could not save the PNG image.") }
    }
}
