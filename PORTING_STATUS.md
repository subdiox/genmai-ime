# Porting status

Status: `-` not started, `P` ported, `T` C++ tests ported and passing (or Swift tests for code without C++ tests), `V` parity-verified against the oracle, `n/a` not applicable to the Swift architecture (Qt/Windows/IPC-only).

Total runtime C++ lines in scope (incl. headers/comments): 119435

330 rows: 9 V (parity-verified), 233 T (tests ported / passing), 40 P (ported, no dedicated test), 48 n/a (not applicable on macOS / build-time tools / IPC), 0 missing. Every runtime .cc/.h/.mm of Vendor/mozc/src outside third_party, android, ios, win32, unix, build_tools and testing is listed (audited 2026-10-20).

## GenmaiBase

| file | lines | status |
|---|---|---|
| base/android_util | 230 | n/a (Android) |
| base/bits | 295 | T |
| base/clock | 163 | T |
| base/codegen_bytearray_stream | 325 | n/a (build-time code generator for gen_* tools; data is read from genmai.data) |
| base/config_file_stream | 368 | T |
| base/const | 153 | P (GenmaiBase/Const.swift: `GenmaiConst` with the macOS + common constants, OSS branding; Windows/Linux constants n/a) |
| base/coordinates | 90 | T (GenmaiRenderer/Coordinates) |
| base/cpu_stats | 296 | T |
| base/date_util | 283 | T |
| base/embedded_file | 77 | n/a (C++ embeds the data set in the binary; Swift memory-maps genmai.data — OssDataManager / MockDataManager / PosListProvider read files) |
| base/encryptor | 567 | T |
| base/environ | 126 | P |
| base/file_stream | 150 | P |
| base/file_util | 892 | T |
| base/hash | 226 | T |
| base/init_mozc | 159 | n/a (absl flag parsing / log init of C++ mains; genmai-engine has its own FlagParser) |
| base/japanese_util | 58 | T |
| base/log_file | 117 | n/a (absl log sink; logging goes to os.Logger via GenmaiBase/GenmaiLog.swift) |
| base/mmap | 508 | T |
| base/multifile | 151 | T |
| base/number_util | 1121 | T |
| base/password_manager | 410 | T |
| base/port | 175 | n/a (C++ platform macros) |
| base/process | 503 | T (GenmaiBase/Process.swift `GenmaiProcess`: OpenBrowser, SpawnProcess (posix_spawn / .app via NSWorkspace), SpawnGenmaiProcess, WaitProcess, IsProcessAlive, IsThreadAlive, LaunchErrorMessageDialog; Win32/Linux branches n/a; Swift tests, no C++ test) |
| base/process_mutex | 380 | T |
| base/protobuf_util | 159 | P (its only runtime user, renderer_style_handler, sanitizes the RendererStyle string fields explicitly in GenmaiRenderer/RendererStyleHandler.swift; swift-protobuf has no reflection API for the generic version) |
| base/random | 149 | T |
| base/run_level | 430 | P |
| base/stopwatch | 147 | T |
| base/system_util | 827 | T |
| base/text_normalizer | 345 | T |
| base/thread | 410 | n/a (mozc::Thread / BackgroundFuture / AtomicSharedPtr → Swift concurrency, Mutex / OSAllocatedUnfairLock, Foundation Thread where the C++ uses a thread) |
| base/unverified_aes256 | 414 | T |
| base/unverified_sha1 | 308 | T |
| base/update_util | 114 | n/a (Windows Omaha registry) |
| base/url | 163 | T (GenmaiBase/Url.swift; url_test ported) |
| base/util | 1419 | T |
| base/version | 163 | T |
| base/version_def_template | 49 | P |
| base/clock_mock | 146 | T (GenmaiBase/ClockMock.swift) |
| base/environ_mock | 62 | T (inside GenmaiBase/Environ.swift) |
| base/file_util_mock | 192 | T (GenmaiBase/FileUtilMock.swift) |
| base/vlog | 112 | n/a (MOZC_VLOG → GenmaiLog) |
| base/mac/mac_util | 456 | T (GenmaiBase/Mac/MacUtil.swift: directories, OS version, serial number; GetFrontmostWindowNameAndOwner / IsSuppressSuggestionWindow in GenmaiMac/MacWindowUtil.swift; StartLaunchdService and the prelauncher login-item functions n/a: no launchd converter/renderer services, no prelauncher in the in-process architecture) |
| base/mac/mac_process | 182 | T (GenmaiBase/Mac/MacProcess.swift: OpenBrowserForMac, OpenApplication, LaunchGenmaiTool / LaunchErrorMessageDialog open the tool app (GenmaiTool, installed as Genmai.app in Genmai.app/Contents/Resources) with --mode / --error_type; the IME uses GenmaiMac/MacToolLauncher with the same convention) |
| base/mac/scoped_cftyperef | 74 | n/a (CF types are ARC-managed in Swift) |
| base/port/reversed_view, varint (+ _internal) | 277 | n/a (no runtime user in 3.35.6354; C++ template helpers) |
| base/protobuf/* (coded_stream, descriptor, message, text_format, ...) | - | n/a (protobuf aliases; swift-protobuf in GenmaiProtocol) |
| base/win32/* | - | n/a (Windows) |
| base/strings/assign | 80 | n/a (C++ string assignment helpers) |
| base/strings/japanese | 204 | T |
| base/strings/pfchar | 125 | n/a (platform file-name char type; Swift String everywhere) |
| base/strings/strip | 120 | T |
| base/strings/unicode | 695 | T |
| base/strings/internal/double_array | 192 | T (GenmaiBase/Strings/Internal/DoubleArray.swift) |
| base/strings/internal/japanese_rules | 2010 | T (GenmaiBase/Strings/Internal/JapaneseRules.swift, generated tables) |
| base/strings/internal/japanese_rules_compiler | 158 | n/a (build-time generator of japanese_rules) |
| base/strings/internal/utf8_internal | 370 | T (GenmaiBase/Strings/Internal/Utf8Internal.swift; Utf8InternalTests) |
| base/container/arena | 154 | n/a (memory arena; nodes / candidates are ARC objects, NodeAllocator keeps the C++ node-count limit) |
| base/container/bitarray | 97 | T |
| base/container/flat_concurrent_cache | 250 | T (located in GenmaiCore/Prediction/FlatConcurrentCache.swift, its only users being the user-history / realtime-decoder caches; tests in Tests/GenmaiCoreTests/Prediction/FlatConcurrentCacheTests.swift) |
| base/container/flat_internal | 92 | T |
| base/container/flat_map | 97 | T |
| base/container/flat_multimap | 102 | T |
| base/container/flat_set | 88 | T |
| base/container/serialized_string_array | 455 | T |
| base/container/trie | 236 | T |
| base/container/tuple | 116 | n/a (C++ template metaprogramming for modules / rewriter wiring) |
| base/file/recursive | 244 | T |
| base/file/temp_dir | 373 | T |

## GenmaiStorage

| file | lines | status |
|---|---|---|
| storage/encrypted_string_storage | 269 | T |
| storage/existence_filter | 509 | T |
| storage/lru_cache | 428 | T |
| storage/lru_storage | 751 | T |
| storage/louds/bit_stream | 155 | T |
| storage/louds/bit_vector_based_array | 154 | T |
| storage/louds/bit_vector_based_array_builder | 201 | T |
| storage/louds/louds | 269 | T |
| storage/louds/louds_trie | 356 | T |
| storage/louds/louds_trie_builder | 298 | T |
| storage/louds/simple_succinct_bit_vector_index | 426 | T |

## GenmaiCore/DataManager

| file | lines | status |
|---|---|---|
| data_manager/connection_file_reader | 145 | T |
| data_manager/data_manager | 827 | T |
| data_manager/data_manager_test_base | 372 | T (all checks incl. SegmenterTest_SameAsInternal: IsBoundaryInternal evaluated from id.def / special_pos.def / segmenter.def like gen_segmenter_code.py (Tests/.../DataManager/SegmenterInternal.swift); run for OSS and mock data) |
| data_manager/dataset_reader | 263 | T |
| data_manager/dataset_writer | 173 | T |
| data_manager/emoji_data | 108 | T |
| data_manager/pos_list_provider | 127 | T |
| data_manager/serialized_dictionary | 561 | T |
| data_manager/oss/oss_data_manager | 110 | T |
| data_manager/testing/mock_data_manager | 112 | T |

## GenmaiCore/Config

| file | lines | status |
|---|---|---|
| config/character_form_manager | 1032 | T |
| config/config_handler | 451 | T |

## GenmaiCore/Dictionary

| file | lines | status |
|---|---|---|
| dictionary/dictionary_impl | 384 | T |
| dictionary/dictionary_interface | 312 | T |
| dictionary/dictionary_token | 76 | T |
| dictionary/pos_group | 63 | T |
| dictionary/pos_id_map | 140 | T |
| dictionary/pos_matcher | 125 | T |
| dictionary/pos_pattern_matcher | 283 | T |
| dictionary/single_kanji_dictionary | 301 | T |
| dictionary/suffix_dictionary | 222 | T |
| dictionary/text_dictionary_loader | 440 | T |
| dictionary/user_dictionary | 869 | T |
| dictionary/user_dictionary_util | 338 | T |
| dictionary/user_pos | 407 | T |
| dictionary/dictionary_mock | 142 | T (test target: Tests/GenmaiCoreTests/Dictionary/DictionaryMock.swift) |
| dictionary/dictionary_test_util | 324 | T (test target: DictionaryTestUtil.swift) |
| dictionary/user_dictionary_stub | 73 | T (Dictionary/UserDictionaryStub.swift) |
| dictionary/system/codec | 878 | T |
| dictionary/system/key_expansion_table | 105 | T |
| dictionary/system/system_dictionary | 1295 | T |
| dictionary/system/system_dictionary_builder | 588 | T |
| dictionary/system/token_decode_iterator | 195 | T |
| dictionary/system/value_dictionary | 242 | T |
| dictionary/system/words_info | 106 | T |
| dictionary/file/codec | 289 | T |
| dictionary/file/dictionary_file | 157 | T |
| dictionary/file/dictionary_file_builder | 154 | T |
| dictionary/file/section | 49 | T |

## GenmaiCore/Composer (+ Transliteration)

| file | lines | status |
|---|---|---|
| composer/char_chunk | 866 | T |
| composer/composer | 1850 | T |
| composer/composition | 695 | T |
| composer/composition_input | 204 | T |
| composer/key_event_util | 452 | T |
| composer/key_parser | 324 | T |
| composer/mode_switching_handler | 145 | T |
| composer/query | 68 | P |
| composer/special_key | 254 | T |
| composer/table | 808 | T |
| composer/transliterators | 431 | T |
| transliteration/transliteration | 190 | T |

## GenmaiCore/Converter

| file | lines | status |
|---|---|---|
| converter/attribute | 140 | P (no C++ test) |
| converter/caching_connector | 164 | T |
| converter/candidate | 333 | T |
| converter/candidate_filter | 784 | T |
| converter/connector | 497 | T |
| converter/converter | 1348 | V (tests needing the real engine ported in Engine/ConverterEngineTests.swift; parity via converter_main) |
| converter/converter_interface | 171 | P |
| converter/converter_main | 676 | V (genmai-engine CLI + Engine/ConverterMain.swift; Tools/compare_oracle.sh and ConverterMainParityTests: identical output except debug `log:` lines) |
| converter/converter_util | 605 | T |
| converter/debug_util | 194 | T |
| converter/gen_segmenter_bitarray | 292 | n/a (build-time generator; the segmenter bit array is read from genmai.data) |
| converter/history_reconstructor | 228 | T |
| converter/immutable_converter | 2002 | V (lattice dump + segments/top-5 identical for 734 inputs) |
| converter/immutable_converter_interface | 53 | P |
| converter/inner_segment | 513 | T |
| converter/key_corrector | 690 | T |
| converter/lattice | 309 | T |
| converter/nbest_generator | 1002 | T |
| converter/node | 148 | P (no C++ test; covered by lattice/nbest tests) |
| converter/node_allocator | 61 | P (no C++ test; covered by lattice tests) |
| converter/node_list_builder | 147 | P (no C++ test; used by immutable_converter) |
| converter/pos_id_printer | 134 | T |
| converter/quality_regression_test_lib | 223 | T (QualityRegressionTestLib.swift: RunTestForPlatform / ExamineResults return the EXPECT failures and LOG lines; loadTestData mirrors gen_quality_regression_test_data.py; QualityRegressionTests) |
| converter/quality_regression_main | 132 | V (Engine/QualityRegressionMain.swift; QualityRegressionTests: data/dictionary_oss/evaluation.tsv 680/680 cases identical (status, input, actual output, command, argument; 482 OK / 198 FAILED, same as the C++ binary); mobile 680/680 vs C++ --engine_type=mobile; myoji.tsv 50,612/50,612 vs C++ (opt-in MOZC_QUALITY_REGRESSION_MYOJI=1, 215 s debug)) |
| converter/converter_mock | 108 | T (test target: Tests/GenmaiCoreTests/Converter/ConverterMock.swift) |
| converter/quality_regression_util | 538 | T |
| converter/reverse_converter | 201 | T |
| converter/segmenter | 168 | T (DataManagerTestBase segmenter checks) |
| converter/segments | 1086 | T |
| converter/segments_matchers | 253 | T (test target) |

## GenmaiCore/Rewriter

| file | lines | status |
|---|---|---|
| rewriter/a11y_description_rewriter | 338 | T |
| rewriter/calculator_rewriter | 298 | T (incl. rewriter/calculator/calculator: recursive-descent parser, testset.txt) |
| rewriter/collocation_rewriter | 801 | T |
| rewriter/collocation_util | 157 | T |
| rewriter/command_rewriter | 262 | T |
| rewriter/correction_rewriter | 380 | T |
| rewriter/date_rewriter | 1942 | T (injectable clock via withScopedClockMock) |
| rewriter/dice_rewriter | 172 | T |
| rewriter/dictionary_generator | 232 | n/a (build-time tool for gen_symbol_rewriter_dictionary_main; not used at runtime) |
| rewriter/emoji_rewriter | 368 | T |
| rewriter/emoticon_rewriter | 284 | T (stable sort by cost; libc++ std::sort tie order may differ for かおもじ/かお) |
| rewriter/english_variants_rewriter | 350 | T |
| rewriter/environmental_filter_rewriter | 641 | T |
| rewriter/focus_candidate_rewriter | 496 | T |
| rewriter/fortune_rewriter | 264 | T |
| rewriter/gen_emoticon_rewriter_data | 140 | n/a (build-time generator) |
| rewriter/gen_existence_data | 139 | n/a (build-time generator) |
| rewriter/gen_single_kanji_noun_prefix_data | 107 | n/a (build-time generator) |
| rewriter/ivs_variants_rewriter | 237 | T |
| rewriter/language_aware_rewriter | 315 | T |
| rewriter/merger_rewriter | 189 | T |
| rewriter/number_compound_util | 305 | T |
| rewriter/number_rewriter | 940 | T |
| rewriter/remove_redundant_candidate_rewriter | 116 | T |
| rewriter/rewriter | 252 | T (RewriterImpl; all 31 rewriters wired) |
| rewriter/rewriter_interface | 164 | P |
| rewriter/rewriter_util | 126 | T |
| rewriter/single_kanji_rewriter | 323 | T (test builds PosMatcher/SingleKanjiDictionary from MockDataManager instead of engine::Modules) |
| rewriter/small_letter_rewriter | 362 | T |
| rewriter/symbol_rewriter | 540 | T |
| rewriter/t13n_promotion_rewriter | 249 | T |
| rewriter/transliteration_rewriter | 557 | T |
| rewriter/unicode_rewriter | 287 | T |
| rewriter/usage_rewriter | 370 | T |
| rewriter/user_boundary_history_rewriter | 417 | T |
| rewriter/user_dictionary_rewriter | 137 | T |
| rewriter/user_segment_history_rewriter | 1071 | T |
| rewriter/variants_rewriter | 958 | T |
| rewriter/version_rewriter | 187 | T |
| rewriter/zipcode_rewriter | 213 | T |

## GenmaiCore/Prediction

| file | lines | status |
|---|---|---|
| prediction/decoder_util | 352 | T |
| prediction/dictionary_decoder | 607 | T |
| prediction/dictionary_predictor | 1377 | V (all TEST_F/TEST_P ported; prediction parity: `p` on 200 inputs, desktop + mobile, top-10 value/key/cost/scost/wcost/lid/rid match — PredictionParityTests) |
| prediction/english_decoder | 217 | T |
| prediction/handwriting_decoder | 302 | T |
| prediction/number_decoder | 635 | T |
| prediction/predictor | 490 | V (see dictionary_predictor; engine::Modules subset = PredictionModules & UserHistoryPredictorModules) |
| prediction/predictor_interface | 103 | T |
| prediction/realtime_decoder | 364 | T |
| prediction/result | 495 | T (PredictionResult; debug `log` / MOZC_WORD_LOG omitted) |
| prediction/result_filter | 460 | T |
| prediction/single_kanji_decoder | 208 | T |
| prediction/suggestion_filter | 133 | T (no C++ test; covered by result_filter / dictionary_predictor tests) |
| prediction/user_history_predictor | 3421 | T (all 91 TEST_F ported; engine::Modules / RealtimeDecoder / SupplementalModel abstracted by protocols in UserHistoryPredictor.swift) |
| prediction/user_history_storage | 672 | T (syncer on a Foundation Thread; `.history.db` byte compatible) |
| prediction/zero_query_decoder | 506 | T |
| prediction/zero_query_dict | 146 | T |

## GenmaiCore/Engine (+ Request)

| file | lines | status |
|---|---|---|
| engine/candidate_list | 547 | T (CandidateList.Candidate / CandidateList.Attribute nested to avoid clashing with converter Candidate/Attribute) |
| engine/data_loader | 404 | T (detached Swift task + NSCondition wait instead of a thread; magic_number bytes = Latin-1 scalars of the proto string) |
| engine/engine | 342 | V (all engine_test cases; converter_main parity: conversion 734/734, prediction 200/200 desktop + mobile, 50 scripted sessions 273/273 + 43 mobile 238/238) |
| engine/engine_converter | 2419 | T (all 81 tests of engine_converter_test ported, EngineConverterTests1-3; usage-stats name builder is a no-op; consumed_key_size = inout Int, kConsumedAllCharacters = Int.max) |
| engine/engine_converter_interface | 286 | P (header only; exercised by engine_converter tests) |
| engine/engine_factory | 39 | T (Swift tests) |
| engine/engine_interface | 117 | P (protocol; defaults in extension, Engine implements all) |
| engine/engine_output | 687 | T (namespace output = enum EngineOutput; NDEBUG behavior: CandidateWord.log not filled) |
| engine/eval_engine_factory | 101 | T (Swift tests) |
| engine/minimal_converter | 215 | T (Swift tests; no C++ test) |
| engine/mock_data_engine_factory | 96 | T (Swift tests) |
| engine/modules | 467 | V (conforms to the Converter/Prediction/UserHistoryPredictor/Rewriter modules protocols; modules_test ported; parity via converter_main) |
| engine/oss_engine_factory | 52 | T (Swift tests; reads Data/genmai.data) |
| engine/supplemental_model_interface | 122 | P (refines the partial supplemental model protocols; SupplementalModelStub is the open base class) |
| engine/engine_mock, supplemental_model_mock | 148 | T (test doubles in GenmaiSessionTests/SessionTestFixture.swift, GenmaiCoreTests/Prediction/PredictionTestSupport.swift) |
| engine/engine_converter_stress_test | 115 | T (EngineConverterStressTests.swift) |
| request/conversion_request | 483 | T |
| request/options | 155 | P |
| request/request_util | 70 | P |
| request/request_test_util | 114 | T (Request/RequestTestUtil.swift; request_test_util_test ported) |

## GenmaiCore/UserDictionaryClient (client/user_dictionary)

No UserDictionarySession / user_dictionary_session_handler exists in 3.35.6354 (the session layer
was removed upstream; session/session_handler has no user-dictionary commands), so only storage and
importer are ported. The non-Qt parts of the GUI import path live here too.

| file | lines | status |
|---|---|---|
| client/user_dictionary/user_dictionary_storage | 569 | T |
| client/user_dictionary/user_dictionary_importer | 646 | T |
| dictionary/pos_map.inc (generated by gen_pos_map.py) | - | T (UserDictionaryImporterPosMap.swift) |
| gui/base/encoding_util (+ sjis_to_ucs2_table.h) | 199 | T |
| gui/dictionary_tool/dictionary_tool.cc: UTF16/MultiByteTextLineIterator, CreateTextLineIterator | ~190 | T (DictionaryToolTextLineIterator.swift; UI part not ported) |

## GenmaiSession (+ usage_stats)

| file | lines | status |
|---|---|---|
| session/common | 43 | P (Common.swift) |
| session/ime_context | 288 | T |
| session/key_event_transformer | 287 | T |
| session/key_info_util | 194 | T |
| session/keymap | 1311 | T (all embedded keymaps + custom keymap from config) |
| session/random_keyevents_generator | 442 | T (+ generated RandomKeyEventsGeneratorData.swift) |
| session/session | 3331 | T (session_test 187/187, session_regression_test 11/11) |
| session/session_handler | 841 | T (session_handler_test 21/21) |
| session/session_handler_tool | 1004 | T (scenario runner) |
| session/session_handler_scenario_test | 280 | T (79/79 files, 7259/7259 steps, mock data) |
| session/session_handler_main (oracle) | 266 | V (scenario parity vs C++ session_handler_main: 164/164 file runs, mock + OSS data, identical failing lines; Tests/Fixtures/session/scenario_oracle.tsv) |
| session/session_server | 187 | n/a (IPC server; replaced by the in-process GenmaiClient/SessionHandlerBackend.swift: watch dog (CLEANUP), SYNC_DATA, RELOAD) |
| server/mozc_server | 187 | n/a (server process main / GenmaiConverter.app; replaced by GenmaiClient/SessionHandlerBackend.swift in the IME process) |
| session/session_watch_dog | 331 | T (client abstracted as SessionWatchDogClient) |
| session/session_handler_stress_test | 115 | T (SessionHandlerStressTests.swift: 2500 random key events in 32 shards through SessionHandlerTool + OSS engine; MOZC_STRESS_RANDOM_SEED / MOZC_STRESS_MOBILE=1 for the flags) |
| session/session_client_main | - | n/a (IPC client tool) |
| usage_stats/ | - | n/a (not present in 3.35.6354; OSS disables usage stats; SessionHandlerInterpreter.clearUsageStats is a no-op) |

## IME app (mac/renderer/gui)

| file | lines | status |
|---|---|---|
| mac/KeyCodeMap | 271 | T |
| mac/common | 83 | P |
| mac/main | 132 | T (GenmaiIME/main.swift: engine start-up, `--self_test` / `--help`) |
| mac/mozc_imk_input_controller | 1258 | T |
| mac/Uninstaller/{Uninstaller,DialogsController,Uninstaller_main} | 380 | T (GenmaiUninstaller: SwiftUI app, one window instead of the Dialogs.xib dialogs (confirm with the items to remove → progress → restart now / later, or the error with Try Again), Genmai's own strings (en/ja); removes /Library/Input Methods/Genmai.app (which contains the uninstaller), /Applications/Genmai of 0.1.0 installs, the user data kinds the user checks, and a manual install of this bundle id via `/bin/rm -rf` run by AppleScript `do shell script ... with administrator privileges` (AuthorizationExecuteWithPrivileges is deprecated); restart via loginwindow instead of /sbin/reboot; the uninstall survey (Google build only) is not ported; LaunchAgents / prelauncher n/a. Bundle: Tools/make_uninstaller_bundle.sh. GenmaiUninstallerTests run the deletion unprivileged against a temp dir) |
| mac/installer (pkg, preflight / postflight, LaunchAgents) + mac/build_package.py | - | P (Tools/make_installer_pkg.sh: pkgbuild + productbuild with Tools/installer/{distribution.xml, preflight / postflight templates}; installs /Library/Input Methods/Genmai.app (the uninstaller is inside it; nothing in /Applications); postinstall kills GenmaiIME and runs `--register_input_source`; BundleOverwriteAction "" as upstream, plus BundleIsRelocatable false; pkg unsigned unless PKG_SIGN_IDENTITY (bundles ad-hoc signed). LaunchAgents for converter / renderer are n/a in-process. Verified with pkgutil --expand / --payload-files, not installed) |
| mac/renderer_receiver | 134 | T |
| renderer/init_mozc_renderer | 94 | n/a (in-process renderer) |
| renderer/renderer_client | 683 | n/a (in-process renderer) |
| renderer/renderer_interface | 67 | P |
| renderer/renderer_server | 339 | n/a (in-process renderer) |
| renderer/renderer_style_handler | 142 | T |
| renderer/table_layout | 577 | T |
| renderer/table_layout_interface | 70 | P |
| renderer/renderer_mock | 53 | T (test target: GenmaiMacTests/Mocks.swift) |
| renderer/table_layout_mock | 69 | n/a (only used by the Win32 renderer tests) |
| renderer/qt/*, renderer/win32/* | - | n/a (Linux Qt / Windows renderers) |
| renderer/window_util | 337 | T |
| renderer/mac/CandidateController | 356 | T (helpers) |
| renderer/mac/CandidateView | 580 | T (SwiftUI; own design by choice: rounded translucent panel, system colors, AI badge, no footer logo; TableLayout geometry and mouse handling kept) |
| renderer/mac/CandidateWindow | 160 | P (transparent panel with window shadow) |
| renderer/mac/InfolistView | 259 | T (SwiftUI) |
| renderer/mac/InfolistWindow | 225 | P |
| renderer/mac/RendererBaseWindow | 198 | P |
| renderer/mac/mac_server | 190 | n/a (in-process renderer) |
| renderer/mac/mac_server_send_command | 103 | n/a (in-process renderer) |
| renderer/mac/mac_view_util | 171 | P |
| gui/config_dialog/character_form_editor | 254 | T (SwiftUI) |
| gui/config_dialog/combobox_delegate | 161 | P (SwiftUI Picker) |
| gui/config_dialog/config_dialog | 928 | T (SwiftUI) |
| gui/config_dialog/config_dialog_libmain | 63 | P (GenmaiTool) |
| gui/config_dialog/generic_table_editor | 433 | T (SwiftUI) |
| gui/config_dialog/keybinding_editor | 629 | T (SwiftUI) |
| gui/config_dialog/keybinding_editor_delegate | 189 | P (SwiftUI) |
| gui/config_dialog/keymap_editor | 618 | T (SwiftUI; command names from GenmaiSession KeyMapManager) |
| gui/config_dialog/roman_table_editor | 359 | T (SwiftUI) |
| gui/dictionary_tool/dictionary_content_table_widget | 158 | P (SwiftUI Table) |
| gui/dictionary_tool/dictionary_tool | 1836 | T (SwiftUI) |
| gui/dictionary_tool/dictionary_tool_libmain | 74 | P (GenmaiTool) |
| gui/dictionary_tool/find_dialog | 223 | T (SwiftUI) |
| gui/dictionary_tool/import_dialog | 277 | T (SwiftUI) |
| gui/dictionary_tool/zero_width_splitter | 111 | n/a (HSplitView) |
| gui/word_register_dialog/word_register_dialog | 590 | T (SwiftUI; GetReading uses real reverse conversion through GenmaiClient/ToolSessionBackend, as in C++) |
| gui/word_register_dialog/word_register_dialog_libmain | 65 | P (GenmaiTool) |
| gui/about_dialog/about_dialog | 225 | T (SwiftUI) |
| gui/about_dialog/about_dialog_libmain | 60 | P (GenmaiTool) |
| gui/base/debug_util | 119 | n/a (Qt) |
| gui/base/encoding_util | 199 | T (GenmaiCore/UserDictionaryClient) |
| gui/base/msime_user_dictionary_importer | 307 | n/a (Windows) |
| gui/base/setup_util | 237 | n/a (Windows) |
| gui/base/singleton_window_helper | 237 | P (GenmaiTool) |
| gui/base/sjis_to_ucs2_table | 11319 | T (GenmaiCore/UserDictionaryClient) |
| gui/base/stats_config_util | 298 | n/a (OSS: usage stats off) |
| gui/base/table_util | 106 | n/a (Qt) |
| gui/base/util | 244 | P (Base/Localization) |
| gui/base/win_util | 405 | n/a (Windows) |
| gui/base/window_title_modifier | 113 | n/a (Qt) |
| gui/error_message_dialog/error_message_dialog | 209 | T (SwiftUI) |
| gui/error_message_dialog/error_message_dialog_libmain | 60 | P (GenmaiTool `--mode=error_message_dialog --error_type=...`) |
| gui/administration_dialog/* | 271 | n/a (Windows only) |
| gui/post_install_dialog/* | 253 | n/a (Windows only, see mozc_tool_libmain) |
| gui/tool/prelauncher_libmain | 69 | n/a (macOS login-item prelauncher that starts the converter / renderer servers early; nothing to pre-launch in-process. The config dialog's startup checkbox is a no-op in the OSS-build platform hooks) |
| gui/tool/mozc_tool_main_noqt | 34 | n/a (non-Qt stub) |
| gui/tool/mozc_tool_libmain | 207 | P (GenmaiTool) |
| client/client_interface | 225 | P (GenmaiClient) |
| client/client | 1215 | T (GenmaiClient/InProcessClient; direct-mode key check via KeyInfoUtil, DELETE_SESSION on deinit; IPC parts n/a) |
| client/client_mock | 98 | T (test target: GenmaiMacTests/Mocks.swift) |
| ipc/* (ipc, ipc_path_manager, mach_ipc, named_event, process_watch_dog, unix_ipc, win32_ipc, ipc_mock) | 4097 | n/a (no IPC: converter, renderer and tool talk in-process / via the config file + distributed notifications) |
| client/server_launcher | 261 | n/a (in-process) |

The IME app layer runs the converter and the renderer in the IME process: `GenmaiClient.InProcessClient` builds the
same `commands::Input` messages as client/client.cc and hands them to `SessionHandlerBackend`, which owns the
Engine (OSS data set) and GenmaiSession's SessionHandler (`FakeSessionBackend` is kept for UI tests only). GenmaiTool
talks to the IME through the config file and a distributed "reload" notification instead of IPC. The IME keeps its
user profile (learning data, user dictionary, settings) in `~/Library/Application Support/Genmai`, separate from an
installed C++ Mozc.

## Evaluation sets (data/)

| set | status |
|---|---|
| data/dictionary_oss/evaluation.tsv (quality_regression_test/oss.tsv + regression.tsv, OSS data, desktop) | V: 680/680 cases identical to evaluation.tsv and to the C++ quality_regression_main (482 OK / 198 FAILED in both) — QualityRegressionTests |
| same, `--engine_type=mobile` | V: 680/680 vs C++ (Tests/Fixtures/quality_regression/evaluation_mobile_oracle.tsv) |
| data/test/quality_regression_test/myoji.tsv (50,612 prediction cases) | V: 50,612/50,612 vs C++ (41,201 OK / 9,411 FAILED; opt-in `MOZC_QUALITY_REGRESSION_MYOJI=1`, ~215 s in a debug build) |
| data/test/session/scenario | V (see session_handler_main) |
| data/test/calculator/testset.txt | T (CalculatorTests) |
| data/test/stress_test | T (SessionHandlerStressTests; sentences.txt feeds RandomKeyEventsGenerator) |

## Data generation (build tools)

`genmai-datagen` (target GenmaiDataGen, `Sources/GenmaiDataGen/<mozc dir>/`) replaces the Bazel/Python/C++ data set
build: `Tools/build_data.sh` writes `Data/genmai.data` and `Data/mock_genmai.data` (byte-identical to
`//data_manager/oss:mozc_dataset_for_oss` / `//data_manager/testing:mozc_dataset_for_testing`; OSS ~29 s and
~1.8 GB peak in a release build, mock ~0.6 s). External inputs: `@ja_usage_dict` is committed under
`Data/sources/japanese-usage-dictionary/`; the zip code CSVs are downloaded (pinned, sha256-checked) into
`Data/external/`. `genmai-datagen sections|diff` compare section by section. Fix to an existing writer:
`ExistenceFilterBuilder.createOptimal` truncates the hash count like the C++ cast (it trapped for tiny inputs
such as the mock suggestion filter). These rows are not included in the summary counts below.

| Mozc source | Swift | status |
|---|---|---|
| data_manager/mozc_data.bzl (`mozc_dataset` macro), oss/BUILD.bazel, testing/BUILD.bazel | GenmaiDataSet.swift, DataGenSources.swift | V: whole `mock_genmai.data` and `genmai.data` byte-identical (GenmaiDataSetTests; OSS opt-in `MOZC_DATAGEN_OSS=1`) |
| data_manager/dataset_writer_main.cc | GenmaiDataSet.write (DataSetWriter) | V |
| dictionary/pos_util.py | Dictionary/PosUtil.swift | V |
| dictionary/gen_user_pos_data.py | Dictionary/GenUserPosData.swift | V (sections byte-identical, mock + OSS); pos_list.data identical too |
| dictionary/gen_pos_matcher_code.py | Dictionary/GenPosMatcherCode.swift | V (sections byte-identical, mock + OSS) |
| dictionary/gen_pos_id_map.py | Dictionary/GenPosIdMap.swift | V (sections byte-identical, mock + OSS) |
| dictionary/gen_pos_rewrite_rule.py | Dictionary/GenPosRewriteRule.swift | V (sections byte-identical, mock + OSS) |
| converter/gen_boundary_data.py | Converter/GenBoundaryData.swift | V (sections byte-identical, mock + OSS) |
| converter/gen_segmenter_code.py | Converter/GenSegmenterCode.swift | V (sections byte-identical, mock + OSS); evaluates the rules directly instead of emitting C++ |
| converter/gen_segmenter_bitarray.{h,cc} | Converter/GenSegmenterBitarray.swift | V (sections byte-identical, mock + OSS) |
| data_manager/{oss,testing}/gen_*_segmenter_bitarray_main.cc | DataManager/GenSegmenterBitarrayMain.swift | V (sections byte-identical, mock + OSS) |
| data_manager/gen_connection_data.py | DataManager/GenConnectionData.swift | V (sections byte-identical, mock + OSS) |
| data_manager/gen_data_version.py | DataManager/GenDataVersion.swift | V (sections byte-identical, mock + OSS) |
| dictionary/gen_system_dictionary_data_main.cc | Dictionary/GenSystemDictionaryDataMain.swift | V (sections byte-identical, mock + OSS) (reuses TextDictionaryLoader / SystemDictionaryBuilder unchanged) |
| dictionary/gen_suffix_data.py | Dictionary/GenSuffixData.swift | V (sections byte-identical, mock + OSS) |
| dictionary/gen_zip_code_seed.py, zip_code_util.py | Dictionary/GenZipCodeSeed.swift, ZipCodeUtil.swift | V (zip_code.tsv identical; cp932 decoding) |
| dictionary/gen_filtered_dictionary.py | Dictionary/GenFilteredDictionary.swift | V (data/dictionary_oss dictionary.txt identical) |
| dictionary/gen_aux_dictionary.py | Dictionary/GenAuxDictionary.swift | V (aux_dictionary.txt identical) |
| data/dictionary_oss/BUILD.bazel, dictionary/BUILD.bazel `zip_code_data` | Dictionary/OssDictionaryRules.swift | V (Bazel passes zip_code.tsv before dictionary00..09) |
| rewriter/gen_collocation_data_main.cc, gen_collocation_suppression_data_main.cc, gen_existence_data.{h,cc} | Rewriter/GenCollocation*.swift, GenExistenceData.swift | V (sections byte-identical, mock + OSS) |
| prediction/gen_suggestion_filter_main.cc | Prediction/GenSuggestionFilterMain.swift | V (sections byte-identical, mock + OSS) |
| rewriter/gen_counter_suffix_array.py | Rewriter/GenCounterSuffixArray.swift | V (sections byte-identical, mock + OSS) |
| rewriter/gen_reading_correction_data.py | Rewriter/GenReadingCorrectionData.swift | V (sections byte-identical, mock + OSS) |
| rewriter/gen_symbol_rewriter_dictionary_main.cc, dictionary_generator.{h,cc} | Rewriter/GenSymbolRewriterDictionaryMain(+JisX0208).swift, DictionaryGenerator.swift | V (sections byte-identical, mock + OSS) |
| rewriter/gen_emoticon_rewriter_data.cc | Rewriter/GenEmoticonRewriterData.swift | V (sections byte-identical, mock + OSS) |
| rewriter/gen_emoji_rewriter_data.py | Rewriter/GenEmojiRewriterData.swift | V (sections byte-identical, mock + OSS) |
| rewriter/gen_single_kanji_rewriter_data.py | Rewriter/GenSingleKanjiRewriterData.swift | V (sections byte-identical, mock + OSS) |
| rewriter/gen_single_kanji_noun_prefix_data.cc | Rewriter/GenSingleKanjiNounPrefixData.swift | V (sections byte-identical, mock + OSS) |
| rewriter/gen_a11y_description_rewriter_data.py | Rewriter/GenA11yDescriptionRewriterData.swift | V (sections byte-identical, mock + OSS) |
| rewriter/gen_usage_rewriter_dictionary_main.cc | Rewriter/GenUsageRewriterDictionaryMain.swift | V (sections byte-identical, mock + OSS) |
| prediction/gen_zero_query_util.py, gen_zero_query_data.py | Prediction/GenZeroQueryUtil.swift, GenZeroQueryData.swift | V (sections byte-identical, mock + OSS); the side output zero_query_data.tsv is not generated (its line order depends on Python's hash seed) |
| prediction/gen_zero_query_number_data.py | Prediction/GenZeroQueryNumberData.swift | V (sections byte-identical, mock + OSS) |
| build_tools/code_generator_util.py, serialized_string_array_builder.py | Support/PyCompat.swift, CodeGeneratorUtil.swift (+ SerializedStringArray.serializeToBuffer) | V (Python str/split/strip/splitlines/dict-order semantics) |

## Known gaps

- base/protobuf_util's generic reflection-based sanitizer is specialized to RendererStyle (its only user).

Summary: 330 rows: 9 V (parity-verified), 233 T (tests ported / passing), 40 P (ported, no dedicated test), 48 n/a (not applicable on macOS / build-time tools / IPC), 0 missing. Every runtime .cc/.h/.mm of Vendor/mozc/src outside third_party, android, ios, win32, unix, build_tools and testing is listed (audited 2026-10-20).
