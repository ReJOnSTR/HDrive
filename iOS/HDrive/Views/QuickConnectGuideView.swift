//
//  QuickConnectGuideView.swift
//  HDrive
//

import SwiftUI

public struct QuickConnectGuideView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var config = ServerConfig.shared
    
    @State private var selectedOS: Int = 0
    @State private var copiedText: String? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // İşletim Sistemi Seçici
                    Picker("İşletim Sistemi", selection: $selectedOS) {
                        Text("Windows").tag(0)
                        Text("macOS").tag(1)
                        Text("Web / Tarayıcı").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)
                    
                    if selectedOS == 0 {
                        windowsGuideView
                    } else if selectedOS == 1 {
                        macOSGuideView
                    } else {
                        webBrowserGuideView
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("PC Bağlantı Kılavuzu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Windows Rehberi
    private var windowsGuideView: some View {
        VStack(alignment: .leading, spacing: 18) {
            guideCard(title: "Yöntem 1: Dosya Gezgini İle Doğrudan Bağlama (Önerilen)", badge: "Sürücü Harfi (Z:)") {
                VStack(alignment: .leading, spacing: 12) {
                    stepRow(number: "1", text: "Windows'ta Dosya Gezgini'ni (Windows Explorer) açın.")
                    stepRow(number: "2", text: "Sol menüdeki 'Bu Bilgisayar' seçeneğine sağ tıklayın ve 'Ağ Sürücüsü Eşle...' (Map Network Drive) seçin.")
                    stepRow(number: "3", text: "Sürücü harfi olarak Z: veya boş bir harf seçin.")
                    stepRow(number: "4", text: "Klasör kutucuğuna şu adresi yapıştırın:")
                    
                    codeCopyBox(text: config.serverAddress)
                    
                    stepRow(number: "5", text: "'Son' butonuna basın. Telefonunuz artık Dosya Gezgini'nde harici sabit disk gibi açılır!")
                }
            }
            
            guideCard(title: "Yöntem 2: Tek Tıkla Bağlantı Scripti", badge: "Otomatik") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Proje içindeki 'pc-connect/windows-mount.bat' dosyasını bilgisayarınızda çalıştırarak tek tıkla otomatik bağlayabilirsiniz.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Text("Komut satırından manuel bağlamak için:")
                        .font(.caption.weight(.semibold))
                    
                    codeCopyBox(text: "net use Z: \(config.serverAddress)")
                }
            }
        }
    }
    
    // MARK: - macOS Rehberi
    private var macOSGuideView: some View {
        VStack(alignment: .leading, spacing: 18) {
            guideCard(title: "macOS Finder İle Bağlanma", badge: "Yerel Disk") {
                VStack(alignment: .leading, spacing: 12) {
                    stepRow(number: "1", text: "Masaüstünde Finder'ı açın.")
                    stepRow(number: "2", text: "Klavyeden Cmd + K tuşlarına basın (veya üst menüden Git > Sunucuya Bağlan).")
                    stepRow(number: "3", text: "Sunucu Adresi alanına şu adresi yazın:")
                    
                    codeCopyBox(text: config.serverAddress)
                    
                    stepRow(number: "4", text: "'Bağlan' butonuna basın. Finder yan menüsünde telefonunuz belirecektir!")
                }
            }
        }
    }
    
    // MARK: - Web Tarayıcı Rehberi
    private var webBrowserGuideView: some View {
        VStack(alignment: .leading, spacing: 18) {
            guideCard(title: "Tarayıcı Web Dashboard", badge: "Tüm Cihazlar") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Bilgisayarınızda Chrome, Edge, Safari veya Firefox tarayıcısını açıp adresi adres çubuğuna yazmanız yeterlidir:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    codeCopyBox(text: config.serverAddress)
                    
                    Text("• Sürükle-bırak ile dosya ve klasör yükleme\n• Video, ses ve fotoğraf doğrudan oynatma\n• Yeni klasör oluşturma, silme ve adlandırma")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Kart ve Adım Bileşenleri
    private func guideCard<Content: View>(title: String, badge: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text(badge)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.12))
                    .foregroundColor(.indigo)
                    .cornerRadius(6)
            }
            Divider()
            content()
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Color.indigo)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
    
    private func codeCopyBox(text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundColor(.indigo)
                .lineLimit(1)
            Spacer()
            Button(action: {
                UIPasteboard.general.string = text
                copiedText = text
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedText = nil
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: copiedText == text ? "checkmark" : "doc.on.doc")
                    Text(copiedText == text ? "Kopyalandı" : "Kopyala")
                }
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.indigo)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
}
