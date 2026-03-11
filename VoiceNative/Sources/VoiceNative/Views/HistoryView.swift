import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptionRecord.timestamp, order: .reverse) private var records: [TranscriptionRecord]
    
    @State private var searchText = ""
    
    private var filteredRecords: [TranscriptionRecord] {
        if searchText.isEmpty {
            return records
        }
        return records.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            
            Divider()
            
            if filteredRecords.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search transcriptions...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(10)
        .background(.bar)
    }
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Transcriptions", systemImage: "text.bubble")
        } description: {
            if searchText.isEmpty {
                Text("Your transcription history will appear here.")
            } else {
                Text("No results for \"\(searchText)\"")
            }
        }
    }
    
    private var recordsList: some View {
        List {
            ForEach(filteredRecords) { record in
                RecordRow(record: record)
            }
            .onDelete(perform: deleteRecords)
        }
        .listStyle(.plain)
    }
    
    private func deleteRecords(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredRecords[index])
        }
    }
}

struct RecordRow: View {
    let record: TranscriptionRecord
    
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.text)
                .font(.body)
                .lineLimit(3)
            
            HStack {
                Text(record.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .foregroundStyle(.quaternary)
                
                Text(String(format: "%.1fs", record.audioDurationSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .foregroundStyle(.quaternary)
                
                Text(record.modelVersion)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                Button {
                    copyToClipboard()
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)
        
        isCopied = true
        
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            isCopied = false
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: TranscriptionRecord.self, inMemory: true)
}
