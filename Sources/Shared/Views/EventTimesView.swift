// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct EventTimesView: View {
    public enum Target: Identifiable {
        case add
        case edit(EventTime)

        public var id: String {
            switch self {
            case .add: return "add"
            case .edit(let time): return time.id
            }
        }
    }

    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss

    @State private var editorTarget: Target?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    if engine.eventTimes.isEmpty {
                        Text(isManagedByPCO
                            ? "This Planning Center plan has no service times."
                            : "No event times yet. Add one for each time this run sheet runs — like a 9:00 and an 11:00 event.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(engine.eventTimes) { time in
                        row(time)
                    }
                    .onDelete(perform: isManagedByPCO ? nil : { offsets in
                        for index in offsets where engine.eventTimes.indices.contains(index) {
                            engine.removeEventTime(id: engine.eventTimes[index].id)
                        }
                    })
                } footer: {
                    Text(isManagedByPCO
                        ? "These are the plan's service times in Planning Center. Change them there and sync the plan again."
                        : "At the end of the run sheet you can jump to the next time and start over from the top.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Event Times")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { editorTarget = .add }) {
                        Label("Add Event Time", systemImage: "plus")
                    }
                    .disabled(isManagedByPCO || engine.eventTimes.count >= CueEngine.maxEventTimes)
                }
            }
            .sheet(item: $editorTarget) { target in
                EventTimeEditorView(target: target)
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320, idealHeight: 420)
        #endif
    }

    private var isManagedByPCO: Bool {
        engine.isEventTimesManagedByPCO
    }

    private func row(_ time: EventTime) -> some View {
        let isLive = engine.liveEventTime?.id == time.id
        return HStack {
            Image(systemName: isLive ? "dot.radiowaves.left.and.right" : "clock")
                .foregroundStyle(isLive ? AppPalette.positive : Color.secondary)
            Text(time.displayName(engine.clockFormat))
            Spacer()
            if time.pcoPlanTimeId != nil {
                Text("PCO")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if !isLive {
                Button("Make Live") { engine.setLiveEventTime(id: time.id) }
                    .disabled(engine.isChangingEventTime)
            }
            if !isManagedByPCO {
                Button(action: { editorTarget = .edit(time) }) {
                    Image(systemName: "pencil")
                }
                .help("Edit this event time")
                Button(role: .destructive, action: { engine.removeEventTime(id: time.id) }) {
                    Image(systemName: "trash")
                }
                .help("Delete this event time")
            }
        }
        .buttonStyle(.borderless)
    }
}

struct EventTimeEditorView: View {
    enum DayMode: Hashable {
        case none
        case date
        case weekday
    }

    let target: EventTimesView.Target

    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var hasStartTime: Bool
    @State private var startTime: Date
    @State private var dayMode: DayMode
    @State private var date: Date
    @State private var weekday: Int

    init(target: EventTimesView.Target) {
        self.target = target
        let existing: EventTime?
        switch target {
        case .add: existing = nil
        case .edit(let time): existing = time
        }
        _name = State(initialValue: existing?.name ?? "")
        _hasStartTime = State(initialValue: existing == nil || existing?.startTime != nil)
        _startTime = State(initialValue: existing?.startTime?.date(on: Date()) ?? Self.defaultStart())
        switch existing?.day {
        case .date?:
            _dayMode = State(initialValue: .date)
            _date = State(initialValue: existing?.day?.date() ?? Date())
            _weekday = State(initialValue: Calendar.current.component(.weekday, from: Date()))
        case .weekday(let value)?:
            _dayMode = State(initialValue: .weekday)
            _date = State(initialValue: Date())
            _weekday = State(initialValue: value)
        case nil:
            _dayMode = State(initialValue: .none)
            _date = State(initialValue: Date())
            _weekday = State(initialValue: Calendar.current.component(.weekday, from: Date()))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $name)
                    Toggle("Start Time", isOn: $hasStartTime)
                    if hasStartTime {
                        #if os(tvOS)
                        LabeledContent("Starts") {
                            Text(TimeOfDay(date: startTime).formatted(engine.clockFormat))
                                .font(.clock(.body, weight: .regular))
                        }
                        #else
                        DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                            .environment(\.locale, engine.clockFormat.pickerLocale)
                        #endif
                    }
                }

                Section {
                    Picker("Day", selection: $dayMode) {
                        Text("Any Day").tag(DayMode.none)
                        Text("Date").tag(DayMode.date)
                        Text("Day of Week").tag(DayMode.weekday)
                    }
                    switch dayMode {
                    case .none:
                        EmptyView()
                    case .date:
                        #if os(tvOS)
                        LabeledContent("Date") {
                            Text(EventDay(date: date).formatted)
                        }
                        #else
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                        #endif
                    case .weekday:
                        Picker("Weekday", selection: $weekday) {
                            ForEach(1...7, id: \.self) { value in
                                Text(Calendar.current.weekdaySymbols[value - 1]).tag(value)
                            }
                        }
                    }
                } footer: {
                    Text("Leave the day as Any Day for times on the same day. Use a day of the week for a run sheet you reuse every week.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isAdding ? "Add Event Time" : "Edit Event Time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!hasStartTime && dayMode == .none && name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 400, minHeight: 320, idealHeight: 360)
        #endif
    }

    private var isAdding: Bool {
        if case .add = target { return true }
        return false
    }

    private var resolvedDay: EventDay? {
        switch dayMode {
        case .none: return nil
        case .date: return EventDay(date: date)
        case .weekday: return .weekday(weekday)
        }
    }

    private func save() {
        let time = hasStartTime ? TimeOfDay(date: startTime) : nil
        switch target {
        case .add:
            engine.addEventTime(name: name, day: resolvedDay, startTime: time)
        case .edit(let existing):
            engine.updateEventTime(id: existing.id, name: name, day: resolvedDay, startTime: time)
        }
        dismiss()
    }

    private static func defaultStart() -> Date {
        let calendar = Calendar.current
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: calendar.component(.hour, from: nextHour), minute: 0, second: 0, of: nextHour) ?? nextHour
    }
}
