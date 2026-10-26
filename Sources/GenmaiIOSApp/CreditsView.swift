// The licenses of Mozc and the other open source software in Genmai (credits_en.html: Mozc's data/installer one plus
// SudachiDict's notice, made by Tools/make_ios_project.sh; required by Mozc's BSD license).

#if os(iOS)
  import GenmaiGUI
  import SwiftUI
  import WebKit

  struct CreditsView: View {
    var body: some View {
      Group {
        if let url = Bundle.main.url(forResource: "credits_en", withExtension: "html") {
          CreditsWebView(url: url)
        } else {
          ContentUnavailableView(AppStrings.text(.licenses), systemImage: "doc.text")
        }
      }
      .navigationTitle(AppStrings.text(.licenses))
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  /// SwiftUI's WebView needs iOS 26.
  private struct CreditsWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
      let view = WKWebView()
      view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
      return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
  }
#endif
