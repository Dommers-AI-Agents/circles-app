import UIKit

/// Settings → Birthday treats (2026-11-09): the month and day, so stores
/// where they earn rewards can send a happy birthday (services/storeAutomations).
/// Only the month and day are saved; no store sees the date.
final class BirthdayViewController: BaseViewController {

    private var birthday: String?
    var onChanged: ((String?) -> Void)?

    private let explanation: UILabel = {
        let label = UILabel()
        label.text = StoreAutomationsCopy.birthdayExplanation
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()
    private let picker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .wheels
        picker.maximumDate = Date()
        return picker
    }()
    private lazy var saveButton = UIButton.primaryButton(title: "Save my birthday")
    private lazy var removeButton = UIButton.secondaryButton(title: "Remove my birthday")

    override func viewDidLoad() {
        super.viewDidLoad()
        title = StoreAutomationsCopy.birthdayRowTitle
        view.backgroundColor = .systemBackground
        let stack = UIStackView(arrangedSubviews: [explanation, picker, saveButton, removeButton])
        stack.axis = .vertical
        stack.spacing = Constants.Spacing.medium
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.Spacing.large),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.medium),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.medium)
        ])
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        removeButton.isHidden = true
    }

    override func loadData(completion: (() -> Void)? = nil) {
        RewardsService.shared.fetchBirthday { [weak self] result in
            DispatchQueue.main.async {
                completion?()
                guard let self else { return }
                if case .success(let birthday) = result {
                    self.birthday = birthday
                    self.removeButton.isHidden = birthday == nil
                    if let birthday, let date = Self.date(from: birthday) { self.picker.date = date }
                }
            }
        }
    }

    /// "MM-DD" on a leap year, so Feb 29 shows on the wheels
    private static func date(from value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(from: DateComponents(year: 2000, month: parts[0], day: parts[1]))
    }

    @objc private func saveTapped() {
        set(StoreAutomationsCopy.birthdayValue(from: picker.date))
    }

    @objc private func removeTapped() {
        set(nil)
    }

    private func set(_ value: String?) {
        saveButton.isEnabled = false
        RewardsService.shared.setBirthday(value) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.saveButton.isEnabled = true
                switch result {
                case .success(let saved):
                    self.birthday = saved
                    self.removeButton.isHidden = saved == nil
                    self.onChanged?(saved)
                    self.showSuccess(saved == nil ? "Your birthday was removed." : "Saved. Stores you earn with can wish you a happy birthday.")
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
}
