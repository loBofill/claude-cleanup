// claude-cleanup-ui: native picker for claude-cleanup.
//
// Usage: claude-cleanup-ui [refresh-command args...]
// Reads JSON on stdin: {"test": bool, "idleThreshold": int,
//                       "sessions": [{pid, idleHours, memMB, title, recap, cwd, app}]}
// If a refresh command is given, the "Refresca" button runs it; it must print the same JSON.
// The list then follows reality: sessions that stopped being idle disappear, new
// idle ones appear (checked), and anything you unchecked stays unchecked.
// On "close", prints the selected PIDs (one per line) and exits 0.
// On "not now" or closing the window, exits 1.
//
// Build: claude-cleanup --build-ui

import AppKit
import SwiftUI

struct Session: Codable, Identifiable {
    let pid: Int
    let idleHours: Int
    let memMB: Int
    let title: String
    let recap: String
    let cwd: String
    let app: String?
    var id: Int { pid }
}

struct Input: Codable {
    let test: Bool
    let idleThreshold: Int
    let sessions: [Session]
}

func finish(_ pids: [Int]?) -> Never {
    if let pids {
        print(pids.map(String.init).joined(separator: "\n"))
        fflush(stdout)
        exit(0)
    }
    exit(1)
}

func idleText(_ hours: Int) -> String {
    hours >= 48 ? "inactiva \(hours / 24) dies" : "inactiva \(hours) h"
}

func memText(_ mb: Int) -> String {
    mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
}

final class Store: ObservableObject {
    @Published var input: Input
    @Published var unchecked: Set<Int> = []
    @Published var lastRefresh = Date()
    @Published var refreshing = false
    private let refreshCommand: [String]

    init(input: Input, refreshCommand: [String]) {
        self.input = input
        self.refreshCommand = refreshCommand
    }

    var selected: [Session] { input.sessions.filter { !unchecked.contains($0.pid) } }

    func toggle(_ pid: Int) {
        if unchecked.contains(pid) { unchecked.remove(pid) } else { unchecked.insert(pid) }
    }

    func refresh() {
        guard !refreshCommand.isEmpty, !refreshing else { return }
        refreshing = true
        let command = refreshCommand
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var fresh: Input?
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    fresh = try? JSONDecoder().decode(Input.self, from: data)
                }
            }
            DispatchQueue.main.async {
                self.refreshing = false
                guard let fresh else { return }  // keep the current list if a refresh fails
                self.input = fresh
                // Forget unchecks for sessions that are gone, so a reused PID starts checked.
                self.unchecked.formIntersection(Set(fresh.sessions.map(\.pid)))
                self.lastRefresh = Date()
            }
        }
    }
}

struct SessionRow: View {
    let session: Session
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                if !session.recap.isEmpty {
                    Text(session.recap)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    if let app = session.app, !app.isEmpty {
                        Label(app, systemImage: "macwindow")
                        Text("·")
                    }
                    Label(session.cwd, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                    Text(idleText(session.idleHours))
                    Text("·")
                    Text(memText(session.memMB))
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isOn ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isOn ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

struct ContentView: View {
    @ObservedObject var store: Store

    var body: some View {
        let input = store.input
        let selected = store.selected
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(input.sessions.isEmpty ? "Cap sessió de Claude inactiva"
                                                : "\(input.sessions.count) sessions de Claude inactives")
                        .font(.title2.weight(.semibold))
                    if input.test {
                        Text("PROVA · no es tancarà res")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if store.refreshing {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        store.refresh()
                    } label: {
                        Label("Refresca", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.refreshing)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Torna a llegir quines sessions estan inactives (⌘R)")
                }
                Text("Fa més de \(input.idleThreshold) h que no fan res. Desmarca les que vulguis mantenir. Les que tanquis es poden reprendre amb claude --resume, i el recap queda escrit al seu terminal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Totes") { store.unchecked = [] }
                    Button("Cap") { store.unchecked = Set(input.sessions.map(\.pid)) }
                    Spacer()
                    Text("Llista de les \(store.lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .buttonStyle(.link)
                .font(.callout)
                .padding(.top, 2)
            }
            .padding(20)

            Divider()

            if input.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 36)).foregroundStyle(.green)
                    Text("Totes les sessions s'han reactivat o ja no hi són.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(input.sessions) { s in
                            SessionRow(session: s, isOn: !store.unchecked.contains(s.pid)) {
                                store.toggle(s.pid)
                            }
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            HStack {
                Text(selected.isEmpty ? "Cap seleccionada"
                                      : "\(selected.count) seleccionades · ~\(memText(selected.map(\.memMB).reduce(0, +))) de RAM")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Ara no") { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(selected.isEmpty ? "Tanca" : "Tanca \(selected.count)") {
                    finish(selected.map(\.pid))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .padding(16)
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

final class WindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { finish(nil) }
}

let data = FileHandle.standardInput.readDataToEndOfFile()
guard let input = try? JSONDecoder().decode(Input.self, from: data), !input.sessions.isEmpty else {
    FileHandle.standardError.write("claude-cleanup-ui: no sessions in input\n".data(using: .utf8)!)
    exit(2)
}

let store = Store(input: input, refreshCommand: Array(CommandLine.arguments.dropFirst()))
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = WindowDelegate()
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
    styleMask: [.titled, .closable, .resizable],
    backing: .buffered, defer: false)
window.title = "Claude cleanup"
window.delegate = delegate
window.contentView = NSHostingView(rootView: ContentView(store: store))
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()
