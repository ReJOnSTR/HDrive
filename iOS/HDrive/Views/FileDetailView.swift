//
//  FileDetailView.swift
//  HDrive
//

import SwiftUI
import AVKit
import PDFKit
import QuickLook

public struct FileDetailView: View {
    public let file: FileItem
    
    @State private var textContent: String = ""
    @State private var isSharing = false
    
    public init(file: FileItem) {
        self.file = file
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Önizleme Penceresi
                previewContent
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 280, maxHeight: 420)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(18)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
                
                // 2. Dosya Bilgileri (Metadata)
                metadataSection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isSharing = true }) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $isSharing) {
            ShareSheet(activityItems: [file.url])
        }
        .onAppear {
            loadTextContentIfNeeded()
        }
    }
    
    // MARK: - Önizleme İçeriği
    @ViewBuilder
    private var previewContent: some View {
        switch file.category {
        case .image:
            if let uiImage = UIImage(contentsOfFile: file.url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(14)
                    .padding(8)
            } else {
                fallbackIconView
            }
            
        case .video:
            VideoPlayer(player: AVPlayer(url: file.url))
                .cornerRadius(14)
            
        case .audio:
            VStack(spacing: 16) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 60))
                    .foregroundColor(.pink)
                Text(file.name)
                    .font(.headline)
                VideoPlayer(player: AVPlayer(url: file.url))
                    .frame(height: 50)
            }
            .padding(24)
            
        case .document:
            if file.url.pathExtension.lowercased() == "pdf" {
                PDFViewer(url: file.url)
                    .cornerRadius(14)
            } else if !textContent.isEmpty {
                ScrollView {
                    Text(textContent)
                        .font(.system(.footnote, design: .monospaced))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                fallbackIconView
            }
            
        default:
            fallbackIconView
        }
    }
    
    private var fallbackIconView: some View {
        VStack(spacing: 12) {
            Image(systemName: file.systemIcon)
                .font(.system(size: 64))
                .foregroundColor(file.iconColor)
            Text(file.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(file.formattedSize)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
    }
    
    // MARK: - Metadata Kartı
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dosya Bilgileri")
                .font(.headline.weight(.semibold))
            
            VStack(spacing: 10) {
                metaRow(title: "Dosya Adı", value: file.name)
                metaRow(title: "Dosya Boyutu", value: file.formattedSize)
                metaRow(title: "Tür", value: file.mimeType)
                metaRow(title: "Son Değiştirilme", value: file.formattedDate)
                metaRow(title: "Konum", value: file.url.lastPathComponent)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    private func metaRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
    
    private func loadTextContentIfNeeded() {
        let ext = file.url.pathExtension.lowercased()
        if ["txt", "md", "json", "swift", "py", "js", "html", "css", "csv", "xml"].contains(ext) {
            if let content = try? String(contentsOf: file.url, encoding: .utf8) {
                self.textContent = content
            }
        }
    }
}

// MARK: - PDFKit Görüntüleyici
struct PDFViewer: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {}
}
