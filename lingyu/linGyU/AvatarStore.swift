import SwiftUI
import PhotosUI

/// Local photo avatars. The host only knows colour/shape, so a photo avatar
/// lives in the app sandbox: Documents/avatars/<ownerId>.jpg (JPEG, max
/// 512 px). Owner ids are bot ids, group ids, or `meOwnerId` for the user.
/// No photo-library permission is needed: the system picker handles access.
/// All access is @MainActor; views observe `generation` to re-render.
@MainActor
final class AvatarStore: ObservableObject {
    static let shared = AvatarStore()

    /// Owner id for the user's own avatar.
    static let meOwnerId = "me"

    /// Bumped on every save/remove so observing AvatarViews re-render.
    @Published private(set) var generation = 0

    private var cache: [String: UIImage] = [:]

    private var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("avatars", isDirectory: true)
    }

    /// The stored photo for an owner, or nil when none is set.
    func photo(for ownerId: String) -> UIImage? {
        if let cached = cache[ownerId] { return cached }
        let url = fileURL(for: ownerId)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        cache[ownerId] = image
        return image
    }

    func hasPhoto(for ownerId: String) -> Bool {
        photo(for: ownerId) != nil
    }

    /// Downscale, store as JPEG, and notify observers.
    func save(_ image: UIImage, for ownerId: String) {
        let scaled = AvatarStore.downscaled(image)
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: ownerId), options: .atomic)
            cache[ownerId] = scaled
            generation += 1
        } catch {
            // Local-only failure: keep the letter disc, do not surface an error.
        }
    }

    func remove(for ownerId: String) {
        cache[ownerId] = nil
        try? FileManager.default.removeItem(at: fileURL(for: ownerId))
        generation += 1
    }

    /// Load a picked photo into a UIImage, downscaled and upright.
    static func load(_ item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return nil }
        return downscaled(image)
    }

    /// Downscale to at most 512 px on the long side, drawing upright so the
    /// stored JPEG needs no orientation flag.
    static func downscaled(_ image: UIImage, maxDimension: CGFloat = 512) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private func fileURL(for ownerId: String) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let safe = ownerId.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()
        return directory.appendingPathComponent((safe.isEmpty ? "unknown" : safe) + ".jpg")
    }
}
