# csv2

`csv2` 是以 Swift 撰寫的命令列 CSV 解析器與編輯器。它支援 RFC 4180
CSV、雙標頭 `.csv2`、Markdown 表格、JSON Lines、串流輸入輸出、索引讀取、
平行搜尋，以及受保護欄位。

English documentation: [README.md](README.md)。

## 狀態

解析器、編輯器、Markdown 讀寫、索引、平行搜尋、加密、記錄，以及跨平台建置
都已實作並由測試涵蓋。
公開 Swift module surface 已提供，並已在 macOS、aarch64 Linux、WSL 與 Windows
透過獨立 module／client 檢查完成驗證。

## 建置與安裝

需求：Swift 6，並將警告視為錯誤。建置使用純 Swift 原始檔、Foundation 與
Dispatch，不使用 SwiftPM 或 SwiftNIO。

```zsh
./compile_csv2.zsh
./test/test_csv2.zsh
./install.zsh
```

建置腳本會自動辨識 macOS、Linux 與 Windows。POSIX 系統輸出
`release/csv2`，Windows 輸出 `release/csv2.exe`。`install.zsh` 支援
`--dry-run`、`--prefix DIR`（裝進 `DIR/bin`）、`--dir DIR`（就裝進 `DIR` 這個目錄）、
`--no-rc` 與 `--uninstall`。

在 macOS 上，如果有「經 ssh 執行的腳本」需要找到它，請裝到 `/usr/local/bin` 而不是 Homebrew
的目錄：一個乾淨的非登入 shell，PATH 裡有 `/usr/local/bin`，而**沒有** `/opt/homebrew/bin`
——後者是 `path_helper` 從 `/etc/zprofile` 加的，那只在登入 shell 執行。install.zsh 會說出
你拿到的是哪一種。

## 格式

輸入副檔名會宣告格式：

| 副檔名 | 標頭 | 規則 |
|---|---:|---|
| `.csv` | 1 列 | RFC 4180；支援引號內逗號與換行 |
| `.csv2` | 2 列 | 英文與繁體中文標頭；一筆一行；使用 `\\n` 與 `\\r` 跳脫 |
| `.md` | 從表格還原 | Markdown 表格；文件有多張表時使用 `--md-table N` |
| 其他或沒有副檔名 | 0 列 | 每行一欄；位元組原樣保留 |

**沒有副檔名的檔案沒有結構可與之矛盾，因此裡面沒有任何東西是可疑的。** `#`、一個 JSON
物件、一行 XML 宣告、一張 Markdown 表的資料列與它的 `|---|` 分隔列，全都會以自己的位元組
回來——那正是「一份含表格的文件可以逐行編輯」的原因。而含 `|---|` 的 `.csv` 或 `.csv2`
**會**被拒絕，因為那裡的副檔名宣告的是另一回事，而一個「只有一欄、又長得像 Markdown」的檔案，
是被冠上錯誤名字的 `-md` 輸出。

**空行在那裡也是一筆紀錄**，所以 `-insert N ''` 與 `-append ''` 會放進一個真正的空行——
散文絕大部分是空行，而一份插不進空行的文件不算可以編輯。`.csv` 與 `.csv2` 仍然拒絕 `''`，
因為那裡的副檔名已經說了一筆紀錄有幾欄，而空字串不是其中之一。

輸出的紀錄分隔符一律是 LF。加引號 CSV 欄位內的 CR 與其他位元組都是資料，
會被保留。UTF-8 BOM 會被移除；UTF-16 輸入會拒絕並提供轉換指令。

選取輸出預設不含標頭，給 `-t` 才會包含。把沒有標頭的資料列寫到
`.csv` 或 `.csv2` 路徑會被拒絕，因為副檔名會錯誤描述檔案。csv2 不會靜默
把單標頭格式與雙標頭格式互相轉換。

## 讀取與選取

```sh
csv2 -r -i data.csv
csv2 -head 10 -t -i data.csv2
csv2 -tail 5 -i data.csv
csv2 -mid 20,30 -i data.csv
csv2 -contains MIT -i data.csv
csv2 -contains MIT --filter -t -o matches.csv -i data.csv
```

對 repository fixture，JSON metadata 會回報資料紀錄與命中數量：

```text
$ csv2 -contains busybox --json -i test/fixtures/TARGET_PACKAGES.csv
{"meta":{"records":21,"matched":3}}
```

讀取選項：

```text
-r                 讀取紀錄（預設）
-contains S        回報每個含有 S 的儲存格，格式為 record:field
--filter           搭配 -contains 時輸出命中的紀錄
--include-headers  搜尋標頭列
--normalize       以 NFC 比對；儲存位元組不正規化
-A N -B N -C N     命中前後的紀錄上下文
-head N -tail N    前 N 筆／後 N 筆紀錄
-mid a,b           包含兩端的紀錄範圍；任一端可省略
-t                 輸出標頭列
-rownum            在最前面加入紀錄號欄位
--physical         在位址中加入實體起始行
--a1               在位址中加入試算表 A1 表示法
-get r:c           輸出一個儲存格的值
```

紀錄號計算資料紀錄，不是實體行。`.csv` 標頭位址是 `0`，`.csv2` 標頭位址是
`0a`／`0b`。`-contains` 預設搜尋所有欄位；使用 `--search-cell R:C`、
`--search-row R` 或 `--search-column C`，即可限定只搜尋一格、一筆或一欄。
這些範圍選項互斥，且必須搭配 `-contains`。
欄名不可包含 `:`，因為該字元保留給 `r:c` 定址語法。`:hash`、`:hmac:` 與 `:enc:`
後綴是 csv2 保留的保護標記，不是使用者定義的欄名。

## 輸出格式與串流

```sh
csv2 -r --json -i data.csv2
csv2 -r --json --json-ascii -i data.csv2
csv2 -r -t -md --pretty -i data.csv2
csv2 -r -si --headers 1 -so < data.csv
```

`--json` 輸出 JSON Lines；第一行與最後一行是 metadata，中間才是紀錄。
對 `.csv2`，第一行 metadata 會以按位置排列的 `header_zh` 陣列提供第二列標頭，
讓消費端可以使用任一列標頭。
`--json-ascii` 會跳脫非 ASCII 字元。`-md` 輸出 Markdown，必須搭配 `-t`；
`--md-style preserve|compact|pretty` 選擇排版。`--pretty` 會把選取的表格
保留在記憶體中，受 `CSV2_PRETTY_MAX_BYTES` 限制。

人類可讀的輸出可用 `--en` 或 `--zh` 選擇標頭語言。`--version`／`-V` 會印出
建置版本；`--help`／`-h` 會印出完整選項清單。

`-si` 從 stdin 讀取，`-so` 寫到 stdout；兩者都不會把整個輸入載入記憶體。
使用 stdin 時必須給 `--headers`，因為 stdin 沒有可以用來宣告格式的副檔名。

**`--headers 0` 會把輸入逐行讀** —— 每行一個欄位，位元組原樣。那是「沒有 `.csv`／`.csv2`
副檔名的檔案」本來就有的格式，而在此之前它只能靠「**沒有**副檔名」來取得，因此 stdin 與散文
`.md` 都指名不到它。它也是唯一一個「會宣告的副檔名蓋不過去」的值：`.csv2` 搭配 `--headers 1|2`
會被拒，因為那個副檔名已經回答過「有幾列標頭」，而 `0` 是**拒絕回答**那個問題，不是換一個答案。
以這種方式讀的 `.md` 是散文，可以當成散文編輯並寫回去——給那些「裡面**含有**一張表」而不是
「本身就是一張表」的文件用。

## 錯誤

錯誤會寫到 stderr，先是英文行，再是繁體中文行；stdout 保持空白，因此可以安全
接在管線中處理。所有錯誤都以非零狀態結束。

**`#` 開頭的一行是資料，不是註解。** CSV 沒有註解語法，而一個叫 `#id` 的欄位是合法的，
因此跳過這樣的一行就等於去猜哪些行是資料。開頭有 `# ...` 的檔案會以「指名那個 `#`」的方式被
拒絕，而不是以欄數——欄數離原因有兩步之遙。

**要在不動那個檔案的前提下把它當成一行行來讀，用管線送進來**：`csv2 -si --headers 0 < FILE`。
以「沒有 `.csv`／`.csv2` 副檔名」的名字讀取效果相同；移除那一行則會讓它成為一份 CSV。注意：
在**有**那兩種副檔名的檔案上，`--headers 0` 的意思是「沒有標頭列的 CSV」而不是逐行——副檔名
已經宣告了逗號分隔。先前的訊息只說出那條要改檔名的路，於是一個讀到它的節點得出「這個檔案
根本讀不了」的結論。

## 編輯

```sh
csv2 -update 12:3 'new value' -i data.csv --in-place
csv2 -update-where 'pending' 'done' -i data.csv --in-place
csv2 -update 12:3 --value-file value.bin -i data.csv --in-place
csv2 -insert 4 'a,b,c' -i data.csv --in-place
csv2 -append 'a,b,c' -i data.csv --in-place
csv2 -delete 4 -i data.csv --in-place
csv2 -delete -cell 4:3 -i data.csv --in-place
csv2 -delete -col 3 -i data.csv --in-place
csv2 -add-column 3 'note,備註' 'todo' -i data.csv2 --in-place
```

支援的編輯動詞是 `-insert`、`-append`、`-delete`、`-update`、`-add-column`，以及依內容定位的
`-update-where`。
所有索引都以原始輸入為準，並在一次通過中套用。`-delete -cell` 會清空欄位，
不改變欄數；`-delete -col` 會從每筆紀錄及每列標頭移除欄位。`.csv2` 的
`-add-column` 需要兩個標頭名稱；省略繁中名稱時會留下空白標頭並發出警告。

`--in-place` 透過私有暫存檔與 rename 寫回，`-append` 除外：它使用追加快路徑。
`-append` 寫入前會驗證輸入，只寫入新增的位元組，但仍會讀取既有檔案以驗證最後
一筆紀錄。平行追加可保證完整寫入，但不支援一般平行編輯。

`-append --in-place` 不使用暫存檔，也不會 rename 結果；它會開啟既有檔案並直接追加。
如果程序在寫入開始後被訊號中斷，檔案可能留下部分紀錄。一般就地編輯所提供的「失敗時
原檔完整保留」保證，不適用於這條只追加的快路徑。

`--truncate-partial` 在重寫時丟棄結尾不完整的紀錄。它與 `-append` 併用會被拒絕，
因為追加無法移除既有位元組。

`-update-where OLD VALUE` 要求資料區中恰好有一個儲存格的完整內容等於 `OLD`。
零個命中、多個命中，或重複指定而命中同一格，都會在寫出任何內容前被拒絕。
這是整格更新，不是子字串取代。

`--value-file PATH` 與 `--value-stdin` 會把 `-update` 的值當成原始位元組讀取，
包括結尾換行與空白。它們必須恰好搭配一個 `-update`，不可與字面值或 `-si` 併用。

`--dry-run` 目前預覽 `-update` 與 `-update-where`，會以 `old -> new` 印出每個變更
儲存格，且不寫入任何檔案。其他編輯動詞會被拒絕，而不是回傳一個可能被誤認為「沒有變更」的
空輸出。`--in-place` 搭配
`--backup` 會把原始輸入備份為旁邊的 `INPUT.bak`，若備份已存在則拒絕覆寫。在 `--json` 下，
拒絕會以 stderr 上的一個 JSON 錯誤物件輸出，包含穩定的 `code`、`message` 與 `message_zh`；
離開碼仍為 1。

當目的地是 Markdown 時，編輯可以搭配 `-md`。搭配 `--md-table N --in-place` 時，只替換選定的表格；
周邊散文會被帶回，所有輸出行尾統一為 LF。

## 保護與稽核記錄

```sh
csv2 -hash email -i data.csv -o masked.csv -t
csv2 -encrypt secret -keyfile key.bin -i data.csv -o encrypted.csv -t
csv2 -decrypt secret -keyfile key.bin -i encrypted.csv -o clear.csv -t
csv2 -log audit.log -update 1:2 value -i data.csv -o result.csv
```

沒有金鑰的 `-hash` 使用 SHA-256；搭配 `-keyfile`／`--yes` 時使用 keyed hash。
雜湊不可還原，但相同值仍可比較。`-encrypt` 使用 ChaCha20-Poly1305，每次使用
新的 nonce。受保護欄位會標記在標頭中；對它直接編輯會被拒絕。金鑰從檔案讀取，
不接受命令列上的秘密值。`-debug` 將診斷寫到 stderr；`-log` 追加帶時間戳的操作記錄。

沒有 `-key` 選項：命令列上的秘密會被其他行程看見，也可能留在 shell 歷史中。
請改用 `-keyfile`。

## 索引與效能

索引 sidecar 是完整資料檔名再加 `.index`，例如 `data.csv.index`。它只是最佳化，
不是資料來源，也不是必要條件：

```sh
csv2 --build-index -i data.csv
csv2 --verify-index -i data.csv
csv2 -contains needle --no-index -i data.csv
```

缺少、過期、損毀或不支援的索引會被捨棄並改用掃描。`--verify-index` 會完整驗證，
sidecar 不存在或無效時以非零結束。`--no-index` 同時停用讀取與寫入 sidecar。
在格式與門檻允許時，`-contains` 可使用平行搜尋，輸出與單執行緒路徑逐位元相同。

測試與調校使用的環境變數：

| 變數 | 預設值 | 用途 |
|---|---:|---|
| `CSV2_INDEX_MIN_BYTES` | 16 MiB | 建立 sidecar 的最小檔案大小 |
| `CSV2_PARALLEL_MIN_BYTES` | 16 MiB | 平行搜尋的最小檔案大小 |
| `CSV2_PARALLEL_CHUNK_BYTES` | 4 MiB | 搜尋區塊大小 |
| `CSV2_PRETTY_MAX_BYTES` | 16 MiB | `--pretty` 保留材料的上限 |
| `CSV2_MD_MAX_BYTES` | 16 MiB | Markdown 輸入上限 |
| `CSV2_MAX_BUFFER_RECORDS` | 1,000,000 | `-tail` 與上下文緩衝上限 |

## 測試與量測

```zsh
./test/test_csv2.zsh
../test_submodules/run_csv2_test.zsh
./verifications/measure.zsh
```

本地測試會回報通過、失敗與略過數量，任何失敗都以非零結束。母專案 runner
會在 aarch64 Linux guest 建置 csv2、比較 host 與 guest 輸出、執行 guest 測試，
並保存量測結果。

### 讀寫效能量測

以下是基準資料集的 wall-clock 完整執行時間，以微秒（µs）表示。這不是固定的每筆成本保證；
數字包含行程啟動、儲存裝置、資料集大小與主機條件。macOS 與 Windows 使用 200,000 筆
（25.4 MiB）；Linux guest 使用 20,000 筆（2.48 MiB），因此只能比較資料量相同的列。

| 量測項目 | macOS arm64<br>2026-08-17 | Windows x86_64<br>2026-08-27 | Linux aarch64 guest<br>2026-08-30 |
|---|---:|---:|---:|
| 完整讀取，單執行緒 | 556,000 µs | 2,512,000 µs | 93,000 µs |
| 完整讀取，平行 | 203,000 µs | 839,000 µs | 101,000 µs |
| 小型耐久編輯 | 19,200 µs | 81,500 µs | 10,600 µs |
| 整檔重寫 | 655,000 µs | 2,444,000 µs | 192,000 µs |

原始量測保存在 `verifications/measure_output*.txt`，由
`verifications/measure.zsh` 以 best-of-N 時間產生。

### 平行搜尋吞吐量與 RSS

平行搜尋量測使用相同的 10,000,000 筆資料：`.csv` 檔案為
1,307,777,815 位元組，`.csv2` 檔案為 1,307,777,833 位元組。每筆資料都命中
`needle`；以下是在 macOS arm64、10 個工作者、4 MiB 區塊下，每種格式與上限各執行一次的結果。

| 格式 | `CSV2_PARALLEL_MAX_BYTES` | 時間 | 吞吐量 | 峰值 RSS |
|---|---:|---:|---:|---:|
| `.csv` | 預設 1 GiB | 34.886 秒 | 35.8 MiB/s | 9.28 MiB |
| `.csv2` | 預設 1 GiB | 39.609 秒 | 31.5 MiB/s | 51.84 MiB |
| `.csv` | 8 MiB | 34.354 秒 | 36.3 MiB/s | 9.30 MiB |
| `.csv2` | 8 MiB | 32.376 秒 | 38.5 MiB/s | 51.69 MiB |

這是量測結果，不是效能保證；只有在二進位檔、資料筆數、主機與搜尋條件相同時才適合比較。
原始輸出見 [`verifications/measure_parallel_rss_output.txt`](verifications/measure_parallel_rss_output.txt)。

## 什麼時候該停止使用它

下表每一列都是 2026-09-01 實測的，不是從舊清單抄過來的。原本在表上的兩項已經移除，因為那兩個
功能做出來了。

| 不提供 | 改用什麼 |
|---|---|
| 欄位投影（`-cols`） | `--json` 加 `jq`，或逐格 `-get` |
| 不分大小寫比對 | 沒有任何東西做得到——`-contains mit` 找不到 `MIT`。請用 `--json` 加一次你自己的處理 |
| 把搜尋限定在「一欄」 | 沒有任何東西做得到。`-contains` 比對的是**每一欄**裡的子字串，因此 `-contains MIT` 也會找到 `transMITter`——見下方最後一個範例。只要那個字在別處出現過，用它來計數就會安靜地錯 |
| 跳過 `#` 註解行 | 沒有任何東西做得到，而且是刻意的：`#` 是資料，而 `#id` 是合法的欄名，跳過它就等於去猜哪些行是資料。那道拒絕會指名那個 `#` |
| 不讀檔就計數 | `--json` 最後那行 meta 上的 `records`——但取得它最直覺的做法會讀完每一個位元組 |
| 在 `.csv` 與 `.csv2` 之間轉換 | 刻意拒絕；請把紀錄寫出去，再讀回來 |
| 安全的並行寫入 | 請自己把寫入者排成序列；兩個寫入者會靜默地弄丟其中一次編輯。兩個並行的 `-append --in-place` 是例外：兩筆紀錄都會完整落地，而「後完成的那一個」會警告自己無法更新索引 |

這張表原本還說了兩件事，現在不再說：**編輯 Markdown 表**已經支援，而**以程式分辨不同的拒絕**
可以用 `--json` 的錯誤物件做到——兩者都在下方的範例裡。

## 範例

自足：這裡每一道指令都對著第一個區塊建出來的檔案執行，而每一段輸出都是這個版本實際印出來的。

```console
$ printf 'pkg,version,license\n套件,版本,授權\nzlib,1.3.1,MIT\nzstd,1.5.6,BSD\n' > pkgs.csv2
```

讀出紀錄。兩列標頭不是紀錄，因此不會被印出來：

```console
$ csv2 -r -i pkgs.csv2
zlib,1.3.1,MIT
zstd,1.5.6,BSD

$ csv2 -r -t -i pkgs.csv2
pkg,version,license
套件,版本,授權
zlib,1.3.1,MIT
zstd,1.5.6,BSD
```

一格的值，以名稱定址，前後不帶任何東西：

```console
$ csv2 -get 1:license -i pkgs.csv2
MIT
```

**定位報告是以 TAB 分隔的三個欄位：位址、欄位名稱、值。** 它不是 CSV，而那是刻意的——一個含
逗號的值會弄壞 CSV 格式的報告：

```console
$ csv2 -contains MIT -i pkgs.csv2
1:3	license	MIT
```

**`--json` 會輸出兩行 metadata，而它們都不是紀錄。** 第一行說出 csv2 認為自己在讀什麼；
最後一行帶著計數。一個「把每一行都當紀錄」的解析器，第一筆輸入就會撞上它：

```console
$ csv2 -r --json -i pkgs.csv2
{"meta":{"format":"csv2","headers":2,"fields":3,"header_zh":["套件","版本","授權"]}}
{"record":1,"line":3,"fields":{"pkg":"zlib","version":"1.3.1","license":"MIT"}}
{"record":2,"line":4,"fields":{"pkg":"zstd","version":"1.5.6","license":"BSD"}}
{"meta":{"records":2,"matched":0}}
```

一張 Markdown 表。兩列標頭以 `<br>` 分隔、裝在同一格裡，而 `--pretty` 是依**顯示寬度**對齊的，
因此那些中日韓標題各算兩欄：

```console
$ csv2 -r -t -md --pretty -i pkgs.csv2
| pkg<br>套件 | version<br>版本 | license<br>授權 |
|-------------|-----------------|-----------------|
| zlib        | 1.3.1           | MIT             |
| zstd        | 1.5.6           | BSD             |
```

**動手之前先看見那次編輯。** `--dry-run` 印出將要發生的改變，而且不寫入任何東西：

```console
$ csv2 -update 1:version '1.3.2' --dry-run -i pkgs.csv2 --in-place
update 1:version: "1.3.1" -> "1.3.2"

$ csv2 -update 1:version '1.3.2' --backup -i pkgs.csv2 --in-place
$ csv2 -r -i pkgs.csv2
zlib,1.3.2,MIT
zstd,1.5.6,BSD
$ ls pkgs.csv2*
pkgs.csv2	pkgs.csv2.bak
```

**以「內容」定位的編輯，在命中不唯一時會拒絕**，而且會列出它找到的每一個位址，不會替你挑一個：

```console
$ printf 'k,v\n甲,乙\na,x\nb,x\n' > dup.csv2
$ csv2 -update-where x Z -i dup.csv2 --in-place
csv2: -update-where "x": more than one data cell matches (1:2, 2:2); refusing an ambiguous update
csv2：-update-where「x」：有多個資料儲存格符合（1:2, 2:2）；拒絕這個有歧義的更新
```

**在 `--json` 之下，拒絕是程式讀得懂的**——stderr 上的一行，帶一個穩定的 `code`。結束狀態
仍然是 1：

```console
$ csv2 --json -i nosuch.csv
{"error":{"code":"not-found","message":"cannot open input file: nosuch.csv","message_zh":"無法開啟輸入檔：nosuch.csv"}}
```

**還有一個值得看一次的陷阱：** `-contains` 是「跨每一欄」的子字串搜尋，因此它也會在另一個值
的內部找到那個字：

```console
$ printf 'pkg,license\n套件,授權\nzlib,MIT\ntransMITter,BSD\n' > lic.csv2
$ csv2 -contains MIT -i lic.csv2
1:2	license	MIT
2:1	pkg	transMITter
```

## 授權

MIT。見 [LICENSE](LICENSE)。
