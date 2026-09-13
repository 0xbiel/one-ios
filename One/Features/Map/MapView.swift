import SwiftUI

struct MapView: View {
    @Bindable var store: AppStore
    @State private var showEvidence = true
    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if store.scene.isRenderable3D {
                    RoomPlan3DSceneView(store: store)
                } else {
                    RoomMapCanvas(scan: store.scan)
                }
            }
            .ignoresSafeArea()
            .onTapGesture { showEvidence = true }
            if !showEvidence { LiquidGlassControl { Button { showEvidence = true } label: { Label("Show evidence", systemImage: "line.3.horizontal.decrease.circle").padding(.horizontal, 16).padding(.vertical, 10) } }.padding(.bottom, 32) }
        }.sheet(isPresented: $showEvidence) { MapEvidenceSheet(store: store).presentationDetents([.height(245), .medium, .large]).presentationDragIndicator(.visible).presentationBackgroundInteraction(.enabled(upThrough: .medium)).presentationContentInteraction(.scrolls) }
    }
}

struct RoomMapCanvas: View {
    let scan: RoomScan
    private var labels: [String] { Array((scan.objects.map(\.name) + scan.zones.map(\.name)).prefix(4)) }

    var body: some View { ZStack { LinearGradient(colors: [Color(red: 0.70, green: 0.90, blue: 0.94), Color(red: 0.92, green: 0.95, blue: 0.91)], startPoint: .top, endPoint: .bottom); GeometryReader { _ in Canvas { context, size in for x in stride(from: 0, through: size.width, by: 28) { var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); context.stroke(p, with: .color(.white.opacity(0.3)), lineWidth: 0.6) }; for y in stride(from: 0, through: size.height, by: 28) { var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); context.stroke(p, with: .color(.white.opacity(0.3)), lineWidth: 0.6) } }.overlay { RoundedRectangle(cornerRadius: 26).stroke(OneTheme.accentBlue.opacity(0.45), lineWidth: 2).padding(.horizontal, 42).padding(.vertical, 180).overlay { if labels.isEmpty { Label("No room map yet", systemImage: "map") .font(.headline) .foregroundStyle(OneTheme.secondaryInk) } else { HStack(spacing: 18) { ForEach(Array(labels.enumerated()), id: \.offset) { index, label in RoomMapPin(title: label, color: index.isMultiple(of: 2) ? OneTheme.accentCyan : OneTheme.accentBlue) } }.padding(.horizontal, 48) } } } } }.accessibilityElement(children: .combine).accessibilityLabel(labels.isEmpty ? "No room map available" : "Room map with \(labels.joined(separator: ", "))") } }

struct RoomMapPin: View { let title: String; let color: Color; var body: some View { VStack(spacing: 5) { Circle().fill(color).frame(width: 30, height: 30).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 6); Text(title).font(.caption.weight(.semibold)).foregroundStyle(OneTheme.ink).padding(.horizontal, 8).padding(.vertical, 4).background(OneTheme.surface, in: Capsule()) } } }

struct MapEvidenceSheet: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Home map").font(.largeTitle.weight(.bold)).tracking(-1)
                            Text(store.scene.isRenderable3D ? "Native RoomPlan · metric 3D" : "Approximate locations · local view")
                                .font(.subheadline)
                                .foregroundStyle(OneTheme.secondaryInk)
                        }
                        Spacer()
                        NavigationLink { ScanView(store: store) } label: {
                            Image(systemName: "viewfinder").font(.title3).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Update room scan")
                    }

                    if store.scene.isRenderable3D {
                        SurfaceCard(radius: 20) {
                            Label(store.scene.hasReadyUSDZ ? "LiDAR model available" : "LiDAR geometry available · 3D asset pending", systemImage: store.scene.hasReadyUSDZ ? "cube.fill" : "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(OneTheme.accentBlue)
                                .padding(16)
                        }
                        CameraRegistrationStatusCard(registration: store.scene.cameraRegistration)
                    } else if store.events.isEmpty {
                        SurfaceCard(radius: 20) {
                            Label("No observations yet", systemImage: "tray").font(.subheadline).foregroundStyle(OneTheme.secondaryInk).padding(16)
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(store.events.prefix(3)) { event in
                                EventRow(event: event)
                                if event.id != store.events.prefix(3).last?.id { Divider() }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(.regularMaterial)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CameraRegistrationStatusCard: View {
    let registration: CameraRegistrationDescriptor?

    private var copy: (title: String, detail: String) {
        switch registration?.status ?? .unavailable {
        case .positioned:
            return ("Camera positioned", "Placed in the RoomPlan coordinate frame.")
        case .needsRescan:
            return ("Camera placement needs another attempt", "Keep the fixed camera still and retry Position this camera in 3D from that camera's own live view.")
        case .unavailable:
            return ("Camera placement pending", "The LiDAR map is ready. Position the fixed Mac or browser camera later from its own live view; the room does not need another LiDAR scan.")
        }
    }

    var body: some View {
        let state = registration?.status ?? .unavailable
        SurfaceCard(radius: 20) {
            HStack(spacing: 12) {
                Image(systemName: state == .positioned ? "camera.viewfinder" : "camera.badge.ellipsis")
                    .foregroundStyle(state == .positioned ? OneTheme.accentBlue : OneTheme.secondaryInk)
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy.title)
                        .font(.subheadline.weight(.semibold))
                    Text(copy.detail)
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
            }
            .padding(16)
        }
    }
}

struct ScanView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var isCapturing = false
    @State private var showCapture = false
    @State private var captureError: String?
    @State private var selectedCameraID: UUID?

    var body: some View {
        ZStack {
            if showCapture && RoomPlanCapability.isSupported {
                RoomPlanCaptureView(isCapturing: $isCapturing) { result in
                    isCapturing = false
                    showCapture = false
                    switch result {
                    case let .success(capture):
                        Task {
                            await store.uploadRoomPlan(capture, cameraID: selectedCameraID)
                            if store.authError == nil && (selectedCameraID == nil || store.scene.cameraRegistration?.status == .positioned) {
                                dismiss()
                            }
                        }
                    case let .failure(error):
                        captureError = error.localizedDescription
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Refresh the home map")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .tracking(-1)
                        Text("Scan the room with this iPhone. If your fixed camera is a Mac or another browser device, leave Map only selected; ONE will place that camera later from its own fixed live view.")
                            .foregroundStyle(OneTheme.secondaryInk)

                        if !store.pairedCameras.isEmpty {
                            SurfaceCard(radius: 22) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Direct camera registration").font(.headline)
                                    Picker("Direct camera registration", selection: $selectedCameraID) {
                                        Text("Map only (recommended for Mac/browser camera)").tag(UUID?.none)
                                        ForEach(store.pairedCameras) { camera in
                                            Text(camera.name).tag(UUID?.some(camera.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    Text("Leave Map only selected when this iPhone is only the LiDAR scanner. Choose a camera only when this exact iPhone is also the paired fixed camera; its final RoomPlan pose will be registered directly.")
                                        .font(.footnote)
                                        .foregroundStyle(OneTheme.secondaryInk)
                                }
                                .padding(18)
                            }
                        }

                        if store.isRoomPlanUploading {
                            ProgressView("Saving RoomPlan scan…").tint(OneTheme.accentBlue)
                            Text("The 3D map is saved even if camera positioning needs another scan.")
                                .font(.subheadline)
                                .foregroundStyle(OneTheme.secondaryInk)
                        } else if RoomPlanCapability.isSupported {
                            Button {
                                captureError = nil
                                showCapture = true
                                isCapturing = true
                            } label: {
                                Label("Start LiDAR scan", systemImage: "viewfinder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(OneTheme.accentBlue)
                            .foregroundStyle(.white)
                        } else {
                            Label("LiDAR is not available on this device.", systemImage: "iphone.slash").font(.headline)
                            Text("You can still use ONE with a caregiver-created zone map, but automatic camera placement requires a LiDAR-capable iPhone or iPad.")
                                .foregroundStyle(OneTheme.secondaryInk)
                            Button("Create zones manually") { dismiss() }.buttonStyle(.bordered)
                        }

                        if let registration = store.scene.cameraRegistration, store.scene.isRenderable3D {
                            CameraRegistrationStatusCard(registration: registration)
                        }
                        if let captureError { Text(captureError).font(.footnote).foregroundStyle(.red) }
                        if let authError = store.authError { Text(authError).font(.footnote).foregroundStyle(.red) }
                        if let mapError = store.roomPlanModelError { Text(mapError).font(.footnote).foregroundStyle(OneTheme.secondaryInk) }
                    }
                    .padding(24)
                }
            }
        }
        .background(OneTheme.canvas.ignoresSafeArea())
        .navigationTitle("Room scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showCapture && RoomPlanCapability.isSupported {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCapturing = false
                    } label: {
                        Label("Done scanning", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(!isCapturing)
                }
            }
        }
    }
}
