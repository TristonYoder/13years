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

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                if let next = engine.nextScheduledService {
                    Section {
                        Label(nextScheduledLine(next), systemImage: "clock.badge.checkmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                schedulesSection
            }
            .formStyle(.grouped)
            .navigationTitle("Service Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { editorTarget = .add }) {
                        Label("Add Schedule", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                ServiceScheduleEditorView(target: target)
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
                Text("No schedules yet — add one to have this device go live automatically ahead of a service, at whatever lead time you pick.")
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
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                    Text("\(schedule.startsAt.formatted(date: .abbreviated, time: .shortened)) \u{2014} live at \(schedule.goLiveAt.formatted(date: .omitted, time: .shortened))")
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
                .buttonStyle(.bordered)
                .controlSize(.small)

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
            .tint(.blue)

            Button {
                engine.goLiveWithSchedule(id: schedule.id)
            } label: {
                Label("Go Live Now", systemImage: "play.fill")
            }
            .tint(.green)

            Button(role: .destructive) {
                pendingDeleteSchedule = schedule
            } label: {
                Label("Delete\u{2026}", systemImage: "trash")
            }
        }
    }

    private func nextScheduledLine(_ schedule: ServiceSchedule) -> String {
        "Next: \(schedule.title) \u{2014} \(schedule.startsAt.formatted(date: .abbreviated, time: .shortened)), live at \(schedule.goLiveAt.formatted(date: .omitted, time: .shortened))"
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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    TextField("Title", text: $title)
                    #if os(tvOS)
                    LabeledContent("Starts At") {
                        Text(startsAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    #else
                    DatePicker("Starts At", selection: $startsAt)
                    #endif
                }

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
            ? "Goes live at service time"
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
                    Text(minutes == 0 ? "At service time" : "\(minutes) min before")
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
            Text("Live at \(resolvedGoLiveAt.formatted(date: .omitted, time: .shortened)).")
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
                    pcoPlanId = nil
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
                isEnabled: isEnabled
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
                isEnabled: isEnabled
            )
        }
        dismiss()
    }
}
