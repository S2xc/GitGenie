import SwiftUI
import Foundation
import Combine

// MARK: - Models
struct Repository: Identifiable {
    let id = UUID()
    let path: String
    var commitCount: Int = 0
}

struct CommitStatistics {
    var totalCommits: Int = 0
    var fileCommits: [String: Int] = [:]
    var lastCommitDate: Date?
    var commitHistory: [Date] = []
}

// Структура для логов с уникальным ID
struct LogEntry: Identifiable {
    let id: String
    let message: String
}

// MARK: - Git Manager
class GitManager: ObservableObject {
    @Published var repositories: [Repository] = []
    @Published var stats = CommitStatistics()
    @Published var isProcessing = false
    @Published var logs: [LogEntry] = []  // Изменён тип на [LogEntry]
    
    private let fileManager = FileManager.default
    private var processingTask: Task<Void, Never>? // Для отслеживания текущей задачи
    
    init() {
        loadRepositories()
    }
    
    func loadRepositories() {
        // Пример путей к репозиториям (можно заменить на выбор через UI)
        let paths = [
            "/Users/s2xdeb/Desktop/g/и/SQL-50-LeetCode",
            "/Users/s2xdeb/Desktop/ed_g/pythhon"
        ]
        repositories = paths.compactMap { path in
            if fileManager.fileExists(atPath: path) {
                addLog("Repository path exists: \(path)")
                return Repository(path: path)
            } else {
                addLog("Repository path does not exist: \(path)")
                return nil
            }
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
            // Рекурсивно найти все поддерживаемые файлы
            let supportedExts: Set<String> = [".py", ".sql", ".cpp", ".hpp", ".cxx", ".h", ".kt", ".kts", ".swift"]
            let allFiles = try findFiles(in: repoPath, withExtensions: supportedExts)
            
            addLog("Found files in \(repoPath): \(allFiles)")  // Дополнительное логирование
            guard !allFiles.isEmpty else {
                addLog("No supported files found in \(repoPath)")
                return false
            }
            
            guard let fileToChange = allFiles.randomElement() else {
                addLog("No files to change in \(repoPath)")
                return false
            }
            
            guard makeMinimalChange(to: fileToChange) else { return false }
            
            // Git operations с созданием нового Process для каждой команды
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
        // Предотвращаем повторные запуски, если задача уже выполняется
        guard !isProcessing else {
            addLog("Processing already in progress, please wait...")
            return
        }
        
        isProcessing = true
        processingTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let availableRepos = self.repositories.filter { self.checkAccess(path: $0.path) }
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
            } catch {
                DispatchQueue.main.async {
                    self.addLog("Error processing repositories: \(error.localizedDescription)")
                    self.isProcessing = false
                }
            }
            
            // Очистка задачи после завершения
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
    
    // Метод для отмены текущей задачи (если нужно)
    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        addLog("Processing cancelled by user")
    }
}

// MARK: - UI
struct ContentView: View {
    @StateObject private var gitManager = GitManager()
    @State private var commitCount: String = ""
    @State private var showResetAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                Text("Git Commit Simulator")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                // Stats
                StatsView(stats: gitManager.stats)
                
                // Controls
                VStack(spacing: 15) {
                    TextField("Number of commits (optional)", text: $commitCount)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    
                    Button(action: startProcessing) {
                        Text(gitManager.isProcessing ? "Processing..." : "Start Commits")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(gitManager.isProcessing)
                    
                    Button(action: { showResetAlert = true }) {
                        Text("Reset Changes")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(gitManager.isProcessing || gitManager.stats.totalCommits == 0)
                    
                    // Добавлена кнопка для отмены, если нужно
                    if gitManager.isProcessing {
                        Button(action: gitManager.cancelProcessing) {
                            Text("Cancel Processing")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.yellow)
                                .foregroundColor(.black)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Logs
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(gitManager.logs.reversed(), id: \.id) { logEntry in
                            Text(logEntry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Dashboard")
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
}

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
    }
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
        }
    }
}

// MARK: - App
@main  // Убедился, что это единственное место с @main в модуле
struct GitCommitSimulatorApp: App {  // Сохранил уникальное имя
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}
