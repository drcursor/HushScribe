import SwiftUI
import AppKit

struct SummarizeView: View {
    let settings: AppSettings
    let logger: TranscriptLogger

    @State private var transcriptURL: URL?
    @State private var transcriptText = ""
    @State private var parsedUtterances: [ParsedUtterance] = []
    @State private var summary: String? = nil
    @State private var isGenerating = false
    @State private var isSaving = false
    @State private var savedConfirmation = false
    @State private var savedFilename = ""
    @State private var showOverwriteAlert = false
    @State private var pendingSummaryURL: URL? = nil
    @State private var summaryRendered = true
    @State private var showPicker = false

    init(initialURL: URL? = nil, settings: AppSettings, logger: TranscriptLogger) {
        self.settings = settings
        self.logger = logger
        self._transcriptURL = State(initialValue: initialURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if transcriptURL == nil {
                emptyState
            } else {
                transcriptPane
                if summary != nil {
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                        Text("AI Summary")
                            .font(.system(size: 10, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)

                        Spacer()

                        Button {
                            Task { await save() }
                        } label: {
                            if isSaving {
                                ProgressView().controlSize(.small)
                            } else if savedConfirmation {
                                Label("Saved · \(savedFilename)", systemImage: "checkmark")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .disabled(isSaving || savedConfirmation)
                    }
                    .foregroundStyle(Color.accent1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.accent1.opacity(0.06))
                    .overlay(Rectangle().fill(Color(NSColor.separatorColor)).frame(height: 1), alignment: .bottom)
                    summaryPane
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            if let url = transcriptURL { loadTranscript(from: url) }
        }
        .alert("Overwrite existing summary?", isPresented: $showOverwriteAlert, presenting: pendingSummaryURL) { summaryURL in
            Button("Overwrite", role: .destructive) {
                Task { await performWrite(summaryURL: summaryURL) }
            }
            Button("Cancel", role: .cancel) { pendingSummaryURL = nil }
        } message: { summaryURL in
            Text("\"\(summaryURL.lastPathComponent)\" already exists. Do you want to replace it?")
        }
        .sheet(isPresented: $showPicker) {
            TranscriptPickerView(
                meetingsPath: settings.vaultMeetingsPath,
                voicePath: settings.vaultVoicePath
            ) { url in
                selectTranscript(url)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                generate()
            } label: {
                if isGenerating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Generating…")
                    }
                } else {
                    Label("Generate Summary", systemImage: "sparkles")
                }
            }
            .disabled(isGenerating || transcriptText.isEmpty)

            Spacer()

            Button {
                showPicker = true
            } label: {
                Label("Browse Transcripts", systemImage: "doc.badge.plus")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No transcript selected")
                .font(.system(size: 14, weight: .semibold))
            Text("Open a saved transcript to view it or generate a summary.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Browse Transcripts") { showPicker = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Transcript pane

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Transcript")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let url = transcriptURL {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if transcriptText.isEmpty {
                Text("Loading…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !parsedUtterances.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(parsedUtterances) { ParsedBubble(utterance: $0) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            } else {
                ScrollView {
                    Text(transcriptText)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Summary pane

    private var summaryPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Summary")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { summaryRendered.toggle() }
                } label: {
                    Label(summaryRendered ? "Plain Text" : "Preview",
                          systemImage: summaryRendered ? "text.alignleft" : "doc.richtext")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accent1)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ScrollView {
                Group {
                    if summaryRendered, let rendered = try? AttributedString(
                        markdown: summary ?? "",
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    ) {
                        Text(rendered)
                    } else {
                        Text(summary ?? "")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 220)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Actions

    private func selectTranscript(_ url: URL) {
        transcriptURL = url
        transcriptText = ""
        parsedUtterances = []
        summary = nil
        savedConfirmation = false
        loadTranscript(from: url)
        NSApp.keyWindow?.title = "Transcript Viewer — \(url.deletingPathExtension().lastPathComponent)"
    }

    private func loadTranscript(from url: URL) {
        Task.detached {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            let raw = SummaryService.extractTranscript(from: content)
            let utterances = ParsedUtterance.parse(raw)
            await MainActor.run {
                transcriptText = raw
                parsedUtterances = utterances
            }
        }
    }

    private func generate() {
        isGenerating = true
        savedConfirmation = false
        savedFilename = ""
        summaryRendered = true
        let text = transcriptText
        Task.detached {
            let result = SummaryService.summarize(transcript: text)
            await MainActor.run {
                summary = result
                isGenerating = false
            }
        }
    }

    @MainActor
    private func save() async {
        guard summary != nil, let transcriptURL else { return }
        let summaryURL = transcriptURL.deletingLastPathComponent()
            .appendingPathComponent("\(transcriptURL.deletingPathExtension().lastPathComponent) summary.md")
        if FileManager.default.fileExists(atPath: summaryURL.path) {
            pendingSummaryURL = summaryURL
            showOverwriteAlert = true
        } else {
            await performWrite(summaryURL: summaryURL)
        }
    }

    @MainActor
    private func performWrite(summaryURL: URL) async {
        guard let s = summary, let transcriptURL else { return }
        pendingSummaryURL = nil
        isSaving = true
        await logger.writeSummaryFile(s, for: transcriptURL)
        isSaving = false
        savedFilename = summaryURL.lastPathComponent
        withAnimation { savedConfirmation = true }
    }

    // MARK: - Window factory

    private static weak var sharedWindow: NSWindow?

    @MainActor
    static func openWindow(for url: URL? = nil, settings: AppSettings, logger: TranscriptLogger) {
        if url == nil, let w = sharedWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SummarizeView(initialURL: url, settings: settings, logger: logger)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        let titleSuffix = url.map { " — \($0.deletingPathExtension().lastPathComponent)" } ?? ""
        window.title = "Transcript Viewer\(titleSuffix)"
        window.setContentSize(NSSize(width: 660, height: 560))
        window.minSize = NSSize(width: 520, height: 420)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if url == nil { sharedWindow = window }
    }
}

// MARK: - Parsed Utterance

struct ParsedUtterance: Identifiable {
    let id = UUID()
    let speaker: String
    let isYou: Bool
    let time: String
    let text: String

    private static let headerRegex = try? NSRegularExpression(
        pattern: #"^\*\*([^*]+)\*\*\s*\(([^)]+)\)"#
    )

    static func parse(_ raw: String) -> [ParsedUtterance] {
        var result: [ParsedUtterance] = []
        let blocks = raw.components(separatedBy: "\n\n")
        for block in blocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lines = trimmed.components(separatedBy: "\n")
            guard let firstLine = lines.first else { continue }
            let ns = firstLine as NSString
            guard let match = headerRegex?.firstMatch(in: firstLine, range: NSRange(location: 0, length: ns.length)) else { continue }
            let speaker = ns.substring(with: match.range(at: 1))
            let time = ns.substring(with: match.range(at: 2))
            let text = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            result.append(ParsedUtterance(speaker: speaker, isYou: speaker == "You", time: time, text: text))
        }
        return result
    }
}

// MARK: - Parsed Bubble

private struct ParsedBubble: View {
    let utterance: ParsedUtterance

    private var accentColor: Color {
        utterance.isYou ? .accent1 : .fg2
    }

    var body: some View {
        HStack {
            if utterance.isYou { Spacer() }

            VStack(alignment: .leading, spacing: 4) {
                Text(utterance.speaker)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(accentColor)

                Text(utterance.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.fg1)
                    .textSelection(.enabled)

                Text(utterance.time)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.fg3)
            }
            .padding(10)
            .frame(maxWidth: 360, alignment: .leading)
            .background(Color.bg1.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor)))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                    .fill(accentColor)
                    .frame(width: 3)
            }

            if !utterance.isYou { Spacer() }
        }
    }
}

// MARK: - Transcript Picker

struct TranscriptPickerView: View {
    let meetingsPath: String
    let voicePath: String
    let onSelect: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var meetingFiles: [TranscriptFile] = []
    @State private var voiceFiles: [TranscriptFile] = []
    @State private var typeFilter: TypeFilter = .all
    @State private var dateFilter: DateFilter = .allTime

    enum TypeFilter: String, CaseIterable {
        case all = "All"
        case meetings = "Meetings"
        case voice = "Voice Memos"
    }

    enum DateFilter: String, CaseIterable {
        case allTime = "All Time"
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
    }

    struct TranscriptFile: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
        let modifiedDate: Date
        let fileSize: Int
    }

    private var filteredMeetings: [TranscriptFile] {
        guard typeFilter != .voice else { return [] }
        return meetingFiles.filter { matchesDate($0.modifiedDate) }
    }

    private var filteredVoice: [TranscriptFile] {
        guard typeFilter != .meetings else { return [] }
        return voiceFiles.filter { matchesDate($0.modifiedDate) }
    }

    private var isEmpty: Bool { filteredMeetings.isEmpty && filteredVoice.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Open Transcript")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Filter bar
            HStack(spacing: 10) {
                Picker("", selection: $typeFilter) {
                    ForEach(TypeFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Spacer()

                Picker("", selection: $dateFilter) {
                    ForEach(DateFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 120)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(meetingFiles.isEmpty && voiceFiles.isEmpty
                         ? "No transcripts found"
                         : "No results for this filter")
                        .font(.system(size: 13, weight: .semibold))
                    Text(meetingFiles.isEmpty && voiceFiles.isEmpty
                         ? "Transcripts will appear here after you record a session."
                         : "Try changing the type or date filter.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    if !filteredMeetings.isEmpty {
                        Section {
                            ForEach(filteredMeetings) { fileRow($0) }
                        } header: {
                            Label("Meetings", systemImage: "person.2")
                        }
                    }
                    if !filteredVoice.isEmpty {
                        Section {
                            ForEach(filteredVoice) { fileRow($0) }
                        } header: {
                            Label("Voice Memos", systemImage: "mic")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 520, height: 460)
        .onAppear { loadFiles() }
    }

    private func fileRow(_ file: TranscriptFile) -> some View {
        Button {
            onSelect(file.url)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(file.modifiedDate, style: .date)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatSize(file.fileSize))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func matchesDate(_ date: Date) -> Bool {
        let cal = Calendar.current
        switch dateFilter {
        case .allTime:   return true
        case .today:     return cal.isDateInToday(date)
        case .thisWeek:  return cal.isDate(date, equalTo: .now, toGranularity: .weekOfYear)
        case .thisMonth: return cal.isDate(date, equalTo: .now, toGranularity: .month)
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    }

    private func loadFiles() {
        meetingFiles = transcriptFiles(in: meetingsPath)
        voiceFiles = transcriptFiles(in: voicePath)
    }

    private func transcriptFiles(in path: String) -> [TranscriptFile] {
        guard !path.isEmpty else { return [] }
        let dir = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: keys,
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasSuffix(" summary.md") }
            .compactMap { url -> TranscriptFile? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let date = values?.contentModificationDate ?? .distantPast
                let size = values?.fileSize ?? 0
                return TranscriptFile(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    modifiedDate: date,
                    fileSize: size
                )
            }
            .sorted { $0.modifiedDate > $1.modifiedDate }
    }
}
