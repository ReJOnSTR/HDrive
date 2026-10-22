import SwiftUI
import AppKit

@MainActor
final class AppUpdateModel: ObservableObject {
    static let shared = AppUpdateModel()
    @Published var release: AppRelease?
    @Published var message = "Yeni sürümleri buradan kontrol edebilirsiniz."
    @Published var busy = false
    @Published var downloading = false
    @Published var progress = 0.0
    @Published var lastChecked: Date?
    @Published var installer: URL?
    private var operation: Task<Void, Never>?
    var canDownload: Bool { release?.isNewer(than: AppUpdateService.currentVersion) == true && release?.macAsset?.sha256 != nil }
    func check() {
        guard !busy else { return }
        busy = true; release = nil; installer = nil
        message = "Güncellemeler kontrol ediliyor…"
        operation = Task {
            defer { busy = false }
            do {
                release = try await AppUpdateService.check()
                lastChecked = Date()
                guard let release else { message = "Henüz yayımlanmış bir sürüm bulunmuyor."; return }
                if release.isNewer(than: AppUpdateService.currentVersion) {
                    message = canDownload ? "\(release.tag_name) sürümü hazır." : "\(release.tag_name) yayımlandı. Uygun kurulum paketi için yayın sayfasına bakın."
                } else if AppReleaseVersion(release.tag_name) == AppReleaseVersion(AppUpdateService.currentVersion) {
                    message = "HDrive güncel."
                } else { message = "Bu kurulum, yayımlanan \(release.tag_name) sürümünden daha yeni." }
            } catch { message = "Kontrol yapılamadı: " + error.localizedDescription }
        }
    }
    func download() {
        guard !busy, let release, canDownload else { return }
        busy = true; downloading = true; progress = 0; installer = nil
        message = "Güncelleme indiriliyor…"
        operation = Task {
            defer { busy = false; downloading = false }
            do {
                installer = try await AppUpdateService.download(release) { value in
                    Task { @MainActor in self.progress = value }
                }
                try Task.checkCancellation()
                openInstaller()
            } catch is CancellationError { message = "İndirme iptal edildi." }
            catch { message = Task.isCancelled ? "İndirme iptal edildi." : "İndirme başarısız: " + error.localizedDescription }
        }
    }
    func cancel() { operation?.cancel() }
    func openInstaller() {
        guard let installer else { return }
        if NSWorkspace.shared.open(installer) {
            message = "Kurulum paketi açıldı. HDrive’ı kapatıp paketteki HDrive uygulamasını Uygulamalar klasörüne taşıyın; ardından yeniden açın."
        } else { message = "Paket indirildi ancak açılamadı. İndirilenler klasöründen açabilirsiniz." }
    }
}

struct AppUpdatesView: View {
    @StateObject private var model = AppUpdateModel.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Güncellemeler", systemImage: "arrow.down.circle").font(.title2.bold())
            Text("Mevcut sürüm: \(AppUpdateService.currentVersion)").foregroundStyle(.secondary)
            Text(model.message).textSelection(.enabled).accessibilityIdentifier("updateStatus")
            if let date = model.lastChecked { Text("Son kontrol: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            if model.downloading {
                ProgressView(value: model.progress)
                Text("%\(Int(model.progress * 100))").font(.caption)
                Button("İptal") { model.cancel() }
            } else if model.busy { ProgressView() }
            HStack {
                Button("Güncellemeleri kontrol et") { model.check() }.disabled(model.busy)
                if model.canDownload {
                    Button("İndir ve kurulumu başlat") { model.download() }.disabled(model.busy).buttonStyle(.borderedProminent)
                }
            }
            if model.installer != nil {
                Button("Kurulum paketini aç") { model.openInstaller() }.disabled(model.busy)
            }
            Link("Yayın sayfasını aç", destination: model.release?.pageURL ?? AppUpdateService.releasesURL)
            if let release = model.release {
                Divider()
                Text("\(release.tag_name) — Yenilikler").font(.headline)
                Text(release.body?.isEmpty == false ? release.body! : "Bu sürüm için yayın notu yok.").textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
