// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct ServiceScheduleView: View {
    public enum Target: Identifiable {
        case add
        case edit(ServiceSchedule)

        public var id: String {
            switch self {
            case .add: return "add"
            case .edit(let schedule): return schedule.id
            }
        }
    }

    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss

    @State private var editorTarget: Target?
    @State private var pendingDeleteSchedule: ServiceSchedule?
    @State private var showingImport = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                if let next = engine.nextScheduledService {
                    Section {
                        nextCard(next)
                    }
                }

                schedulesSection
            }
            .formStyle(.grouped)
            .navigationTitle("Event Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Schedule\u{2026}") { editorTarget = .add }
                        Button("From Event & Rehearsal Times\u{2026}") { showingImport = true }
                            .disabled(engine.eventTimes.isEmpty && engine.rehearsalPlanTimes.isEmpty)
                    } label: {
                        Label("Add Schedule", systemImage: "plus")
                    }
                }
            }
            .onScreenshotTourSignal("settings.add-schedule") { _ in editorTarget = .add }
            .sheet(item: $editorTarget) { target in
                ServiceScheduleEditorView(target: target)
            }
            .sheet(isPresented: $showingImport) {
                ScheduleImportSheet()
            }
            .confirmationDialog(
                "Delete this schedule?",
                isPresented: Binding(
                    get: { pendingDeleteSchedule != nil },
                    set: { if !$0 { pendingDeleteSchedule = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeleteSchedule
            ) { schedule in
                Button("Delete", role: .destructive) {
                    engine.removeServiceSchedule(id: schedule.id)
                    pendingDeleteSchedule = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteSchedule = nil }
            } message: { schedule in
                Text("\u{201C}\(schedule.title)\u{201D} will no longer go live automatically.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 600)
        #endif
    }

    private var schedulesSection: some View {
        Section {
            if engine.serviceSchedules.isEmpty {
                Text("No schedules yet — add one to have this device go live automatically ahead of an event, at whatever lead time you pick.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(engine.serviceSchedules) { schedule in
                scheduleRow(schedule)
            }
        } header: {
            Text("Schedules")
        } footer: {
            Text("Weekly rolls itself forward to the next occurrence the moment it fires. Once fires a single time, then disables itself — a record of what ran, rather than disappearing outright.")
        }
    }

    private func scheduleRow(_ schedule: ServiceSchedule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(schedule.title)
                            .fontWeight(.medium)
                        if schedule.recurrence == .weekly {
                            Text("WEEKLY")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(AppPalette.surfaceSubtle, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                    Text("\(engine.clockFormat.dateTime(schedule.startsAt)) \u{00B7} live \(leadDescription(schedule)) before")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: Binding(
                    get: { schedule.isEnabled },
                    set: { engine.updateServiceSchedule(id: schedule.id, isEnabled: $0) }
                ))
                .labelsHidden()
            }

            HStack {
                Button("Go Live Now") {
                    engine.goLiveWithSchedule(id: schedule.id)
                }
                .producerSecondaryButton()
                .compactControlSize()

                Spacer()

                #if os(macOS)
                RowActionButton(systemImage: "pencil", label: "Edit schedule\u{2026}") {
                    editorTarget = .edit(schedule)
                }
                RowActionButton(systemImage: "trash", label: "Delete schedule\u{2026}") {
                    pendingDeleteSchedule = schedule
                }
                #endif
            }
        }
        .padding(.vertical, 2)
        .rowActions {
            Button {
                editorTarget = .edit(schedule)
            } label: {
                Label("Edit\u{2026}", systemImage: "pencil")
            }
            .tint(AppPalette.info)

            Button {
                engine.goLiveWithSchedule(id: schedule.id)
            } label: {
                Label("Go Live Now", systemImage: "play.fill")
            }
            .tint(AppPalette.positive)

            Button(role: .destructive) {
                pendingDeleteSchedule = schedule
            } label: {
                Label("Delete\u{2026}", systemImage: "trash")
            }
        }
    }

    /// The next run, called out at the top with the one action you reach for: go live now.
    private func nextCard(_ schedule: ServiceSchedule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next: \(engine.clockFormat.dateTime(schedule.goLiveAt))")
                    .font(.headline)
                Text("\(schedule.title) \u{00B7} live \(leadDescription(schedule)) before \(engine.clockFormat.string(from: schedule.startsAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Go Live Now") { engine.goLiveWithSchedule(id: schedule.id) }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private func leadDescription(_ schedule: ServiceSchedule) -> String {
        let minutes = schedule.goLiveOffsetSeconds / 60
        return minutes == 0 ? "at start" : "\(minutes) min"
    }
}

private struct ServiceScheduleEditorView: View {
    let target: ServiceScheduleView.Target

    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss

    private static let leadPresets = [0, 5, 10, 15, 30, 45, 60, 90]

    private enum LeadOption: Hashable {
        case preset(Int)
        case custom
    }

    @State private var title: String
    @State private var startsAt: Date
    @State private var leadOption: LeadOption
    @State private var customLeadMinutes: Int
    @State private var recurrence: ServiceSchedule.Recurrence
    @State private var isEnabled: Bool
    @State private var pcoServiceTypeId: String?
    @State private var pcoPlanId: String?
    @State private var timeTarget: ServiceSchedule.TimeTarget?
    @State private var startsFirstItem: Bool

    init(target: ServiceScheduleView.Target) {
        self.target = target
        let schedule: ServiceSchedule?
        switch target {
        case .add: schedule = nil
        case .edit(let existing): schedule = existing
        }

        _title = State(initialValue: schedule?.title ?? "")
        _startsAt = State(initialValue: schedule?.startsAt ?? Self.defaultStartsAt())
        let minutes = schedule?.goLiveOffsetMinutes ?? 30
        _leadOption = State(initialValue: Self.leadPresets.contains(minutes) ? .preset(minutes) : .custom)
        _customLeadMinutes = State(initialValue: minutes)
        _recurrence = State(initialValue: schedule?.recurrence ?? .weekly)
        _isEnabled = State(initialValue: schedule?.isEnabled ?? true)
        _pcoServiceTypeId = State(initialValue: schedule?.pcoServiceTypeId ?? nil)
        _pcoPlanId = State(initialValue: schedule?.pcoPlanId ?? nil)
        _timeTarget = State(initialValue: schedule?.target)
        _startsFirstItem = State(initialValue: schedule?.startsFirstItem ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    #if os(tvOS)
                    LabeledContent("Starts At") {
                        Text(engine.clockFormat.dateTime(startsAt))
                            .font(.clock(.body, weight: .regular))
                    }
                    #else
                    DatePicker("Starts At", selection: $startsAt)
                        .environment(\.locale, engine.clockFormat.pickerLocale)
                    #endif
                }

                runSection
                leadTimeSection
                recurrenceSection
                pcoPlanSection
            }
            .formStyle(.grouped)
            .navigationTitle(isAdding ? "Add Schedule" : "Edit Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 480, idealHeight: 580)
        #endif
    }

    private var isAdding: Bool {
        if case .add = target { return true }
        return false
    }

    private var resolvedLeadMinutes: Int {
        switch leadOption {
        case .preset(let minutes): return minutes
        case .custom: return customLeadMinutes
        }
    }

    private var leadSentence: String {
        resolvedLeadMinutes == 0
            ? "Goes live at start time"
            : "Goes live \(resolvedLeadMinutes) minute\(resolvedLeadMinutes == 1 ? "" : "s") before"
    }

    private var resolvedGoLiveAt: Date {
        startsAt.addingTimeInterval(-Double(resolvedLeadMinutes * 60))
    }

    private var leadTimeSection: some View {
        Section {
            Text(leadSentence)
                .font(.subheadline)

            Picker("Lead Time", selection: $leadOption) {
                ForEach(Self.leadPresets, id: \.self) { minutes in
                    Text(minutes == 0 ? "At start time" : "\(minutes) min before")
                        .tag(LeadOption.preset(minutes))
                }
                Text("Custom\u{2026}").tag(LeadOption.custom)
            }

            if case .custom = leadOption {
                #if os(tvOS)
                Picker("Custom Lead Time", selection: $customLeadMinutes) {
                    ForEach(0...240, id: \.self) { minutes in
                        Text("\(minutes) minute\(minutes == 1 ? "" : "s") before").tag(minutes)
                    }
                }
                #else
                Stepper(
                    "Custom: \(customLeadMinutes) minute\(customLeadMinutes == 1 ? "" : "s") before",
                    value: $customLeadMinutes,
                    in: 0...240
                )
                #endif
            }
        } header: {
            Text("Go-Live Timing")
        } footer: {
            Text("Live at \(engine.clockFormat.string(from: resolvedGoLiveAt)).")
        }
    }

    /// Which event or rehearsal time this makes current, and whether it starts the first item.
    private var runSection: some View {
        Section {
            Picker("Time", selection: Binding(
                get: { timeTarget.map { "\($0.kind.rawValue):\($0.id)" } ?? "" },
                set: { pickTarget($0) }
            )) {
                Text("None \u{2014} keep the current time").tag("")
                if !engine.eventTimes.isEmpty {
                    Section("Events") {
                        ForEach(engine.eventTimes) { time in
                            Text(time.displayName(engine.clockFormat)).tag("event:\(time.id)")
                        }
                    }
                }
                if !engine.rehearsalPlanTimes.isEmpty {
                    Section("Rehearsals") {
                        ForEach(engine.rehearsalPlanTimes) { time in
                            Text(Self.rehearsalLabel(time, engine.clockFormat)).tag("rehearsal:\(time.id)")
                        }
                    }
                }
            }
            Toggle("Start the first item", isOn: $startsFirstItem)
        } header: {
            Text("When It Goes Live")
        } footer: {
            Text("Makes that event or rehearsal the current one. Starting the first item runs its timer by itself, for a pre-show countdown that fires without anyone pressing play.")
        }
    }

    static func rehearsalLabel(_ time: PCOPlanTimeInfo, _ format: ClockFormat) -> String {
        [time.name, time.startsAt.map { format.string(from: $0) }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    /// Choosing a time fills in an empty title and, when adding, the start, so the schedule matches it.
    private func pickTarget(_ raw: String) {
        guard !raw.isEmpty, let separator = raw.firstIndex(of: ":"),
              let kind = ServiceSchedule.TimeTarget.Kind(rawValue: String(raw[..<separator])) else {
            timeTarget = nil
            return
        }
        let id = String(raw[raw.index(after: separator)...])
        timeTarget = ServiceSchedule.TimeTarget(kind: kind, id: id)
        guard isAdding else { return }
        switch kind {
        case .event:
            guard let time = engine.eventTime(id: id) else { return }
            if title.trimmingCharacters(in: .whitespaces).isEmpty { title = time.name ?? time.displayName(engine.clockFormat) }
            if let start = CueEngine.nextStart(day: time.day, time: time.startTime) { startsAt = start }
        case .rehearsal:
            guard let time = engine.rehearsalPlanTimes.first(where: { $0.id == id }) else { return }
            if title.trimmingCharacters(in: .whitespaces).isEmpty { title = time.name ?? "Rehearsal" }
            if let start = time.startsAt { startsAt = start }
        }
    }

    private var recurrenceSection: some View {
        Section {
            Picker("Repeats", selection: $recurrence) {
                ForEach(ServiceSchedule.Recurrence.allCases, id: \.self) { option in
                    Text(recurrenceLabel(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Enabled", isOn: $isEnabled)
        } footer: {
            Text(recurrence == .weekly
                ? "Rolls forward to next week automatically the moment it fires."
                : "Fires once, then disables itself so you still have a record of what ran.")
        }
    }

    private func recurrenceLabel(_ recurrence: ServiceSchedule.Recurrence) -> String {
        switch recurrence {
        case .once: return "Once"
        case .weekly: return "Weekly"
        }
    }

    @ViewBuilder
    private var pcoPlanSection: some View {
        Section {
            Picker("Plan Type", selection: Binding(
                get: { pcoServiceTypeId ?? "" },
                set: { newValue in
                    pcoServiceTypeId = newValue.isEmpty ? nil : newValue
                    pcoPlanId = newValue.isEmpty ? nil : PCOClient.upcomingPlanId
                    if !newValue.isEmpty {
                        engine.selectPCOServiceType(newValue)
                    }
                }
            )) {
                Text("None \u{2014} use whatever's already loaded").tag("")
                ForEach(engine.pcoServiceTypes) { serviceType in
                    Text(serviceType.name).tag(serviceType.id)
                }
            }

            if let pcoServiceTypeId, !pcoServiceTypeId.isEmpty {
                Picker("Plan", selection: Binding(
                    get: { pcoPlanId ?? "" },
                    set: { pcoPlanId = $0.isEmpty ? nil : $0 }
                )) {
                    Text("None").tag("")
                    Text("Next upcoming plan").tag(PCOClient.upcomingPlanId)
                    ForEach(engine.pcoPlans) { plan in
                        Text(plan.title).tag(plan.id)
                    }
                }
            }
        } header: {
            Text("Planning Center Plan")
        } footer: {
            Text(pcoPlanId == nil
                ? "No plan chosen — going live just switches this device into the live producer view and leaves whatever plan is already loaded alone."
                : pcoPlanId == PCOClient.upcomingPlanId
                    ? "Each time this schedule fires, it loads the next upcoming plan of this type from Planning Center — no need to pick one every week."
                    : "Loads this plan from Planning Center the moment this schedule fires.")
        }
        .task {
            if engine.pcoServiceTypes.isEmpty {
                engine.fetchPCOServiceTypes()
            }
        }
    }

    private static func defaultStartsAt() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let daysUntilSunday = (8 - weekday) % 7
        let daysToAdd = daysUntilSunday == 0 ? 7 : daysUntilSunday
        let sunday = calendar.date(byAdding: .day, value: daysToAdd, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: sunday) ?? sunday
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        switch target {
        case .add:
            engine.addServiceSchedule(
                title: trimmedTitle,
                startsAt: startsAt,
                goLiveOffsetSeconds: resolvedLeadMinutes * 60,
                pcoServiceTypeId: pcoServiceTypeId,
                pcoPlanId: pcoPlanId,
                recurrence: recurrence,
                isEnabled: isEnabled,
                target: timeTarget,
                startsFirstItem: startsFirstItem
            )
        case .edit(let existing):
            engine.updateServiceSchedule(
                id: existing.id,
                title: trimmedTitle,
                startsAt: startsAt,
                goLiveOffsetSeconds: resolvedLeadMinutes * 60,
                pcoServiceTypeId: .some(pcoServiceTypeId),
                pcoPlanId: .some(pcoPlanId),
                recurrence: recurrence,
                isEnabled: isEnabled,
                target: .some(timeTarget),
                startsFirstItem: startsFirstItem
            )
        }
        dismiss()
    }
}

private extension ClockFormat {
    func dateTime(_ date: Date) -> String {
        "\(date.formatted(date: .abbreviated, time: .omitted)), \(string(from: date))"
    }
}

/// Turns event and rehearsal times into schedules in one go.
private struct ScheduleImportSheet: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss

    private struct Candidate: Identifiable {
        let id: String
        let target: ServiceSchedule.TimeTarget
        let title: String
        let detail: String
        let startsAt: Date
        let recurrence: ServiceSchedule.Recurrence
    }

    private static let leadPresets = [0, 5, 10, 15, 30, 45, 60, 90]

    @State private var chosen: Set<String> = []
    @State private var leadMinutes = 30
    @State private var startsFirstItem = false
    @State private var seeded = false

    private var candidates: [Candidate] {
        let taken = Set(engine.serviceSchedules.compactMap(\.target))
        var result: [Candidate] = []
        for time in engine.eventTimes {
            guard let start = CueEngine.nextStart(day: time.day, time: time.startTime) else { continue }
            let target = ServiceSchedule.TimeTarget(kind: .event, id: time.id)
            guard !taken.contains(target) else { continue }
            var weekly = false
            if case .weekday? = time.day { weekly = true }
            result.append(Candidate(
                id: "event:\(time.id)", target: target,
                title: time.name ?? time.displayName(engine.clockFormat),
                detail: "Event \u{00B7} \(engine.clockFormat.dateTime(start))",
                startsAt: start, recurrence: weekly ? .weekly : .once
            ))
        }
        for time in engine.rehearsalPlanTimes {
            guard let start = time.startsAt else { continue }
            let target = ServiceSchedule.TimeTarget(kind: .rehearsal, id: time.id)
            guard !taken.contains(target) else { continue }
            result.append(Candidate(
                id: "rehearsal:\(time.id)", target: target,
                title: time.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Rehearsal",
                detail: "Rehearsal \u{00B7} \(engine.clockFormat.dateTime(start))",
                startsAt: start, recurrence: .once
            ))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if candidates.isEmpty {
                        Text("Every event and rehearsal time with a start already has a schedule.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { candidate in
                        Toggle(isOn: Binding(
                            get: { chosen.contains(candidate.id) },
                            set: { if $0 { chosen.insert(candidate.id) } else { chosen.remove(candidate.id) } }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.title)
                                Text(candidate.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Times")
                } footer: {
                    Text("Each becomes a schedule that makes that time the current one when it goes live. A weekday event repeats weekly.")
                }

                Section {
                    Picker("Go live", selection: $leadMinutes) {
                        ForEach(Self.leadPresets, id: \.self) { minutes in
                            Text(minutes == 0 ? "At the start" : "\(minutes) min before").tag(minutes)
                        }
                    }
                    Toggle("Start the first item", isOn: $startsFirstItem)
                } header: {
                    Text("For all of them")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add from Times")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(chosen.count)") { importChosen() }
                        .disabled(chosen.isEmpty)
                }
            }
            .onAppear {
                guard !seeded else { return }
                seeded = true
                chosen = Set(candidates.map(\.id))
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 440, idealHeight: 520)
        #endif
    }

    private func importChosen() {
        for candidate in candidates where chosen.contains(candidate.id) {
            engine.addServiceSchedule(
                title: candidate.title,
                startsAt: candidate.startsAt,
                goLiveOffsetSeconds: leadMinutes * 60,
                recurrence: candidate.recurrence,
                target: candidate.target,
                startsFirstItem: startsFirstItem
            )
        }
        dismiss()
    }
}
