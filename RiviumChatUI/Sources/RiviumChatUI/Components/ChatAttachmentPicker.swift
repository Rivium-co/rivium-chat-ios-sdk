import SwiftUI
import UniformTypeIdentifiers

/// Types of attachments that can be picked.
public enum AttachmentType: String, CaseIterable, Identifiable {
    case photo
    case camera
    case document
    case location

    public var id: String { rawValue }

    var icon: String {
        switch self {
        case .photo: return "photo.on.rectangle"
        case .camera: return "camera.fill"
        case .document: return "doc.fill"
        case .location: return "location.fill"
        }
    }

    var title: String {
        switch self {
        case .photo: return "Photo"
        case .camera: return "Camera"
        case .document: return "Document"
        case .location: return "Location"
        }
    }

    var color: Color {
        switch self {
        case .photo: return .purple
        case .camera: return .orange
        case .document: return .blue
        case .location: return .green
        }
    }
}

/// Result of picking an attachment.
public struct AttachmentResult {
    public let type: AttachmentType
    public let url: URL?
    public let data: Data?
    public let fileName: String
    public let mimeType: String

    public init(type: AttachmentType, url: URL? = nil, data: Data? = nil, fileName: String, mimeType: String) {
        self.type = type
        self.url = url
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

/// A full-featured attachment picker supporting photos, camera, and documents.
public struct ChatAttachmentPicker: View {
    @Binding var isPresented: Bool
    let onAttachmentSelected: (AttachmentResult) -> Void
    var allowedTypes: [AttachmentType] = [.photo, .camera, .document]

    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showDocumentPicker = false

    public init(
        isPresented: Binding<Bool>,
        onAttachmentSelected: @escaping (AttachmentResult) -> Void,
        allowedTypes: [AttachmentType] = [.photo, .camera, .document]
    ) {
        self._isPresented = isPresented
        self.onAttachmentSelected = onAttachmentSelected
        self.allowedTypes = allowedTypes
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Attachment")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
            }
            .padding()

            Divider()

            // Attachment type grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(allowedTypes) { type in
                    AttachmentTypeButton(type: type) {
                        handleSelection(type)
                    }
                }
            }
            .padding()

            Spacer()
        }
        .background(Color(UIColor.systemBackground))
        .sheet(isPresented: $showPhotoPicker) {
            ImagePickerView(sourceType: .photoLibrary) { result in
                if let result = result {
                    onAttachmentSelected(result)
                }
                showPhotoPicker = false
                isPresented = false
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { result in
                if let result = result {
                    onAttachmentSelected(result)
                }
                showCamera = false
                isPresented = false
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { result in
                if let result = result {
                    onAttachmentSelected(result)
                }
                showDocumentPicker = false
                isPresented = false
            }
        }
    }

    private func handleSelection(_ type: AttachmentType) {
        switch type {
        case .photo:
            showPhotoPicker = true
        case .camera:
            showCamera = true
        case .document:
            showDocumentPicker = true
        case .location:
            break
        }
    }
}

struct AttachmentTypeButton: View {
    let type: AttachmentType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(type.color.opacity(0.15))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: type.icon)
                            .font(.title2)
                            .foregroundColor(type.color)
                    )

                Text(type.title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Photo library picker using UIImagePickerController (works on iOS 14+).
struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onComplete: (AttachmentResult?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (AttachmentResult?) -> Void

        init(onComplete: @escaping (AttachmentResult?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                let result = AttachmentResult(
                    type: .photo,
                    data: data,
                    fileName: "photo_\(Date().timeIntervalSince1970).jpg",
                    mimeType: "image/jpeg"
                )
                onComplete(result)
            } else {
                onComplete(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }
    }
}

/// Camera view wrapper for UIImagePickerController.
struct CameraView: UIViewControllerRepresentable {
    let onComplete: (AttachmentResult?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (AttachmentResult?) -> Void

        init(onComplete: @escaping (AttachmentResult?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                let result = AttachmentResult(
                    type: .camera,
                    data: data,
                    fileName: "camera_\(Date().timeIntervalSince1970).jpg",
                    mimeType: "image/jpeg"
                )
                onComplete(result)
            } else {
                onComplete(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }
    }
}

/// Document picker wrapper.
struct DocumentPicker: UIViewControllerRepresentable {
    let onComplete: (AttachmentResult?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .pdf, .text, .image])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: (AttachmentResult?) -> Void

        init(onComplete: @escaping (AttachmentResult?) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onComplete(nil)
                return
            }

            guard url.startAccessingSecurityScopedResource() else {
                onComplete(nil)
                return
            }

            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

                let result = AttachmentResult(
                    type: .document,
                    url: url,
                    data: data,
                    fileName: url.lastPathComponent,
                    mimeType: mimeType
                )
                onComplete(result)
            } catch {
                onComplete(nil)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete(nil)
        }
    }
}

/// Content view for the attachment picker sheet.
public struct ChatAttachmentPickerContent: View {
    let onAttachmentSelected: (AttachmentResult) -> Void
    let onDismiss: () -> Void
    var allowedTypes: [AttachmentType] = [.photo, .camera, .document]

    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showDocumentPicker = false

    public init(
        onAttachmentSelected: @escaping (AttachmentResult) -> Void,
        onDismiss: @escaping () -> Void,
        allowedTypes: [AttachmentType] = [.photo, .camera, .document]
    ) {
        self.onAttachmentSelected = onAttachmentSelected
        self.onDismiss = onDismiss
        self.allowedTypes = allowedTypes
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Handle bar
            Capsule()
                .fill(Color(UIColor.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Attachment options
            HStack(spacing: 24) {
                ForEach(allowedTypes) { type in
                    AttachmentTypeButton(type: type) {
                        handleSelection(type)
                    }
                }
            }
            .padding(.vertical)

            Spacer()
        }
        .frame(height: 160)
        .background(Color(UIColor.systemBackground))
        .sheet(isPresented: $showPhotoPicker) {
            ImagePickerView(sourceType: .photoLibrary) { result in
                if let result = result {
                    onAttachmentSelected(result)
                }
                showPhotoPicker = false
                onDismiss()
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { result in
                if let result = result {
                    onAttachmentSelected(result)
                }
                showCamera = false
                onDismiss()
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { result in
                if let result = result {
                    onAttachmentSelected(result)
                }
                showDocumentPicker = false
                onDismiss()
            }
        }
    }

    private func handleSelection(_ type: AttachmentType) {
        switch type {
        case .photo:
            showPhotoPicker = true
        case .camera:
            showCamera = true
        case .document:
            showDocumentPicker = true
        case .location:
            break
        }
    }
}
