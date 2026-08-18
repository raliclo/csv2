# csv2

以 Swift 撰寫的命令列 CSV 解析器與編輯器，目標為
[LinuxCS](https://github.com/raliclo/LinuxCS) 專案的 aarch64 Linux guest，
以及建置它的 macOS host。

English: [README.md](./README.md)

## 狀態

**第 1–6 階段已實作並通過測試；第 7 階段（出貨）是刻意暫緩。**

```zsh
./compile_csv2.zsh       # 建置 release/csv2
./test/test_csv2.zsh    # macOS（arm64、Swift 6.4）上 112 通過、0 失敗、1 略過
```

| 可用 | 尚未做 |
|---|---|
| RFC 4180 解析、引號、內嵌逗號與換行、CRLF、BOM | 隨 rootfs 出貨、`install.zsh`（第 7 階段） |
| `-r`、`-contains`、`-A`/`-B`/`-C`、`-head`/`-tail`/`-mid`、`-rownum` | |
| `.csv2` 兩列標頭、`--json`、`-md`、`--pretty`（UAX #11 寬度） | |
| `-insert`/`-append`/`-delete`/`-update`、`-delete -cell`、`-delete -col` | |
| `-hash`、`-encrypt`、`-decrypt`、`-keyfile`、`-debug`、`-log` | |
| `-append` 的 O(1) 快路徑 | |
| `.csv.index` / `.csv2.index` sidecar、`--verify-index` | |
| 平行搜尋，且與單執行緒逐位元相同 | |
| 可在 aarch64 Linux 上建置執行，且與 macOS 逐位元相同 | |

進度以核取方塊記在 [plan/plan.md](./plan/plan.md) 文末，且**只有在
[test/test_csv2.zsh](./test/test_csv2.zsh) 中對應的案例通過時才打勾**。
工具尚未能滿足的案例會回報為 SKIP 並附原因，不會安靜地略過。

目前**不**隨 LinuxCS 的 guest rootfs 出貨——需要它的腳本都在 macOS host 上執行。
但測試在 **macOS 與 aarch64 Linux 兩個平台**上都做，且要求兩邊輸出逐位元相同：
Linux 上的 Foundation 是另一份實作，「在 macOS 上會過」對 Linux 不構成證據。那就是
案例 T47，由母專案的 `test_submodules/run_csv2_test.zsh` 驅動——它在 guest 內建置
csv2，並逐一以 sha256 比對十二組呼叫。

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

**`--headers 1|2` 在 `-si` 時是必要的**——stdin 沒有副檔名可以宣告格式。搭配 `-i` 時，
只有在它與副檔名**一致**才會被接受；牴觸即拒絕：

```console
$ csv2 -r --headers 1 -i vs-sqlite.csv2
csv2: vs-sqlite.csv2 declares 2 header row(s) by its suffix, but --headers says 1. The suffix declares the format; --headers is for input with no suffix to declare it. Rename the file or drop --headers.
csv2：vs-sqlite.csv2 的副檔名宣告了 2 列標頭，但 --headers 說 1 列。副檔名宣告格式，--headers 是給「沒有副檔名可宣告」的輸入用的。請改檔名，或拿掉 --headers。
$ echo $?
1
```

2026-08-18 之前，這個覆蓋不經檢查就被接受，而後果比「讀錯」更嚴重，因為它會被寫回去：
對一個兩列標頭的檔案下 `--headers 1 -delete 1`，會在 rc=0 下把 22 筆變成 21 筆，
丟掉繁體中文標題列並讓一筆**資料**列取而代之——而檔案仍然結構合法、仍然讀得出來、
不報任何錯。它同時也讓本文件所推薦的檢查失效：`--json` 屆時會回報
`{"format":"csv2","headers":1}`，一個自相矛盾的值，而斷言會愉快地通過。兩者現已拒絕，
由 T56c 涵蓋。

基於同樣的理由，csv2 不會在兩種格式之間轉換：把一列標頭的輸入寫進 `.csv2` 路徑會被
拒絕，而不是靜默地因為缺少第二列標頭而少掉一筆（T56d）。

兩列標頭的形式之所以存在，是因為本專案的資料檔是雙語的；把中文欄位標題放在檔案裡，
勝過放在另一份會逐漸失真的文件中。

`.csv2` 除此之外就是一份普通的 CSV——第二列只是第二列標頭，沒有標記、也沒有分隔：

```csv
pkg,ver,note
套件,版本,備註
zlib,1.3.2,first record
zstd,1.5.6,second record
```

那個檔案有**兩**筆紀錄，不是三筆。`csv2 --json` 的第一行會說明這件事，那是確認 csv2
讀成你要的格式最快的方法：

```console
$ csv2 -r --json -i example.csv2 | head -1
{"meta":{"format":"csv2","headers":2,"fields":3}}
```

兩列標頭的欄數必須與資料相同。`.csv2` 的儲存格內不得含原始換行——一筆永遠是一行——
因此值裡的換行寫成 `\n`、CR 寫成 `\r`、反斜線寫成 `\\`。

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
  --headers 1|2         搭配 -si 時為必要：stdin 沒有副檔名可宣告格式。亦可與
                        -i 併用，此時會「覆蓋」副檔名——這是全篇唯一不由檔名
                        宣告格式的地方。見上方警告；絕不要與編輯動詞併用
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
  -delete -col N|名稱   從每一筆與兩列標頭中移除該欄——唯一能保持對齊的刪除
  -update r:c VAL       更新一個儲存格
  --truncate-partial    丟棄結尾不完整的紀錄，而非以錯誤結束

保護
  -hash COLS            單向遮蔽欄位。確定性的，因此相等的值仍然相等
                        ——但請先讀下方的警告
  -encrypt COLS         加密欄位（ChaCha20-Poly1305，每次新 nonce）
                        不論有沒有給 -t，標頭一律會寫出：金鑰指紋與 salt 就在
                        標頭裡，salt 每次執行都不同，沒有它們的密文任何人都
                        永遠解不開。-encrypt 與選取旗標併用原本會在 rc=0 下
                        丟掉標頭；已於 2026-08-18 修正，由 T56a／T56b 斷言。
  -decrypt COLS         解密；COLS 可用 `all` 表示所有被標記的欄位
  -keyfile PATH         金鑰檔；預設為 multissh 的私鑰。
                        與 -hash 併用時，會從純 SHA-256 改為 HMAC
  --yes                 不經詢問即採用預設金鑰

COLS 是以逗號分隔的清單，可用欄名、1-based 欄號，或兩者混用：
`-hash license`、`-hash 7`、`-hash 6,license`。

索引
  --no-index            完全不讀也不寫 .index sidecar
                        sidecar 是完整檔名加上 ".index"：packages.csv ->
                        packages.csv.index、pkgs.csv2 -> pkgs.csv2.index
  --build-index         立即建立 sidecar。否則索引只會以「副作用」出現：寫入時建一個、
                        -tail 因為本來就要讀完整檔而建一個——只用 -mid 的話永遠不會有
  --verify-index        O(n) 的完整比對；正常路徑上的 O(1) 檢查刻意只是啟發式，
                        不是證明

診斷
  -debug                診斷訊息輸出到 stderr，含一行 metrics:
  -debug=trace          再低一級：每一筆紀錄的選取決定
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

### 各種模式實際輸出什麼

這支工具會吐出四種不同的形狀，而挑錯是最容易犯的錯：**`-contains` 印的是「報告」，
不是 CSV。**

```console
$ csv2 -contains busybox -i TARGET_PACKAGES.csv
1:1	pkg_name	busybox
1:4	source	fork raliclo/busybox branch develop; upstream git.busybox.net
1:6	status_notes	CORRECTED 2026-08-10 after reading the generated…
6:6	status_notes	Added 2026-08-09. Fills the busybox zstd gap.…
13:6	status_notes	Required because compile.zsh is zsh-only (${0:A:h}…
```

五行，因為有五個**儲存格**命中——過長的值是為了排版在此以 `…` 截短的，不是 csv2 截的。

三個欄位以 **TAB** 分隔：位址、欄名、值。每個命中的**儲存格**一行，因此同一筆有兩欄
命中就印兩行，而同一格內出現兩次只印一行。在腳本裡就是 `cut -f1`、`cut -f2`、`cut -f3`。

**值會被跳脫**，使用與 `.csv2` 相同的反斜線慣例再加上 `\t`：字面的 tab 變成 `\t`、
換行變成 `\n`、CR 變成 `\r`、反斜線變成 `\\`。少了它，含 tab 或換行的儲存格會破壞
報告自己承諾的格式——而「同時含有這兩者的帶引號散文」正是這支工具當初為之而寫的資料。

比對是**區分大小寫**的，且沒有旗標可以改變。`--normalize` 只影響 Unicode 正規化，
與大小寫無關。

**沒有欄位投影**：沒有任何東西可以「只取 license 那一欄」。要取單一值，請用 `--json`
讀出你要的欄位，或用 `-contains` 取 `cut -f3`。

```console
$ csv2 -contains busybox --filter -i TARGET_PACKAGES.csv
busybox,fce9d7f35ea3 (submodule),896 KiB,fork raliclo/busybox branch develop,…
```

`--filter` 改為輸出命中的**紀錄**，形式為 CSV。要一併帶出標頭請加 `-t`——`-t` 在哪些
情況下不是選用的，見下方的「會被拒絕的組合」。

`-A`、`-B`、`-C` **隱含 `--filter`**：上下文紀錄沒有命中的儲存格，儲存格報告對它無話
可說。不相鄰的區塊之間以 `--` 分隔，與 grep 相同。

```console
$ csv2 -contains busybox --json -i TARGET_PACKAGES.csv
{"meta":{"format":"csv","headers":1,"fields":7}}
{"record":1,"field":1,"header_en":"pkg_name","value":"busybox","line":2}
{"record":1,"field":4,"header_en":"source","value":"fork raliclo/busybox …"}
{"meta":{"records":21,"matched":3}}
```

JSON Lines。**第一行**是 metadata，帶出 csv2「認為」自己正在讀的格式，讓呼叫端可以
斷言 `headers` 是否符合預期，而不是默默接受一個猜錯的解析。**最後一行**帶總數：它們
無法放進第一行，除非先讀完整份輸入才開始輸出，而那正是串流保證的反面。

那兩個數字要精確理解。`records` 是**讀到**幾筆資料，不是檔案裡有幾筆——在 21 筆的檔案上
`-mid 5,5` 會回報 5，因為它讀到那裡就停了。`matched` 數的是命中的**紀錄**數，而兩個
metadata 之間的每一行對應一個命中的**儲存格**——因此只要有紀錄在多欄命中，兩個數字就
不一樣。

「選取」而非「搜尋」時輸出的是另一種物件，每筆一個：

```console
$ csv2 -mid 5,5 --json -i TARGET_PACKAGES.csv
{"meta":{"format":"csv","headers":1,"fields":7}}
{"record":5,"line":6,"fields":{"pkg_name":"zlib (libzlib)","version":"1.3.2…",…}}
{"meta":{"records":5,"matched":0}}
```

`fields` 以欄名為鍵，那是「不必數欄位就能取出某一欄」的方式。

`-md` 產生 Markdown 表格，且是單向的——csv2 無法把它讀回來。

### 在管線裡

`-si` 與 `-so` 和每一個動詞都能組合；管線沒有任何特別之處，只差在 stdin 沒有副檔名，
因此必須由 `--headers` 說明格式：

```console
$ cat packages.csv | csv2 -si --headers 1 -contains busybox --filter -so
busybox,1.37.0,"fork raliclo/busybox, branch develop",GPL-2.0
```

**它確實是串流的，但 stdout 以 64 KiB 為單位緩衝，不是逐行。**「不緩衝整個檔案」講的是
記憶體，而那句為真：在持續湧入的串流上，第一批輸出立刻就出現，記憶體也保持平坦。但只要
輸出不足 64 KiB，就要等到整個執行結束才會出現——因此把 csv2 接進一個你正在盯著看的東西，
看起來會像是卡住了，實際上只是還沒有東西可以 flush。若你需要「每產生一筆就拿到一筆」，
你需要的是一支逐行緩衝的工具；csv2 是為管線中的吞吐量而寫的，不是為互動式即時觀看。
這是量出來的、不是假設的：輸出 8000 筆時，第一批位元組在 0.01 秒抵達而輸入持續 3 秒；
輸出 2000 筆時，直到結束前什麼都沒有。由 T61 斷言。

### 結束狀態

成功為 `0`，任何錯誤為非零，沒有第三種情況：csv2 不會「部分成功」。失敗的執行不會
在 `-o` 留下任何東西，因為輸出寫的是暫存檔，一切都成功之後才 rename。

**`--in-place` 同樣成立，而且在那裡更要緊：** 失敗的就地編輯會讓原檔**逐位元原封不動**，
旁邊也不會留下暫存檔。這是唯一沒有退路的一條保證——用 `-o` 時輸出錯了你手上還有輸入，
而用 `--in-place` 時輸入「就是」輸出。它本來可以從「`--in-place`……以暫存檔加 rename」
加上上面那句推論出來，但「推論得出」不等於「寫出來了」；2026-08-18 一位只讀 README 的
讀者指出他必須自己推。由 T28c 斷言。

`--build-index` 與 `--verify-index` 各自會印一行到 **stdout**——它們是明確的管理動作、
不屬於正常路徑，但若你把它們接進管線，那一行就在你的串流裡。

錯誤訊息走 stderr，恰好**兩行**（英文一行、中文一行）。給了 `-log FILE` 時，同一個失敗
會另外帶時間戳追加到該檔；沒給則不會再印任何東西。正常路徑上完全不輸出任何訊息——它必須
能放進管線。

**訊息帶多少位置資訊，取決於實際上有多少可帶。** 不要寫一支「預期每則訊息裡都找得到
`record N, field M`」的腳本：

| 錯誤發生在 | 訊息會指出 | 範例 |
|---|---|---|
| 某一格 | `record N, field M` | `record 3, field 2: undefined escape sequence \q` |
| 某一筆，但不屬於單一欄位 | `record N` | `record 1 (line 2) has 2 fields but the header has 3` |
| 參數 | 兩者都不指出——它在讀到任何一筆之前就被丟出 | `unknown flag --nope` |
| 整個檔案 | 兩者都不指出——沒有紀錄可指 | `cannot open input file: /nope.csv` |

在 2026-08-18 之前，這一節無條件宣稱錯誤會「指出是哪一筆、哪一欄」。八則錯誤中只有一則
如此；其餘只指出紀錄，或什麼都不指——因為再沒有別的為真的東西可指。由 T60 斷言。

**參數**本身的錯誤是在 `-log` 被讀到之前就丟出的，因此它會到 stderr 但不會進 log 檔：
要寫進哪個 log，正來自那批解析失敗的參數。

### 會被拒絕的組合，以及為什麼

「拒絕」正是這支工具的重點，所以在此列出，而不是留給人自己撞到。以下每一項都會以
非零結束，並說明原因：

| 組合 | 為什麼被拒絕 |
|---|---|
| `-head 3 -o out.csv2`（未給 `-t`） | 把不帶標頭的資料列寫進一個「副檔名承諾了標頭」的路徑；下次讀取會把最前面的紀錄當成標頭吃掉。**這條適用於選取，不適用於編輯**——見下 |
| `-md` 未給 `-t` | 沒有標頭列就渲染不出 Markdown 表格；自動補上會讓「預設不帶標頭」出現一個看不見的例外 |
| `-md -o out.csv2` | 副檔名宣告的是 CSV，內容卻是 Markdown |
| `-si` 未給 `--headers 1` 或 `2` | stdin 沒有副檔名，格式未被宣告；此處的預設值就是猜測 |
| `-head` 與 `-tail` 併用 | 兩者沒有一個明顯正確的合併讀法 |
| `-mid 7,3` | `a > b`；不替你對調，因為範圍寫反通常表示別處的邏輯也反了 |
| `-i x -o x` 未給 `--in-place` | 開啟輸出會在輸入讀完前把它截斷 |
| `-delete 12:6` | 那是儲存格位址；請加 `-cell`，或改給紀錄號 |
| `-delete -cell -col 3` | 兩者是相反的：`-cell` 清空一格並保留該欄，`-col` 則移除整欄 |
| `-delete -col` 移除全部欄位 | 沒有任何欄位的檔案不是 CSV 檔 |
| `-delete -col X` 同時對 X 下 `-update`／`-delete -cell`／`-encrypt`／`-hash` | 該編輯不會有效果，卻仍會被回報為已完成 |
| `-delete -col` 與 `-insert`／`-append` 併用 | 那列字面值必須符合舊形狀或新形狀其中之一，而無法判斷是哪一個 |
| `-insert -cell` | 在一列中間插入儲存格，會把該列後面的欄位全部往後推一格 |
| 在 21 筆的檔案上 `-update 99:3` | 越界是錯誤，絕不是「自動長大」 |
| 在 7 欄的檔案上 `-append 'a,b,c'` | 欄數必須與標頭相符；csv2 不會補空或截斷來湊合 |
| `-encrypt` 未給 `-keyfile` 且沒有 tty | 無法顯示的提示絕不視為「是」 |
| 編輯時沒有給 `-o`、`-so` 或 `--in-place` | `-insert`/`-append`/`-delete`/`-update` 需要明確的目的地；沒有「隱含就地編輯」這回事 |
| `-o /dev/stdout` | 輸出會先寫到目標旁的暫存檔再 rename，那需要一個一般檔案。請改用 `-so` |
| 未知旗標 | 絕不被當成別的東西吞掉 |

### `-t` 管的是選取，從不管編輯

選取產生的是**片段**，因此「標頭要不要跟著出去」是一個問題，由 `-t` 回答。編輯產生的是
一個**檔案**，因此那不是問題：標頭一律寫出，給不給 `-t` 都一樣；寫到 `.csv2` 目的地時
兩列都寫。

```console
$ csv2 -head 1 -i pkgs.csv2 -o sel.csv2
csv2: sel.csv2 declares a format with a header, so writing data rows there needs -t; without it the next read would take the first record(s) as the header
csv2：sel.csv2 的副檔名宣告了帶標頭的格式，因此在此寫入資料列必須給 -t；否則下次讀取會把最前面的紀錄當成標頭
$ echo $?
1

$ csv2 -update 1:note X -i pkgs.csv2 -o edited.csv2   # 沒給 -t，也沒有被拒
$ head -2 edited.csv2
pkg,ver,note
套件,版本,備註
```

這個不對稱正是重點。拒絕編輯，會讓人根本無法在不記得某個旗標的情況下編輯 `.csv2`——
而那個旗標一旦漏掉，唯一可能的產物就是一個壞掉的檔案；接受選取，產生的就正好是那個壞掉的
檔案。由 T59 斷言。

### 遮蔽欄位：使用 `-hash` 之前請先讀這一段

`-hash` 是**確定性**的——那正是選它而不選 `-encrypt` 的全部理由。相等的值產生相等的
摘要，因此你仍然分得出哪些列原本的值相同。`-encrypt` 每格用新的 nonce，相同的明文會
得到不同的密文，那個能力就沒有了。

確定性是有代價的，而且代價不小：

> **沒有金鑰的 `-hash` 就是該值無鹽的純 SHA-256。** 對於可能值很少的欄位——
> `license`、`status`、`category`、國碼——任何拿到雜湊後檔案的人，只要把一份詞表
> 拿去雜湊，就能把該欄直接讀回來。

這不是假設。一次對本工具的盲測，**僅憑雜湊後的輸出**、沒有原始檔、只用一份 SPDX
識別碼清單，就還原了範例檔中 21 個 license 裡的 3 個。

**給 `-keyfile`，它就變成 HMAC-SHA256。** 仍然是確定性的，相等的值仍然相等，但摘要
現在取決於一份秘密，那份詞表因此失效：

```console
$ csv2 -hash license -i TARGET_PACKAGES.csv -o masked.csv -t
$ head -1 masked.csv | cut -d, -f7
license:hash                       # 無金鑰——字典適用

$ csv2 -hash license -keyfile k.bin -i TARGET_PACKAGES.csv -o masked.csv -t
$ head -1 masked.csv | cut -d, -f7
license:hmac:289b9391              # 有金鑰——附上所用金鑰的指紋
```

只有在值空間確實夠大時才選無金鑰的形式——長的自由文字欄位、不透明的識別碼——或者
你其實並不需要對「拿到檔案的人」隱藏那些值。

### 受保護的欄位會在檔案中被標記

`-hash`、`-encrypt`、`-decrypt` 會改寫**標頭**，讓檔案記錄下對哪一欄做了什麼：

| 標記 | 意義 |
|---|---|
| `license:hash` | 無金鑰的 SHA-256 |
| `license:hmac:<指紋>` | HMAC-SHA256，`<指紋>` 標識所用的金鑰 |
| `license:enc:<指紋>:<salt>` | 已加密；`-decrypt all` 會找出這些 |

定址仍使用原本的欄名：遮蔽之後 `-update 3:license` 照樣可用。對已標記的欄位再次遮蔽
會被拒絕，而不是疊加一層。

`--json` 的鍵維持乾淨的欄名，因此同樣的標記改為出現在 metadata 那一行：

```console
$ csv2 -head 1 -t --json -i masked.csv
{"meta":{"format":"csv","headers":1,"fields":7,"protected":{"license":"hmac"}}}
```

沒有任何欄位受保護時，該鍵完全不會出現。

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
  比沒有索引糟得多。`packages.csv` 的 sidecar 是 `packages.csv.index`——完整檔名再加上
  `.index`，因此 `foo.csv` 與 `foo.csv2` 永遠不會相撞。那也就是要寫進 `.gitignore` 的
  那一行：它從資料檔衍生而來、永遠不是真實來源，因此不該提交，也不需要備份。
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
