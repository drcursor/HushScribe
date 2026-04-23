import SwiftUI
import AppKit

struct SummarizeView: View {
    @Bindable var settings: AppSettings
    let logger: TranscriptLogger

    @State private var transcriptURL: URL?
    @State private var transcriptText = ""
    @State private var parsedUtterances: [ParsedUtterance] = []
    @State private var summary: String? = nil
    @State private var summaryGeneratedBy: SummaryModel? = nil
    @State private var thinkingContent: String? = nil
    @State private var showThinking = false
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
                        Text(summaryGeneratedBy.map { "AI Summary · \($0.displayName)" } ?? "AI Summary")
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
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Generate + Export + Browse
            HStack(spacing: 10) {
                Button {
                    generate()
                } label: {
                    if isGenerating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            let status = LLMSummaryEngine.shared.generationStatus
                            Text(status.isEmpty ? "Generating…" : status)
                        }
                    } else {
                        Label("Generate Summary", systemImage: "sparkles")
                    }
                }
                .disabled(isGenerating || transcriptText.isEmpty)

                Menu {
                    Button("Export as SRT") { exportTranscript(format: .srt) }
                    Button("Export as JSON") { exportTranscript(format: .json) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(parsedUtterances.isEmpty && transcriptText.isEmpty)
                .fixedSize()

                Spacer()

                Button {
                    showPicker = true
                } label: {
                    Label("Browse Transcripts", systemImage: "doc.badge.plus")
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Row 2: Model picker + inline warning or prompt picker
            HStack(spacing: 8) {
                Picker("", selection: $settings.summaryModel) {
                    ForEach(SummaryModel.allCases, id: \.self) { model in
                        Group {
                            if !model.isBuiltIn && !LLMSummaryEngine.shared.isModelDownloaded(model) {
                                Text("\(model.displayName) · not downloaded")
                            } else {
                                Text(model.displayName)
                            }
                        }
                        .tag(model)
                    }
                }
                .frame(width: 200)
                .disabled(isGenerating)

                if settings.summaryModel.isBuiltIn {
                    // Inline Apple NL warning
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Results are usually not satisfactory. Use Qwen3, Gemma 3, or Gemma 4.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                } else {
                    // Prompt picker — default + named custom prompts
                    let namedCustoms = settings.customSummaryPrompts.enumerated()
                        .filter { !$0.element.isEmpty }
                    if !namedCustoms.isEmpty || settings.selectedSummaryPrompt != .default {
                        Picker("", selection: $settings.selectedSummaryPrompt) {
                            Text("Default prompt").tag(SummaryPromptSelection.default)
                            ForEach(Array(namedCustoms), id: \.offset) { i, prompt in
                                Text(prompt.name).tag(SummaryPromptSelection.custom(i))
                            }
                        }
                        .frame(width: 160)
                        .disabled(isGenerating)
                    }
                }

                Spacer()
            }
            .padding(.bottom, 8)
            .padding(.leading, -22) // manual alignment, avoid changing!
        }
        .padding(.horizontal, 14)
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

                if thinkingContent != nil {
                    Button {
                        showThinking = true
                    } label: {
                        Label("Thinking", systemImage: "brain")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accent1)
                    }
                    .buttonStyle(.plain)
                }

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
        .sheet(isPresented: $showThinking) {
            ThinkingSheetView(content: thinkingContent ?? "")
        }
    }

    // MARK: - Actions

    private func selectTranscript(_ url: URL) {
        transcriptURL = url
        transcriptText = ""
        parsedUtterances = []
        summary = nil
        summaryGeneratedBy = nil
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
        thinkingContent = nil
        summaryGeneratedBy = nil
        let text = transcriptText
        let chosenModel = settings.summaryModel
        let llm = LLMSummaryEngine.shared
        let chosenSystemPrompt: String? = {
            guard case .custom(let i) = settings.selectedSummaryPrompt,
                  i < settings.customSummaryPrompts.count,
                  !settings.customSummaryPrompts[i].body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return settings.customSummaryPrompts[i].body
        }()

        Task {
            if chosenModel.isBuiltIn {
                let result = await Task.detached { SummaryService.summarize(transcript: text) }.value
                summary = result
                summaryGeneratedBy = chosenModel
                isGenerating = false
            } else {
                do {
                    try await llm.loadContainer(for: chosenModel)
                    let effectivePrompt = chosenSystemPrompt ?? LLMSummaryEngine.defaultSystemPrompt
                    let isCustomPrompt = chosenSystemPrompt != nil
                    var output = try await llm.summarize(transcript: text, temperature: Float(settings.summaryTemperature), maxTokens: settings.summaryMaxTokens, systemPrompt: chosenSystemPrompt)
                    var attempts = 1
                    while isPromptEcho(output.summary, prompt: effectivePrompt, isCustomPrompt: isCustomPrompt), attempts < 5 {
                        output = try await llm.summarize(transcript: text, temperature: Float(settings.summaryTemperature), maxTokens: settings.summaryMaxTokens, systemPrompt: chosenSystemPrompt)
                        attempts += 1
                    }
                    summary = output.summary
                    summaryGeneratedBy = chosenModel
                    thinkingContent = output.thinking
                } catch {
                    summary = "Summary generation failed: \(error.localizedDescription)"
                }
                isGenerating = false
            }
        }
    }

    /// Returns true if the model echoed back the system prompt instead of summarising.
    private func isPromptEcho(_ result: String, prompt: String, isCustomPrompt: Bool) -> Bool {
        let r = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty { return true }
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if r == p || p.contains(r) { return true }

        if isCustomPrompt {
            // Custom prompt: check if result starts with the first 60 chars of the prompt
            let prefix = String(p.prefix(50))
            if !prefix.isEmpty && r.hasPrefix(prefix) { return true }
        } else {
            // Default system prompt: check the first 60 chars of the Highlights and To-Dos sections
            for marker in ["**Highlights**", "**To-Dos**"] {
                if let range = p.range(of: marker) {
                    let section = String(p[range.lowerBound...].prefix(30))
                    if !section.isEmpty && r.contains(section) { return true }
                }
            }
        }
        return false
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

    // MARK: - Export

    private enum ExportFormat { case srt, json }

    private func exportTranscript(format: ExportFormat) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let baseName = transcriptURL?.deletingPathExtension().lastPathComponent ?? "transcript"
        switch format {
        case .srt:
            panel.nameFieldStringValue = "\(baseName).srt"
            panel.allowedContentTypes = [.init(filenameExtension: "srt")!]
            panel.title = "Export as SRT"
        case .json:
            panel.nameFieldStringValue = "\(baseName).json"
            panel.allowedContentTypes = [.json]
            panel.title = "Export as JSON"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content: String
        switch format {
        case .srt:  content = buildSRT()
        case .json: content = buildJSON()
        }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func buildSRT() -> String {
        guard !parsedUtterances.isEmpty else {
            // Fallback: plain text as a single subtitle entry
            return "1\n00:00:00,000 --> 00:00:01,000\n\(transcriptText)\n"
        }
        var lines: [String] = []
        for (i, utt) in parsedUtterances.enumerated() {
            let start = srtTimestamp(utt.time)
            let endSeconds = (i + 1 < parsedUtterances.count)
                ? secondsFromTime(parsedUtterances[i + 1].time)
                : secondsFromTime(utt.time) + 5
            let end = srtTimestampFromSeconds(endSeconds)
            lines.append("\(i + 1)\n\(start) --> \(end)\n\(utt.speaker): \(utt.text)")
        }
        return lines.joined(separator: "\n\n") + "\n"
    }

    private func buildJSON() -> String {
        var obj: [String: Any] = [:]
        if let url = transcriptURL {
            obj["file"] = url.deletingPathExtension().lastPathComponent
        }
        if !parsedUtterances.isEmpty {
            obj["utterances"] = parsedUtterances.enumerated().map { i, u in
                ["index": i + 1, "speaker": u.speaker, "time": u.time, "text": u.text]
            }
        } else {
            obj["text"] = transcriptText
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func secondsFromTime(_ time: String) -> Int {
        let parts = time.components(separatedBy: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return 0
        }
    }

    private func srtTimestamp(_ time: String) -> String {
        srtTimestampFromSeconds(secondsFromTime(time))
    }

    private func srtTimestampFromSeconds(_ total: Int) -> String {
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d,000", h, m, s)
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

// MARK: - Thinking Sheet

private struct ThinkingSheetView: View {
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Thinking", systemImage: "brain")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                Text(content)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
        }
        .frame(width: 560, height: 400)
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

    private var filteredFiles: [(file: TranscriptFile, isMeeting: Bool)] {
        var result: [(TranscriptFile, Bool)] = []
        if typeFilter != .voice {
            result += meetingFiles.filter { matchesDate($0.modifiedDate) }.map { ($0, true) }
        }
        if typeFilter != .meetings {
            result += voiceFiles.filter { matchesDate($0.modifiedDate) }.map { ($0, false) }
        }
        return result.sorted { $0.0.modifiedDate > $1.0.modifiedDate }
    }

    private var isEmpty: Bool { filteredFiles.isEmpty }

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
                    ForEach(filteredFiles, id: \.file.id) { entry in
                        fileRow(entry.file, isMeeting: entry.isMeeting)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 520, height: 460)
        .onAppear { loadFiles() }
    }

    private func fileRow(_ file: TranscriptFile, isMeeting: Bool) -> some View {
        Button {
            onSelect(file.url)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isMeeting ? "person.2" : "mic")
                    .font(.system(size: 12))
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
