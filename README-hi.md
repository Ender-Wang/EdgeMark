<img src=".github/assets/EdgeMark.svg" alt="EdgeMark" width="128" align="left" />

<b><font>EdgeMark</font></b>

 एक नेटिव macOS साइड-पैनल Markdown नोट्स ऐप। हमेशा एक किनारे की दूरी पर।

<br clear="all" />

<p align="center">
  <a href="README.md">English</a> · <a href="README-zh-Hans.md">简体中文</a> · <b>हिन्दी</b> · <a href="README-ES.md">Español</a>
</p>

<p align="center">
  <a href="https://github.com/Ender-Wang/EdgeMark/releases"><img src="https://img.shields.io/github/v/release/Ender-Wang/EdgeMark?label=Latest%20Release&color=green" alt="Latest Release" /></a>
  <a href="https://github.com/Ender-Wang/EdgeMark/releases"><img src="https://img.shields.io/github/downloads/Ender-Wang/EdgeMark/total?color=green" alt="Total Downloads" /></a>
  <br />
  <img src="https://img.shields.io/badge/Swift-6.2-orange?logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/macOS-15.7+-black?logo=apple" alt="macOS" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Ender-Wang/EdgeMark?color=blue" alt="License" /></a>
</p>

**EdgeMark क्यों बनाया गया:** [SideNotes](https://www.apptorium.com/sidenotes) ने इंटरैक्शन को सही अंदाज़ में पकड़ा — एक नोट्स पैनल जो स्क्रीन के किनारे से स्लाइड होकर आता है, हमेशा एक जेस्चर दूर। लेकिन यह क्लोज्ड-सोर्स और पेड है — योगदान, कस्टमाइज़ या जाँच का कोई तरीका नहीं कि यह आपके डेटा के साथ क्या करता है।

EdgeMark ओपन-सोर्स विकल्प है: **हल्का, Markdown-फर्स्ट**, और आपके जाँचने, संशोधित करने और बढ़ाने के लिए। आपके नोट्स डिस्क पर सादे `.md` फ़ाइलें हैं — किसी भी एडिटर में खोलें, किसी भी सेवा से सिंक करें, जैसे चाहें बैकअप लें।

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/screenshot-dark.png" />
    <source media="(prefers-color-scheme: light)" srcset=".github/assets/screenshot-light.png" />
    <img alt="EdgeMark Screenshots" src=".github/assets/screenshot-light.png" />
  </picture>
</p>

# इंस्टॉल

```bash
brew install --cask ender-wang/tap/edgemark
```

या [Releases](https://github.com/Ender-Wang/EdgeMark/releases) से नवीनतम `.dmg` डाउनलोड करें, इंस्टॉल करें, फिर टर्मिनल में यह रन करें:

```bash
xattr -cr /Applications/EdgeMark.app
```

---

# फ़ीचर्स

🪟 **साइड पैनल**

- 🔲 बॉर्डरलेस फ़्लोटिंग पैनल, फ़ुल-हाइट, हमेशा ऊपर
- 🖥️ हर वर्चुअल डेस्कटॉप और फुलस्क्रीन ऐप्स के साथ काम करता है
- ✨ स्मूद स्लाइड-इन/आउट या फ़ेड एनिमेशन (कॉन्फ़िगरेबल), एज एक्टिवेशन के साथ — स्क्रीन किनारे पर माउस ले जाकर खोलें
- 🖱️ बाहर क्लिक, Escape, या ऑटो-हाइड से डिस्मिस
- 📌 पैनल खुला रखने के लिए पिन करें — फ़ोकस बदलने, माउस बाहर जाने और स्पेस स्विच पर भी बना रहता है (आना-जाना कॉपी-पेस्ट के लिए बढ़िया)
- 📐 मल्टी-मॉनिटर सपोर्ट, कॉन्फ़िगरेबल लेफ्ट या राइट एज
- ↔️ एडजस्टेबल चौड़ाई — भीतरी किनारे को ड्रैग करके रीसाइज़ करें, रीस्टार्ट पर सेव
- 🪟 पैनल स्टाइल — ट्रांसलुसेंट और ओपेक पैनल बैकग्राउंड के बीच टॉगल
- 🎨 पैनल टिंट — क्यूरेटेड पैलेट में से चुनें (System, Graphite, Slate, Sand, Sage, Rose)

✍️ **Markdown एडिटिंग**

- 👁️ नेटिव TextKit 2 WYSIWYG एडिटर — [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) द्वारा संचालित, कोई JavaScript या WebKit नहीं
- 📝 फ़ुल Markdown: हेडिंग्स, बोल्ड, इटैलिक, कोड, लिस्ट्स, टास्क लिस्ट्स, ब्लॉककोट्स, लिंक्स, टेबल्स, विकि-लिंक्स
- 🖼️ इनलाइन इमेजेज — पेस्ट (`⌘V`) या ड्रैग करके एम्बेड; नोट के साथ को-लोकेटेड एसेट फ़ाइलों में स्टोर
- ✅ चेक किए गए टास्क आइटम ऑटोमैटिकली स्ट्राइक-थ्रू; अनचेक करें तो रिस्टोर
- 📋 फेंस्ड कोड ब्लॉक पर वन-क्लिक कॉपी बटन
- 🔴 नेटिव स्पेल चेक, ग्रामर चेक और ऑटोकरेक्ट (macOS सिस्टम डिक्शनरी)
- ⚡ स्लैश कमांड्स (`/h1`, `/todo`, `/code`, `/quote`, `/table`, `/divider`, और और भी)
- ⌨️ फ़ॉर्मेटिंग शॉर्टकट्स: `⌘B` बोल्ड, `⌘I` इटैलिक, `⌘E` इनलाइन कोड, `⌘K` लिंक, `⇧⌘X` स्ट्राइकथ्रू
- 🔗 रेंडर किए गए लिंक पर क्लिक कर ब्राउज़र में खोलें
- 🔍 फाइंड और रिप्लेस (`⌘F`)
- 🔤 कस्टमाइज़ेबल एडिटर फ़ॉन्ट और साइज़ — सिस्टम फ़ॉन्ट पैनल से कोई भी इंस्टॉल्ड फ़ॉन्ट चुनें, लाइव प्रीव्यू के साथ
- 🧮 LaTeX रेंडरिंग — ब्लॉक (`$$...$$`) और इनलाइन (`$...$`) SwiftMath द्वारा

🗂️ **नोट्स और स्टोरेज**

- 📄 सादे `.md` फ़ाइलें, कोई इंजेक्टेड हेडर नहीं — किसी भी एडिटर में खोलें, किसी भी सेवा से सिंक करें; मेटाडेटा हिडन `.edgemark/meta.json` साइडकार में रहता है
- 📁 फ़ोल्डर-आधारित ऑर्गनाइज़ेशन, ड्रैग-और-ड्रॉप के साथ
- 🎨 कस्टम फ़ोल्डर रंग — राइट-क्लिक → फ़ोल्डर रंग से किसी भी फ़ोल्डर के आइकन को पैलेट रंग में टिंट करें
- 📂 कॉन्फ़िगरेबल स्टोरेज डायरेक्टरी
- 💾 1-सेकंड डिबाउंस्ड ऑटो-सेव
- 🔍 सर्च खाली होने पर सभी नोट्स हाल में बदले गए क्रम में — एक त्वरित "रिसेंट नोट्स" फ़ीड
- 🏷️ फाइंडर-स्टाइल कलर टैग्स (Red, Orange, Yellow, Green, Blue, Purple, Gray), रीनेम-एबल लेबल के साथ; प्रति नोट मल्टी-टैग
- 🎯 सर्च के अंदर टैग फ़िल्टर — टैग डॉट्स पर क्लिक कर नैरो करें, मल्टी-सेलेक्ट OR की तरह, टेक्स्ट सर्च के साथ कंबाइन
- ☑️ नेटिव macOS मल्टी-सेलेक्शन — क्लिक / ⇧-क्लिक / ⌘-क्लिक पंक्तियाँ, मार्की-ड्रैग से बॉक्स-सेलेक्ट, फिर राइट-क्लिक मेनू से बैच **Move**, **Tag**, या **Trash**; बैच में टकराव कतारबद्ध और हल करने योग्य
- 🔄 एक्सटर्नल फ़ाइल सिंक — दूसरे ऐप्स के एडिट पैनल खुलने पर डिटेक्ट; दोनों तरफ बदलाव होने पर प्रॉम्ट
- 🗑️ ट्रैश, 30-दिन ऑटो-पर्ज और रीड-ओनली प्रीव्यू के साथ
- 👁️ हॉवर-टू-पीक — नोट या फ़ोल्डर पंक्ति पर हॉवर कर कंटेंट फ़्लोटिंग पैनल में प्रीव्यू; नोट प्रीव्यू फ़ुल Markdown इमेजेज के साथ, फ़ोल्डर प्रीव्यू में सबफ़ोल्डर और सभी नोट्स

⌨️ **कीबोर्ड और शॉर्टकट्स**

- 🌐 ग्लोबल शॉर्टकट: `Ctrl+Shift+Space` किसी भी ऐप से टॉगल (कस्टमाइज़ेबल)
- 🎹 फुली कस्टमाइज़ेबल लोकल शॉर्टकट्स — नया नोट, नया फ़ोल्डर, सर्च, पिन, प्रीवियस/नेक्स्ट नोट — सब सेटिंग्स में रीबाइंड और कॉन्फ्लिक्ट डिटेक्शन के साथ
- ⏱️ कॉन्फ़िगरेबल एक्टिवेशन डिले और कॉर्नर एक्सक्लूज़न ज़ोन
- 🔑 डिफ़ॉल्ट पैनल शॉर्टकट्स: `⌘N` नया नोट, `⇧⌘N` नया फ़ोल्डर, `⌘F` सर्च, `⌘P` पिन/अनपिन
- 👁️ `Space` से क्विक लुक — नोट या फ़ोल्डर सेलेक्ट कर `Space` दबाकर प्रीव्यू; `↑↓` ब्राउज़, `Space`/`ESC` डिस्मिस
- 👆 हेडर पर टू-फ़िंगर राइट स्वाइप से बैक नेविगेट (कॉन्फ़िगरेबल टॉगल और सेंसिटिविटी)
- 👆 एडिटर पर टू-फ़िंगर लेफ्ट/राइट स्वाइप या `⌘←`/`⌘→` से करंट फ़ोल्डर के नोट्स के बीच नेविगेट

🔄 **ऑटो-अपडेट और CI/CD**

- 🔔 इन-ऐप अपडेट चेक (GitHub Releases, 24h थ्रॉटल)
- 📦 प्रोग्रेस बार के साथ डाउनलोड, SHA256 वेरिफिकेशन, इंस्टॉल और रीस्टार्ट
- ⚙️ GitHub Actions बिल्ड पाइपलाइन (अनसाइंड Release, DMG, SHA256)
- 🍺 Homebrew Cask इंस्टालेशन

🌟 **क्वालिटी ऑफ़ लाइफ**

- 🌗 अपीयरेंस ओवरराइड: System, Light, या Dark मोड
- 📌 मेन्यू बार रेज़िडेंट (कोई Dock आइकन नहीं)
- 🚀 लॉगिन पर लॉन्च
- 📋 कॉपी ऐज़ प्लेन टेक्स्ट, Markdown, या रिच टेक्स्ट — एडिटर में सेलेक्शन-अवेयर राइट-क्लिक कॉन्टेक्स्ट मेन्यू
- 🎨 सभी कॉन्टेक्स्ट मेन्यू में SF Symbol आइकन्स
- 🔀 स्मूद डायरेक्शनल पेज ट्रांज़िशन्स
- 🌍 English + 简体中文 + हिन्दी + Español (JSON-आधारित, योगदान देना आसान)

---

# योगदान

आर्किटेक्चर ओवरव्यू, सोर्स ट्री, की पैटर्न्स, लोकलाइज़ेशन गाइड और डेवलपमेंट सेटअप के लिए [CONTRIBUTING.md](CONTRIBUTING.md) देखें।

---

# लाइसेंस

EdgeMark [GNU General Public License v3.0](LICENSE) के तहत लाइसेंस्ड है।

# अभिस्वीकृतियाँ

EdgeMark इन ओपन-सोर्स प्रोजेक्ट्स के ऊपर बना है:

| प्रोजेक्ट | लाइसेंस | विवरण |
|---------|---------|-------------|
| [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) | Apache 2.0 | TextKit 2 / NSTextView WYSIWYG Markdown एडिटर — एडिटिंग अनुभव को पावर देता है। कोड ब्लॉक सिंटैक्स हाइलाइटिंग के लिए [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) और LaTeX रेंडरिंग के लिए [SwiftMath](https://github.com/mgriebling/SwiftMath) बंडल करता है। |
| [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) | MIT | बिल्ड पाइपलाइन में उपयोग कोड फ़ॉर्मेटिंग टूल |

---

# Star हिस्ट्री

<a href="https://star-history.com/#Ender-Wang/EdgeMark&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Ender-Wang/EdgeMark&type=Date" />
 </picture>
</a>
