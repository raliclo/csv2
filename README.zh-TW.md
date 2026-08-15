# csv2

以 Swift 撰寫的命令列 CSV 解析器與編輯器，目標為
[LinuxCS](https://github.com/raliclo/LinuxCS) 專案的 aarch64 Linux guest，
以及建置它的 macOS host。

English: [README.md](./README.md)

## 狀態

**第 1–6 階段已實作並通過測試；第 7 階段（出貨）是刻意暫緩。**

```zsh
./compile_csv2.zsh       # 建置 release/csv2
./test/test_csv2.zsh    # macOS（arm64、Swift 6.4）上 74 通過、0 失敗、1 略過
```

| 可用 | 尚未做 |
|---|---|
| RFC 4180 解析、引號、內嵌逗號與換行、CRLF、BOM | 隨 rootfs 出貨、`install.zsh`（第 7 階段） |
| `-r`、`-contains`、`-A`/`-B`/`-C`、`-head`/`-tail`/`-mid`、`-rownum` | |
| `.csv2` 兩列標頭、`--json`、`-md`、`--pretty`（UAX #11 寬度） | |
| `-insert`/`-append`/`-delete`/`-update`、`-delete -cell` | |
| `-hash`、`-encrypt`、`-decrypt`、`-keyfile`、`-debug`、`-log` | |
| `-append` 的 O(1) 快路徑 | |
| `.csv.index` / `.csv2.index` sidecar、`--verify-index` | |
| 平行搜尋，且與單執行緒逐位元相同 | |
| 可在 aarch64 Linux 上建置執行，且與 macOS 逐位元相同 | |

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

## 介面

```
選取
  -r                    讀取
  -contains S           輸出每個含有 S 的「儲存格」，形式為 紀錄:欄位
  --filter              與 -contains 併用時，改為輸出命中的紀錄
  --include-headers     一併搜尋標頭列（回報為紀錄 0a／0b）
  --normalize           以 NFC 比對；已儲存的內容絕不正規化
  -A N  -B N  -C N      以「筆」為單位的上下文，如 grep；區塊之間以 -- 分隔
  -head N               前 N 筆              （筆，不是行）
  -tail N               後 N 筆
  -mid a,b              第 a 到第 b 筆，含兩端；`a,` 與 `,b` 為開放端
  -t                    輸出帶上標頭列（預設不帶）
  -rownum               最前面加一欄紀錄號
  --physical            額外輸出該紀錄起始的物理行號
  --a1                  額外輸出試算表的 A1 記法

輸入／輸出
  -i FILE  -o FILE      檔案路徑；-o 會寫暫存檔再 rename
  -si  -so              由 stdin 讀／寫到 stdout，且不整檔緩衝
  --headers 1|2         搭配 -si 時為必要：stdin 沒有副檔名可宣告格式
  --in-place            就地編輯 -i，同樣走暫存檔加 rename

輸出形狀
  -md [--pretty]        Markdown 表格；需要 -t。--pretty 以「顯示寬度」對齊，
                        因此放棄串流
  --json                JSON Lines；--json-ascii 會跳脫非 ASCII
  --en  --zh            以哪一列標頭命名欄位

編輯
  -insert N ROW         插入為第 N 筆；ROW 是一列 CSV 文字
  -append ROW           加在最後（就地寫入時為 O(1)）
  -delete a[,b]         刪除第 a 筆，或第 a 到第 b 筆
  -delete -cell r:c     清空一個儲存格（欄數不變）
  -update r:c VAL       更新一個儲存格
  --truncate-partial    丟棄結尾不完整的紀錄，而非以錯誤結束

保護
  -hash COLS            以 SHA-256 遮蔽欄位，單向
  -encrypt COLS         加密欄位（ChaCha20-Poly1305，每次新 nonce）
  -decrypt COLS         解密；COLS 可用 `all` 表示所有被標記的欄位
  -keyfile PATH         金鑰檔；預設為 multissh 的私鑰
  --yes                 不經詢問即採用預設金鑰

索引
  --no-index            完全不讀也不寫 .index sidecar
  --verify-index        O(n) 的完整比對；正常路徑上的 O(1) 檢查刻意只是啟發式，
                        不是證明

診斷
  -debug                診斷訊息輸出到 stderr，含一行 metrics:
  -log FILE             追加帶時間戳的操作紀錄
  --version  --help
```

每個旗標兩種寫法都接受：`-contains` 與 `--contains` 等價。**未知**旗標一律報錯——
multissh 已經被「未知選項被當成主機名稱吞掉」咬過一次。

刻意不提供 `-key`。命令列上傳遞的秘密，在 `ps` 中對本機每個行程都可見，也會留在
shell 歷史裡。

全篇的 `N` 數的都是**筆數，不是行數**。含引號換行的紀錄會跨多行，數行只會得到半筆資料。

位址一律為 `紀錄:欄位`，1-based——這正是 `-contains` 輸出的格式，因此尋找與修改可以
直接銜接：

```sh
csv2 -contains "舊的值" -i a.csv2     # → 12:6 status_notes …
csv2 -update 12:6 "新的值" -i a.csv2 -o b.csv2
```

### 環境變數

每一個的存在理由都是**讓它的邏輯能被測試**，而不是為了調校：一個不能被調低的門檻，
唯一的測試方式就是真的產生它本來要防的那種資料（例如一個 16 MiB 的 fixture）。

| 變數 | 預設 | 作用 |
|---|---|---|
| `CSV2_INDEX_MIN_BYTES` | 16 MiB | 低於此值不讀也不寫索引 |
| `CSV2_PARALLEL_MIN_BYTES` | 16 MiB | 設成大於檔案大小即可強制走單執行緒 |
| `CSV2_PARALLEL_CHUNK_BYTES` | 4 MiB | 調小可讓小檔案也切出多個區塊，區塊邊界才真的被測到 |
| `CSV2_PRETTY_MAX_BYTES` | 16 MiB | `-md --pretty` 超過此值時拒絕，而不是被 OOM 殺掉 |
| `CSV2_MAX_BUFFER_RECORDS` | 1,000,000 | `-tail N` 與 `-B N` 的上限 |

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
- **索引永遠是最佳化，永遠不是必要條件。** 沒有索引時行為完全相同。過期、截斷、
  損毀、版本不符——一律丟棄改用掃描，沒有一個是錯誤。一個會很快給你錯資料的索引，
  比沒有索引糟得多。
- **平行的輸出必須與單執行緒逐位元相同。** 那是驗收條件而非期望：本專案的失敗多半
  是靜默的，而平行化尤其擅長產生「大部分情況正確」的結果。
- **`--pretty` 以顯示寬度對齊，而那是第四個數字。** `套件名稱` 是 12 位元組、
  4 個碼位、4 個 grapheme cluster，以及 **8 欄**。Swift 的 `String.count` 給的是
  cluster 數，用它對齊在中文上就是錯的——而這在 emoji 出現之前就已經成立，因為
  `.csv2` 的第二列標頭就是繁體中文。

## 比較

[`compare/vs-sqlite.csv2`](./compare/vs-sqlite.csv2) 與
[`compare/vs-postgresql.csv2`](./compare/vs-postgresql.csv2) 逐項列出比較結果。
它們就以自己所描述的格式寫成——兩列標頭，第一列英文、第二列繁體中文——因此同時是
第一批真實的 `.csv2` 測試素材。

每一列都有 `basis`（依據）欄，標明該項是在此地**實測**、取自**已記載**的行為、
由工作的形狀**推論**而得，還是**UNMEASURED**（尚未量測，不可倚賴）。這一欄比結論本身
更重要：儲存空間各列是實測的，而全檔掃描各列不是。

那些表寫成時，理由是「還沒有 Swift 的 RFC 4180 解析器可以量」。現在有了，所以那些列
是量得出來的，只是還沒去量——一個比較站不住腳的理由；而表格仍標示 UNMEASURED，
因為那就是它們的現狀。

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

`src/Crypto.swift` 是從 `multissh/swift_tar/crypto.swift` **複製**進來的，不是引用：
swift_tar 位於本 repo 之外，一個會伸出去取檔案的建置只在這台機器上成立，而計畫要求
csv2 同樣要能在 Linux guest 上建置。

那份複本是同一位作者自己的程式碼（`raliclo/multissh`），因此沒有任何第三方授權隨之
而來。這一點值得講清楚，因為 multissh 本身**沒有 LICENSE 檔**：在此以 MIT 重新授權，
是著作權人自己的選擇，而不是繼承來的。若有人沿用本設計、但那些密碼學原語的來源不同，
那就是一個本檔回答不了的授權問題。
