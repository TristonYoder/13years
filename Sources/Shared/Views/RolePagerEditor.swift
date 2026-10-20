// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#if os(macOS) || os(iOS)
import SwiftUI

struct PagerChipPayload {
    static let marker = "13years.pager-chip"
    private static let separator: Character = "\u{1F}"

    let sourceRoleId: String?
    let item: RolePagerItem

    var encoded: String {
        [Self.marker, sourceRoleId ?? "", item.token].joined(separator: String(Self.separator))
    }

    init(sourceRoleId: String?, item: RolePagerItem) {
        self.sourceRoleId = sourceRoleId
        self.item = item
    }

    init?(_ raw: String) {
        let parts = raw.split(separator: Self.separator, maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == Self.marker, let item = RolePagerItem(token: String(parts[2])) else { return nil }
        self.sourceRoleId = parts[1].isEmpty ? nil : String(parts[1])
        self.item = item
    }
}

struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(width: proposal.width ?? usedWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension RolePagerItem {
    var symbolName: String {
        switch self {
        case .note(let category): return RunSheetNotePill.symbolName(forCategory: category)
        case .field(let field):
            switch field {
            case .key: return "music.note"
            case .bpm: return "metronome"
            case .meter: return "music.note.list"
            case .arrangement: return "list.bullet.rectangle"
            case .sequence: return "repeat"
            case .description: return "text.alignleft"
            case .mediaType: return "film"
            case .servicePosition: return "clock.arrow.circlepath"
            case .startTime: return "clock"
            case .leader: return "person.fill"
            case .type: return "tag"
            case .length: return "timer"
            case .itemDetails: return "doc.richtext"
            }
        }
    }

    var kindName: String {
        switch self {
        case .field: return "item field"
        case .note: return "note"
        }
    }

    var chipFill: Color {
        switch self {
        case .field: return AppPalette.chipFieldFill
        case .note: return AppPalette.chipNoteFill
        }
    }
}

private struct PagerChipContent: View {
    let item: RolePagerItem

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: item.symbolName)
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(item.label)
                .lineLimit(1)
        }
        .font(.callout.weight(.medium))
    }
}

private struct PaletteChip: View {
    let item: RolePagerItem
    let onActivate: () -> Void

    var body: some View {
        PagerChipContent(item: item)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(item.chipFill, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture(perform: onActivate)
            .draggable(PagerChipPayload(sourceRoleId: nil, item: item).encoded) {
                PagerChipContent(item: item)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(item.chipFill, in: Capsule())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.label), \(item.kindName)")
            .accessibilityHint("Adds it to a role. You can also drag it onto a role.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onActivate)
    }
}

private struct RoleChip: View {
    let item: RolePagerItem
    let roleId: String
    let index: Int
    let count: Int
    let onRemove: () -> Void
    let onShift: (Int) -> Void
    let onDrop: ([String], Int) -> Bool

    var body: some View {
        HStack(spacing: 4) {
            PagerChipContent(item: item)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.label), \(item.kindName), \(index + 1) of \(count)")
                .accessibilityAction(named: "Move earlier") { onShift(-1) }
                .accessibilityAction(named: "Move later") { onShift(1) }
                .accessibilityAction(named: "Remove") { onRemove() }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.label)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(item.chipFill, in: Capsule())
        .draggable(PagerChipPayload(sourceRoleId: roleId, item: item).encoded) {
            PagerChipContent(item: item)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(item.chipFill, in: Capsule())
        }
        .dropDestination(for: String.self) { payloads, _ in
            onDrop(payloads, index)
        }
    }
}

private struct RolePersonField: View {
    @EnvironmentObject var engine: CueEngine
    let role: RoleCue
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Person", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
            .focused($focused)
            .onAppear { text = role.personName ?? "" }
            .onChange(of: role.personName) { _, new in
                if !focused { text = new ?? "" }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onSubmit(commit)
            .accessibilityLabel("Person for \(role.name)")
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let current = role.personName ?? ""
        guard trimmed != current else { return }
        engine.setPersonName(forRoleId: role.id, personName: trimmed.isEmpty ? nil : trimmed)
    }
}

struct RolePagerEditorContent: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.horizontalSizeClass) private var sizeClass
    let categories: [String]
    let onRename: (RoleCue) -> Void
    let onDelete: (RoleCue) -> Void

    @State private var filter = ""
    @State private var newRoleName = ""
    @State private var targetedRoleId: String?
    @State private var paletteTargeted = false
    @State private var pendingAdd: RolePagerItem?

    private var showsPalette: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    private var noteCategories: [String] {
        var set = Set(categories)
        for role in engine.roles { set.formUnion(role.assignedNoteCategories) }
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func matches(_ label: String) -> Bool {
        let query = filter.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || label.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        Group {
            if showsPalette {
                HStack(alignment: .top, spacing: 0) {
                    palette
                        .frame(width: 270)
                    Divider()
                    rolesPane
                }
            } else {
                rolesPane
            }
        }
        .confirmationDialog(
            pendingAdd.map { "Add \($0.label) to" } ?? "Add to",
            isPresented: Binding(get: { pendingAdd != nil }, set: { if !$0 { pendingAdd = nil } }),
            titleVisibility: .visible,
            presenting: pendingAdd
        ) { item in
            ForEach(engine.roles) { role in
                Button(role.name) { add(item, to: role) }
            }
            Button("Cancel", role: .cancel) { pendingAdd = nil }
        }
    }

    private var palette: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Available")
                    .font(.headline)
                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Filter available fields")
                Text("Drag a chip onto a role, or click it to pick a role. Each role shows its chips in the order you set. Drag a chip back here to remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                paletteGroup("Item", items: PagerItemField.allCases.map(RolePagerItem.field).filter { matches($0.label) })
                paletteGroup("Notes", items: noteCategories.map(RolePagerItem.note).filter { matches($0.label) }, empty: noteCategories.isEmpty ? "No note categories yet. Sync from Planning Center or add a note to any item in the Run Sheet." : nil)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(paletteTargeted ? AppPalette.dropTargetFill : Color.clear)
        .dropDestination(for: String.self) { payloads, _ in
            guard let raw = payloads.first, let payload = PagerChipPayload(raw), let source = payload.sourceRoleId,
                  let role = engine.roles.first(where: { $0.id == source }) else { return false }
            engine.setPagerItems(forRoleId: source, RolePagerItem.removing(payload.item, from: role.pagerItems ?? []))
            return true
        } isTargeted: { paletteTargeted = $0 }
    }

    private func paletteGroup(_ title: String, items: [RolePagerItem], empty: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if let empty {
                Text(empty)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if items.isEmpty {
                Text("No matches")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ChipFlowLayout {
                    ForEach(items) { item in
                        PaletteChip(item: item) { activate(item) }
                    }
                }
            }
        }
    }

    private func activate(_ item: RolePagerItem) {
        if engine.roles.count == 1, let role = engine.roles.first {
            add(item, to: role)
        } else if !engine.roles.isEmpty {
            pendingAdd = item
        }
    }

    private func add(_ item: RolePagerItem, to role: RoleCue) {
        engine.setPagerItems(forRoleId: role.id, RolePagerItem.inserting(item, into: role.pagerItems ?? []))
        pendingAdd = nil
    }

    private var rolesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if engine.roles.isEmpty {
                    Text("No roles yet. Add one below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(engine.roles) { role in
                    roleCard(role)
                }
                addRoleRow
                Text("Roles can be deleted down to none; add a new one any time. Notes show as the Current and Next panel on a role's pager; item fields show as one line under the current and next item.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private var addRoleRow: some View {
        HStack {
            TextField("New role name", text: $newRoleName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addRole)
            Button("Add", action: addRole)
                .disabled(newRoleName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addRole() {
        let trimmed = newRoleName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        engine.addRole(name: trimmed)
        newRoleName = ""
    }

    private func roleCard(_ role: RoleCue) -> some View {
        let items = role.pagerItems ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(role.name)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                addMenu(for: role)
                Menu {
                    Button("Rename\u{2026}") { onRename(role) }
                    Button("Delete\u{2026}", role: .destructive) { onDelete(role) }
                    if !items.isEmpty {
                        Divider()
                        Button("Clear all") { engine.setPagerItems(forRoleId: role.id, nil) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions for \(role.name)")
            }

            ChipFlowLayout(spacing: 8) {
                RolePersonField(role: role)
                positionMenu(for: role)
                clockMenu(for: role)
                plotipharMenu(for: role)
            }

            dropZone(for: role, items: items)
        }
        .padding(12)
        .background(AppPalette.sectionCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppPalette.sectionCardBorder))
    }

    private func dropZone(for role: RoleCue, items: [RolePagerItem]) -> some View {
        let targeted = targetedRoleId == role.id
        return Group {
            if items.isEmpty {
                Text("Drag fields and notes here, or use Add field.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            } else {
                ChipFlowLayout(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                        RoleChip(
                            item: item,
                            roleId: role.id,
                            index: index,
                            count: items.count,
                            onRemove: { engine.setPagerItems(forRoleId: role.id, RolePagerItem.removing(item, from: items)) },
                            onShift: { engine.setPagerItems(forRoleId: role.id, RolePagerItem.shifting(item, in: items, by: $0)) },
                            onDrop: { drop($0, onto: role.id, before: $1) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .background(targeted ? AppPalette.dropTargetFill : AppPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(targeted ? AppPalette.info : AppPalette.sectionCardBorder, style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: items.isEmpty ? [5, 4] : []))
        )
        .dropDestination(for: String.self) { payloads, _ in
            drop(payloads, onto: role.id, before: nil)
        } isTargeted: { isTargeted in
            if isTargeted { targetedRoleId = role.id } else if targetedRoleId == role.id { targetedRoleId = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(role.name) pager fields and notes")
    }

    private func drop(_ payloads: [String], onto roleId: String, before index: Int?) -> Bool {
        guard let raw = payloads.first, let payload = PagerChipPayload(raw),
              let role = engine.roles.first(where: { $0.id == roleId }) else { return false }
        engine.setPagerItems(forRoleId: roleId, RolePagerItem.dropping(payload.item, into: role.pagerItems ?? [], before: index))
        return true
    }

    private func addMenu(for role: RoleCue) -> some View {
        let used = Set(role.pagerItems ?? [])
        let fields = PagerItemField.allCases.map(RolePagerItem.field).filter { !used.contains($0) }
        let notes = noteCategories.map(RolePagerItem.note).filter { !used.contains($0) }
        return Menu {
            if !fields.isEmpty {
                Section("Item") {
                    ForEach(fields) { item in
                        Button(item.label) { add(item, to: role) }
                    }
                }
            }
            if !notes.isEmpty {
                Section("Notes") {
                    ForEach(notes) { item in
                        Button(item.label) { add(item, to: role) }
                    }
                }
            }
        } label: {
            Label("Add field", systemImage: "plus")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(fields.isEmpty && notes.isEmpty)
        .accessibilityLabel("Add field to \(role.name)")
    }

    @ViewBuilder
    private func positionMenu(for role: RoleCue) -> some View {
        if let context = engine.pcoPlanContext, !context.teamPositionReferences.isEmpty {
            let references = context.teamPositionReferences
            Picker("Position", selection: Binding(
                get: { role.pcoTeamPosition ?? "" },
                set: { engine.setPCOTeamPosition(forRoleId: role.id, $0.isEmpty ? nil : $0) }
            )) {
                Text("No position").tag("")
                if let current = role.pcoTeamPosition, !references.contains(current) {
                    Text(current).tag(current)
                }
                ForEach(references, id: \.self) { reference in
                    Text(reference).tag(reference)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Links this role to a Planning Center team position. With no person name set, the confirmed person for that position fills in automatically.")
        }
    }

    private func clockMenu(for role: RoleCue) -> some View {
        Picker("Clock", selection: Binding(
            get: { role.clockFormat },
            set: { engine.setClockFormat(forRoleId: role.id, $0) }
        )) {
            Text("Producer default (\(engine.clockFormat.label))").tag(ClockFormat?.none)
            ForEach(ClockFormat.allCases) { format in
                Text(format.label).tag(ClockFormat?.some(format))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }

    @ViewBuilder
    private func plotipharMenu(for role: RoleCue) -> some View {
        if FeatureFlags.plotiphar && !engine.plotipharRoles.isEmpty {
            Picker("Plotiphar", selection: Binding(
                get: { role.plotipharRoleId ?? "" },
                set: { engine.setPlotipharRoleId(forRoleId: role.id, plotipharRoleId: $0.isEmpty ? nil : $0) }
            )) {
                Text("Not linked").tag("")
                ForEach(engine.plotipharRoles, id: \.id) { plotipharRole in
                    Text(plotipharRole.name).tag(plotipharRole.id)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}
#endif
