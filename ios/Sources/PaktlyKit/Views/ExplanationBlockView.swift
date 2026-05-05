import SwiftUI

/// Renders an `explanation` block — free-form text introducing a concept.
/// SwiftUI's `Text` supports inline markdown when initialised from
/// `AttributedString(markdown:)` or via the `LocalizedStringKey` initializer
/// with a literal string; we route the manifest's plain text through
/// AttributedString so creators can use `**bold**`, `*italic*`, links, and
/// other CommonMark inline syntax without pre-rendering.
public struct ExplanationBlockView: View {
    public let block: ExplanationBlock
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void

    public init(block: ExplanationBlock, pack: InstalledPack, onAudioRequest: @escaping (URL) -> Void) {
        self.block = block
        self.pack = pack
        self.onAudioRequest = onAudioRequest
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                renderedText
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let media = block.media {
                    MediaAttachmentView(media: media, pack: pack, onAudioRequest: onAudioRequest)
                }
            }
            .padding()
        }
    }

    private var renderedText: Text {
        // AttributedString handles inline markdown; on parse failure fall back
        // to the raw text so a malformed snippet doesn't blank the screen.
        if let attributed = try? AttributedString(markdown: block.text) {
            return Text(attributed)
        }
        return Text(block.text)
    }
}

/// Lightweight media chip embedded in an explanation block. Audio surfaces
/// as a play button; image / video reserve a slot for future inline preview.
struct MediaAttachmentView: View {
    let media: MediaRef
    let pack: InstalledPack
    let onAudioRequest: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let path = media.audio, let url = pack.mediaURL(forRelativePath: path) {
                Button {
                    onAudioRequest(url)
                } label: {
                    Label {
                        Text("button.playAudio", bundle: .module)
                    } icon: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                }
                .buttonStyle(.bordered)
            }
            if let path = media.image, let url = pack.mediaURL(forRelativePath: path) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Color.clear.frame(height: 0)
                    }
                }
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
