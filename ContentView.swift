import SwiftUI
import Foundation
import Combine

// MARK: - Models
struct Repository: Identifiable, Codable {
    var id: UUID
    let path: String
    var isEnabled: Bool = true
    
    init(id: UUID = UUID(), path: String, isEnabled: Bool = true) {
        self.id = id
        self.path = path
        self.isEnabled = isEnabled
    }
}

struct CommitStatistics {
    var totalCommits: Int = 0
    var fileCommits: [String: Int] = [:]
    var lastCommitDate: Date?
    var commitHistory: [Date] = []
}

struct LogEntry: Identifiable, Codable {
    let id: String
    let message: String
}

// MARK: - Git Manager
class GitManager: ObservableObject {
    @Published var repositories: [Repository] = []
    @Published var stats = CommitStatistics()
    @Published var isProcessing = false
    @Published var logs: [LogEntry] = []
    
    private let fileManager = FileManager.default
    private var processingTask: Task<Void, Never>?
    
    private let repositoriesKey = "savedRepositories"
    
    init() {
        loadRepositories()
        loadSavedRepositories()
    }
    
    func loadRepositories() {
        loadSavedRepositories()
    }
    
    func loadSavedRepositories() {
        if let data = UserDefaults.standard.data(forKey: repositoriesKey),
           let savedRepos = try? JSONDecoder().decode([Repository].self, from: data) {
            repositories = savedRepos
            addLog("Loaded saved repositories: \(savedRepos.map { $0.path })")
        } else {
            addLog("No saved repositories found, using default paths")
            let defaultPaths = [
                "/Users/s2xdeb/Desktop/g/и/SQL-50-LeetCode",
                "/Users/s2xdeb/Desktop/ed_g/pythhon"
            ]
            repositories = defaultPaths.map { Repository(path: $0) }
            saveRepositories()
        }
    }
    
    func saveRepositories() {
        if let data = try? JSONEncoder().encode(repositories) {
            UserDefaults.standard.set(data, forKey: repositoriesKey)
        }
    }
    
    func getComment(for language: String) -> String {
        let comments = [
            "python": "# Refactored function for better performance",
            "sql": "-- Optimized query for faster response",
            "cpp": "// Improved memory management",
            "kotlin": "// Enhanced null-safety check",
            "swift": "// Updated UI component initialization"
        ]
        return comments[language] ?? "# General update"
    }
    
    func getLanguage(from path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "py": return "python"
        case "sql": return "sql"
        case "cpp", "hpp", "cxx", "h": return "cpp"
        case "kt", "kts": return "kotlin"
        case "swift": return "swift"
        default: return "unknown"
        }
    }
    
    func makeMinimalChange(to filePath: String) -> Bool {
        guard fileManager.fileExists(atPath: filePath) else {
            addLog("File \(filePath) doesn't exist")
            return false
        }
        
        do {
            let content = try String(contentsOf: URL(fileURLWithPath: filePath), encoding: .utf8)
            let language = getLanguage(from: filePath)
            let timestamp = Date().formatted(.dateTime)
            let comment = getComment(for: language)
            
            var lines = content.components(separatedBy: .newlines)
            let insertPosition = Int.random(in: 0...max(lines.count - 1, 0))
            lines.insert("\n\(comment) - \(timestamp)\n", at: insertPosition)
            
            try lines.joined().write(to: URL(fileURLWithPath: filePath), atomically: true, encoding: .utf8)
            addLog("Modified file: \(filePath)")
            return true
        } catch {
            addLog("Error modifying file \(filePath): \(error.localizedDescription)")
            return false
        }
    }
    
    func gitCommit(repoPath: String, message: String) -> Bool {
        do {
            let supportedExts: Set<String> = [".py", ".sql", ".cpp", ".hpp", ".cxx", ".h", ".kt", ".kts", ".swift"]
            let allFiles = try findFiles(in: repoPath, withExtensions: supportedExts)
            
            addLog("Found files in \(repoPath): \(allFiles)")
            guard !allFiles.isEmpty else {
                addLog("No supported files found in \(repoPath)")
                return false
            }
            
            guard let fileToChange = allFiles.randomElement() else {
                addLog("No files to change in \(repoPath)")
                return false
            }
            
            guard makeMinimalChange(to: fileToChange) else { return false }
            
            let commands = [
                ["git", "add", "."],
                ["git", "commit", "-m", message],
                ["git", "push"]
            ]
            
            for cmd in commands {
                let shell = Process()
                shell.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                shell.currentDirectoryURL = URL(fileURLWithPath: repoPath)
                shell.arguments = cmd
                
                try shell.run()
                shell.waitUntilExit()
                if shell.terminationStatus != 0 {
                    addLog("Git command failed: \(cmd.joined(separator: " ")) with status \(shell.terminationStatus)")
                    return false
                }
            }
            
            updateStats(filePath: fileToChange)
            return true
        } catch {
            addLog("Error in git commit: \(error.localizedDescription)")
            return false
        }
    }
    
    private func findFiles(in directory: String, withExtensions extensions: Set<String>) throws -> [String] {
        var files: [String] = []
        let enumerator = fileManager.enumerator(atPath: directory)
        
        while let file = enumerator?.nextObject() as? String {
            let fullPath = (directory as NSString).appendingPathComponent(file)
            let ext = (file as NSString).pathExtension.lowercased()
            if extensions.contains(".\(ext)") {
                files.append(fullPath)
            }
        }
        
        return files
    }
    
    func processRepositories(totalCommits: Int?) {
        guard !isProcessing else {
            addLog("Processing already in progress, please wait...")
            return
        }
        
        isProcessing = true
        processingTask = Task { [weak self] in
            guard let self = self else { return }
            
            let availableRepos = self.repositories.filter { $0.isEnabled && self.checkAccess(path: $0.path) }
            guard !availableRepos.isEmpty else {
                DispatchQueue.main.async {
                    self.addLog("No accessible repositories found")
                    self.isProcessing = false
                }
                return
            }
            
            let commitCount = totalCommits ?? Int.random(in: 1...50)
            var remainingCommits = commitCount
            
            for repo in availableRepos.shuffled() {
                let commitsThisRepo = min(remainingCommits, Int.random(in: 1...remainingCommits))
                remainingCommits -= commitsThisRepo
                
                for _ in 0..<commitsThisRepo {
                    let message = self.getRealisticCommitMessage()
                    if self.gitCommit(repoPath: repo.path, message: message) {
                        DispatchQueue.main.async {
                            self.stats.totalCommits += 1
                        }
                    }
                }
                
                if remainingCommits <= 0 { break }
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.addLog("Processing completed. Total commits: \(self.stats.totalCommits)")
            }
            
            self.processingTask = nil
        }
    }
    
    func checkAccess(path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "push", "--dry-run"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            addLog("Access check failed for \(path)")
            return false
        }
    }
    
    func resetChanges(repoPath: String) -> Bool {
        let commands = [
            ["git", "reset", "--hard", "HEAD"],
            ["git", "push", "--force"]
        ]
        
        for cmd in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = cmd
            process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
            
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 { return false }
            } catch {
                addLog("Reset failed for \(repoPath)")
                return false
            }
        }
        return true
    }
    
    private func updateStats(filePath: String) {
        stats.fileCommits[filePath, default: 0] += 1
        stats.commitHistory.append(Date())
        stats.lastCommitDate = Date()
    }
    
    private func getRealisticCommitMessage() -> String {
        let types = ["feat", "fix", "refactor", "docs", "test"]
        let messages = [
            "feat: implement new functionality",
            "fix: resolve memory issue",
            "refactor: optimize performance",
            "docs: update documentation",
            "test: add unit tests"
        ]
        return messages.randomElement() ?? "feat: general update"
    }
    
    public func addLog(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            let newLog = LogEntry(id: UUID().uuidString, message: "\(Date().formatted(.dateTime)): \(message)")
            self?.logs.append(newLog)
        }
    }
    
    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        addLog("Processing cancelled by user")
    }
    
    func addRepository(path: String) {
        if !repositories.contains(where: { $0.path == path }) {
            let newRepo = Repository(path: path, isEnabled: true)
            repositories.append(newRepo)
            saveRepositories()
            addLog("Added new repository: \(path)")
        } else {
            addLog("Repository already exists: \(path)")
        }
    }
    
    func toggleRepository(_ repo: Repository) {
        if let index = repositories.firstIndex(where: { $0.id == repo.id }) {
            repositories[index].isEnabled.toggle()
            saveRepositories()
            addLog("Toggled repository \(repo.path) to \(repositories[index].isEnabled ? "enabled" : "disabled")")
        }
    }
    
    func removeRepository(_ repo: Repository) {
        repositories.removeAll { $0.id == repo.id }
        saveRepositories()
        addLog("Removed repository: \(repo.path)")
    }
}

// MARK: - UI
struct ContentView: View {
    @StateObject private var gitManager = GitManager()
    @State private var commitCount: String = ""
    @State private var newRepoPath: String = ""
    @State private var showResetAlert = false
    
    var body: some View {
        NavigationSplitView {
            // Левая часть: основное содержимое
            VStack(spacing: 20) {
                Text("Git Commit Simulator")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                
                StatsView(stats: gitManager.stats)  // Убедились, что StatsView определён
                    .padding(.horizontal)
                
                VStack(spacing: 15) {
                    TextField("Number of commits (optional)", text: $commitCount)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .padding(.horizontal)
                    
                    Button(action: startProcessing) {
                        Text(gitManager.isProcessing ? "Processing..." : "Start Commits")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(gitManager.isProcessing ? Color.blue.opacity(0.7) : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .disabled(gitManager.isProcessing)
                    
                    Button(action: { showResetAlert = true }) {
                        Text("Reset Changes")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(color: .red.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .disabled(gitManager.isProcessing || gitManager.stats.totalCommits == 0)
                    
                    if gitManager.isProcessing {
                        Button(action: gitManager.cancelProcessing) {
                            Text("Cancel Processing")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.yellow)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                                .shadow(color: .yellow.opacity(0.3), radius: 5, x: 0, y: 2)
                        }
                    }
                }
                .padding(.horizontal)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(gitManager.logs.reversed(), id: \.id) { logEntry in
                            Text(logEntry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 10)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 200)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 2)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(gradient: Gradient(colors: [.blue.opacity(0.1), .black]), startPoint: .top, endPoint: .bottom))
            .navigationTitle("Dashboard")
        } detail: {
            // Правая часть: управление репозиториями
            VStack(spacing: 20) {
                Text("Repository Manager")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                
                VStack(spacing: 15) {
                    TextField("Enter repository path", text: $newRepoPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                        .padding(.horizontal)
                    
                    Button(action: addRepository) {
                        Text("Add Repository")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(color: .green.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .disabled(newRepoPath.isEmpty)
                }
                
                List {
                    ForEach(gitManager.repositories) { repo in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { repo.isEnabled },
                                set: { _ in gitManager.toggleRepository(repo) }
                            )) {
                                Text(repo.path)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .toggleStyle(.switch)
                            .padding(.vertical, 4)
                            
                            Spacer()
                            
                            Button(action: { gitManager.removeRepository(repo) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }
                }
                .listStyle(.inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 2)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(gradient: Gradient(colors: [.purple.opacity(0.1), .black]), startPoint: .top, endPoint: .bottom))
        }
        .alert(isPresented: $showResetAlert) {
            Alert(
                title: Text("Reset Changes"),
                message: Text("Are you sure you want to reset all changes?"),
                primaryButton: .destructive(Text("Reset")) {
                    resetAllChanges()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func startProcessing() {
        let totalCommits = commitCount.isEmpty ? nil : Int(commitCount)
        gitManager.processRepositories(totalCommits: totalCommits)
    }
    
    private func resetAllChanges() {
        for repo in gitManager.repositories {
            if gitManager.resetChanges(repoPath: repo.path) {
                gitManager.addLog("Successfully reset changes in \(repo.path)")
            }
        }
        gitManager.stats = CommitStatistics()
    }
    
    private func addRepository() {
        gitManager.addRepository(path: newRepoPath.trimmingCharacters(in: .whitespaces))
        newRepoPath = ""
    }
}

// MARK: - Stats View (переместил сюда для видимости)
struct StatsView: View {
    let stats: CommitStatistics
    
    var body: some View {
        VStack(spacing: 10) {
            StatRow(title: "Total Commits", value: "\(stats.totalCommits)")
            StatRow(title: "Modified Files", value: "\(stats.fileCommits.count)")
            if let lastDate = stats.lastCommitDate {
                StatRow(title: "Last Commit", value: lastDate.formatted(.dateTime))
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
        .shadow(color: .blue.opacity(0.3), radius: 5, x: 0, y: 2)
    }
    
    struct StatRow: View {
        let title: String
        let value: String
        
        var body: some View {
            HStack {
                Text(title)
                    .foregroundColor(.gray)
                Spacer()
                Text(value)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - App
    @main
    struct GitCommitSimulatorApp: App {
        var body: some Scene {
            WindowGroup {
                ContentView()
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
    }
}
