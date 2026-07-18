#if os(iOS)
import SwiftUI
import Vision
import VisionKit

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static let recognizedSymbologies: [VNBarcodeSymbology] = [
        .ean13, .ean8, .code128, .code39, .code39Checksum, .codabar, .upce, .itf14,
    ]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.recognizedSymbologies)],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard case let .barcode(barcode) = addedItems.first, let payload = barcode.payloadStringValue else { return }
            onScan(payload)
        }
    }
}

enum BarcodeScannerAvailability {
    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }
}
#endif
