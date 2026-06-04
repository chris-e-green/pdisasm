import AppKit
import SwiftUI
import pdisasm

struct DisassemblyTableView: NSViewRepresentable {
    var viewModel: DisassemblyViewModel
    var lines: [OutputLine]
    var selectedLineIDs: Set<Int>
    var procedureScrollRequest: Int
    var selectedProcedureFilteredIndex: Int?
    var restoreScrollRequest: Int
    var restoreFilteredIndex: Int?
    var currentMatchScrollIndex: Int?
    var searchMatchIndices: [Int]
    var searchMatchIndexSet: Set<Int>

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.rowHeight = Coordinator.rowHeight
        tableView.intercellSpacing = .zero
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.style = .plain
        tableView.headerView = nil
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))

        let lineColumn = NSTableColumn(identifier: Coordinator.lineColumnID)
        lineColumn.title = "Line"
        lineColumn.width = Coordinator.lineColumnWidth
        lineColumn.minWidth = Coordinator.lineColumnWidth
        lineColumn.maxWidth = Coordinator.lineColumnWidth
        lineColumn.resizingMask = []
        tableView.addTableColumn(lineColumn)

        let textColumn = NSTableColumn(identifier: Coordinator.textColumnID)
        textColumn.title = "Disassembly"
        textColumn.width = 900
        textColumn.minWidth = 300
        textColumn.resizingMask = []
        tableView.addTableColumn(textColumn)

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = context.coordinator.tableView else { return }

        context.coordinator.updateTextColumnWidth(for: scrollView)
        tableView.reloadData()
        context.coordinator.syncSelectionToTable()
        context.coordinator.handlePendingScrollRequests()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        static let lineColumnID = NSUserInterfaceItemIdentifier("line")
        static let textColumnID = NSUserInterfaceItemIdentifier("text")
        static let rowHeight: CGFloat = 20
        static let lineColumnWidth: CGFloat = 64
        static let textPadding: CGFloat = 8

        var parent: DisassemblyTableView
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        private var isSyncingSelection = false
        private var lastProcedureScrollRequest = 0
        private var lastRestoreScrollRequest = 0
        private var lastCurrentMatchScrollIndex: Int?
        private let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        init(_ parent: DisassemblyTableView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.lines.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            Self.rowHeight
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.lines.indices.contains(row),
                  let tableColumn
            else { return nil }

            let identifier = tableColumn.identifier
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? makeCell(identifier: identifier)
            let line = parent.lines[row]

            if identifier == Self.lineColumnID {
                cell.textField?.stringValue = "\(line.id + 1)"
                cell.textField?.alignment = .right
                cell.textField?.textColor = .tertiaryLabelColor
            } else {
                cell.textField?.stringValue = line.text
                cell.textField?.alignment = .left
                cell.textField?.textColor = .labelColor
            }
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = DisassemblyRowView()
            rowView.normalBackgroundColor = backgroundColor(for: row)
            return rowView
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection,
                  let tableView = notification.object as? NSTableView
            else { return }
            parent.viewModel.selectOutputRows(tableView.selectedRowIndexes)
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView,
                  tableView.clickedRow >= 0,
                  parent.lines.indices.contains(tableView.clickedRow)
            else { return }

            let row = tableView.clickedRow
            let line = parent.lines[row]
            if !tableView.selectedRowIndexes.contains(row) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }

            let copyItem = NSMenuItem(
                title: "Copy Selected Lines",
                action: #selector(copySelectedLines(_:)),
                keyEquivalent: ""
            )
            copyItem.target = self
            menu.addItem(copyItem)

            let commentItem = NSMenuItem(
                title: "Edit Comment",
                action: #selector(editComment(_:)),
                keyEquivalent: ""
            )
            commentItem.target = self
            commentItem.isEnabled = line.commentReference != nil
            menu.addItem(commentItem)

            let clearItem = NSMenuItem(
                title: "Clear Selection",
                action: #selector(clearSelection(_:)),
                keyEquivalent: ""
            )
            clearItem.target = self
            clearItem.isEnabled = parent.viewModel.selectedOutputLineCount > 0
            menu.addItem(clearItem)
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard parent.lines.indices.contains(row) else { return }
            parent.viewModel.beginEditingOutputLine(
                on: parent.lines[row],
                filteredIndex: row,
                atCharacterOffset: characterOffsetForCurrentClick(in: sender)
            )
        }

        @objc private func copySelectedLines(_ sender: Any?) {
            parent.viewModel.copySelectedOutputLines()
        }

        @objc private func editComment(_ sender: Any?) {
            guard let tableView,
                  tableView.clickedRow >= 0,
                  parent.lines.indices.contains(tableView.clickedRow)
            else { return }
            parent.viewModel.beginEditingComment(
                on: parent.lines[tableView.clickedRow],
                filteredIndex: tableView.clickedRow
            )
        }

        @objc private func clearSelection(_ sender: Any?) {
            parent.viewModel.clearOutputSelection()
            isSyncingSelection = true
            tableView?.deselectAll(nil)
            isSyncingSelection = false
        }

        func syncSelectionToTable() {
            guard let tableView else { return }
            let selectedRows = IndexSet(parent.lines.indices.filter {
                parent.selectedLineIDs.contains(parent.lines[$0].id)
            })
            guard tableView.selectedRowIndexes != selectedRows else { return }
            isSyncingSelection = true
            tableView.selectRowIndexes(selectedRows, byExtendingSelection: false)
            isSyncingSelection = false
        }

        func handlePendingScrollRequests() {
            if parent.procedureScrollRequest != lastProcedureScrollRequest {
                lastProcedureScrollRequest = parent.procedureScrollRequest
                if let index = parent.selectedProcedureFilteredIndex {
                    scroll(to: index, anchor: .top)
                }
            }

            if parent.restoreScrollRequest != lastRestoreScrollRequest {
                lastRestoreScrollRequest = parent.restoreScrollRequest
                if let index = parent.restoreFilteredIndex {
                    scroll(to: index, anchor: .top)
                    DispatchQueue.main.async { [weak self] in
                        self?.scroll(to: index, anchor: .top)
                    }
                }
            }

            if parent.currentMatchScrollIndex != lastCurrentMatchScrollIndex {
                lastCurrentMatchScrollIndex = parent.currentMatchScrollIndex
                if let index = parent.currentMatchScrollIndex {
                    scroll(to: index, anchor: .center)
                }
            }
        }

        func updateTextColumnWidth(for scrollView: NSScrollView) {
            guard let tableView,
                  let textColumn = tableView.tableColumns.first(where: { $0.identifier == Self.textColumnID })
            else { return }

            let visibleWidth = max(scrollView.contentView.bounds.width - Self.lineColumnWidth, 300)
            let longest = parent.lines.lazy.map(\.text.count).max() ?? 80
            let characterWidth = max(font.advancement(forGlyph: font.glyph(withName: "0")).width, 1)
            let textWidth = CGFloat(longest) * characterWidth + (Self.textPadding * 2) + 24
            textColumn.width = min(max(visibleWidth, textWidth), 30_000)
        }

        private enum ScrollAnchor {
            case top
            case center
        }

        private func scroll(to row: Int, anchor: ScrollAnchor) {
            guard let tableView,
                  let scrollView,
                  parent.lines.indices.contains(row)
            else { return }

            tableView.scrollRowToVisible(row)
            guard anchor == .center else { return }

            let rowRect = tableView.rect(ofRow: row)
            let visibleHeight = scrollView.contentView.bounds.height
            var origin = scrollView.contentView.bounds.origin
            origin.y = max(rowRect.midY - (visibleHeight / 2), 0)
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.font = font
            textField.lineBreakMode = .byClipping
            textField.maximumNumberOfLines = 1
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = textField
            cell.addSubview(textField)

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Self.textPadding),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Self.textPadding),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

        private func characterOffsetForCurrentClick(in tableView: NSTableView) -> Int? {
            guard tableView.clickedColumn >= 0,
                  tableView.tableColumns[tableView.clickedColumn].identifier == Self.textColumnID,
                  let event = tableView.window?.currentEvent
            else { return nil }

            let point = tableView.convert(event.locationInWindow, from: nil)
            let textColumnRect = tableView.rect(ofColumn: tableView.clickedColumn)
            let x = point.x - textColumnRect.minX - Self.textPadding
            let characterWidth = max(font.advancement(forGlyph: font.glyph(withName: "0")).width, 1)
            return max(Int(x / characterWidth), 0)
        }

        private func backgroundColor(for row: Int) -> NSColor {
            guard parent.lines.indices.contains(row) else { return .clear }
            if parent.currentMatchScrollIndex == row {
                return NSColor.systemYellow.withAlphaComponent(0.30)
            }
            if parent.searchMatchIndexSet.contains(row) {
                return NSColor.systemYellow.withAlphaComponent(0.14)
            }
            return backgroundColor(for: parent.lines[row].kind)
        }

        private func backgroundColor(for kind: LineKind) -> NSColor {
            switch kind {
            case .markup:      return NSColor.systemGray.withAlphaComponent(0.04)
            case .pcode:       return NSColor.systemBlue.withAlphaComponent(0.025)
            case .pseudocode:  return NSColor.systemGreen.withAlphaComponent(0.035)
            case .variable:    return NSColor.systemOrange.withAlphaComponent(0.035)
            case .global:      return NSColor.systemPurple.withAlphaComponent(0.03)
            case .header:      return NSColor.systemGray.withAlphaComponent(0.08)
            case .diagnostic:  return NSColor.systemRed.withAlphaComponent(0.06)
            }
        }
    }
}

private final class DisassemblyRowView: NSTableRowView {
    var normalBackgroundColor: NSColor = .clear

    override func drawBackground(in dirtyRect: NSRect) {
        normalBackgroundColor.setFill()
        dirtyRect.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.22).setFill()
        dirtyRect.fill()
    }
}
