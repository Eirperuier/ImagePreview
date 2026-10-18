import ImagePreview
import SwiftUI

struct FeedView: View {
    @State private var posts: [Post] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach($posts) { $post in
                        PostView(post: $post)
                        Divider()
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("ImagePreview")
        }
        .task {
            guard posts.isEmpty else { return }
            posts = Artwork.posts() + [Artwork.remotePost()]
            await loadRemoteThumbnails()
        }
    }

    private func loadRemoteThumbnails() async {
        guard let p = posts.firstIndex(where: { $0.id == "r" }) else { return }
        for (i, photo) in posts[p].photos.enumerated() {
            let id = photo.id.dropFirst()
            guard let url = URL(string: "https://picsum.photos/id/\(id)/600/400"),
                  let data = try? await URLSession.shared.data(from: url).0,
                  let image = PlatformImage(data: data) else { continue }
            posts[p].photos[i].thumbnail = image
            // The viewer starts from the thumbnail it already has.
            posts[p].photos[i].image = PreviewImage(url: URL(string: "https://picsum.photos/id/\(id)/2400/1600")!, placeholder: image)
        }
    }
}

struct PostView: View {
    @Binding var post: Post
    @State private var opened: Photo.ID?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(hue: Double(post.author.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 12) / 12, saturation: 0.4, brightness: 0.85))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 8) {
                Text(post.author).font(.headline)
                Text(post.text)
                MediaGrid(photos: post.photos) { opened = $0 }
            }
        }
        .padding(16)
        .imagePreview(selection: $opened, items: post.photos, configuration: .example) { photo in
            photo.image
        }
    }
}

/// One to four images, laid out the way social apps do: one wide, two side by side, three with one tall, four in a grid.
struct MediaGrid: View {
    let photos: [Photo]
    let open: (Photo.ID) -> Void
    private let spacing: CGFloat = 3

    var body: some View {
        Group {
            switch photos.count {
            case 1:
                cell(photos[0]).aspectRatio(min(max(photos[0].aspectRatio, 0.75), 1.8), contentMode: .fit)
            case 2:
                HStack(spacing: spacing) { cell(photos[0]); cell(photos[1]) }.aspectRatio(1.6, contentMode: .fit)
            case 3:
                HStack(spacing: spacing) {
                    cell(photos[0])
                    VStack(spacing: spacing) { cell(photos[1]); cell(photos[2]) }
                }
                .aspectRatio(1.6, contentMode: .fit)
            default:
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) { cell(photos[0]); cell(photos[1]) }
                    HStack(spacing: spacing) { cell(photos[2]); cell(photos[3]) }
                }
                .aspectRatio(1.6, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if photos.count > 4 {
                        Text("+\(photos.count - 4)").font(.headline).foregroundStyle(.white).padding(8)
                    }
                }
            }
        }
    }

    private func cell(_ photo: Photo) -> some View {
        Color.secondary.opacity(0.15)
            .overlay {
                if let thumbnail = photo.thumbnail {
                    Image(platform: thumbnail).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .imagePreviewSource(photo.id, cornerRadius: 12)
            .onTapGesture { open(photo.id) }
    }
}

extension ImagePreviewConfiguration {
    /// The defaults; `PREVIEW_TRANSITION_RESPONSE` (seconds) slows the transitions down to watch them.
    static var example: ImagePreviewConfiguration {
        var configuration = ImagePreviewConfiguration()
        if let value = ProcessInfo.processInfo.environment["PREVIEW_TRANSITION_RESPONSE"], let response = Double(value) {
            configuration.transitionSpring = PreviewSpring(response: response, dampingRatio: 1)
        }
        return configuration
    }
}
