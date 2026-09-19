//
//  TransferSheetView.swift
//  HDrive - iOS Transfer Kuyruğu Görünümü
//

import SwiftUI
import UIKit

public struct TransferSheetView: View {
    @ObservedObject var transferManager = TransferManager.shared
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if transferManager.items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("Aktif veya geçmiş transfer bulunmuyor")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 60)
                } else {
                    List {
                        ForEach(transferManager.items) { item in
                            IOSTransferRowView(item: item)
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Transferler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !transferManager.items.isEmpty {
                        Button("Temizle") {
                            transferManager.clearCompleted()
                        }
                        .font(.subheadline)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct IOSTransferRowView: View {
    @ObservedObject var item: TransferItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Yön ve Durum Simgesi
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 36, height: 36)
                
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(iconColor)
            }
            
            // Bilgi ve İlerleme
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.fileName)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(item.status.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(statusColor)
                }
                
                // İlerleme Çubuğu
                if item.status == .running || item.status == .paused {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .tint(statusColor)
                }
                
                // Alt Metin: Boyut & Hız
                HStack {
                    Text(item.formattedSize)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if !item.formattedSpeed.isEmpty {
                        Text("• \(item.formattedSpeed)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.indigo)
                    }
                    
                    Spacer()
                    
                    if let err = item.errorMessage {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                }
            }
            
            // Eylem Butonları
            HStack(spacing: 6) {
                if item.status == .running {
                    Button(action: { TransferManager.shared.pauseTask(id: item.id) }) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { TransferManager.shared.cancelTask(id: item.id) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else if item.status == .paused {
                    Button(action: { TransferManager.shared.resumeTask(id: item.id) }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.indigo)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { TransferManager.shared.cancelTask(id: item.id) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else if item.status == .failed {
                    Button(action: { TransferManager.shared.retryTask(id: item.id) }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
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
        case .running: return .indigo
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
        case .running: return .indigo
        case .paused: return .orange
        case .queued: return .secondary
        case .cancelled: return .secondary
        }
    }
}
