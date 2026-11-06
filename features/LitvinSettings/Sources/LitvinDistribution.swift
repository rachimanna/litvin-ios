import Foundation
import UIKit

enum LitvinDistribution {
    private static let repository = "https://github.com/rachimanna/litvin-ios"
    private static let api = "https://api.github.com/repos/rachimanna/litvin-ios/releases/latest"

    static func show() {
        let controller = LitvinRowsController(title: "Установка через ESign")
        controller.rows = [
            .init(title: "Скачать готовый IPA", detail: "Последний опубликованный Litvin.ipa для импорта в ESign.", action: {
                latestAsset(named: "Litvin.ipa") { url in UIApplication.shared.open(url) }
            }),
            .init(title: "Скопировать источник ESign", detail: "Добавь URL в список источников, если твоя версия ESign поддерживает этот формат.", action: {
                latestAsset(named: "esign-source.json") { _ in
                    UIPasteboard.general.string = repository + "/releases/latest/download/esign-source.json"
                    LitvinTools.info("Источник скопирован", "В ESign открой список источников приложений, нажми добавление и вставь URL. Если источник не распознаётся, скачай IPA и импортируй его вручную.")
                }
            }),
            .init(title: "Как подписать и установить", detail: "IPA → импорт в ESign → подпись своим сертификатом → установка.", action: {
                LitvinTools.info("Установка Litvin через ESign", "1. Скачай Litvin.ipa и сохрани в «Файлы».\n2. В ESign импортируй IPA и добавь его в библиотеку приложений.\n3. Выбери свой действующий сертификат .p12 и подходящий provisioning profile .mobileprovision.\n4. Подпиши приложение и выбери установку.\n\nТестовая подпись сборки не предназначена для установки на устройство. Учётные данные Telegram вводятся только в установленном клиенте.")
            }),
            .init(title: "Опубликовать успешную сборку", detail: "Откроет GitHub Actions → Publish IPA for ESign → Run workflow. Публикуется только успешно собранная основная ветка.", action: {
                if let url = URL(string: repository + "/actions/workflows/publish-esign.yml") { UIApplication.shared.open(url) }
            }),
            .init(title: "Все выпуски и контрольные суммы", detail: "IPA, SHA-256, значок приложения и файл источника.", action: {
                if let url = URL(string: repository + "/releases") { UIApplication.shared.open(url) }
            }),
        ]
        LitvinTools.list(controller)
    }

    private static func latestAsset(named name: String, completion: @escaping (URL) -> Void) {
        guard let url = URL(string: api) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Litvin-iOS", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            guard error == nil, status == 200, let data, data.count < 1024 * 1024,
                  let release = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let assets = release["assets"] as? [[String: Any]],
                  let asset = assets.first(where: { $0["name"] as? String == name }),
                  let address = asset["browser_download_url"] as? String,
                  let assetURL = URL(string: address), assetURL.scheme == "https", assetURL.host == "github.com",
                  assetURL.path.hasPrefix("/rachimanna/litvin-ios/releases/download/") else {
                DispatchQueue.main.async {
                    if status == 404 { LitvinTools.info("Готовый выпуск ещё не опубликован", "Дождись успешной сборки основной ветки и запусти Publish IPA for ESign в GitHub Actions.") }
                    else { LitvinTools.info("Не удалось получить IPA", "Проверь соединение и раздел Releases в репозитории. Файл появится после публикации успешной сборки.") }
                }
                return
            }
            DispatchQueue.main.async { completion(assetURL) }
        }.resume()
    }
}
