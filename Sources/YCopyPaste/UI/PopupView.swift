import SwiftUI

enum PasteMode {
    case normal      // вставить
    case plain       // вставить без форматирования
    case copyOnly    // только скопировать
}

@MainActor
struct PopupView: View {
    @ObservedObject var vm: PopupViewModel
    let onPick: (ClipItem, PasteMode) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                list.frame(width: 340)
                Divider()
                PreviewPane(item: vm.selectedItem, store: vm.store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: 780, height: 470)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .onReceive(vm.$focusTrigger) { _ in
            Task { @MainActor in searchFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 15))
            TextField("Поиск по истории", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
            Picker("", selection: $vm.filter) {
                ForEach(PopupViewModel.Filter.allCases) { f in Text(f.title).tag(f) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(WindowDragArea())
        .help("Окно можно перетащить за эту панель")
    }

    private var list: some View {
        Group {
            if vm.results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: vm.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(emptyText).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(vm.results.enumerated()), id: \.element.id) { index, item in
                                ClipRow(item: item, index: index, selected: index == vm.selection, store: vm.store)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) {
                                        vm.selection = index
                                        onPick(item, .normal)
                                    }
                                    .onTapGesture { vm.selection = index }
                                    .contextMenu {
                                        Button("Вставить") { onPick(item, .normal) }
                                        Button("Вставить без форматирования") { onPick(item, .plain) }
                                        Button("Только скопировать") { onPick(item, .copyOnly) }
                                        Divider()
                                        Button(item.pinned ? "Открепить" : "Закрепить") {
                                            vm.store.setPinned(item.id, !item.pinned)
                                        }
                                        Button("Удалить") { vm.store.delete(item.id) }
                                    }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: vm.selection) { newValue in
                        guard vm.results.indices.contains(newValue) else { return }
                        proxy.scrollTo(vm.results[newValue].id)
                    }
                }
            }
        }
    }

    private var emptyText: String {
        if !vm.query.isEmpty { return "Ничего не найдено" }
        if vm.filter == .pinned { return "Нет закреплённых.\nВыберите элемент и нажмите ⌘P" }
        return "История пуста.\nСкопируйте что-нибудь (⌘C)"
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if let notice = vm.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                hint("↩", "вставить")
                hint("⌥↩", "без формата")
                hint("⌘↩", "копировать")
                hint("⌘P", "закрепить")
                hint("⌘⌫", "удалить")
                hint("⇥", "закреплённые")
            }
            Spacer()
            Text("\(vm.results.count)").foregroundStyle(.tertiary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Text(key).fontWeight(.semibold)
            Text(text)
        }
        .foregroundStyle(.secondary)
    }
}

@MainActor
struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let store: HistoryStore

    var body: some View {
        HStack(spacing: 8) {
            leading.frame(width: 22, height: 22)
            Text(item.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 13))
            Spacer(minLength: 4)
            if item.pinned {
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.orange)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.28) : Color.clear)
        )
    }

    @ViewBuilder private var leading: some View {
        if item.kind == .image, let img = store.image(for: item) {
            Image(nsImage: img).resizable().scaledToFill()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if let icon = AppIcons.icon(for: item.sourceBundle) {
            Image(nsImage: icon).resizable().scaledToFit()
        } else {
            Image(systemName: item.kind.symbolName).foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct PreviewPane: View {
    let item: ClipItem?
    let store: HistoryStore

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                meta(item)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        } else {
            Text("Нет выбранного элемента")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            if let img = store.image(for: item) {
                Image(nsImage: img).resizable().scaledToFit()
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Не удалось загрузить изображение").foregroundStyle(.secondary).padding()
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.filePaths, id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text((path as NSString).lastPathComponent).lineLimit(1)
                                Text(path).font(.system(size: 10)).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
                .padding(12)
            }
        default:
            ScrollView {
                Text(String(item.text.prefix(30_000)))
                    .font(.system(size: 12, design: item.kind == .url ? .default : .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
    }

    private func meta(_ item: ClipItem) -> some View {
        HStack(spacing: 6) {
            if let icon = AppIcons.icon(for: item.sourceBundle) {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            }
            Text(item.sourceName ?? item.kind.title)
            Text("·")
            Text(Formatters.relativeString(item.used))
            Spacer()
            if item.kind == .text || item.kind == .rich || item.kind == .url {
                Text("\(item.text.count) симв.")
            } else {
                Text(Formatters.bytes(item.byteSize))
            }
            if item.copyCount > 1 { Text("×\(item.copyCount)") }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
