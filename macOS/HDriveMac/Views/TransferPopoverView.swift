//
//  TransferPopoverView.swift
//  HDriveMac - Transfer Paneli Görünümü (Popover / Modal)
//

import SwiftUI
import AppKit

public struct TransferPopoverView: View {
    @ObservedObject var transferManager = TransferManager.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // ÜST BAŞLIK
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                    Text("Transferler")
                        .font(.system(size: 14, weight: .bold))
                }
                
                Spacer()
                
                if !transferManager.items.isEmpty {
                    Button(action: {
                        transferManager.clearCompleted()
                    }) {
                        Text("Temizle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // TRANSFER LİSTESİ
            if transferManager.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Aktif veya geçmiş transfer bulunmuyor")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(transferManager.items) { item in
                            TransferRowView(item: item)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 340)
            }
        }
        .frame(width: 360)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct TransferRowView: View {
    @ObservedObject var item: TransferItem
    
    var body: some View {
        HStack(spacing: 10) {
            // Yön ve Durum Simgesi
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 32, height: 32)
                
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            // Bilgi ve İlerleme
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.fileName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(item.status.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(statusColor)
                }
                
                // İlerleme Çubuğu
                if item.status == .running || item.status == .paused {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .scaleEffect(y: 0.6)
                }
                
                // Alt Metin: Boyut & Hız
                HStack {
                    Text(item.formattedSize)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    if !item.formattedSpeed.isEmpty {
                        Text("• \(item.formattedSpeed)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    
                    Spacer()
                    
                    if let err = item.errorMessage {
                        Text(err)
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                }
            }
            
            // Eylem Butonları
            HStack(spacing: 4) {
                if item.status == .running {
                    Button(action: { TransferManager.shared.pauseTask(id: item.id) }) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    
                    Button(action: { TransferManager.shared.cancelTask(id: item.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                } else if item.status == .paused {
                    Button(action: { TransferManager.shared.resumeTask(id: item.id) }) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    
                    Button(action: { TransferManager.shared.cancelTask(id: item.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                } else if item.status == .failed {
                    Button(action: { TransferManager.shared.retryTask(id: item.id) }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                } else if item.status == .completed {
                    Button(action: {
                        NSWorkspace.shared.selectFile(item.localURL.path, inFileViewerRootedAtPath: "")
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .foregroundColor(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.7))
        )
    }
    
    private var iconName: String {
        switch item.direction {
        case .download: return "arrow.down"
        case .upload: return "arrow.up"
        }
    }
    
    private var iconColor: Color {
        switch item.status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .accentColor
        case .paused: return .orange
        default: return .secondary
        }
    }
    
    private var iconBackgroundColor: Color {
        iconColor.opacity(0.12)
    }
    
    private var statusColor: Color {
        switch item.status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .blue
        case .paused: return .orange
        case .queued: return .secondary
        case .cancelled: return .secondary
        }
    }
}
