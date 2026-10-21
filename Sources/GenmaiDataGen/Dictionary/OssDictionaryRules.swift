// Port of the dictionary preprocessing genrules of
// mozc/src/data/dictionary_oss/BUILD.bazel (`aux_dictionary`,
// `filtered_dictionary`) and mozc/src/dictionary/BUILD.bazel
// (`zip_code_data`) (3.35.6354).

import Foundation
import GenmaiBase

extension OssDictionarySources {
  /// `//dictionary:zip_code_data` (gen_zip_code_seed --zip_code KEN_ALL.CSV
  /// --jigyosyo JIGYOSYO.CSV): the contents of zip_code.tsv.
  public func zipCodeTsv() throws -> [UInt8] {
    Array(try GenZipCodeSeed.generate(zipCode: zipCodeKenAll, jigyosyo: zipCodeJigyosyo).utf8)
  }

  /// Runs `zip_code_data`, `filtered_dictionary` and `aux_dictionary`, writing
  /// zip_code.tsv, dictionary.txt and aux_dictionary.txt into `workDir`.
  /// Returns the paths of aux_dictionary.txt and dictionary.txt (the
  /// `//data/dictionary_oss:dictionary_data` filegroup, in its order).
  public func generate(workDir: String) throws -> (auxDictionary: String, filteredDictionary: String) {
    func out(_ name: String) -> String { (workDir as NSString).appendingPathComponent(name) }

    // :base_dictionary_data = dictionary00.txt ... dictionary09.txt +
    // //dictionary:zip_code_data.  `$(locations :base_dictionary_data)` lists
    // the generated zip_code.tsv FIRST, then dictionary00..09.txt (checked
    // against the Bazel output of :filtered_dictionary).
    let zipCode = out("zip_code.tsv")
    try FileUtil.setContents(zipCode, try zipCodeTsv())
    let base = [zipCode] + baseDictionaryTexts

    // gen_filtered_dictionary --filter_tsv dictionary_filter.tsv
    //   --dictionary_txts $(locations :base_dictionary_data)
    let filtered = out("dictionary.txt")
    try FileUtil.setContents(filtered, try GenFilteredDictionary.generate(filterTsv: filterTsv, dictionaryTxts: base))

    // gen_aux_dictionary --strict --aux_tsv aux_dictionary.tsv --id_def id.def
    //   --words_tsv $(locations //data/dictionary_manual)
    //   --dictionary_txts $(locations :base_dictionary_data)
    let aux = out("aux_dictionary.txt")
    try FileUtil.setContents(
      aux,
      try GenAuxDictionary.generate(
        auxTsv: auxTsv, wordsTsvs: wordsTsvs, dictionaryTxts: base, idDef: idDef, strict: true))
    return (aux, filtered)
  }
}
