// Oracle for genmai-ime: converts every query read from stdin (one per line) with
// ImmutableConverter exactly like converter/immutable_converter_main.cc, and writes
//   <out_dir>/lattice/NNNN.tsv : DumpNodes(lattice)
//   <out_dir>/segments.tsv     : per query, "#\tNNNN\tquery", then per segment
//                                "S\tkey\tcandidates_size" and the top N candidates
//                                "C\tvalue\tkey\tcontent_key\tcontent_value\tcost\twcost\tstructure_cost\tlid\trid\tattributes"
#include <cstdio>
#include <iostream>
#include <memory>
#include <string>
#include <utility>

#include "absl/flags/flag.h"
#include "absl/status/statusor.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/str_format.h"
#include "base/file_stream.h"
#include "base/init_mozc.h"
#include "converter/candidate.h"
#include "converter/debug_util.h"
#include "converter/immutable_converter.h"
#include "converter/lattice.h"
#include "converter/segments.h"
#include "data_manager/data_manager.h"
#include "data_manager/oss/oss_data_manager.h"
#include "engine/modules.h"
#include "request/conversion_request.h"

ABSL_FLAG(std::string, out_dir, "", "Output directory");
ABSL_FLAG(int32_t, top_n, 5, "Candidates per segment");

namespace mozc {
namespace {

int RunMain(int argc, char** argv) {
  InitGenmai(argv[0], &argc, &argv);
  auto modules_or =
      engine::Modules::Create(std::make_unique<const oss::OssDataManager>());
  if (!modules_or.ok()) return 1;
  std::unique_ptr<engine::Modules> modules = std::move(modules_or.value());
  ImmutableConverter immutable_converter(*modules);
  const std::string out_dir = absl::GetFlag(FLAGS_out_dir);
  const int top_n = absl::GetFlag(FLAGS_top_n);
  OutputFileStream seg_os(absl::StrCat(out_dir, "/segments.tsv"));
  std::string query;
  int index = 0;
  while (std::getline(std::cin, query)) {
    ++index;
    const std::string id = absl::StrFormat("%04d", index);
    ConversionRequest::Options options = {
        .request_type = ConversionRequest::CONVERSION,
        .use_actual_converter_for_realtime_conversion = true,
        .create_partial_candidates = false,
    };
    const ConversionRequest conversion_request =
        ConversionRequestBuilder()
            .SetOptions(std::move(options))
            .SetKey(query)
            .Build();
    Segments segments;
    Lattice lattice;
    segments.InitForConvert(conversion_request.key());
    const bool ok = immutable_converter.Convert(conversion_request.options(),
                                                &segments, &lattice);
    {
      OutputFileStream os(absl::StrCat(out_dir, "/lattice/", id, ".tsv"));
      if (ok) os << converter::DumpNodes(lattice);
    }
    seg_os << "#\t" << id << "\t" << query << "\t" << (ok ? 1 : 0) << "\n";
    if (!ok) continue;
    for (const Segment& segment : segments.conversion_segments()) {
      seg_os << "S\t" << segment.key() << "\t" << segment.candidates_size()
             << "\n";
      for (int i = 0; i < segment.candidates_size() && i < top_n; ++i) {
        const converter::Candidate& c = segment.candidate(i);
        seg_os << "C\t" << c.value << "\t" << c.key << "\t" << c.content_key
               << "\t" << c.content_value << "\t" << c.cost << "\t" << c.wcost
               << "\t" << c.structure_cost << "\t" << c.lid << "\t" << c.rid
               << "\t" << c.attributes << "\n";
      }
    }
  }
  return 0;
}

}  // namespace
}  // namespace mozc

int main(int argc, char** argv) { return mozc::RunMain(argc, argv); }
