import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    let app: AppController

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Основные", systemImage: "gearshape") }
            HotKeySettings()
                .tabItem { Label("Клавиши", systemImage: "keyboard") }
            PrivacySettings(app: app)
                .tabItem { Label("Приватность", systemImage: "hand.raised") }
            AboutView()
                .tabItem { Label("О программе", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 470)
    }
}

@MainActor
private struct GeneralSettings: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var trusted = Accessibility.isTrusted
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Запускать при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LaunchAtLogin.set($0) }
                Picker("Окно истории", selection: $prefs.popupPosition) {
                    ForEach(PopupPosition.allCases) { Text($0.title).tag($0) }
                }
                Picker("Недавние в меню", selection: $prefs.menuRecentCount) {
                    Text("Не показывать").tag(0)
                    Text("5").tag(5)
                    Text("10").tag(10)
                    Text("20").tag(20)
                }
            }
            Section("Вставка") {
                Toggle("Вставлять сразу после выбора", isOn: $prefs.autoPaste)
                Toggle("По умолчанию вставлять без форматирования", isOn: $prefs.plainByDefault)
                Toggle("Поднимать вставленный элемент наверх", isOn: $prefs.moveToTopOnPaste)
                HStack {
                    if trusted {
                        Label("Универсальный доступ разрешён", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Нет доступа — элементы будут только копироваться", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Разрешить…") {
                            if !Accessibility.prompt() { Accessibility.openSettings() }
                        }
                    }
                }
            }
            Section("Хранение") {
                Picker("Хранить элементов", selection: $prefs.maxItems) {
                    Text("100").tag(100)
                    Text("500").tag(500)
                    Text("1 000").tag(1000)
                    Text("5 000").tag(5000)
                    Text("10 000").tag(10000)
                    Text("Без ограничения").tag(0)
                }
                Picker("Хранить не дольше", selection: $prefs.maxDays) {
                    Text("Всегда").tag(0)
                    Text("1 день").tag(1)
                    Text("1 неделю").tag(7)
                    Text("1 месяц").tag(30)
                    Text("3 месяца").tag(90)
                    Text("1 год").tag(365)
                }
                Text("Закреплённые элементы не удаляются автоматически.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted = Accessibility.isTrusted }
    }
}

@MainActor
private struct HotKeySettings: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Открыть историю") { KeyRecorder(combo: $prefs.popupHotKey) }
                LabeledContent("Режим Flycut") { KeyRecorder(combo: $prefs.flycutHotKey) }
                Button("Вернуть по умолчанию") {
                    prefs.popupHotKey = .defaultPopup
                    prefs.flycutHotKey = .defaultFlycut
                }
            } footer: {
                Text("Нажмите на сочетание и введите новое. Нужен хотя бы один из ⌘ ⌃ ⌥. Esc — отмена.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("В окне истории") {
                shortcut("↑ ↓", "выбор элемента")
                shortcut("↩", "вставить")
                shortcut("⌥↩", "вставить без форматирования")
                shortcut("⌘↩", "только скопировать в буфер")
                shortcut("⌘1 … ⌘9", "вставить элемент по номеру")
                shortcut("⌘P", "закрепить / открепить")
                shortcut("⌘⌫", "удалить из истории")
                shortcut("⇥", "переключить «Все / Закреплённые»")
                shortcut("⎋", "очистить поиск / закрыть")
            }
            Section("Режим Flycut") {
                Text("Держите модификаторы (по умолчанию ⌃⌘) и нажимайте V: каждое нажатие — элемент постарше. Отпустите клавиши, и выбранный элемент вставится. ↑↓ листают, ⎋ отменяет.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcut(_ keys: String, _ text: String) -> some View {
        LabeledContent(text) { Text(keys).fontWeight(.semibold) }
    }
}

@MainActor
private struct PrivacySettings: View {
    let app: AppController
    @ObservedObject private var prefs = Preferences.shared
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                Toggle("Приостановить запись истории", isOn: $prefs.isPaused)
                Toggle("Не сохранять пароли и скрытые данные", isOn: $prefs.skipConcealed)
                Text("Менеджеры паролей помечают скопированные пароли особым образом — такие данные не попадают в историю.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Не записывать из приложений") {
                List(selection: $selection) {
                    ForEach(prefs.ignoredApps, id: \.self) { bundleID in
                        HStack {
                            if let icon = AppIcons.icon(for: bundleID) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            }
                            Text(appName(bundleID))
                            Spacer()
                            Text(bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(bundleID)
                    }
                }
                .frame(minHeight: 120)
                HStack {
                    Button("Добавить приложение…", action: addApp)
                    Button("Удалить") {
                        if let s = selection { prefs.ignoredApps.removeAll { $0 == s } }
                        selection = nil
                    }
                    .disabled(selection == nil)
                }
            }
            Section {
                Button("Очистить историю…", role: .destructive) { app.confirmClearHistory() }
                Text("Данные хранятся только на этом Mac: \(HistoryStore.storageDirectory.path)")
                    .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Добавить"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !prefs.ignoredApps.contains(id) {
                prefs.ignoredApps.append(id)
            }
        }
    }
}

@MainActor
private struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
            Text("YCopyPaste").font(.title.bold())
            Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("Менеджер буфера обмена для macOS.\nИстория, поиск, закрепление, режим Flycut.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Кнопка записи сочетания клавиш.
@MainActor
struct KeyRecorder: View {
    @Binding var combo: KeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Нажмите сочетание…" : combo.displayString)
                .frame(minWidth: 150)
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        HotKeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
            } else if let newCombo = KeyCombo(event: event) {
                combo = newCombo
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        if recording {
            recording = false
            HotKeyManager.shared.resume()
        }
    }
}
