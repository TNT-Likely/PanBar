import XCTest
@testable import PanBar

/// SymbolSearch.parse 的解析 / 过滤测试。
///
/// fixture 取自腾讯 smartbox(`smartbox.gtimg.cn/s3`)的真实响应结构
/// (`market~code~name~pinyin~type`,多条用 `^` 分隔)。为可读性,名称这里直接
/// 写中文;smartbox 实际返回的是 `\uXXXX` 转义,`parse()` 会解码 ——
/// 该解码路径由 `testDecodesUnicodeEscapedNames()` 用真实转义序列单独覆盖。
///
/// 这些用例锁定「每个市场 / 板块都能被搜索到」,并守住科创板回归
/// (688xxx 的 type=GP-A-KCB 曾被精确白名单漏掉)。
final class SymbolSearchTests: XCTestCase {
    private let search = SymbolSearch()

    private struct MarketCase {
        let label: String        // 用例说明(失败时打印)
        let raw: String          // 原始响应(真实抓取)
        let market: Market       // 期望市场
        let code: String         // 期望代码
        let displayName: String  // 期望名称(\uXXXX 解码后)
    }

    /// 每个市场 / 板块至少一条真实响应。
    private let marketCases: [MarketCase] = [
        MarketCase(
            label: "沪市主板",
            raw: #"v_hint="sh~600519~贵州茅台~gzmt~GP-A";"#,
            market: .a, code: "600519", displayName: "贵州茅台"
        ),
        MarketCase(
            label: "深市主板",
            raw: #"v_hint="sh~000002~A股指数~agzs~ZS^sz~000002~万科A~wka~GP-A";"#,
            market: .a, code: "000002", displayName: "万科A"
        ),
        MarketCase(
            label: "创业板",
            raw: #"v_hint="sz~300750~宁德时代~ndsd~GP-A";"#,
            market: .a, code: "300750", displayName: "宁德时代"
        ),
        MarketCase(
            label: "科创板(回归:GP-A-KCB)",
            raw: #"v_hint="sh~688256~寒武纪~hwj~GP-A-KCB";"#,
            market: .a, code: "688256", displayName: "寒武纪"
        ),
        MarketCase(
            label: "港股",
            raw: #"v_hint="hk~00700~腾讯控股~txkg~GP";"#,
            market: .hk, code: "00700", displayName: "腾讯控股"
        ),
        MarketCase(
            label: "美股",
            raw: #"v_hint="us~aapl.oq~苹果~pg~GP";"#,
            market: .us, code: "AAPL", displayName: "苹果"
        ),
        MarketCase(
            label: "场内基金 / ETF",
            raw: #"v_hint="sh~510300~沪深300ETF华泰柏瑞~hs300etfhtbr~ETF";"#,
            market: .a, code: "510300", displayName: "沪深300ETF华泰柏瑞"
        ),
    ]

    /// 核心:每个市场 / 板块都能解析出预期标的(代码 + 市场 + 名称)。
    func testEveryMarketIsSearchable() {
        for c in marketCases {
            let results = search.parse(c.raw)
            guard let hit = results.first(where: { $0.symbol.code == c.code && $0.symbol.market == c.market }) else {
                XCTFail("[\(c.label)] 期望解析出 \(c.market.rawValue):\(c.code),实际:\(results.map(\.symbol.description))")
                continue
            }
            XCTAssertEqual(hit.name, c.displayName, "[\(c.label)] 名称解码不符")
        }
    }

    /// 回归用例:科创板 type=GP-A-KCB。
    /// 此前白名单写死 {GP, GP-A, GP-B, ...} 精确匹配,漏掉 GP-A-KCB,
    /// 导致寒武纪(688256)及整个科创板搜不到。
    func testStarMarketStockIsSearchable() {
        let results = search.parse(#"v_hint="sh~688256~寒武纪~hwj~GP-A-KCB";"#)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.symbol.market, .a)
        XCTAssertEqual(results.first?.symbol.code, "688256")
        XCTAssertEqual(results.first?.name, "寒武纪")
    }

    /// 非可交易品种应被过滤:同一查询里混入指数(ZS)与场外基金(KJ),
    /// 只保留可交易的股票。fixture 是 "000001" 的真实响应。
    func testFiltersIndicesAndOTCFunds() {
        let raw = #"v_hint="sh~000001~上证指数~szzs~ZS^sz~000001~平安银行~payh~GP-A^jj~000001~华夏成长混合~hxczhh~KJ";"#
        let results = search.parse(raw)
        XCTAssertEqual(results.count, 1, "上证指数(ZS)与华夏成长混合(KJ 场外基金)应被过滤")
        XCTAssertEqual(results.first?.name, "平安银行")
        XCTAssertEqual(results.first?.symbol.market, .a)
    }

    /// 港股查询常夹带大量场外基金(KJ / KJ-CX),只应保留股票(GP*)。
    /// fixture 是 "00700" 的真实响应:腾讯控股(港股 GP)+ 7 只基金 + 3 只 7 系 A 股。
    func testHongKongQueryKeepsStocksDropsFunds() {
        let raw = #"v_hint="hk~00700~腾讯控股~txkg~GP^jj~007005~中金新医药股票C~zjxyygpc~KJ^jj~007000~鹏华中债13年国开行债券指数A~phzz13ngkhzqzsa~KJ^jj~007001~鹏华中债13年国开行债券指数C~phzz13ngkhzqzsc~KJ^jj~007008~中邮纯债优选一年定期开放债券A~zyczyxyndqkfzqa~KJ-CX^jj~007002~国融稳康债券~grwkzq~KJ^jj~007009~中邮纯债优选一年定期开放债券C~zyczyxyndqkfzqc~KJ-CX^sz~000700~模塑科技~mskj~GP-A^sz~300700~岱勒新材~dlxc~GP-A^sh~600700~*ST数码~stsm~GP-A";"#
        let results = search.parse(raw)
        // 7 只 KJ/KJ-CX 场外基金全部过滤,只剩 4 只股票(腾讯 + 3 只 7 系 A 股)
        XCTAssertEqual(results.count, 4, "场外基金(KJ / KJ-CX)应被过滤,只留股票")
        XCTAssertTrue(
            results.contains { $0.symbol.market == .hk && $0.symbol.code == "00700" },
            "港股 腾讯控股 00700 应被解析"
        )
        XCTAssertTrue(results.contains { $0.symbol.code == "000700" && $0.symbol.market == .a })
        XCTAssertTrue(results.contains { $0.symbol.code == "300700" && $0.symbol.market == .a })
    }

    /// 名称解码:smartbox 返回的中文是 `\uXXXX` 转义,parse 应解出可读中文。
    /// fixture 用寒武纪的真实转义序列(寒武纪 = 寒武纪),验证 parse 的解码路径。
    func testDecodesUnicodeEscapedNames() {
        let results = search.parse(#"v_hint="sh~688256~\u5bd2\u6b66\u7eaa~hwj~GP-A-KCB";"#)
        XCTAssertEqual(results.first?.name, "寒武纪", "\\uXXXX 转义应被解码为中文")
        XCTAssertEqual(results.first?.symbol.code, "688256")
    }

    /// 空结果("N")与脏输入都应安全返回空数组,不崩。
    func testEmptyAndGarbageReturnEmpty() {
        XCTAssertTrue(search.parse(#"v_hint="N";"#).isEmpty)
        XCTAssertTrue(search.parse("").isEmpty)
        XCTAssertTrue(search.parse("not a real response").isEmpty)
        XCTAssertTrue(search.parse(#"v_hint="";"#).isEmpty)
    }
}
