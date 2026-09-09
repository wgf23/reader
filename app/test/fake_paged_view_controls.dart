import 'package:reader_app/engines/paged_view_controls.dart';

/// 测试用分页控件（REQ-007 D4）：记录调用次数，可配置翻页结果。
class FakePagedViewControls implements PagedViewControls {
  FakePagedViewControls({
    this.nextResult = true,
    this.prevResult = true,
    this.pageCountValue = 1,
    this.gotoResult = true,
  });

  bool nextResult;
  bool prevResult;
  int pageCountValue;
  bool gotoResult;

  int nextCalls = 0;
  int prevCalls = 0;
  int pageCountCalls = 0;
  int relayoutCalls = 0;
  int relayoutAfterLoadCalls = 0;
  int? lastGoto;

  @override
  Future<bool> nextPage() async {
    nextCalls++;
    return nextResult;
  }

  @override
  Future<bool> prevPage() async {
    prevCalls++;
    return prevResult;
  }

  @override
  Future<int> pageCount() async {
    pageCountCalls++;
    return pageCountValue;
  }

  @override
  Future<bool> gotoPage(int index) async {
    lastGoto = index;
    return gotoResult;
  }

  @override
  Future<void> relayout() async {
    relayoutCalls++;
  }

  @override
  Future<void> relayoutAfterLoad() async {
    relayoutAfterLoadCalls++;
  }
}
