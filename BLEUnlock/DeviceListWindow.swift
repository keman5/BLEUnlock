import Cocoa

struct DeviceListEntry: Equatable {
    let id: UUID
    let name: String
    let serialNumber: String?
    let macAddress: String?
    let rssi: Int
    let isMonitored: Bool
    private let model: String?

    init(device: Device, monitoredUUID: UUID?) {
        id = device.uuid
        name = device.description
        serialNumber = device.serialNumber
        macAddress = device.macAddr?.replacingOccurrences(of: "-", with: ":").uppercased()
        rssi = device.rssi
        isMonitored = id == monitoredUUID
        model = device.model
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let addressQuery = query.replacingOccurrences(of: "-", with: ":")
        return [name, serialNumber, model, id.uuidString].compactMap { $0 }
            .contains { $0.localizedStandardContains(query) }
            || macAddress?.localizedStandardContains(addressQuery) == true
    }
}

private final class DeviceListContentView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

final class DeviceListWindow: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let search = NSSearchField()
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let chooseButton = NSButton(title: t("choose_device", "Select Device"), target: nil, action: nil)
    private var entries: [DeviceListEntry] = []
    private var visibleEntries: [DeviceListEntry] = []
    var onChoose: ((UUID) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 690, height: 360),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = t("device")
        contentMinSize = NSSize(width: 530, height: 220)
        isReleasedWhenClosed = false

        search.placeholderString = t("search_devices", "Search devices")
        search.setAccessibilityLabel(t("search_devices", "Search devices"))
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)

        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(chooseDevice)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        let columns: [(String, String, CGFloat)] = [
            ("name", t("device_name", "Name"), 240),
            ("serial", t("device_serial_number", "Serial Number"), 135),
            ("address", t("device_bluetooth_address", "Bluetooth Address"), 140),
            ("signal", t("device_signal", "Signal"), 75)
        ]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = id == "name" ? 120 : 60
            table.addTableColumn(column)
        }

        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table

        status.textColor = .secondaryLabelColor
        chooseButton.target = self
        chooseButton.action = #selector(chooseDevice)
        chooseButton.keyEquivalent = "\r"
        chooseButton.isEnabled = false

        let content = DeviceListContentView()
        for view in [search, scroll, status, chooseButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: chooseButton.topAnchor, constant: -10),
            status.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            status.centerYAnchor.constraint(equalTo: chooseButton.centerYAnchor),
            status.trailingAnchor.constraint(lessThanOrEqualTo: chooseButton.leadingAnchor, constant: -10),
            chooseButton.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            chooseButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        contentView = content
        initialFirstResponder = content
        content.nextKeyView = search
        search.nextKeyView = table
        table.nextKeyView = chooseButton
        chooseButton.nextKeyView = search
        applySearch()
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    func controlTextDidChange(_ notification: Notification) {
        applySearch()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(cancelOperation(_:)) else { return false }
        close()
        return true
    }

    func update(devices: [Device], monitoredUUID: UUID?) {
        entries = devices.map { DeviceListEntry(device: $0, monitoredUUID: monitoredUUID) }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
        applySearch()
    }

    @objc private func searchChanged() {
        applySearch()
    }

    private func applySearch() {
        let results = entries.filter { $0.matches(search.stringValue) }
        let index = table.selectedRow
        let selectedID = visibleEntries.indices.contains(index) ? visibleEntries[index].id : nil
        if results.map(\.id) != visibleEntries.map(\.id) {
            visibleEntries = results
            table.reloadData()
            if let row = results.firstIndex(where: { $0.id == selectedID }) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else {
                table.deselectAll(nil)
            }
        } else if results != visibleEntries {
            let changedRows = IndexSet(results.indices.filter { results[$0] != visibleEntries[$0] })
            visibleEntries = results
            table.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
        }
        status.stringValue = results.isEmpty ? (entries.isEmpty ? t("scanning") : t("no_matching_devices", "No matching devices")) : ""
        chooseButton.isEnabled = table.selectedRow >= 0
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let entry = visibleEntries[row]
        let text: String
        switch column.identifier.rawValue {
        case "name": text = entry.isMonitored ? "✓  " + entry.name : entry.name
        case "serial": text = entry.serialNumber ?? "—"
        case "address": text = entry.macAddress ?? "—"
        case "signal": text = "\(entry.rssi) dBm"
        default: return nil
        }
        let label = (tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTextField)
            ?? NSTextField(labelWithString: "")
        label.identifier = column.identifier
        label.stringValue = text
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = text
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        chooseButton.isEnabled = table.selectedRow >= 0
    }

    @objc private func chooseDevice(_ sender: Any?) {
        let row = sender as? NSTableView === table ? table.clickedRow : table.selectedRow
        guard visibleEntries.indices.contains(row) else { return }
        let id = visibleEntries[row].id
        close()
        onChoose?(id)
    }
}
