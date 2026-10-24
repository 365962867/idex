import SwiftUI

struct CatalogSheet: View {
    @Bindable var store: DexStore
    @State private var query = ""
    @State private var seenOnly = false

    var body: some View {
        NavigationStack {
            let matches = results
            VStack(spacing: 0) {
                Toggle(store.text("Discovered only", "仅显示已发现"), isOn: $seenOnly)
                    .font(.system(size: 13, design: .monospaced)).padding(.horizontal, 20).padding(.vertical, 10)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 12)], spacing: 12) {
                        ForEach(matches) { pokemon in
                            Button {
                                store.browse(pokemon)
                            } label: {
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("#\(pokemon.number)").font(DexTheme.pixel(7))
                                        Spacer()
                                        if store.seenIDs.contains(pokemon.id) { Image(systemName: "checkmark.seal.fill").font(.system(size: 11)) }
                                    }
                                    Image(pokemon.spriteName).resizable().interpolation(.none).scaledToFit().frame(height: 80).accessibilityHidden(true)
                                    Text(pokemon.name(in: store.language))
                                        .font(PixelFont.font(size: store.language == .en ? 8 : 16, language: store.language))
                                        .lineLimit(1).minimumScaleFactor(0.5)
                                }.padding(12).foregroundStyle(DexTheme.ink)
                                    .background(DexTheme.lcd, in: RoundedRectangle(cornerRadius: 5))
                            }.buttonStyle(.plain).accessibilityIdentifier("pokemon-\(pokemon.id)")
                        }
                    }.padding(20)
                    if matches.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .background(DexTheme.charcoal)
            .navigationTitle(store.text("Kanto archive", "关都图鉴"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: store.text("Name, number or type", "名称、编号或属性"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.text("Done", "完成")) { store.showingCatalog = false }.accessibilityIdentifier("settings-done") } }
        }.preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: store.language == .en ? "en" : "zh-Hans"))
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
    }

    private var results: [Pokemon] {
        PokemonCatalog.shared.search(query, language: store.language).filter { !seenOnly || store.seenIDs.contains($0.id) }
    }
}

struct SettingsSheet: View {
    @Bindable var store: DexStore
    var body: some View {
        @Bindable var audio = store.audio
        NavigationStack {
            Form {
                Section(store.text("Language / 语言", "语言 / Language")) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            store.language = language
                            store.audio.play(.button)
                        } label: {
                            HStack {
                                Text(language.title).foregroundStyle(.primary)
                                Spacer()
                                if store.language == language { Image(systemName: "checkmark").foregroundStyle(.green) }
                            }
                        }.accessibilityIdentifier("language-\(language.rawValue)")
                    }
                }
                Section(store.text("Sound", "声音")) {
                    Toggle(store.text("Device sounds & spoken entries", "设备音效与图鉴语音"), isOn: $audio.isSoundEnabled)
                        .accessibilityIdentifier("sound-toggle")
                    Button(store.text("Stop reading", "停止朗读")) { audio.stopSpeaking() }
                }
                Section(store.text("Field guide", "使用指南")) {
                    Label(store.text("Point at a Pokémon, then identify.", "将取景器对准宝可梦，轻点识别。"), systemImage: "viewfinder")
                    Label(store.text("Unfold to reveal the research panel.", "展开屏幕，查看内部研究面板。"), systemImage: "book")
                    Label(store.text("Photos and recognition stay on your iPhone.", "照片与识别过程均留在你的 iPhone 上。"), systemImage: "lock.shield")
                    Text(store.text("The bundled model recognizes the original 151 Kanto Pokémon. Uncertain scans ask you to try again. Samples use the same model as your camera.", "内置模型可识别最初的151种关都宝可梦。匹配不确定时会提示重试。样本与相机使用相同的识别模型。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(store.text("Credits", "制作信息")) {
                    Text("iDex · FIELD UNIT 001").font(DexTheme.pixel(8))
                    Text(store.text("An independent fan project. Pokémon and its characters belong to Nintendo, Creatures, and GAME FREAK. Not affiliated with or endorsed by them.", "独立粉丝项目。宝可梦及相关角色归任天堂、Creatures及GAME FREAK所有。本项目与其无关联，亦未获得其认可。"))
                        .font(.footnote).foregroundStyle(.secondary)
                    Link(store.text("Sprites · Pokémon Database", "像素图 · Pokémon Database"), destination: URL(string: "https://pokemondb.net/sprites")!)
                    Link(store.text("Pokédex data · PokéAPI", "图鉴数据 · PokéAPI"), destination: URL(string: "https://github.com/PokeAPI/pokeapi")!)
                    Link(store.text("On-device model · BiernyVR", "本地模型 · BiernyVR"), destination: URL(string: "https://huggingface.co/BiernyVR/pokemon-classifier-mobilenetv3")!)
                    Text("Press Start 2P · Fusion Pixel · SIL OFL 1.1").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle(store.text("Device settings", "设备设置"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.text("Done", "完成")) { store.showingSettings = false }.accessibilityIdentifier("settings-done") } }
        }.preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: store.language == .en ? "en" : "zh-Hans"))
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
    }
}
