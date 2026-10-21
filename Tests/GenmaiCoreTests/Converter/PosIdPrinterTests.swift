// Port of mozc/src/converter/pos_id_printer_test.cc (3.35.6354).

import GenmaiBase
import Testing
@testable import GenmaiCore

@Suite struct PosIdPrinterTests {
  @Test func basicIdTest() {
    let printer = PosIdPrinter(
      InputFileStream(ConverterCoreTestSupport.sourcePath("data", "test", "dictionary", "id.def")))
    #expect(printer.idToString(1934) == "名詞,サ変接続,*,*,*,*,*")
    #expect(printer.idToString(1935) == "名詞,サ変接続,*,*,*,*,*,使用")
    #expect(printer.idToString(0) == "BOS/EOS,*,*,*,*,*,*")

    // Invalid ID returns an empty string.
    #expect(printer.idToString(-1) == "")
  }
}
