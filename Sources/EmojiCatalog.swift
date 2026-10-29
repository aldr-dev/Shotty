import Foundation

/// Emoji grouped like the macOS picker. Glyphs come from Apple Color Emoji, names from the system's
/// own emoji name tables, so search works in Russian and English.
enum EmojiCatalog {
    struct Category: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let emojis: [String]
    }

    static var categories: [Category] {
        [
            Category(id: "smileys", title: L("Смайлики"), symbol: "face.smiling", emojis: list("""
            😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 🫠 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🫢 🫣 🤫 🤔 🫡 \
            🤐 🤨 😐 😑 😶 🫥 😶‍🌫️ 😏 😒 🙄 😬 😮‍💨 🤥 🫨 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 😵‍💫 🤯 🤠 🥳 🥸 \
            😎 🤓 🧐 😕 🫤 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 🥹 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 \
            ☠️ 💩 🤡 👹 👺 👻 👽 👾 🤖 😺 😸 😹 😻 😼 😽 🙀 😿 😾 🙈 🙉 🙊 💋 💯 💢 💥 💫 💦 💨 🕳️ 💬 👁️‍🗨️ 🗨️ 🗯️ 💭 💤
            """)),
            Category(id: "people", title: L("Люди и жесты"), symbol: "hand.wave", emojis: list("""
            👋 🤚 🖐️ ✋ 🖖 🫱 🫲 🫳 🫴 🫷 🫸 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 🫵 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 \
            👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 🦵 🦶 👂 👃 🧠 🫀 🫁 🦷 🦴 👀 👁️ 👅 👄 🫦 👶 🧒 👦 👧 🧑 👱 👨 🧔 👩 🧓 👴 👵 \
            🙍 🙎 🙅 🙆 💁 🙋 🧏 🙇 🤦 🤷 🧑‍💻 👨‍💻 👩‍💻 🧑‍🔧 🧑‍🏫 🧑‍⚕️ 🧑‍🍳 🧑‍🚀 👮 🕵️ 💂 🥷 👷 🤴 👸 🦸 🦹 🧙 🧚 🧛 🧜 🧝 🧞 🧟 \
            🚶 🏃 💃 🕺 👯 🧘 🛀 🛌 👭 👫 👬 💏 💑 👪 🗣️ 👤 👥 🫂 👣 ❤️ 🧡 💛 💚 💙 🩵 💜 🤎 🖤 🩶 🤍 💔 ❤️‍🔥 ❣️ 💕 💞 💓 💗 💖 💘 💝
            """)),
            Category(id: "nature", title: L("Животные и природа"), symbol: "leaf", emojis: list("""
            🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐻‍❄️ 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🫎 🐝 🪱 🐛 🦋 🐌 🐞 🐜 \
            🪲 🪳 🦟 🦗 🕷️ 🦂 🐢 🐍 🦎 🦖 🦕 🐙 🦑 🦐 🦞 🦀 🪼 🐡 🐠 🐟 🐬 🐳 🐋 🦈 🦭 🐊 🐅 🐆 🦓 🦍 🦧 🐘 🦛 🦏 🐪 🐫 \
            🦒 🦘 🦬 🐃 🐂 🐄 🐎 🐖 🐏 🐑 🦙 🐐 🦌 🐕 🐩 🦮 🐈 🐈‍⬛ 🪶 🐓 🦃 🦤 🦚 🦜 🦢 🦩 🕊️ 🐇 🦝 🦨 🦡 🦫 🦦 🦥 🐁 🐀 🐿️ \
            🦔 🐾 🐉 🐲 🌵 🎄 🌲 🌳 🌴 🪵 🌱 🌿 ☘️ 🍀 🎍 🪴 🎋 🍃 🍂 🍁 🍄 🐚 🪸 🪨 🌾 💐 🌷 🌹 🥀 🪷 🌺 🌸 🌼 🌻 🌞 🌝 🌛 \
            🌜 🌚 🌕 🌙 🌎 🌍 🌏 🪐 💫 ⭐️ 🌟 ✨ ⚡️ ☄️ 💥 🔥 🌪️ 🌈 ☀️ 🌤️ ⛅️ 🌥️ ☁️ 🌦️ 🌧️ ⛈️ 🌩️ 🌨️ ❄️ ☃️ ⛄️ 🌬️ 💨 💧 💦 🫧 ☔️ 🌊
            """)),
            Category(id: "food", title: L("Еда и напитки"), symbol: "fork.knife", emojis: list("""
            🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🫑 🌽 🥕 🫒 🧄 🧅 🥔 🍠 🫘 🥐 🥯 🍞 \
            🥖 🥨 🧀 🥚 🍳 🧈 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🫓 🥪 🥙 🧆 🌮 🌯 🫔 🥗 🥘 🫕 🥫 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🦪 🍤 \
            🍙 🍚 🍘 🍥 🥠 🥮 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 🍼 🫖 ☕️ 🍵 🧃 🥤 🧋 🍶 🍺 🍻 \
            🥂 🍷 🥃 🍸 🍹 🧉 🍾 🧊 🥄 🍴 🍽️ 🥣 🥡 🥢 🧂
            """)),
            Category(id: "activity", title: L("Активность"), symbol: "soccerball", emojis: list("""
            ⚽️ 🏀 🏈 ⚾️ 🥎 🎾 🏐 🏉 🥏 🎱 🪀 🏓 🏸 🏒 🏑 🥍 🏏 🪃 🥅 ⛳️ 🪁 🏹 🎣 🤿 🥊 🥋 🎽 🛹 🛼 🛷 ⛸️ 🥌 🎿 ⛷️ 🏂 🪂 \
            🏋️ 🤼 🤸 ⛹️ 🤺 🤾 🏌️ 🏇 🧘 🏄 🏊 🤽 🚣 🧗 🚵 🚴 🏆 🥇 🥈 🥉 🏅 🎖️ 🏵️ 🎗️ 🎫 🎟️ 🎪 🤹 🎭 🩰 🎨 🎬 🎤 🎧 🎼 🎹 \
            🥁 🪘 🎷 🎺 🪗 🎸 🪕 🎻 🪈 🎲 ♟️ 🎯 🎳 🎮 🎰 🧩 🎉 🎊 🎈 🎁 🎀 🪅 🪩
            """)),
            Category(id: "travel", title: L("Путешествия и места"), symbol: "car", emojis: list("""
            🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🦯 🦽 🦼 🛴 🚲 🛵 🏍️ 🛺 🚨 🚔 🚍 🚘 🚖 🚡 🚠 🚟 🚃 🚋 🚞 🚝 🚄 🚅 \
            🚈 🚂 🚆 🚇 🚊 🚉 ✈️ 🛫 🛬 🛩️ 💺 🛰️ 🚀 🛸 🚁 🛶 ⛵️ 🚤 🛥️ 🛳️ ⛴️ 🚢 ⚓️ 🛟 🪝 ⛽️ 🚧 🚦 🚥 🚏 🗺️ 🗿 🗽 🗼 🏰 🏯 \
            🏟️ 🎡 🎢 🎠 ⛲️ ⛱️ 🏖️ 🏝️ 🏜️ 🌋 ⛰️ 🏔️ 🗻 🏕️ ⛺️ 🛖 🏠 🏡 🏘️ 🏚️ 🏗️ 🏭 🏢 🏬 🏣 🏤 🏥 🏦 🏨 🏪 🏫 🏩 💒 🏛️ ⛪️ 🕌 \
            🕍 🛕 🕋 ⛩️ 🛤️ 🛣️ 🗾 🎑 🏞️ 🌅 🌄 🌠 🎇 🎆 🌇 🌆 🏙️ 🌃 🌌 🌉 🌁
            """)),
            Category(id: "objects", title: L("Предметы"), symbol: "lightbulb", emojis: list("""
            ⌚️ 📱 📲 💻 ⌨️ 🖥️ 🖨️ 🖱️ 🖲️ 🕹️ 🗜️ 💽 💾 💿 📀 📼 📷 📸 📹 🎥 📽️ 🎞️ 📞 ☎️ 📟 📠 📺 📻 🎙️ 🎚️ 🎛️ 🧭 ⏱️ ⏲️ ⏰ 🕰️ \
            ⌛️ ⏳ 📡 🔋 🪫 🔌 💡 🔦 🕯️ 🪔 🧯 🛢️ 💸 💵 💴 💶 💷 🪙 💰 💳 🪪 💎 ⚖️ 🪜 🧰 🪛 🔧 🔨 ⚒️ 🛠️ ⛏️ 🪚 🔩 ⚙️ 🪤 🧱 \
            ⛓️ 🧲 🔫 💣 🧨 🪓 🔪 🗡️ ⚔️ 🛡️ 🚬 ⚰️ 🪦 ⚱️ 🏺 🔮 📿 🧿 🪬 💈 ⚗️ 🔭 🔬 🩹 🩺 🩻 💊 💉 🩸 🧬 🦠 🧫 🧪 🌡️ 🧹 🪠 \
            🧺 🧻 🚽 🚰 🚿 🛁 🧼 🪥 🪒 🧽 🪣 🧴 🛎️ 🔑 🗝️ 🚪 🪑 🛋️ 🛏️ 🧸 🪆 🖼️ 🪞 🪟 🛍️ 🛒 🎁 🎈 🎏 🎀 🪄 🪅 🎊 🎉 🎎 🏮 \
            🎐 🧧 ✉️ 📩 📨 📧 💌 📥 📤 📦 🏷️ 🪧 📪 📫 📬 📭 📮 📯 📜 📃 📄 📑 🧾 📊 📈 📉 🗒️ 🗓️ 📆 📅 🗑️ 📇 🗃️ 🗳️ 🗄️ 📋 \
            📁 📂 🗂️ 🗞️ 📰 📓 📔 📒 📕 📗 📘 📙 📚 📖 🔖 🧷 🔗 📎 🖇️ 📐 📏 🧮 📌 📍 ✂️ 🖊️ 🖋️ ✒️ 🖌️ 🖍️ 📝 ✏️ 🔍 🔎 🔏 🔐 🔒 🔓
            """)),
            Category(id: "symbols", title: L("Символы"), symbol: "heart", emojis: list("""
            ✅ ☑️ ✔️ ❌ ❎ ➕ ➖ ➗ ✖️ 🟰 ♾️ ❓ ❔ ❗️ ❕ ‼️ ⁉️ ⚠️ 🚸 ⛔️ 🚫 📛 🔞 📵 🚭 🆘 🆗 🆕 🆒 🆓 🆙 🔝 🔜 🔛 🔚 🔙 \
            ⬆️ ↗️ ➡️ ↘️ ⬇️ ↙️ ⬅️ ↖️ ↕️ ↔️ ↩️ ↪️ ⤴️ ⤵️ 🔀 🔁 🔂 🔄 🔃 ▶️ ⏸️ ⏯️ ⏹️ ⏺️ ⏭️ ⏮️ ⏩ ⏪ ⏫ ⏬ ◀️ 🔼 🔽 🎦 🔅 🔆 \
            📶 🛜 📳 📴 ♻️ ⚜️ 🔱 🔰 ⭕️ 🛑 💯 🔟 🔢 #️⃣ *️⃣ 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔠 🔡 🔤 🅰️ 🅱️ 🆎 🅾️ ℹ️ Ⓜ️ 🅿️ \
            ©️ ®️ ™️ 💲 💱 〰️ ➰ ➿ 🔴 🟠 🟡 🟢 🔵 🟣 🟤 ⚫️ ⚪️ 🟥 🟧 🟨 🟩 🟦 🟪 🟫 ⬛️ ⬜️ ◼️ ◻️ ◾️ ◽️ ▪️ ▫️ 🔶 🔷 🔸 🔹 🔺 🔻 \
            💠 🔘 🔳 🔲 🏁 🚩 🎌 🏴 🏳️ 🏳️‍🌈 🏴‍☠️ 🔔 🔕 📣 📢 💬 💭 🗯️ ♠️ ♣️ ♥️ ♦️ 🃏 🎴 🀄️ ☮️ ✝️ ☪️ 🕉️ ☯️ ✡️ ☸️ ♈️ ♉️ ♊️ ♋️ ♌️ ♍️ \
            ♎️ ♏️ ♐️ ♑️ ♒️ ♓️ ⛎ 🆔 ⚛️ 🉑 ☢️ ☣️ 💮 🉐 ㊙️ ㊗️ 🈴 🈵 🈹 🈲 🔆 〽️
            """)),
            Category(id: "flags", title: L("Флаги"), symbol: "flag", emojis: list("""
            🏳️ 🏴 🏁 🚩 🏳️‍🌈 🏳️‍⚧️ 🏴‍☠️ 🇷🇺 🇺🇦 🇧🇾 🇰🇿 🇺🇿 🇰🇬 🇹🇯 🇹🇲 🇦🇲 🇦🇿 🇬🇪 🇲🇩 🇺🇸 🇬🇧 🇩🇪 🇫🇷 🇮🇹 🇪🇸 🇵🇹 🇳🇱 🇧🇪 🇨🇭 🇦🇹 🇵🇱 \
            🇨🇿 🇸🇰 🇭🇺 🇷🇴 🇧🇬 🇷🇸 🇭🇷 🇸🇮 🇬🇷 🇹🇷 🇮🇱 🇪🇬 🇦🇪 🇸🇦 🇮🇳 🇨🇳 🇯🇵 🇰🇷 🇹🇭 🇻🇳 🇮🇩 🇲🇾 🇸🇬 🇵🇭 🇦🇺 🇳🇿 🇨🇦 🇲🇽 🇧🇷 🇦🇷 🇨🇱 \
            🇨🇴 🇵🇪 🇿🇦 🇳🇬 🇰🇪 🇸🇪 🇳🇴 🇫🇮 🇩🇰 🇮🇸 🇮🇪 🇪🇪 🇱🇻 🇱🇹 🇪🇺 🇺🇳
            """)),
        ]
    }

    private static func list(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    // MARK: Search

    /// Russian and English names from CoreEmoji; empty when the system tables aren't readable.
    private static let names: [String: String] = {
        let base = "/System/Library/PrivateFrameworks/CoreEmoji.framework/Versions/A/Resources/"
        var result: [String: String] = [:]
        for lang in ["en", "ru"] {
            guard let dict = NSDictionary(contentsOfFile: base + lang + ".lproj/AppleName.strings") as? [String: String]
            else { continue }
            for (emoji, name) in dict {
                result[normalized(emoji), default: ""] += " " + name.lowercased()
            }
        }
        return result
    }()

    /// The name tables key some emoji without the U+FE0F variation selector and some with it.
    private static func normalized(_ emoji: String) -> String {
        emoji.replacingOccurrences(of: "\u{FE0F}", with: "")
    }

    static func search(_ query: String) -> [String] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var seen = Set<String>()
        return categories.flatMap(\.emojis).filter { emoji in
            guard seen.insert(emoji).inserted, let name = names[normalized(emoji)] else { return false }
            return words.allSatisfy { name.contains($0) }
        }
    }

    // MARK: Recents

    private static let recentsKey = "emoji.recent"

    static var recents: [String] {
        UserDefaults.standard.stringArray(forKey: recentsKey) ?? ["👍", "🔥", "😂", "❤️", "✅", "❌", "👀", "🎉"]
    }

    static func noteUsed(_ emoji: String) {
        var list = recents.filter { $0 != emoji }
        list.insert(emoji, at: 0)
        UserDefaults.standard.set(Array(list.prefix(24)), forKey: recentsKey)
    }
}
