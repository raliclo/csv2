# csv2

以 Swift 撰寫的命令列 CSV 解析器與編輯器，目標為
[LinuxCS](https://github.com/raliclo/LinuxCS) 專案的 aarch64 Linux guest，
以及建置它的 macOS host。

English: [README.md](./README.md)

## 狀態

**第 1–5 階段已實作並通過測試；第 6–7 階段尚未完成。**

```zsh
./compile_csv2.zsh       # 建置 release/csv2
./test/test_csv2.zsh    # macOS（arm64、Swift 6.4）上 74 通過、0 失敗、1 略過
```

| 可用 | 尚未做 |
|---|---|
| RFC 4180 解析、引號、內嵌逗號與換行、CRLF、BOM | Linux 交叉編譯與 guest 內執行（第 6 階段） |
| `-r`、`-contains`、`-A`/`-B`/`-C`、`-head`/`-tail`/`-mid`、`-rownum` | 隨 rootfs 出貨、`install.zsh`（第 7 階段） |
| `.csv2` 兩列標頭、`--json`、`-md`、`--pretty`（UAX #11 寬度） | |
| `-insert`/`-append`/`-delete`/`-update`、`-delete -cell` | |
| `-hash`、`-encrypt`、`-decrypt`、`-keyfile`、`-debug`、`-log` | |
| `-append` 的 O(1) 快路徑 | |
| `.csv.index` / `.csv2.index` sidecar、`--verify-index` | |
| 平行搜尋，且與單執行緒逐位元相同 | |

進度以核取方塊記在 [plan/plan.md](./plan/plan.md) 文末，且**只有在
[test/test_csv2.zsh](./test/test_csv2.zsh) 中對應的案例通過時才打勾**。
工具尚未能滿足的案例會回報為 SKIP 並附原因，不會安靜地略過。

目前**不**隨 LinuxCS 的 guest rootfs 出貨——需要它的腳本都在 macOS host 上執行。
但測試仍應在 **macOS 與 aarch64 Linux 兩個平台**上進行，且要求兩邊輸出逐位元相同：
Linux 上的 Foundation 是另一份實作，「在 macOS 上會過」對 Linux 不構成證據。
後半尚未做到——那是第 6 階段，測試中的 T47 就是負責斷言它的那個案例。

## 為什麼要做

不是因為世界上缺少 CSV 工具，而是因為**這個專案已經被天真的逗號切割咬過**，而且是
同一天兩次。

`TARGET_PACKAGES.csv` 的 `status_notes` 欄含有帶引號、內有逗號的敘述文字。一支用
`${line%,*}` 切欄位的腳本改寫了那些註記的中段。它以 0 結束，並印出它改了哪些東西；
那份清單裡的「舊值」是半句話。檔案是從 git 還原的。

同一天，`artifacts.csv` 把一個 commit 字串寫進了 `built_utc` 這個時間戳欄位，
沒有任何東西報錯。

這兩次都不是因為 CSV 難懂，而是因為**手邊沒有工具**，於是每個人都改用 `cut -d,` 和
`${line%,*}`。csv2 的目的，是讓「正確處理 CSV」比「隨手切逗號」更方便。

因此第一個需求不是效能，也不是功能數量：

> RFC 4180 的引號、內嵌逗號、內嵌換行、CRLF、BOM 必須全部正確處理；
> 其餘情況一律大聲失敗，而不是安靜地產生一個半對的檔案。

輸出的紀錄分隔符在任何平台上一律為 `\n`，且不偵測作業系統——否則「macOS 與 Linux 輸出
逐位元相同」這項要求無法成立。輸入則接受同一檔案中混用 LF 與 CRLF，以逐筆判斷而非整檔
偵測。引號內的位元組一個都不動，因此「只用 LF」指的是紀錄分隔符，不是檔案裡的每一個
位元組。

## 兩種格式，由副檔名宣告

| 副檔名 | 標頭列數 |
|---|---|
| `.csv` | 1 —— 標準 CSV |
| `.csv2` | 2 —— 第一列英文標題，第二列繁體中文標題 |

格式**由副檔名宣告，永不偵測**。偵測是猜測，而猜錯會把第一筆資料當成標頭——且是靜默地。

兩列標頭的形式之所以存在，是因為本專案的資料檔是雙語的；把中文欄位標題放在檔案裡，
勝過放在另一份會逐漸失真的文件中。

## 規劃中的介面

```
csv2 -r               讀取
csv2 -contains S      輸出含有 S 的紀錄，並附上位址
csv2 -A N -B N -C N   比對前後的上下文，如 grep
csv2 -head N          前 N 筆              （筆，不是行）
csv2 -tail N          後 N 筆
csv2 -mid a,b         第 a 到第 b 筆，含兩端
csv2 -t               輸出帶上標頭列（預設不帶）
csv2 -rownum          最前面加一欄紀錄號
csv2 -md              輸出 Markdown 表格
csv2 --json           輸出 JSON Lines
csv2 -i / -o          輸入／輸出檔
csv2 -si / -so        由 stdin 讀／寫到 stdout，且不整檔緩衝

csv2 -insert N ROW      插入為第 N 筆
csv2 -append ROW        加在最後
csv2 -delete a[,b]      刪除第 a 筆，或第 a 到第 b 筆
csv2 -delete -cell r:c  清空一個儲存格（欄數不變）
csv2 -update r:c VAL    更新一個儲存格

csv2 -hash COLS       以 SHA-256 遮蔽欄位，單向
csv2 -encrypt COLS    加密欄位（ChaCha20-Poly1305）
csv2 -decrypt COLS    解密欄位
csv2 -keyfile PATH    金鑰檔；預設為 multissh 的私鑰

csv2 -debug           診斷訊息輸出到 stderr
csv2 -log FILE        追加帶時間戳的操作紀錄
```

全篇的 `N` 數的都是**筆數，不是行數**。含引號換行的紀錄會跨多行，數行只會得到半筆資料。

位址一律為 `紀錄:欄位`，1-based——這正是 `-contains` 輸出的格式，因此尋找與修改可以
直接銜接：

```sh
csv2 -contains "舊的值" -i a.csv2     # → 12:6 status_notes …
csv2 -update 12:6 "新的值" -i a.csv2 -o b.csv2
```

## 讀程式碼前值得先知道的幾項決定

以下每一項在 [plan/plan.md](./plan/plan.md) 中都有完整論證。

- **標頭是選擇加入的。** 未給 `-t` 時只輸出資料列，因為多數輸出會被接到下一個工具。
  但把不帶標頭的輸出寫進 `.csv`／`.csv2` 檔會被拒絕：那種檔案是在對自己的格式說謊。
- **用 `-update` 而非 `-set`。** `-insert`／`-update`／`-delete` 是 SQL 的既有詞彙，
  一起看就是一組。
- **刪除儲存格的意思是清空。** 真的移除該欄位會使該列少一欄、其後全部左移——正是本
  工具要防止的那類損壞，而且它不會報錯。
- **沒有 `-key` 旗標。** 命令列上的秘密在 `ps` 中可見，也會留在 shell 歷史裡。
  只提供 `-keyfile`。
- **正常路徑上不輸出任何訊息。** 會說話的 CLI 放不進管線。預設的記錄門檻是 WARN。

## 比較

[`compare/vs-sqlite.csv2`](./compare/vs-sqlite.csv2) 與
[`compare/vs-postgresql.csv2`](./compare/vs-postgresql.csv2) 逐項列出比較結果。
它們就以自己所描述的格式寫成——兩列標頭，第一列英文、第二列繁體中文——因此同時是
第一批真實的 `.csv2` 測試素材。

每一列都有 `basis`（依據）欄，標明該項是在此地**實測**、取自**已記載**的行為、
由工作的形狀**推論**而得，還是**UNMEASURED**（尚未量測，不可倚賴）。這一欄比結論本身
更重要：儲存空間各列是實測的，而全檔掃描各列不是——因為目前還沒有 Swift 的 RFC 4180
解析器可供量測。

實測的儲存結果並非一面倒。相對 SQLite，CSV 在文字資料上較小（1.31 倍，若已建索引則為
1.75 倍），但在整數資料上**較大**（SQLite 為 0.75 倍）——因為 SQLite 存的是 varint，
CSV 存的是十進位數字的文字。

## 什麼時候該改用別的

> 超過約 1 GiB 且有寫入流量，或需要依鍵值查詢時，改用 SQLite。

每次編輯都會重寫整個檔案，因此改動 1 GiB 檔案中的一個儲存格要寫入 1 GiB，
而 PostgreSQL 只需約 10 KB。`-append` 是例外，走 O(1) 的路徑。
查詢是依位置而非依鍵值，所以「找出 `pkg_name = busybox` 那一列」是全檔掃描。

真正的鄰居是 SQLite 而非 PostgreSQL——同樣是單一檔案、無 daemon、無 schema migration，
但它有 B-tree、page 級更新與交易。csv2 相對它只保有**一個**優勢：
**檔案仍是人看得懂、git diff 得出來的純文字**。對本專案而言那正是全部的重點，
因為兩次 CSV 事故都是從 git 還原的。

## 授權

MIT —— 見 [LICENSE](./LICENSE)。

若要沿用本設計請注意：計畫中的欄位加密建立在 swift_tar 的 `crypto.swift` 之上。
若日後是把那份程式碼**併入**而非僅僅引用，它自身的授權會一併適用，屆時本檔就不是
授權的全部。
