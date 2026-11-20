import SwiftUI
import WebKit
import UIKit
import Photos

/// 图表放大查看并保存为图片（DDchat 补 6）。
///
/// 商店原文：「图表支持放大查看并保存为图片，方便学习、整理和分享。」
/// 核查（DDCHAT_SUPPLEMENT.md 补 6）：HTMLCardView 只有固定高度 + 圆角描边，
/// 无放大、无保存（grep zoom/放大/保存/save 零命中）。
/// 落法：Mermaid 图表卡片点开放大页（可缩放查看），加「保存为图片」按钮；
/// HTML 卡片只做放大，不做保存（按补单建议）。
///
/// 保存：点「保存为图片」直接存相册（PHPhotoLibrary.performChanges），
/// Info.plist 里已有 NSPhotoLibraryAddUsageDescription（构建 #29 补上）。
struct ChartZoomView: View {
    let code: String
    let kind: HTMLCardView.Kind

    @Environment(\.dismiss) var dismiss
    @State private var height: CGFloat = 400
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var webView: WKWebView?
    @State private var saveStatus: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                GeometryReader { geo in
                    ScrollView([.vertical, .horizontal], showsIndicators: false) {
                        HTMLWebView(html: HTMLCardView.document(for: code, kind: kind),
                                    height: $height,
                                    onWebView: { webView = $0 })
                            .frame(width: geo.size.width, height: max(height, geo.size.height))
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { v in
                                        scale = min(max(lastScale * v, 1), 4)
                                    }
                                    .onEnded { _ in lastScale = scale }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { v in
                                        offset = CGSize(width: lastOffset.width + v.translation.width,
                                                        height: lastOffset.height + v.translation.height)
                                    }
                                    .onEnded { _ in lastOffset = offset }
                            )
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    withAnimation {
                                        if scale > 1 {
                                            scale = 1; lastScale = 1
                                            offset = .zero; lastOffset = .zero
                                        } else {
                                            scale = 2; lastScale = 2
                                        }
                                    }
                                }
                            )
                    }
                }
                if let saveStatus {
                    VStack {
                        Spacer()
                        Text(saveStatus)
                            .font(.caption)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Palette.control, in: Capsule())
                            .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle(kind == .mermaid ? "图表" : "卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if kind == .mermaid {
                    ToolbarItem(placement: .primaryAction) {
                        Button("保存为图片") { saveImage() }
                            .disabled(saving || webView == nil)
                    }
                }
            }
        }
    }

    private func saveImage() {
        guard let wv = webView else { return }
        saving = true
        saveStatus = nil
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: wv.bounds.size)
        wv.takeSnapshot(with: config) { image, error in
            guard let image else {
                saving = false
                saveStatus = "截图失败：\(error?.localizedDescription ?? "再试一次")"
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { ok, error in
                Task { @MainActor in
                    saving = false
                    saveStatus = ok ? "已保存到相册" : "保存失败：\(error?.localizedDescription ?? "再试一次")"
                }
            }
        }
    }
}
