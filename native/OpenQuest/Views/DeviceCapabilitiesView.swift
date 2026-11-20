import SwiftUI

/// 本机能力（FishPocket 式）：一能力一开关，全部默认关。
/// 开关只决定模型看不看得到这个工具；真用时还要过系统授权。
struct DeviceCapabilitiesView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            ForEach(store.deviceCapabilities) { cap in
                Toggle(isOn: Binding(
                    get: { cap.enabled },
                    set: { store.setDeviceCapability(id: cap.id, on: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cap.name)
                        Text(cap.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text("开哪个，智能体才能用哪个。真调用时还要过一次系统授权（日历、照片、通讯录、位置），你在系统弹窗里拒绝，它就用不了，会如实告诉你。剪贴板、日历这些能力只在你开着时才进工具表。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("本机能力")
    }
}
