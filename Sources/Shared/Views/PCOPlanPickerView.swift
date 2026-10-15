// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import SwiftUI

public struct PCOPlanPickerView: View {
    @EnvironmentObject var engine: CueEngine
    @Environment(\.dismiss) private var dismiss

    public init() {}

    private var title: String {
        engine.pcoSelectedServiceTypeId == nil ? "Plan Type" : "Plan"
    }

    @ViewBuilder
    private var content: some View {
        if engine.pcoSelectedServiceTypeId == nil {
            serviceTypeList
        } else {
            planList
        }
    }

    public var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                if engine.pcoSelectedServiceTypeId != nil {
                    Button(action: { engine.clearPCOServiceTypeSelection() }) {
                        Label("Plan Types", systemImage: "chevron.left")
                    }
                }
                Spacer()
                Text(title).font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            content

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(.bar)
        }
        .task {
            if engine.pcoServiceTypes.isEmpty {
                engine.fetchPCOServiceTypes()
            }
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 480, idealHeight: 560)
        #else
        NavigationStack {
            content
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    if engine.pcoSelectedServiceTypeId != nil {
                        ToolbarItem(placement: .navigation) {
                            Button(action: { engine.clearPCOServiceTypeSelection() }) {
                                Label("Plan Types", systemImage: "chevron.left")
                            }
                        }
                    }
                }
                .task {
                    if engine.pcoServiceTypes.isEmpty {
                        engine.fetchPCOServiceTypes()
                    }
                }
        }
        #endif
    }

    private var serviceTypeList: some View {
        List {
            if let error = engine.pcoLastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }

            if engine.pcoServiceTypes.isEmpty && engine.pcoLastError == nil {
                HStack {
                    ProgressView()
                    Text("Loading plan types…")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(engine.pcoServiceTypes) { serviceType in
                let isDefault = engine.pcoDefaultServiceTypeId == serviceType.id
                HStack(spacing: 8) {
                    Button(action: { engine.selectPCOServiceType(serviceType.id) }) {
                        HStack {
                            Text(serviceType.name)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    #if os(macOS)
                    RowActionButton(
                        systemImage: isDefault ? "star.fill" : "star",
                        label: isDefault ? "Unset as default plan type" : "Set as default plan type",
                        tint: isDefault ? .yellow : .secondary
                    ) {
                        engine.setDefaultServiceType(isDefault ? nil : serviceType.id)
                    }
                    #else
                    if isDefault {
                        Label("Default", systemImage: "star.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                    #endif

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .rowActions {
                    if isDefault {
                        Button {
                            engine.setDefaultServiceType(nil)
                        } label: {
                            Label("Unset as Default", systemImage: "star.slash")
                        }
                        .tint(.gray)
                    } else {
                        Button {
                            engine.setDefaultServiceType(serviceType.id)
                        } label: {
                            Label("Set as Default", systemImage: "star.fill")
                        }
                        .tint(.yellow)
                    }
                }
            }
        }
        .refreshable { engine.fetchPCOServiceTypes() }
    }

    private var planList: some View {
        List {
            Section {
                Picker("Show", selection: Binding(
                    get: { engine.pcoPlanFilter },
                    set: { engine.setPlanFilter($0) }
                )) {
                    ForEach(PCOClient.PCOPlanFilter.allCases, id: \.self) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
            #if os(iOS) || os(macOS)
            .listRowSeparator(.hidden)
            #endif

            if let error = engine.pcoLastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }

            Section {
                Button(action: {
                    if let serviceTypeId = engine.pcoSelectedServiceTypeId {
                        engine.fetchPCOPlan(serviceTypeId: serviceTypeId, planId: PCOClient.upcomingPlanId)
                    }
                    dismiss()
                }) {
                    Label("Next Upcoming Plan", systemImage: "calendar.badge.clock")
                }
                .help("Load the soonest upcoming plan of this type")
            }

            if engine.pcoPlans.isEmpty && engine.pcoLastError == nil {
                Text("No \(engine.pcoPlanFilter.displayName.lowercased()) plans.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            ForEach(engine.pcoPlans) { plan in
                Button(action: {
                    if let serviceTypeId = engine.pcoSelectedServiceTypeId {
                        engine.fetchPCOPlan(serviceTypeId: serviceTypeId, planId: plan.id)
                    }
                    dismiss()
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.title)
                            .foregroundStyle(.primary)
                        if let dates = plan.dates, dates != plan.title {
                            Text(dates)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .refreshable { engine.fetchPCOPlans() }
    }
}
