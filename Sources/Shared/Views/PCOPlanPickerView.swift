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
                Spacer()
                Text("Choose a Plan to Sync").font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                typeSidebar
                    .frame(width: 190)
                Divider()
                planPane
            }

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
            selectInitialTypeIfNeeded()
        }
        .onChange(of: engine.pcoServiceTypes) { _, _ in selectInitialTypeIfNeeded() }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 480, idealHeight: 560)
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

    #if os(macOS)
    @State private var search = ""

    /// Open on the plan type that is already synced, else the default, else the first.
    private func selectInitialTypeIfNeeded() {
        guard engine.pcoSelectedServiceTypeId == nil, !engine.pcoServiceTypes.isEmpty else { return }
        let current = engine.planItems.first?.pcoServiceTypeId
        let pick = [current, engine.pcoDefaultServiceTypeId]
            .compactMap { $0 }
            .first { id in engine.pcoServiceTypes.contains(where: { $0.id == id }) }
            ?? engine.pcoServiceTypes.first?.id
        if let pick { engine.selectPCOServiceType(pick) }
    }

    private var typeSidebar: some View {
        List {
            Section("Plan Types") {
                if engine.pcoServiceTypes.isEmpty {
                    if engine.pcoServiceTypesLoaded {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No plan types in this account")
                                .font(.callout.weight(.semibold))
                            Text("Create a service type in Planning Center Services, then reload.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Reload") { engine.fetchPCOServiceTypes() }
                                .controlSize(.small)
                        }
                    } else {
                        HStack { ProgressView().controlSize(.small); Text("Loading\u{2026}").foregroundStyle(.secondary) }
                    }
                }
                ForEach(engine.pcoServiceTypes) { type in
                    let isDefault = engine.pcoDefaultServiceTypeId == type.id
                    let isSelected = engine.pcoSelectedServiceTypeId == type.id
                    HStack {
                        Text(type.name)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        RowActionButton(
                            systemImage: isDefault ? "star.fill" : "star",
                            label: isDefault ? "Unset as default plan type" : "Set as default plan type",
                            tint: isDefault ? AppPalette.favorite : .secondary
                        ) {
                            engine.setDefaultServiceType(isDefault ? nil : type.id)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture { engine.selectPCOServiceType(type.id) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var filteredPlans: [PCOClient.PCOPlanInfo] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return engine.pcoPlans }
        return engine.pcoPlans.filter {
            $0.title.localizedCaseInsensitiveContains(query) || ($0.dates ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var planPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let context = engine.pcoPlanContext {
                HStack(spacing: 8) {
                    Circle().fill(AppPalette.positive).frame(width: 8, height: 8)
                    Text("Currently synced: **\(context.title ?? engine.planTitle ?? "Plan")**")
                        .lineLimit(1)
                    Spacer()
                    Text(context.fetchedAt, style: .relative)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(10)
                .background(AppPalette.positive.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }

            if let error = engine.pcoLastError {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppPalette.warning)
                        .font(.footnote)
                    Button("Sign in again") { engine.signInWithPCO() }
                        .buttonStyle(.bordered)
                }
            }

            HStack {
                TextField("Search plans", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("Show", selection: Binding(
                    get: { engine.pcoPlanFilter },
                    set: { engine.setPlanFilter($0) }
                )) {
                    ForEach(PCOClient.PCOPlanFilter.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if engine.pcoSelectedServiceTypeId == nil {
                Spacer()
                Text("Choose a plan type.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    Button {
                        if let id = engine.pcoSelectedServiceTypeId {
                            engine.fetchPCOPlan(serviceTypeId: id, planId: PCOClient.upcomingPlanId)
                        }
                        dismiss()
                    } label: {
                        Label("Next Upcoming Plan", systemImage: "calendar.badge.clock")
                    }
                    .help("Load the soonest upcoming plan of this type")

                    if filteredPlans.isEmpty && engine.pcoLastError == nil {
                        Text(search.isEmpty ? "No \(engine.pcoPlanFilter.displayName.lowercased()) plans." : "No plans match \u{201C}\(search)\u{201D}.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(filteredPlans) { plan in
                        Button {
                            if let id = engine.pcoSelectedServiceTypeId {
                                engine.fetchPCOPlan(serviceTypeId: id, planId: plan.id)
                            }
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.title).foregroundStyle(.primary)
                                if let dates = plan.dates, dates != plan.title {
                                    Text(dates).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    #endif

    private var serviceTypeList: some View {
        List {
            if let error = engine.pcoLastError {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppPalette.warning)
                        .font(.footnote)
                    Button("Sign in again") { engine.signInWithPCO() }
                        .buttonStyle(.bordered)
                }
            }

            if engine.pcoServiceTypes.isEmpty && engine.pcoLastError == nil {
                if engine.pcoServiceTypesLoaded {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No plan types in this account", systemImage: "tray")
                            .font(.headline)
                        Text("This Planning Center account has no service types yet. Create one in Planning Center Services, then reload.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Reload") { engine.fetchPCOServiceTypes() }
                            if let url = URL(string: "https://services.planningcenteronline.com") {
                                Link("Open Planning Center", destination: url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 6)
                } else {
                    HStack {
                        ProgressView()
                        Text("Loading plan types…")
                            .foregroundStyle(.secondary)
                    }
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
                        tint: isDefault ? AppPalette.favorite : .secondary
                    ) {
                        engine.setDefaultServiceType(isDefault ? nil : serviceType.id)
                    }
                    #else
                    if isDefault {
                        Label("Default", systemImage: "star.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(AppPalette.favorite)
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
                        .tint(AppPalette.favorite)
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
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppPalette.warning)
                        .font(.footnote)
                    Button("Sign in again") { engine.signInWithPCO() }
                        .buttonStyle(.bordered)
                }
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
