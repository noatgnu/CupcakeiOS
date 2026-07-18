import Foundation

enum AnnotationMimeType {
    static func mimeType(annotationType: String, fileExtension: String) -> String {
        switch annotationType {
        case "audio":
            return "audio/m4a"
        case "image":
            return "image/jpeg"
        case "sketch":
            return "application/json"
        case "video":
            switch fileExtension.lowercased() {
            case "mov":
                return "video/quicktime"
            case "m4v":
                return "video/x-m4v"
            default:
                return "video/mp4"
            }
        default:
            return "application/octet-stream"
        }
    }
}
