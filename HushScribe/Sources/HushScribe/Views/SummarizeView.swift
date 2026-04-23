import SwiftUI
import AppKit

struct SummarizeView: View {
    @Bindable var settings: AppSettings
    let logger: TranscriptLogger

    // Content
    @State private var transcriptURL: URL?
    @State private var transcriptText = ""
    @State private var parsedUtterances: [ParsedUtterance] = []

    // Summary
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

    // UI
    @State private var showSidebar = false
    @State private var sidebarWidth: CGFloat = 240
    @State private var activeTab: ActiveTab = .transcript
    @State private var copyTranscriptConfirmed = false
    @State private var copySummaryConfirmed = false

    enum ActiveTab { case transcript, summary }

    init(initialURL: URL? = nil, settings: AppSettings, logger: TranscriptLogger) {
        self.settings = settings
        self.logger = logger
        self._transcriptURL = State(initialValue: initialURL)
    }

    // MARK: - Derived

    private var tabMetaLabel: String {
        guard let url = transcriptURL else { return "" }
        let name = url.deletingPathExtension().lastPathComponent
        if let first = parsedUtterances.first?.time,
           let last = parsedUtterances.last?.time,
           first != last {
            return "\(name) · \(first) – \(last)"
        }
        return name
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                if showSidebar {
                    LibrarySidebar(
                        meetingsPath: settings.vaultMeetingsPath,
                        voicePath: settings.vaultVoicePath,
                        selectedURL: transcriptURL,
                        onSelect: { url in
                            selectTranscript(url)
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                showSidebar = false
                            }
                        },
                        onDelete: { url in
                            if transcriptURL == url {
                                transcriptURL = nil
                                transcriptText = ""
                                parsedUtterances = []
                                summary = nil
                                summaryGeneratedBy = nil
                            }
                        }
                    )
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    // Drag handle
                    SidebarResizeHandle(sidebarWidth: $sidebarWidth)
                }

                VStack(spacing: 0) {
                    if transcriptURL != nil {
                        tabsRow
                    }
                    if transcriptURL == nil {
                        emptyState
                    } else if activeTab == .transcript {
                        transcriptPanel
                    } else {
                        summaryPanel
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 440)
        .onAppear {
            if let url = transcriptURL {
                loadTranscript(from: url)
                loadSavedSummaryIfPresent(for: url)
            }
        }
        .alert("Overwrite existing summary?", isPresented: $showOverwriteAlert, presenting: pendingSummaryURL) { summaryURL in
            Button("Overwrite", role: .destructive) {
                Task { await performWrite(summaryURL: summaryURL) }
            }
            Button("Cancel", role: .cancel) { pendingSummaryURL = nil }
        } message: { summaryURL in
            Text("\"\(summaryURL.lastPathComponent)\" already exists. Do you want to replace it?")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Browse toggle
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    showSidebar.toggle()
                }
            } label: {
                Label("Browse", systemImage: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(ToolbarGhostStyle(isActive: showSidebar))

            Spacer()

            // Export
            Menu {
                Button("Export as Markdown") { exportTranscript(format: .markdown) }
                Button("Export as SRT") { exportTranscript(format: .srt) }
                Button("Export as JSON") { exportTranscript(format: .json) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.bg1.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor)))
            .disabled(parsedUtterances.isEmpty && transcriptText.isEmpty)

            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1, height: 18)

            // Model picker + optional warning
            HStack(spacing: 4) {
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
                .frame(width: 150)
                .disabled(isGenerating)

                if settings.summaryModel.isBuiltIn {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .help("Results are usually not satisfactory. Use Qwen3, Gemma 3, or Gemma 4.")
                }
            }

            // Generate button — menu when custom prompts exist
            let namedCustoms = settings.customSummaryPrompts.enumerated()
                .filter { !$0.element.isEmpty }
            let hasCustomPrompts = !settings.summaryModel.isBuiltIn && !namedCustoms.isEmpty

            if isGenerating {
                Button {} label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        let status = LLMSummaryEngine.shared.generationStatus
                        Text(status.isEmpty ? "Generating" : status)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(true)
            } else if hasCustomPrompts {
                Menu {
                    Button { generate(promptSelection: .default) } label: {
                        Label("Default Summary", systemImage: "sparkles")
                    }
                    Divider()
                    ForEach(Array(namedCustoms), id: \.offset) { i, prompt in
                        Button(prompt.name) { generate(promptSelection: .custom(i)) }
                    }
                } label: {
                    Label("Generate Summary", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .disabled(transcriptText.isEmpty)
            } else {
                Button { generate(promptSelection: .default) } label: {
                    Label("Generate Summary", systemImage: "sparkles")
                }
                .font(.system(size: 12, weight: .medium))
                .controlSize(.small)
                .disabled(transcriptText.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Tabs Row

    private var tabsRow: some View {
        HStack(spacing: 2) {
            // Transcript tab — always visible
            tabButton(
                icon: "doc.text",
                label: "Transcript",
                badge: nil,
                isActive: activeTab == .transcript,
                isPulsing: false
            ) {
                activeTab = .transcript
            }

            // AI Summary tab — only after generating/generated
            if summary != nil || isGenerating {
                let summaryLabel = summaryGeneratedBy.map { "AI Summary · \($0.displayName)" } ?? "AI Summary"
                tabButton(
                    icon: "sparkles",
                    label: summaryLabel,
                    badge: nil,
                    isActive: activeTab == .summary,
                    isPulsing: isGenerating
                ) {
                    activeTab = .summary
                }
            }

            Spacer()

            if !tabMetaLabel.isEmpty {
                Text(tabMetaLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.fg3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.bg1.opacity(0.4))
        .overlay(Divider(), alignment: .bottom)
    }

    private func tabButton(
        icon: String,
        label: String,
        badge: String?,
        isActive: Bool,
        isPulsing: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                if let badge {
                    Text("· \(badge)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.fg3)
                }
                if isPulsing {
                    Circle()
                        .fill(Color.accent1)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                isActive
                    ? Color.bg0
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                isActive
                    ? RoundedRectangle(cornerRadius: 5).stroke(Color(NSColor.separatorColor))
                    : nil
            )
            .foregroundStyle(isActive ? Color.fg1 : Color.fg2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

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
            Button("Browse") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    showSidebar = true
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Transcript Panel

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                    Text("Transcript")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    copyTranscript()
                } label: {
                    Label(
                        copyTranscriptConfirmed ? "Copied" : "Copy",
                        systemImage: copyTranscriptConfirmed ? "checkmark" : "doc.on.doc"
                    )
                    .foregroundStyle(copyTranscriptConfirmed ? .green : Color.accent1)
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .disabled(transcriptText.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 20)

            if transcriptText.isEmpty {
                Text("Loading…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !parsedUtterances.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(parsedUtterances) { ParsedBubble(utterance: $0) }
                    }
                    .padding(.bottom, 16)
                }
            } else {
                ScrollView {
                    Text(transcriptText)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Summary Panel

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack(spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accent1)
                    Text("Summary")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)

                Spacer()

                if thinkingContent != nil {
                    Button { showThinking = true } label: {
                        Label("Thinking", systemImage: "brain")
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accent1)
                }

                if !isGenerating {
                    Button {
                        summary = nil
                        summaryGeneratedBy = nil
                        thinkingContent = nil
                        generate(promptSelection: .default)
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Button { copySummary() } label: {
                    Label(
                        copySummaryConfirmed ? "Copied" : "Copy",
                        systemImage: copySummaryConfirmed ? "checkmark" : "doc.on.doc"
                    )
                    .foregroundStyle(copySummaryConfirmed ? .green : .secondary)
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .disabled(summary == nil)

                Button { Task { await save() } } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else if savedConfirmation {
                        Label("Saved · \(savedFilename)", systemImage: "checkmark")
                            .foregroundStyle(.green)
                    } else {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .disabled(isSaving || savedConfirmation || summary == nil)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { summaryRendered.toggle() }
                } label: {
                    Image(systemName: summaryRendered ? "text.alignleft" : "doc.richtext")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(summaryRendered ? "Show plain text" : "Show markdown preview")
                .disabled(summary == nil)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 20)

            if isGenerating && summary == nil {
                SummaryShimmer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
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
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .textSelection(.enabled)

                        if let model = summaryGeneratedBy {
                            Divider()
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                            Text("Generated by \(model.displayName)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.fg3)
                                .padding(.horizontal, 20)
                                .padding(.top, 10)
                                .padding(.bottom, 16)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showThinking) {
            ThinkingSheetView(content: thinkingContent ?? "")
        }
        .alert("Overwrite existing summary?", isPresented: $showOverwriteAlert, presenting: pendingSummaryURL) { summaryURL in
            Button("Overwrite", role: .destructive) {
                Task { await performWrite(summaryURL: summaryURL) }
            }
            Button("Cancel", role: .cancel) { pendingSummaryURL = nil }
        } message: { summaryURL in
            Text("\"\(summaryURL.lastPathComponent)\" already exists. Do you want to replace it?")
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
        activeTab = .transcript
        loadTranscript(from: url)
        loadSavedSummaryIfPresent(for: url)
        NSApp.keyWindow?.title = "Transcript Viewer — \(url.deletingPathExtension().lastPathComponent)"
    }

    private func loadSavedSummaryIfPresent(for url: URL) {
        let summaryURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) summary.md")
        guard FileManager.default.fileExists(atPath: summaryURL.path) else { return }
        Task.detached {
            guard let content = try? String(contentsOf: summaryURL, encoding: .utf8) else { return }
            await MainActor.run {
                summary = content
                summaryGeneratedBy = nil   // model unknown for saved summaries
            }
        }
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

    private func generate(promptSelection: SummaryPromptSelection = .default) {
        isGenerating = true
        savedConfirmation = false
        savedFilename = ""
        summaryRendered = true
        thinkingContent = nil
        summaryGeneratedBy = nil
        summary = nil
        let text = transcriptText
        let chosenModel = settings.summaryModel
        let llm = LLMSummaryEngine.shared
        let chosenSystemPrompt: String? = {
            guard case .custom(let i) = promptSelection,
                  i < settings.customSummaryPrompts.count,
                  !settings.customSummaryPrompts[i].body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return settings.customSummaryPrompts[i].body
        }()

        withAnimation(.easeInOut(duration: 0.15)) { activeTab = .summary }

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

    private func isPromptEcho(_ result: String, prompt: String, isCustomPrompt: Bool) -> Bool {
        let r = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty { return true }
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if r == p || p.contains(r) { return true }
        if isCustomPrompt {
            let prefix = String(p.prefix(50))
            if !prefix.isEmpty && r.hasPrefix(prefix) { return true }
        } else {
            for marker in ["**Highlights**", "**To-Dos**"] {
                if let range = p.range(of: marker) {
                    let section = String(p[range.lowerBound...].prefix(30))
                    if !section.isEmpty && r.contains(section) { return true }
                }
            }
        }
        return false
    }

    private func copyTranscript() {
        let text: String
        if !parsedUtterances.isEmpty {
            text = parsedUtterances.map { "[\($0.time)] \($0.speaker): \($0.text)" }.joined(separator: "\n\n")
        } else {
            text = transcriptText
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { copyTranscriptConfirmed = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { withAnimation { copyTranscriptConfirmed = false } }
        }
    }

    private func copySummary() {
        guard let s = summary else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        withAnimation { copySummaryConfirmed = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { withAnimation { copySummaryConfirmed = false } }
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
        await logger.writeSummaryFile(s, for: transcriptURL, model: summaryGeneratedBy?.displayName)
        isSaving = false
        savedFilename = summaryURL.lastPathComponent
        withAnimation { savedConfirmation = true }
    }

    // MARK: - Export

    private enum ExportFormat { case srt, json, markdown }

    private func exportTranscript(format: ExportFormat) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let baseName = transcriptURL?.deletingPathExtension().lastPathComponent ?? "transcript"
        switch format {
        case .markdown:
            panel.nameFieldStringValue = "\(baseName).md"
            panel.allowedContentTypes = [.init(filenameExtension: "md")!]
            panel.title = "Export as Markdown"
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
        case .markdown: content = buildMarkdown()
        case .srt:      content = buildSRT()
        case .json:     content = buildJSON()
        }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func buildMarkdown() -> String {
        let title = transcriptURL?.deletingPathExtension().lastPathComponent ?? "Transcript"
        var lines: [String] = ["# \(title)", ""]
        if !parsedUtterances.isEmpty {
            for utt in parsedUtterances {
                lines.append("**\(utt.speaker)** `\(utt.time)`")
                lines.append("")
                lines.append(utt.text)
                lines.append("")
            }
        } else {
            lines.append(transcriptText)
        }
        return lines.joined(separator: "\n")
    }

    private func buildSRT() -> String {
        guard !parsedUtterances.isEmpty else {
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

    // MARK: - Window Factory

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
        window.setContentSize(NSSize(width: 720, height: 580))
        window.minSize = NSSize(width: 520, height: 440)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if url == nil { sharedWindow = window }
    }
}

// MARK: - Sidebar Resize Handle

private struct SidebarResizeHandle: View {
    @Binding var sidebarWidth: CGFloat
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(isHovered ? Color.accent1.opacity(0.4) : Color(NSColor.separatorColor))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newWidth = sidebarWidth + value.translation.width
                        sidebarWidth = max(180, min(400, newWidth))
                    }
            )
            .padding(.horizontal, 3)
    }
}

// MARK: - Toolbar Ghost Button Style

private struct ToolbarGhostStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isActive ? Color.accent1.opacity(0.12) : (configuration.isPressed ? Color.bg1 : Color.clear))
            .foregroundStyle(isActive ? Color.accent1 : Color.fg2)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isActive ? Color.accent1.opacity(0.3) : Color(NSColor.separatorColor)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Summary Shimmer

private struct SummaryShimmer: View {
    @State private var animating = false

    private let rows: [(CGFloat, Bool)] = [
        (0.35, true), (0.90, false), (0.82, false), (0.70, false),
        (0.42, true), (0.88, false), (0.60, false), (0.76, false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                RoundedRectangle(cornerRadius: 3)
                    .foregroundStyle(Color(NSColor.separatorColor).opacity(animating ? 0.45 : 0.2))
                    .frame(height: row.1 ? 10 : 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: row.0, anchor: .leading)
            }
        }
        .padding(20)
        .animation(
            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
            value: animating
        )
        .onAppear { animating = true }
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
    private var accentColor: Color { utterance.isYou ? .accent1 : .fg2 }

    var body: some View {
        if utterance.isYou {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(utterance.time)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.fg3)
                        Text(utterance.speaker)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
                    Text(utterance.text)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.fg1)
                        .textSelection(.enabled)
                        .lineSpacing(1.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accent1.opacity(0.09))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(utterance.speaker)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)
                    Text(utterance.time)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.fg3)
                }
                Text(utterance.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fg1)
                    .textSelection(.enabled)
                    .lineSpacing(1.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Library Sidebar

private struct LibrarySidebar: View {
    let meetingsPath: String
    let voicePath: String
    let selectedURL: URL?
    let onSelect: (URL) -> Void
    let onDelete: (URL) -> Void

    @State private var allFiles: [SidebarFile] = []
    @State private var searchText = ""
    @State private var deleteArmedURL: URL? = nil

    struct SidebarFile: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
        let modifiedDate: Date
        let hasSummary: Bool
    }

    private var filteredFiles: [SidebarFile] {
        guard !searchText.isEmpty else { return allFiles }
        return allFiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var groups: [(label: String, files: [SidebarFile])] {
        let cal = Calendar.current
        let now = Date()
        var today: [SidebarFile] = []
        var yesterday: [SidebarFile] = []
        var thisWeek: [SidebarFile] = []
        var older: [SidebarFile] = []
        for f in filteredFiles {
            if cal.isDateInToday(f.modifiedDate) { today.append(f) }
            else if cal.isDateInYesterday(f.modifiedDate) { yesterday.append(f) }
            else if cal.isDate(f.modifiedDate, equalTo: now, toGranularity: .weekOfYear) { thisWeek.append(f) }
            else { older.append(f) }
        }
        return [
            ("Today", today), ("Yesterday", yesterday),
            ("This Week", thisWeek), ("Earlier", older)
        ].filter { !$0.files.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.fg3)
                TextField("Search…", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.fg3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.bg0)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor)))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)

            Divider().padding(.top, 6)

            if allFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.fg3)
                    Text("No transcripts")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                Text("No results")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.label) { group in
                            Text(group.label)
                                .font(.system(size: 10, weight: .semibold))
                                .textCase(.uppercase)
                                .tracking(0.06)
                                .foregroundStyle(Color.fg3)
                                .padding(.horizontal, 10)
                                .padding(.top, 10)
                                .padding(.bottom, 4)

                            ForEach(group.files) { file in
                                SidebarRow(
                                    file: file,
                                    isSelected: selectedURL == file.url,
                                    isDeleteArmed: deleteArmedURL == file.url,
                                    onSelect: { onSelect(file.url) },
                                    onDeleteTap: { handleDeleteTap(file) }
                                )
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.bg1.opacity(0.6))
        .onAppear { loadFiles() }
    }

    private func handleDeleteTap(_ file: SidebarFile) {
        if deleteArmedURL == file.url {
            try? FileManager.default.removeItem(at: file.url)
            let summaryURL = file.url.deletingLastPathComponent()
                .appendingPathComponent("\(file.url.deletingPathExtension().lastPathComponent) summary.md")
            try? FileManager.default.removeItem(at: summaryURL)
            deleteArmedURL = nil
            onDelete(file.url)
            loadFiles()
        } else {
            deleteArmedURL = file.url
            Task {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    if deleteArmedURL == file.url { deleteArmedURL = nil }
                }
            }
        }
    }

    private func loadFiles() {
        var files: [SidebarFile] = []
        files += transcriptFiles(in: meetingsPath)
        files += transcriptFiles(in: voicePath)
        allFiles = files.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    private func transcriptFiles(in path: String) -> [SidebarFile] {
        guard !path.isEmpty else { return [] }
        let dir = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: .skipsHiddenFiles
        ) else { return [] }
        return contents
            .filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasSuffix(" summary.md") }
            .compactMap { url -> SidebarFile? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let date = values?.contentModificationDate ?? .distantPast
                let summaryURL = url.deletingLastPathComponent()
                    .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) summary.md")
                let hasSummary = FileManager.default.fileExists(atPath: summaryURL.path)
                return SidebarFile(url: url, name: url.deletingPathExtension().lastPathComponent,
                                   modifiedDate: date, hasSummary: hasSummary)
            }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let file: LibrarySidebar.SidebarFile
    let isSelected: Bool
    let isDeleteArmed: Bool
    let onSelect: () -> Void
    let onDeleteTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.fg1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 4) {
                        Text(file.modifiedDate, style: .date)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.fg3)
                        if file.hasSummary {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.accent1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHovered || isDeleteArmed {
                Button(action: onDeleteTap) {
                    if isDeleteArmed {
                        Text("Delete?")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.fg3)
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected
                    ? Color.bg0
                    : (isHovered ? Color.bg0.opacity(0.6) : Color.clear))
        )
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor))
                : nil
        )
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isDeleteArmed)
    }
}

// MARK: - Transcript Picker (kept for any external references)

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

    var body: some View {
        VStack(spacing: 0) {
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
            if filteredFiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(meetingFiles.isEmpty && voiceFiles.isEmpty ? "No transcripts found" : "No results for this filter")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(filteredFiles, id: \.file.id) { entry in
                        Button { onSelect(entry.file.url); dismiss() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: entry.isMeeting ? "person.2" : "mic")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.file.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text(entry.file.modifiedDate, style: .date)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 520, height: 460)
        .onAppear { loadFiles() }
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

    private func loadFiles() {
        meetingFiles = transcriptFiles(in: meetingsPath)
        voiceFiles = transcriptFiles(in: voicePath)
    }

    private func transcriptFiles(in path: String) -> [TranscriptFile] {
        guard !path.isEmpty else { return [] }
        let dir = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: .skipsHiddenFiles
        ) else { return [] }
        return contents
            .filter { $0.pathExtension == "md" && !$0.lastPathComponent.hasSuffix(" summary.md") }
            .compactMap { url -> TranscriptFile? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let date = values?.contentModificationDate ?? .distantPast
                let size = values?.fileSize ?? 0
                return TranscriptFile(url: url, name: url.deletingPathExtension().lastPathComponent,
                                      modifiedDate: date, fileSize: size)
            }
            .sorted { $0.modifiedDate > $1.modifiedDate }
    }
}
