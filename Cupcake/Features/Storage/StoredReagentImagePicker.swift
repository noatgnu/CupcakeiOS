import PhotosUI
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum StoredReagentImageProcessor {
    static let maxDimension: CGFloat = 800

    static func resizedPNGBase64(from data: Data) -> String? {
        guard let image = PlatformImage(data: data) else { return nil }
        guard let pngData = resizedPNG(image) else { return nil }
        return pngData.base64EncodedString()
    }

    private static func resizedPNG(_ image: PlatformImage) -> Data? {
        #if os(iOS)
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.pngData()
        #elseif os(macOS)
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = NSSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        resized.unlockFocus()
        guard let tiffData = resized.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #endif
    }
}

struct StoredReagentPhotoLibraryButton: View {
    let label: String
    let onPick: (String) -> Void

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label(label, systemImage: "photo")
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let base64 = StoredReagentImageProcessor.resizedPNGBase64(from: data) {
                    onPick(base64)
                }
                pickerItem = nil
            }
        }
    }
}

#if os(iOS)
struct StoredReagentCameraButton: View {
    let label: String
    let onPick: (String) -> Void

    @State private var isShowingCamera = false

    var body: some View {
        Button {
            isShowingCamera = true
        } label: {
            Label(label, systemImage: "camera")
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraCaptureView { image in
                if let data = image.pngData(), let base64 = StoredReagentImageProcessor.resizedPNGBase64(from: data) {
                    onPick(base64)
                }
                isShowingCamera = false
            }
            .ignoresSafeArea()
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void

        init(onCapture: @escaping (UIImage) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
        }
    }
}
#endif
