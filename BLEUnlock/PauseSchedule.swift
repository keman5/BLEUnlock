import Cocoa

struct PausePeriod: Codable {
    let start: Int
    let end: Int

    var isValid: Bool {
        (0..<1440).contains(start) && (0..<1440).contains(end) && start != end
    }

    func contains(_ minute: Int) -> Bool {
        guard isValid else { return false }
        if start < end {
            return start <= minute && minute < end
        }
        return start <= minute || minute < end
    }

    var timeRange: String {
        let startTime = String(format: "%02d:%02d", start / 60, start % 60)
        let endTime = String(format: "%02d:%02d", end / 60, end % 60)
        return "\(startTime)–\(endTime)"
    }

    static func minute(of date: Date, in calendar: Calendar = .autoupdatingCurrent) -> Int {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return (time.hour ?? 0) * 60 + (time.minute ?? 0)
    }
}

private final class PauseScheduleContentView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

final class PauseScheduleWindow: NSPanel {
    private let rows = NSStackView()
    private let hint = NSTextField(labelWithString: "")
    private let saveButton = NSButton()
    private let emptyMessage = NSTextField(labelWithString: t("pause_no_periods", "No pause periods"))
    private let calendar: Calendar
    var onSave: (([PausePeriod]) -> Void)?

    init(periods: [PausePeriod]) {
        var clock = Calendar(identifier: .gregorian)
        clock.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = clock
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 285),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = t("pause_periods", "Auto-Lock Pause Schedule")
        isReleasedWhenClosed = false
        let content = PauseScheduleContentView()
        contentView = content
        initialFirstResponder = content

        hint.stringValue = t("pause_schedule_hint", "Repeats daily in your Mac’s local time. A period can cross midnight.")
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        hint.textColor = .secondaryLabelColor

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 7
        rows.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        emptyMessage.textColor = .secondaryLabelColor
        rows.addArrangedSubview(emptyMessage)

        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let document = NSView()
        scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        rows.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rows)

        let add = NSButton(title: t("pause_add_period", "Add Period"), target: self, action: #selector(addPeriod))
        let cancel = NSButton(title: t("cancel"), target: self, action: #selector(cancelOperation(_:)))
        saveButton.title = t("pause_save", "Save")
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"

        for view in [hint, scroll, add, cancel, saveButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: content.topAnchor, constant: 15),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: hint.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: hint.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: add.topAnchor, constant: -12),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            rows.topAnchor.constraint(equalTo: document.topAnchor),
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            rows.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            add.leadingAnchor.constraint(equalTo: hint.leadingAnchor),
            add.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            saveButton.trailingAnchor.constraint(equalTo: hint.trailingAnchor),
            saveButton.centerYAnchor.constraint(equalTo: add.centerYAnchor),
            cancel.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            cancel.centerYAnchor.constraint(equalTo: add.centerYAnchor)
        ])
        for period in periods {
            addRow(period)
        }
        updateValidation()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    private var periods: [PausePeriod] {
        rows.arrangedSubviews.compactMap { view in
            guard let row = view as? NSStackView,
                  let start = row.arrangedSubviews.first as? NSDatePicker,
                  let end = row.arrangedSubviews.dropFirst(2).first as? NSDatePicker else { return nil }
            return PausePeriod(start: PausePeriod.minute(of: start.dateValue, in: calendar),
                               end: PausePeriod.minute(of: end.dateValue, in: calendar))
        }
    }

    private func addRow(_ period: PausePeriod) {
        let start = makeTimePicker(period.start, label: t("pause_start_time", "Start time"))
        let end = makeTimePicker(period.end, label: t("pause_end_time", "End time"))
        let remove = NSButton(title: t("pause_remove_period", "Remove"), target: self, action: #selector(removePeriod(_:)))
        let row = NSStackView(views: [start, NSTextField(labelWithString: "–"), end, remove])
        row.alignment = .centerY
        row.spacing = 8
        rows.addArrangedSubview(row)
    }

    private func makeTimePicker(_ minute: Int, label: String) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerElements = .hourMinute
        picker.datePickerStyle = .textFieldAndStepper
        picker.calendar = calendar
        picker.timeZone = calendar.timeZone
        picker.dateValue = Date(timeIntervalSinceReferenceDate: Double(minute * 60))
        picker.setAccessibilityLabel(label)
        picker.target = self
        picker.action = #selector(updateValidation)
        return picker
    }

    @objc private func addPeriod() {
        addRow(PausePeriod(start: 12 * 60, end: 13 * 60))
        updateValidation()
        recalculateKeyViewLoop()
        if let lastRow = rows.arrangedSubviews.last {
            rows.scrollToVisible(lastRow.frame)
        }
    }

    @objc private func removePeriod(_ sender: NSButton) {
        guard let row = sender.superview else { return }
        rows.removeArrangedSubview(row)
        row.removeFromSuperview()
        updateValidation()
        recalculateKeyViewLoop()
    }

    @objc private func updateValidation() {
        let schedule = periods
        emptyMessage.isHidden = !schedule.isEmpty
        let valid = schedule.allSatisfy(\.isValid)
        hint.stringValue = valid
            ? t("pause_schedule_hint", "Repeats daily in your Mac’s local time. A period can cross midnight.")
            : t("pause_invalid_period", "Start and end times must be different.")
        saveButton.isEnabled = valid
    }

    @objc private func save() {
        // Commit any time still being edited before saving.
        guard makeFirstResponder(contentView) else { return }
        let schedule = periods
        guard schedule.allSatisfy(\.isValid) else {
            updateValidation()
            return
        }
        onSave?(schedule)
        close()
    }
}
