import Foundation
import WhisperKit
import Observation

@MainActor
@Observable
final class ModelManager {
    private(set) var availableModels: [String] = []
    private(set) var downloadedModels: [String] = []
    private(set) var isLoadingModelList = false
    private(set) var downloadProgress: Double = 0
    private(set) var downloadStatus: String = ""
    private(set) var isDownloading = false
    
    private let modelRepo = "argmaxinc/whisperkit-coreml"
    
    var localModelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("VoiceNative/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }
    
    func fetchAvailableModels() async {
        isLoadingModelList = true
        defer { isLoadingModelList = false }
        
        do {
            let models = try await WhisperKit.fetchAvailableModels(from: modelRepo)
            availableModels = models.sorted()
            refreshDownloadedModels()
        } catch {
            print("Failed to fetch available models: \(error)")
            availableModels = WhisperModel.allCases.map(\.rawValue)
        }
    }
    
    func refreshDownloadedModels() {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: localModelsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            downloadedModels = []
            return
        }
        
        downloadedModels = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
    }
    
    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        downloadedModels.contains(model.rawValue)
    }
    
    func downloadModel(_ model: WhisperModel) async throws -> URL {
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Preparing download..."
        
        defer {
            isDownloading = false
            downloadStatus = ""
        }
        
        let modelName = model.rawValue
        let targetFolder = localModelsDirectory.appendingPathComponent(modelName)
        
        if FileManager.default.fileExists(atPath: targetFolder.path) {
            downloadProgress = 1.0
            downloadStatus = "Model already downloaded"
            refreshDownloadedModels()
            return targetFolder
        }
        
        downloadStatus = "Downloading \(model.displayName)..."
        
        let progressHandler: @Sendable (Progress) -> Void = { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress.fractionCompleted
                self?.downloadStatus = "Downloading... \(Int(progress.fractionCompleted * 100))%"
            }
        }
        
        let folder = try await WhisperKit.download(
            variant: modelName,
            from: modelRepo,
            progressCallback: progressHandler
        )
        
        downloadProgress = 1.0
        downloadStatus = "Download complete"
        refreshDownloadedModels()
        
        return folder
    }
    
    func deleteModel(_ model: WhisperModel) throws {
        let modelFolder = localModelsDirectory.appendingPathComponent(model.rawValue)
        try FileManager.default.removeItem(at: modelFolder)
        refreshDownloadedModels()
    }
    
    func modelFolderPath(for model: WhisperModel) -> URL? {
        let folder = localModelsDirectory.appendingPathComponent(model.rawValue)
        if FileManager.default.fileExists(atPath: folder.path) {
            return folder
        }
        return nil
    }
}
