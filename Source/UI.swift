import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConversionItem: Identifiable {
    let id = UUID()
    let input: URL
    var detail = "等待转换"
    var output: URL?
    var state = 0 // queued, running, succeeded, failed
}

final class ConversionModel: ObservableObject {
    @Published var items: [ConversionItem] = []
    @Published var outputFolder: URL?
    @Published var notice: String?
    private let worker = DispatchQueue(label: "local.heif-to-png.converter", qos: .userInitiated)
    var completed: Int { items.filter { $0.state == 2 }.count }
    var active: Int { items.filter { $0.state < 2 }.count }
    var failures: Int { items.filter { $0.state == 3 }.count }

    func add(_ urls: [URL]) {
        notice = nil
        let valid = urls.filter { ["heif", "heic", "hif"].contains($0.pathExtension.lowercased()) }
        if valid.count != urls.count { notice = "仅支持 HEIF / HEIC 图片，其他文件已跳过。" }
        for url in valid {
            if items.contains(where: { $0.input == url && $0.state < 2 }) { continue }
            let item = ConversionItem(input: url)
            let folder = outputFolder
            items.append(item)
            worker.async { [weak self] in
                DispatchQueue.main.async { self?.update(item.id, state: 1, detail: "正在转换…") }
                let result: Result<ConversionResult, Error> = autoreleasepool {
                    Result { try Converter.convert(url, to: folder) }
                }
                DispatchQueue.main.async {
                    switch result {
                    case .success(let output):
                        let size = ByteCountFormatter.string(fromByteCount: Int64(output.bytes), countStyle: .file)
                        self?.update(item.id, state: 2, detail: "\(output.width) × \(output.height) · \(size)", output: output.url)
                    case .failure(let error):
                        self?.update(item.id, state: 3, detail: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func update(_ id: UUID, state: Int, detail: String, output: URL? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state
        items[index].detail = detail
        items[index].output = output
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择 HEIF / HEIC 图片"
        panel.prompt = "转换为 PNG"
        panel.allowedContentTypes = [.heic, .heif]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            if response == .OK { self?.add(panel.urls) }
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择 PNG 保存位置"
        panel.prompt = "保存到这里"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            if response == .OK { self?.outputFolder = panel.url }
        }
    }

    func receive(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [Int: URL] = [:]
        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else { url = item as? URL }
                if let url = url { lock.lock(); urls[index] = url; lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.add(urls.sorted { $0.key < $1.key }.map(\.value))
        }
        return true
    }
}

private let ink = Color(red: 0.13, green: 0.19, blue: 0.19)
private let muted = Color(red: 0.42, green: 0.47, blue: 0.47)
private let accent = Color(red: 0.06, green: 0.43, blue: 0.35)

struct ConverterView: View {
    @ObservedObject var model: ConversionModel
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("格式轻转换").font(.system(size: 13, weight: .semibold)).foregroundColor(accent)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("HEIF").font(.system(size: 36, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.right").font(.system(size: 24, weight: .light)).foregroundColor(muted)
                        Text("PNG").font(.system(size: 36, weight: .bold, design: .rounded))
                    }
                    Text("让照片，随处可用。").font(.system(size: 14)).foregroundColor(muted)
                }
                Spacer()
                Label("本地处理", systemImage: "lock.shield")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(accent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(accent.opacity(0.07), in: Capsule())
            }

            VStack(spacing: 13) {
                HStack(spacing: -5) {
                    formatTile("HEIF", symbol: "photo", tint: muted).rotationEffect(.degrees(-8))
                    formatTile("PNG", symbol: "photo.fill", tint: accent).rotationEffect(.degrees(7)).offset(y: -3)
                }.padding(.bottom, 3)
                Text(hovering ? "松开，开始转换" : "把照片拖到这里").font(.system(size: 22, weight: .semibold))
                Text("支持 HEIF / HEIC · 可一次添加多张").font(.system(size: 13)).foregroundColor(muted)
                Button(action: model.chooseFiles) {
                    Label("选择图片", systemImage: "plus").font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 24).padding(.vertical, 11)
                        .background(accent, in: RoundedRectangle(cornerRadius: 10)).foregroundColor(.white)
                }.buttonStyle(.plain).keyboardShortcut("o", modifiers: .command)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
            .background(hovering ? accent.opacity(0.10) : Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(accent.opacity(hovering ? 0.8 : 0.23), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $hovering, perform: model.receive)

            HStack(spacing: 10) {
                Image(systemName: "folder").foregroundColor(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("保存位置").font(.system(size: 11)).foregroundColor(muted)
                    Text(model.outputFolder?.path ?? "与原图片相同的文件夹")
                        .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        .help(model.outputFolder?.path ?? "每张 PNG 保存到对应原图片的文件夹")
                }
                Spacer()
                if model.outputFolder != nil {
                    Button("恢复默认") { model.outputFolder = nil }.buttonStyle(.plain).foregroundColor(muted).font(.system(size: 12))
                }
                Button("更改…", action: model.chooseFolder).font(.system(size: 12))
            }
            .padding(14).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 10) {
                HStack {
                    Text("转换记录").font(.system(size: 13, weight: .semibold))
                    if model.active > 0 {
                        ProgressView().controlSize(.small).scaleEffect(0.65).frame(width: 14, height: 14)
                        Text("\(model.active) 张处理中").font(.system(size: 11)).foregroundColor(muted)
                    }
                    Spacer()
                    if !model.items.isEmpty {
                        Text("\(model.completed) 张完成" + (model.failures > 0 ? " · \(model.failures) 张失败" : ""))
                            .font(.system(size: 11)).foregroundColor(muted)
                        Button("清空记录") { model.items.removeAll { $0.state >= 2 } }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(muted)
                            .disabled(model.active > 0).help("仅清空列表，不删除图片")
                    }
                }
                if let notice = model.notice {
                    Text(notice).font(.system(size: 12)).foregroundColor(.orange).frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack").font(.system(size: 23, weight: .light))
                        Text("添加图片后，转换结果会显示在这里").font(.system(size: 12))
                    }.foregroundColor(muted.opacity(0.7)).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.items) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: item.state == 3 ? "exclamationmark.circle" : item.state == 2 ? "checkmark.circle.fill" : "photo")
                                        .font(.system(size: 22)).foregroundColor(item.state == 3 ? .orange : accent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.output?.lastPathComponent ?? item.input.lastPathComponent)
                                            .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                        Text(item.detail).font(.system(size: 11)).foregroundColor(item.state == 3 ? .orange : muted)
                                            .lineLimit(2).help(item.detail)
                                    }
                                    Spacer(minLength: 12)
                                    if let url = item.output {
                                        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                                            Image(systemName: "folder").font(.system(size: 14))
                                        }.buttonStyle(.plain).foregroundColor(muted).help("在 Finder 中显示 PNG")
                                    }
                                }.padding(12).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }.frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal")
                Text("保持原始尺寸 · 自动校正方向 · 保留原文件")
                Spacer()
                Text("无需联网")
            }.font(.system(size: 10)).foregroundColor(muted)
        }
        .padding(30).frame(minWidth: 620, minHeight: 700)
        .foregroundColor(ink)
        .background(Color(red: 0.96, green: 0.97, blue: 0.95))
        .preferredColorScheme(.light)
    }

    private func formatTile(_ name: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light))
            Text(name).font(.system(size: 10, weight: .bold, design: .rounded))
        }.foregroundColor(tint).frame(width: 66, height: 78)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.14)))
            .shadow(color: tint.opacity(0.08), radius: 8, y: 5)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ConversionModel()
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 HEIF to PNG", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let fileMenu = NSMenu(title: "文件")
        let open = NSMenuItem(title: "添加图片…", action: #selector(openFiles), keyEquivalent: "o")
        open.target = self; fileMenu.addItem(open)
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: ""); fileItem.submenu = fileMenu; menu.addItem(fileItem)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "HEIF to PNG"
        window.contentView = NSHostingView(rootView: ConverterView(model: model))
        window.center()
        window.setFrameAutosaveName("HEIFtoPNG")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openFiles() { model.chooseFiles() }
    func application(_ sender: NSApplication, open urls: [URL]) { model.add(urls) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.active > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "还有图片正在转换"
        alert.informativeText = "退出将停止尚未完成的转换。已生成的 PNG 会保留。"
        alert.addButton(withTitle: "继续转换")
        alert.addButton(withTitle: "退出")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
}
