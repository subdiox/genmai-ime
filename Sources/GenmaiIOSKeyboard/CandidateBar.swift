// The candidate bar (not in Mozc): the mobile candidate list (`all_candidate_words`: suggestions while typing,
// conversion candidates after the conversion key, zero-query suggestions after a commit), one row that expands to
// a grid over the keys.

#if os(iOS)
  import GenmaiIOS
  import SwiftUI

  struct CandidateBar: View {
    let controller: KeyboardController
    let state: KeyboardHostState

    var body: some View {
      HStack(spacing: 0) {
        ScrollViewReader { proxy in
          ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
              ForEach(controller.candidates) { candidate in
                CandidateButton(
                  candidate: candidate, isFocused: candidate.id == controller.focusedCandidateID,
                  controller: controller, state: state)
              }
            }
            .padding(.leading, 0.5)
          }
          .scrollIndicators(.hidden)
          .noScrollEdgeEffect()
          .onChange(of: controller.focusedCandidateID) { _, id in
            if let id {
              withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
          }
        }
        if !controller.candidates.isEmpty {
          Divider().frame(height: 34)
          Button {
            state.showsAllCandidates.toggle()
          } label: {
            Image(systemName: state.showsAllCandidates ? "chevron.up" : "chevron.down")
              .frame(width: 44, height: KeyboardMetrics.candidateBarHeight)
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(state.showsAllCandidates ? "候補を閉じる" : "すべての候補")
        }
      }
    }
  }

  struct CandidateButton: View {
    let candidate: KeyboardCandidate
    let isFocused: Bool
    let controller: KeyboardController
    let state: KeyboardHostState

    var body: some View {
      Button {
        state.showsAllCandidates = false
        controller.selectCandidate(candidate.id)
      } label: {
        // as on the system keyboard (measured): 20 pt, no separators, texts 20 pt apart, the focused candidate on
        // a light rounded box 3.5 pt around its text and 37 pt high, the first one 7 pt from the edge
        Text(candidate.value)
          .font(.system(size: 20))
          .lineLimit(1)
          .offset(y: 0.7)
          .padding(.horizontal, 3.5)
          .frame(minHeight: 37)
          .background(isFocused ? KeyboardColors.candidateHighlight : .clear, in: .rect(cornerRadius: 10))
          .padding(.horizontal, 6.5)
          .frame(minHeight: KeyboardMetrics.candidateBarHeight)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .id(candidate.id)
      .accessibilityHint(candidate.description)
    }
  }

  /// All candidates over the keys (the expanded candidate bar).
  struct CandidateGrid: View {
    let controller: KeyboardController
    let state: KeyboardHostState
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 4)], spacing: 4) {
          ForEach(controller.candidates) { candidate in
            CandidateButton(
              candidate: candidate, isFocused: candidate.id == controller.focusedCandidateID,
              controller: controller, state: state)
          }
        }
        .padding(4)
      }
      .noScrollEdgeEffect()
      .frame(maxWidth: .infinity)
      .frame(height: KeyboardMetrics.keysHeight(verticalSizeClass))
    }
  }

  extension View {
    /// iOS 26 blurs the content at a scroll view's edges, over the candidates the system keyboard shows plainly.
    @ViewBuilder
    fileprivate func noScrollEdgeEffect() -> some View {
      if #available(iOS 26, *) {
        scrollEdgeEffectHidden(true, for: .all)
      } else {
        self
      }
    }
  }
#endif
