import SwiftUI

/// Renders a `vocabulary` block as a stack of cards. Each item gets a card
/// with the target word, transliteration, IPA, translation, optional audio
/// button, and any v1.1 example sentences. We deliberately avoid platform-
/// specific paging APIs (`PageTabViewStyle` is iOS-only) and use a plain
/// vertical scroll so the SDK stays clean across iOS / macOS development
/// environments. A real card carousel can come in Phase 3g if the demo app
/// asks for it.
public struct VocabularyBlockView: View {
    public let block: VocabularyBlock
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void

    public init(block: VocabularyBlock, pack: InstalledPack, onAudioRequest: @escaping (URL) -> Void) {
        self.block = block
        self.pack = pack
        self.onAudioRequest = onAudioRequest
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { idx, item in
                    VocabularyCardView(
                        item: item,
                        index: idx + 1,
                        total: block.items.count,
                        pack: pack,
                        onAudioRequest: onAudioRequest
                    )
                }
            }
            .padding()
        }
    }
}

/// One vocabulary entry — target word, pronunciation hints, translation,
/// audio play button, and example sentences if present.
public struct VocabularyCardView: View {
    public let item: VocabularyItem
    public let index: Int
    public let total: Int
    public let pack: InstalledPack
    public let onAudioRequest: (URL) -> Void

    public init(
        item: VocabularyItem,
        index: Int,
        total: Int,
        pack: InstalledPack,
        onAudioRequest: @escaping (URL) -> Void
    ) {
        self.item = item
        self.index = index
        self.total = total
        self.pack = pack
        self.onAudioRequest = onAudioRequest
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardCounter

            VStack(alignment: .center, spacing: 8) {
                Text(item.target)
                    .font(.system(size: 40, weight: .semibold))
                    .multilineTextAlignment(.center)

                if let translit = item.transliteration {
                    Text(translit)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let ipa = item.ipa {
                    Text(ipa)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            Text(item.translation)
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .center)

            if let audioPath = item.audio, let url = pack.mediaURL(forRelativePath: audioPath) {
                Button {
                    onAudioRequest(url)
                } label: {
                    Label {
                        Text("button.playAudio", bundle: .module)
                    } icon: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if !item.examples.isEmpty {
                ExampleList(examples: item.examples, pack: pack, onAudioRequest: onAudioRequest)
            }

            if let notes = item.notes, !notes.isEmpty {
                NotesSection(text: notes)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var cardCounter: some View {
        HStack {
            Spacer()
            Text(
                String(
                    format: NSLocalizedString("vocabulary.cardCount", bundle: .module, comment: ""),
                    locale: .current,
                    index, total
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct ExampleList: View {
    let examples: [VocabularyExample]
    let pack: InstalledPack
    let onAudioRequest: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("section.examples", bundle: .module)
                .font(.headline)
            ForEach(Array(examples.enumerated()), id: \.offset) { _, ex in
                VStack(alignment: .leading, spacing: 4) {
                    Text(ex.text).font(.body)
                    Text(ex.translation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let path = ex.audio, let url = pack.mediaURL(forRelativePath: path) {
                        Button {
                            onAudioRequest(url)
                        } label: {
                            Label {
                                Text("button.playAudio", bundle: .module)
                            } icon: {
                                Image(systemName: "speaker.wave.2")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct NotesSection: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("section.notes", bundle: .module)
                .font(.headline)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
