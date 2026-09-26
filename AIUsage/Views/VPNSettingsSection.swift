import SwiftUI

struct VPNSettingsSection: View {
    let store: UsageStore
    @Bindable var preferences: AppPreferences
    @State private var hasLoadedDraft = false
    @State private var endpoint = ""
    @State private var name = "VPN"
    @State private var reveal = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("VPN 用量", systemImage: "network").font(.headline)
                Spacer()
                VStack(spacing: -1) {
                    Text(name.isEmpty ? "VPN" : String(name.prefix(12))).font(.system(size: 9))
                    Text(previewPercentage).font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("菜单栏预览")
            }
            HStack {
                Text("显示名称").frame(width: 72, alignment: .leading)
                TextField("VPN", text: $name).textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, value in name = String(value.prefix(12)) }
            }
            HStack {
                Text("查询 URL").frame(width: 72, alignment: .leading)
                Group {
                    if reveal { TextField("https://…", text: $endpoint) }
                    else { SecureField("https://…", text: $endpoint) }
                }.textFieldStyle(.roundedBorder)
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                }.help(reveal ? "隐藏查询地址" : "显示查询地址")
            }
            HStack {
                Spacer()
                Button("保存并刷新", action: save).buttonStyle(.borderedProminent)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(failed ? .red : .secondary)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            guard !hasLoadedDraft else { return }
            name = preferences.vpnDisplayName
            endpoint = preferences.vpnURL
            hasLoadedDraft = true
        }
    }

    private var previewPercentage: String {
        guard let used = store.states[.vpn]?.snapshot?.resourceUsage?.usedPercent else { return "--" }
        return preferences.vpnDisplayMode.displayedPercent(from: used)
            .formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private func save() {
        do {
            let url = try VPNEndpoint.validate(endpoint)
            preferences.vpnURL = url.absoluteString
            preferences.vpnName = name
            store.configureVPN(name: preferences.vpnDisplayName, endpoint: url.absoluteString)
            failed = false
            message = "已保存。"
            Task { await store.refresh(providerIDs: [.vpn], afterCurrent: true) }
        } catch let error as ProviderFailure {
            failed = true; message = error.message
        } catch {
            failed = true; message = "无法保存，请检查输入。"
        }
    }
}
