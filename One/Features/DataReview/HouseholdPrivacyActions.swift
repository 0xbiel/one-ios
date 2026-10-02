import SwiftUI
import UniformTypeIdentifiers

private struct HouseholdJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct HouseholdPrivacyActions: View {
    let homeID: UUID?
    let canManage: Bool
    let export: () async throws -> Data
    let delete: (String) async throws -> Void
    @State private var document: HouseholdJSONDocument?
    @State private var showExporter = false
    @State private var showDelete = false
    @State private var confirmation = ""
    @State private var busy = false
    @State private var error: String?
    @State private var result: String?

    var body: some View {
        Group {
            Button {
                busy = true; error = nil; result = nil
                Task { @MainActor in
                    defer { busy = false }
                    do { document = HouseholdJSONDocument(data: try await export()); showExporter = true }
                    catch { self.error = error.localizedDescription }
                }
            } label: { Label("Export household JSON", systemImage: "square.and.arrow.up") }
                .disabled(!canManage || homeID == nil || busy)
            Button(role: .destructive) { confirmation = ""; error = nil; result = nil; showDelete = true } label: {
                Label("Delete household data", systemImage: "trash")
            }.disabled(!canManage || homeID == nil || busy)
            if !canManage { Text("Only a household administrator can export or delete household data.").font(.footnote) }
            if busy { ProgressView("Preparing data…") }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            if let result { Text(result).font(.footnote) }
        }
        .fileExporter(isPresented: $showExporter, document: document, contentType: .json, defaultFilename: "ONE-household-export") { outcome in
            switch outcome {
            case .success: result = "Export saved to your chosen location."
            case .failure(let failure): error = failure.localizedDescription
            }
            document = nil
        }
        .sheet(isPresented: $showDelete) {
            NavigationStack {
                Form {
                    Section("Permanent household deletion") {
                        Text("This deletes the household’s retained data for everyone with access. Export anything you need first.")
                        Text("To confirm, type the exact household ID below.")
                        Text(homeID?.uuidString ?? "Unavailable").font(.footnote.monospaced()).textSelection(.enabled)
                        TextField("Household ID", text: $confirmation).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    if let error { Section { Text(error).foregroundStyle(.red) } }
                    Section {
                        Button("Delete household permanently", role: .destructive) {
                            busy = true; error = nil
                            Task { @MainActor in
                                defer { busy = false }
                                do { try await delete(confirmation); result = "Household deletion completed."; showDelete = false }
                                catch { self.error = error.localizedDescription }
                            }
                        }.disabled(busy || !canManage || homeID == nil || confirmation != homeID?.uuidString)
                    }
                }
                .navigationTitle("Delete household")
                .interactiveDismissDisabled(busy)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDelete = false; confirmation = ""; error = nil }.disabled(busy) } }
            }
        }
    }
}
