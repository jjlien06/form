import SwiftUI

@main
struct FormApp: App {
    var body: some Scene {
        WindowGroup { ScannerScreen().preferredColorScheme(.dark).tint(acid) }
    }
}

private let acid = Color(red: 0.80, green: 0.98, blue: 0.40)
private let ink = Color(red: 0.055, green: 0.065, blue: 0.065)

struct ScannerScreen: View {
    @StateObject private var session = ScanSession()
    @StateObject private var library = MeasurementLibrary()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLibrary = false
    @State private var showGuide = false
    @State private var showAdjust = false
    @State private var showSave = false
    @State private var objectName = ""
    @State private var saved = false

    var body: some View {
        ZStack {
            ink.ignoresSafeArea()
            if session.demo {
                DemoScene(box: session.box, unit: session.unit)
                    .ignoresSafeArea()
                    .onTapGesture { session.select(at: .zero) }
            } else if session.available && !session.denied {
                CameraView(session: session).ignoresSafeArea()
            } else {
                unsupported
            }
            VStack(spacing: 0) {
                header
                if session.demo || (session.available && !session.denied) {
                    HStack(spacing: 7) {
                        Circle().fill(session.demo ? .orange : acid).frame(width: 6, height: 6)
                        Text(session.demo ? "DEMO · EXAMPLE DATA" : session.ready ? "LiDAR ACTIVE · ON DEVICE" : "INITIALIZING CAMERA")
                            .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2)
                        Spacer()
                        if session.demo {
                            Button("Exit") { session.leaveDemo() }.font(.caption).foregroundStyle(acid)
                        }
                    }.padding(.horizontal, 24).padding(.top, 20)
                    Spacer()
                    if session.box == nil && !session.busy {
                        Image(systemName: "viewfinder").font(.system(size: 52, weight: .ultraLight))
                            .foregroundStyle(acid.opacity(0.8)).allowsHitTesting(false)
                        Spacer()
                    }
                    scanPanel
                } else { Spacer() }
            }
        }
        .sheet(isPresented: $showLibrary) { LibraryScreen(library: library, unit: session.unit) }
        .sheet(isPresented: $showGuide) { guide }
        .sheet(isPresented: $showAdjust) {
            if let box = session.box { AdjustmentScreen(session: session, box: box) }
        }
        .alert("Save measurement", isPresented: $showSave) {
            TextField("Object name", text: $objectName)
            Button("Save") {
                if let box = session.box, library.save(box, name: objectName, demo: session.demo) {
                    saved = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text(session.demo ? "This will be labeled as an example measurement." : "An estimate of the surfaces captured in this scan.") }
        .alert("Scan needs attention", isPresented: Binding(get: { session.problem != nil }, set: { if !$0 { session.problem = nil } })) {
            Button("OK") { session.problem = nil }
        } message: { Text(session.problem ?? "") }
        .alert("Storage", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.start() }
            else { session.pause() }
        }
        .onChange(of: session.box?.samples) { _, _ in saved = false }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--demo") { session.showDemo() }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                Image(systemName: "cube.transparent").font(.system(size: 27, weight: .light)).foregroundStyle(acid)
                Text("form").font(.system(size: 31, weight: .semibold, design: .rounded)).tracking(-1.5)
            }
            Spacer()
            Button { showGuide = true } label: { Image(systemName: "questionmark").frame(width: 40, height: 40) }
                .accessibilityLabel("Scanning guide")
            Button { showLibrary = true } label: { Image(systemName: "square.stack.3d.up").frame(width: 40, height: 40) }
                .accessibilityLabel("Saved measurements")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 12)
        .background(LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var scanPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.busy ? "Finding its form…" : session.addingView ? "A different perspective." : session.box == nil ? "Give it dimension." : "A little more perspective.")
                        .font(.system(size: 25, weight: .medium)).tracking(-0.7)
                    Text(session.busy ? "Keep the object still while we process this view." : session.message)
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.58)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if session.busy { ProgressView().tint(acid).padding(.top, 8) }
                else if session.box != nil {
                    Button { session.unit = session.unit == .centimeters ? .inches : .centimeters } label: {
                        Text(session.unit.rawValue).font(.system(size: 12, weight: .bold, design: .monospaced))
                            .padding(10).background(.white.opacity(0.08), in: Capsule())
                    }.foregroundStyle(acid).accessibilityLabel("Change measurement units")
                }
            }
            if let box = session.box {
                HStack(spacing: 0) {
                    dimension("WIDTH", value: box.size.x)
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 42)
                    dimension("HEIGHT", value: box.size.y)
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 42)
                    dimension("DEPTH", value: box.size.z)
                }.padding(.vertical, 6)
                HStack(spacing: 6) {
                    Image(systemName: "circle.lefthalf.filled")
                    Text("\(box.views) \(box.views == 1 ? "view" : "views") · \(box.edited ? "manually adjusted" : "surface estimate")")
                    Spacer()
                    Button("Adjust") { showAdjust = true }.foregroundStyle(acid)
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 10) {
                    Button { session.addView() } label: {
                        Label(session.addingView ? "Tap object" : "Add angle", systemImage: "viewfinder")
                            .frame(maxWidth: .infinity).frame(height: 50)
                    }.background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
                    Button {
                        objectName = session.demo ? "Example box" : "Object \(library.items.count + 1)"
                        showSave = true
                    } label: {
                        Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "arrow.down.to.line")
                            .frame(maxWidth: .infinity).frame(height: 50)
                    }.foregroundStyle(ink).background(acid, in: RoundedRectangle(cornerRadius: 15))
                }.font(.system(size: 14, weight: .semibold)).disabled(session.busy)
                Button { session.restart(); saved = false } label: {
                    Label("New measurement", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).padding(.top, 2)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "hand.tap").foregroundStyle(acid)
                    Text("Tap an object in the camera view").font(.system(size: 14, weight: .medium))
                    Spacer()
                }.padding(16).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(22).background(ink.opacity(0.96), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.09), lineWidth: 1))
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    private func dimension(_ name: String, value: Float) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(name).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(.white.opacity(0.45))
            Text(session.unit.format(value)).font(.system(size: 29, weight: .light, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .center)
    }

    private var unsupported: some View {
        VStack(spacing: 22) {
            Image(systemName: session.denied ? "camera" : "cube.transparent")
                .font(.system(size: 70, weight: .ultraLight)).foregroundStyle(acid)
            VStack(spacing: 12) {
                Text(session.denied ? "Let’s see your space." : "Real objects.\nReal dimensions.")
                    .font(.system(size: 36, weight: .medium)).tracking(-1.2).multilineTextAlignment(.center)
                Text(session.denied ? "Allow camera access in Settings to scan and measure objects." : "Live scanning needs an iPhone with LiDAR.\nExplore the experience with an example scan.")
                    .font(.system(size: 15)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center).lineSpacing(5)
            }
            if session.denied {
                Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    .buttonStyle(.bordered).tint(acid)
            }
            Button { session.showDemo() } label: {
                HStack { Text("Explore a demo"); Image(systemName: "arrow.up.right") }
                    .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 26).padding(.vertical, 17)
                    .foregroundStyle(ink).background(acid, in: Capsule())
            }.padding(.top, 8)
            Text("PRIVATE BY DESIGN · PROCESSED ON YOUR IPHONE")
                .font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.white.opacity(0.35))
        }.padding(28)
    }

    private var guide: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("A few angles.\nA fuller picture.").font(.system(size: 36, weight: .medium)).tracking(-1)
                    guideRow("01", "Find a clear subject", "Start with an opaque, stationary object. Keep it fully in view, about 0.2–3 m away, with a little space around it.")
                    guideRow("02", "Tap, then move", "Tap the middle of the object. Choose Add angle, walk around it, and tap the same object again. Don’t move the object between scans.")
                    guideRow("03", "Check the fit", "The green box follows the measured surfaces. Use Adjust to align its horizontal axes or edit dimensions. Hidden sides may be underestimated.")
                    guideRow("04", "Keep what you find", "Save a named measurement in your library. Scanning and storage happen on your iPhone.")
                    Text("Estimates, not precision measurements. Glass, shiny surfaces, thin edges and clutter may produce poor results. More views do not guarantee accuracy.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(ink).navigationTitle("Field guide").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showGuide = false }.tint(acid) } }
        }
    }

    private func guideRow(_ n: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(n).font(.system(.caption, design: .monospaced)).foregroundStyle(acid).padding(.top, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
    }
}

struct AdjustmentScreen: View {
    @ObservedObject var session: ScanSession
    let box: MeasuredBox
    @Environment(\.dismiss) private var dismiss
    @State private var dimensions: SIMD3<Float> = .zero
    @State private var yaw: Float = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Align the box") {
                    Text("Rotate to match the object’s horizontal edges. Rotation refits the captured points; edit lengths afterward.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Slider(value: $yaw, in: -Float.pi...Float.pi).tint(acid)
                        .accessibilityLabel("Box rotation")
                        .onChange(of: yaw) { _, newValue in
                            session.adjust(size: dimensions, yaw: newValue)
                            dimensions = session.box?.size ?? dimensions
                        }
                }
                Section("Dimensions · centimeters") {
                    ForEach(0..<3) { axis in
                        HStack {
                            Text(["Width", "Height", "Depth"][axis])
                            Spacer()
                            TextField("cm", value: Binding(get: { Double(dimensions[axis] * 100) }, set: {
                                if $0.isFinite { dimensions[axis] = Float(min(1000, max(0.5, $0))) / 100 }
                            }), format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                        }
                    }
                }
                Text("Edits are marked as manual. Adding another scan will refit dimensions from the captured surfaces.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Adjust measurement").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { session.adjust(size: dimensions, yaw: yaw); dismiss() }.tint(acid)
            } }
            .onAppear { dimensions = box.size; yaw = box.yaw }
            .onDisappear { session.adjust(size: dimensions, yaw: yaw) }
        }.presentationDetents([.medium, .large])
    }
}

struct LibraryScreen: View {
    @ObservedObject var library: MeasurementLibrary
    let unit: MeasureUnit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if library.items.isEmpty {
                    ContentUnavailableView("Room for discovery.", systemImage: "cube.transparent", description: Text("Your saved measurements will appear here."))
                } else {
                    List {
                        ForEach(library.items) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(item.name).font(.headline)
                                    Spacer()
                                    ShareLink(item: shareText(item)) { Image(systemName: "square.and.arrow.up").foregroundStyle(acid) }
                                }
                                Text("\(unit.format(item.width)) × \(unit.format(item.height)) × \(unit.format(item.depth)) \(unit.rawValue)")
                                    .font(.system(size: 22, weight: .light, design: .rounded))
                                Text("W × H × D · \(item.demo ? "DEMO · " : "")\(item.edited ? "Adjusted" : "Estimate") · \(item.date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 9)
                        }.onDelete(perform: library.delete)
                    }
                }
            }
            .navigationTitle("Your measurements")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(acid) } }
        }
    }

    private func shareText(_ item: SavedMeasurement) -> String {
        "\(item.name)\nWidth: \(unit.format(item.width)) \(unit.rawValue)\nHeight: \(unit.format(item.height)) \(unit.rawValue)\nDepth: \(unit.format(item.depth)) \(unit.rawValue)\n\(item.demo ? "Example data — " : "")\(item.edited ? "Manually adjusted estimate" : "Surface estimate") · \(item.views) views\nMeasured with Form"
    }
}
