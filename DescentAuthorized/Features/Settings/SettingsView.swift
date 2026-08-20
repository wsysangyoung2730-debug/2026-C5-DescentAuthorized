import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings

    @State private var testStrokes: [DrawnStroke] = []
    @State private var lastInputMethod: DrawingInputMethod?
    @State private var canvasController = RuneDrawingCanvasController()

    var body: some View {
        NavigationStack {
            List {
                Section("입력 방식") {
                    Picker("입력 방식", selection: inputPreferenceBinding) {
                        Text("자동").tag(DrawingInputPreference.automatic)
                        Text("Pencil").tag(DrawingInputPreference.pencilOnly)
                        Text("손가락").tag(DrawingInputPreference.fingerOnly)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("마법진 입력 방식")
                }

                Section("입력 확인") {
                    drawingSurface

                    HStack(spacing: 16) {
                        Label(inputMethodTitle, systemImage: inputMethodIcon)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 16)

                        Text("\(testStrokes.count) / 2획")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        Button {
                            canvasController.undoLastStroke()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderless)
                        .disabled(testStrokes.isEmpty)
                        .help("마지막 획 되돌리기")
                        .accessibilityLabel("마지막 획 되돌리기")

                        Button(role: .destructive) {
                            canvasController.clear()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(testStrokes.isEmpty)
                        .help("모든 획 지우기")
                        .accessibilityLabel("모든 획 지우기")
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("설정 닫기")
                    .accessibilityLabel("설정 닫기")
                }
            }
            .alert("설정을 저장하지 못했습니다", isPresented: $appSettings.showsPersistenceError) {
                Button("확인", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }

    private var drawingSurface: some View {
        ZStack {
            Color(red: 0.035, green: 0.04, blue: 0.055)

            grid

            RuneDrawingCanvas(
                inputPreference: appSettings.inputPreference,
                maximumStrokeCount: 2,
                controller: canvasController,
                strokes: $testStrokes,
                lastInputMethod: $lastInputMethod
            )
        }
        .frame(minHeight: 240, idealHeight: 280, maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .accessibilityElement(children: .contain)
    }

    private var grid: some View {
        Canvas { context, size in
            var path = Path()
            let columns = 8
            let rows = 5
            for column in 1..<columns {
                let x = size.width * CGFloat(column) / CGFloat(columns)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 1..<rows {
                let y = size.height * CGFloat(row) / CGFloat(rows)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.055)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private var inputPreferenceBinding: Binding<DrawingInputPreference> {
        Binding(
            get: { appSettings.inputPreference },
            set: { appSettings.setInputPreference($0) }
        )
    }

    private var inputMethodTitle: String {
        switch lastInputMethod {
        case .pencil:
            "Apple Pencil"
        case .finger:
            "손가락"
        case nil:
            "대기"
        }
    }

    private var inputMethodIcon: String {
        switch lastInputMethod {
        case .pencil:
            "pencil.tip"
        case .finger:
            "hand.draw"
        case nil:
            "circle.dotted"
        }
    }
}
