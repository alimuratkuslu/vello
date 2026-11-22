<p align="center">
  <img src="Vello/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="128" height="128" alt="Vello icon">
</p>

<h1 align="center">Vello</h1>

<p align="center">Free, private, on-device dictation for macOS. Hold a key, speak, let go: your words are typed wherever your cursor is.</p>

<p align="center"><a href="https://github.com/alimuratkuslu/vello/releases/latest"><b>Download for Mac</b></a></p>

- **Runs on your Mac.** Speech recognition is local (Whisper large-v3 turbo via [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)). No account, no cloud, no subscription. Works offline after the first launch.
- **Fast.** Speech is transcribed in the background while you talk, so even a one-minute dictation is typed about a second after you let go.
- **Mixed language friendly.** Built for speaking Turkish with English technical words, and works in any language Whisper supports.
- **Lightweight.** Lives in the menu bar, no Dock icon.

[Türkçe](#türkçe)

## Install

1. Download `Vello-x.y.z.dmg` from [Releases](../../releases) and drag Vello to Applications.
2. Open Vello and follow the setup window: pick your speaking language and talk key, allow Microphone and Accessibility, and wait for the speech model (~600 MB, one time).
3. Hold **Right Option** (or the key you picked), speak, release.

Requires macOS 14 or later on Apple Silicon.

## Tips

- **Word list:** Settings → Word list. Add names and terms you use often; they come out spelled right more often. Keep it under ~40 words, longer lists slow typing down.
- **AirPods:** with the microphone on *Automatic*, Vello records from the MacBook mic while AirPods are connected, so your music isn't degraded and the first word isn't cut off.
- **In calls:** Vello works during Zoom, Meet, Teams or Slack calls, but the people on the call hear you dictating unless you mute yourself there.
- **Settings:** open Vello again from Launchpad or Finder, or use the menu bar icon → Settings.

## Türkçe

Vello, macOS için ücretsiz ve tamamen cihaz üzerinde çalışan bir dikte uygulaması. Tuşu basılı tut, konuş, bırak: söylediklerin imlecin olduğu yere yazılır.

- Ses tanıma tamamen Mac'inde çalışır; hesap, bulut veya abonelik yok. İlk açılıştan sonra internetsiz çalışır.
- Konuşurken arka planda çevirir; bir dakikalık Dikte bile tuşu bıraktıktan yaklaşık bir saniye sonra yazılır.
- Türkçe içinde İngilizce teknik kelimelerle konuşmak için tasarlandı.

**Kurulum:** [Releases](../../releases) sayfasından `Vello-x.y.z.dmg` dosyasını indir, Vello'yu Uygulamalar klasörüne sürükle, aç ve kurulum penceresini takip et. macOS 14+ ve Apple Silicon gerekir.

**Görüşmelerde:** Zoom, Meet, Teams veya Slack görüşmesindeyken de çalışır; ama kendini oradan sessize almazsan karşı taraf dikte ettiklerini duyar.

## License

MIT. See [LICENSE](LICENSE).
