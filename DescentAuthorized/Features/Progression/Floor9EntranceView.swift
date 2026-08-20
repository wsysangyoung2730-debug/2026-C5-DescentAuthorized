import SwiftUI

struct Floor9EntranceView: View {
    @EnvironmentObject private var gameSession: GameSessionStore

    @State private var inspectedRecord = false

    var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.023, blue: 0.03)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                recordsHall
                    .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 18) {
                    Text("9-A / 중앙 기록실 입구")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.purple)

                    Text("제9층 기록 보존 구역")
                        .font(.system(size: 30, weight: .semibold))

                    Text("문서의 이름이 눈앞에서 지워진다. 닫힌 중앙 기록실 너머로 도장을 찍는 소리가 일정한 간격으로 반복된다.")
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)

                    resourceExplanation

                    Button {
                        inspectedRecord = true
                        gameSession.send(.readRecord("9-entrance-01"))
                    } label: {
                        Label("바닥의 승인 서류 확인", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(inspectedRecord)

                    if inspectedRecord {
                        Text("승인자 서명이 자신의 필체와 닮아 있다. 이름 칸만 기억침식으로 비어 있다.")
                            .font(.callout)
                            .foregroundStyle(.purple.opacity(0.9))
                            .transition(.opacity)
                    }

                    Spacer()

                    Button {
                        gameSession.send(.enterRecordsBattle)
                    } label: {
                        Label("중앙 기록실 진입", systemImage: "door.left.hand.open")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
                .frame(maxWidth: 540)
                .padding(30)
            }
        }
    }

    private var resourceExplanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("시전 자원 확인", systemImage: "scribble.variable")
                .font(.headline)
                .foregroundStyle(.cyan)

            HStack(spacing: 12) {
                Image(systemName: "pencil.line")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("마나는 그릴 수 있는 선의 양이다")
                        .font(.subheadline.weight(.semibold))
                    Text("선이 길거나 말소된 구역을 지나면 더 빠르게 줄어든다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "pencil.and.outline")
                    .font(.title2)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text("한 턴에는 최대 2획")
                        .font(.subheadline.weight(.semibold))
                    Text("1획 주문 두 개 또는 2획 주문 하나를 시전할 수 있다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var recordsHall: some View {
        ZStack {
            Canvas { context, size in
                var shelves = Path()
                for column in 1..<7 {
                    let x = size.width * CGFloat(column) / 7
                    shelves.move(to: CGPoint(x: x, y: size.height * 0.12))
                    shelves.addLine(to: CGPoint(x: x, y: size.height * 0.88))
                }
                for row in 1..<6 {
                    let y = size.height * CGFloat(row) / 6
                    shelves.move(to: CGPoint(x: size.width * 0.08, y: y))
                    shelves.addLine(to: CGPoint(x: size.width * 0.92, y: y))
                }
                context.stroke(shelves, with: .color(.white.opacity(0.055)), lineWidth: 2)
            }

            VStack(spacing: 18) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 112, weight: .thin))
                    .foregroundStyle(.white.opacity(0.68))
                    .shadow(color: .purple.opacity(0.45), radius: 16)
                Text("기록이 사라지는 서가")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack {
                Spacer()
                Text("맞은편 건물의 모든 층 표시는 9F로 고정되어 있다")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.65))
                    .padding(.bottom, 34)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("이름이 지워진 기록 서가와 9층으로 반복 표시된 창밖 건물")
    }
}
