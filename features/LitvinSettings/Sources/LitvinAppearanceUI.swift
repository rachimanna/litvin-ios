import UIKit
import TelegramCore

final class LitvinAppearanceRowsController: UITableViewController {
    struct Row {
        let title: String
        let detail: String
        let action: () -> Void
    }
    var rows: [Row] = []
    var refresh: (() -> [Row])?
    private var observer: NSObjectProtocol?
    init(title: String) { super.init(style: .insetGrouped); self.title = title }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        observer = NotificationCenter.default.addObserver(forName: LitvinAppearance.changed, object: nil, queue: .main) { [weak self] _ in self?.reload() }
        reload()
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func reload() { if let refresh { rows = refresh() }; tableView.reloadData() }
    @objc private func close() { dismiss(animated: true) }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true { rows = []; refresh = nil }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let row = rows[indexPath.row]
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.detail
        cell.detailTextLabel?.numberOfLines = 3
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        rows[indexPath.row].action()
    }
}

enum LitvinAppearanceUI {
    static func present(_ controller: UIViewController) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }),
              var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        if top is UIAlertController || top.isBeingDismissed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { present(controller) }
        } else { top.present(controller, animated: true) }
    }
    static func list(_ controller: LitvinAppearanceRowsController) { present(UINavigationController(rootViewController: controller)) }
    static func info(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert)
    }
    static func prompt(_ title: String, message: String, fields: [(String, String, Bool)], save: @escaping ([String]) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        for field in fields {
            alert.addTextField { text in
                text.placeholder = field.0; text.text = field.1; text.isSecureTextEntry = field.2
                text.autocorrectionType = .no; text.autocapitalizationType = .none
            }
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in save(alert.textFields?.map { $0.text ?? "" } ?? []) }))
        present(alert)
    }
}
