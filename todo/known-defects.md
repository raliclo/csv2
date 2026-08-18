# csv2 已驗證缺陷 / verified defects

日期：2026-08-16。來源：一次 `read_easy` 檢視（全新 agent，只讀 `README.md` 與
`README.zh-TW.md`，禁讀原始碼、測試、設計文件與 `--help`），共 164 次嘗試 / 82 個目標。
**下列每一條都由母專案 session 親手重現過**；agent 提出但無法重現的一條已被撤回，不列於此。

Verified 2026-08-16 by a read_easy pass — a fresh agent allowed to read only the
two READMEs, forbidden the source, tests, design docs and `--help`. 164 attempts
across 82 goals. **Every item below was reproduced by hand before being written
down.** One claim the agent could not reproduce was retracted and is not listed.

**共同特徵：全部在 `rc=0` 下靜默發生。** 沒有一條會報錯，沒有一條會留下線索。
All of them happen silently at `rc=0`.

---

## 狀態：全部已修（2026-08-18）/ Status: all fixed

十二項斷言涵蓋這六條，編號 **T56a–T56l**，macOS 與 aarch64 Linux 兩邊皆通過。
本檔保留為紀錄：**重現步驟仍然有效**，只是現在每一條都會以非零結束或給出正確結果。

Twelve assertions cover the six items, numbered **T56a-T56l**, passing on both
macOS and the aarch64 Linux guest. This file is kept as the record: the
reproductions still run, they now exit non-zero or produce the right answer.

修法一覽 / what changed:

| # | 修法 |
|---|---|
| 1 | 有轉換時**一律**寫出標頭。salt 只存在於標頭標記中且每次執行都不同，不帶標頭的密文任何人都解不開——沒有值得為它保留的第二種讀法，所以是「強制」而非「拒絕」 |
| 2 | 副檔名與 `--headers` 牴觸即拒絕。副檔名「宣告」格式，`--headers` 是給沒有副檔名的輸入用的；兩者都發言且互斥時，csv2 分不出誰對，所以不猜 |
| 3 | 守衛改為檢查「輸入的標頭列數是否等於輸出副檔名所宣告的」。csv2 不會自行轉換：一列變兩列要「發明」一列標題，而發明資料是這支工具絕不做的事 |
| 4 | 解析器現在分辨「不完整」與「只是沒有結尾換行」。未閉合引號在任何格式下都是錯誤；`.csv` 沒有結尾換行則不是。`--truncate-partial` 真的會丟棄不完整的那一筆 |
| 5 | 兩列標頭分別回報為 `0a` / `0b` |
| 6 | `--en` 只取英文標題；`-log` 預設不再收 DEBUG/TRACE；`-head -1` 報錯；`--physical`／`--a1` 在沒有定位報告時被拒；`--a1` 的列號改用**物理行號**（試算表所稱的列就是那個） |

**一個修正時自己踩到的坑**，記在此處因為它正是同一類問題：第一版把解析器的
`.quotedQuote` 狀態也當成「還在引號內」。它其實是「剛看到一個引號，還不知道是收尾
還是 `""` 跳脫」——在 EOF 時代表**欄位已完整**。那個版本會拒絕每一列「以引號值結尾」
的合法資料，由 T46a 抓到。

---

## 共用的測試前置 / shared setup

```zsh
mkdir -p /tmp/csv2-defects && cd /tmp/csv2-defects
cp /Volumes/LinuxCS/sos/linux_kernal_vm_interactive/TARGET_PACKAGES.csv a.csv
cp /Volumes/LinuxCS/sos/csv2/compare/vs-sqlite.csv2 b.csv2
head -c 64 /dev/urandom > k.bin
```

`a.csv` 是 1 列標頭、21 筆資料。`b.csv2` 是 2 列標頭、22 筆資料。

---

## 1. `-encrypt` 搭配選取旗標 → salt 遺失，資料不可還原

**嚴重度：資料永久遺失。**

金鑰指紋與 salt 存在標頭列。`-encrypt` 與 `-head`／`-tail`／`-mid`／`--filter` 併用而未給
`-t` 時，標頭不會被寫出，於是密文永遠無法解密。

```zsh
csv2 -encrypt license -keyfile k.bin -head 1 -i a.csv > damaged.csv
echo "rc=$?"                                   # rc=0
head -1 damaged.csv | grep -c 'license:enc'    # 0  ← marker 不見了
```

哪些形式會掉，實測：

| 指令 | rc | marker |
|---|---|---|
| `-encrypt license -keyfile k.bin -i a.csv` | 0 | **在** |
| `-encrypt license -keyfile k.bin -head 1 -i a.csv` | 0 | **不見** |
| `-encrypt license -keyfile k.bin -head 1 -t -i a.csv` | 0 | **在** |
| `-encrypt license -keyfile k.bin -mid 2,3 -i a.csv` | 0 | **不見** |
| `-encrypt license -keyfile k.bin -tail 2 -i a.csv` | 0 | **不見** |

**為何不可還原**——顯而易見的補救是「重跑一次拿標頭再嫁接上去」，但 salt 每次執行都不同：

```zsh
for i in 1 2 3; do
  csv2 -encrypt license -keyfile k.bin -t -head 1 -i a.csv | head -1 |
    grep -oE 'license:enc:[^,]*'
done
# license:enc:03d80737:YR1/lpsEiMtJ9PmLPWNqlg==
# license:enc:1757622b:RV0oHpIiUwC1FFNhBUNvFQ==
# license:enc:282b8868:MLIi+OM6x72BH1yNCx3sLA==
```

嫁接後 `-decrypt` 會以 `authentication failed` 失敗（rc=1）——這是正確的行為，但為時已晚。

**機制已經存在。** `-encrypt ... -o out.csv` 不給 `-t` 也會寫出標頭，只是「選取 → stdout」
這條路徑沒有走到。修法二選一：`-encrypt`／`-hash` 啟用時一律強制寫標頭，或比照
`-head 3 -o out.csv2` 的做法直接拒絕該組合。

**README 已就此加註**（`d4a8e6f`），標為已知缺陷，未動程式碼。

---

## 2. `--headers` 覆蓋副檔名且不與檔名交叉檢查

**嚴重度：資料遺失，且會使本專案自己推薦的防護失效。**

`--headers 1|2` 記載為「供 `-si` 宣告格式」，但它同樣可與 `-i` 併用，此時覆蓋副檔名。

```zsh
csv2 -r --json -i b.csv2 | head -1
# {"meta":{"format":"csv2","headers":2,"fields":6}}

csv2 -r --json --headers 1 -i b.csv2 | head -1
# {"meta":{"format":"csv2","headers":1,"fields":6}}   ← 自相矛盾
```

**一份只有一列標頭的 `.csv2` 不存在。** 而 README 把這一行 metadata 賣成「呼叫端可以據此
斷言解析結果符合預期，而不是默默接受一個猜錯的解析」——`--headers` 改變的正是被斷言的那個
數字。**斷言通過了，解析卻是錯的**：安全機制在它本來要捕捉的失敗上回報成功。

寫回時會真的少一筆：

```zsh
csv2 -r --json -i b.csv2 | tail -1              # {"meta":{"records":22,...}}
csv2 --headers 1 -delete 1 -i b.csv2 -o bad.csv2
echo "rc=$?"                                     # rc=0
csv2 -r --json -i bad.csv2 | tail -1             # {"meta":{"records":21,...}}
sed -n '2p' bad.csv2 | cut -c1-40
# "storage, text at scale","1.00x (856,7      ← 資料列被升格成第二列標頭
```

中文標題列消失，**而該檔案結構仍然合法、讀取不報錯**。

也會改到錯的儲存格：

```zsh
csv2 --headers 2 -update 1:1 CLOBBERED -i a.csv -o bad2.csv
echo "rc=$?"                                     # rc=0
sed -n '2p;3p' bad2.csv | cut -c1-30
# busybox,fce9d7f35ea3 (submodul               ← 使用者要改的第 1 筆，沒被動
# CLOBBERED,2.42.9000 (submodule               ← glibc 被改掉了
```

**建議修法**：副檔名與 `--headers` 衝突時直接拒絕，比照既有的 `--build-index --no-index`。

**README 已就此加註**（`d792bdb`），寫在「格式由副檔名宣告」規則被陳述的位置。

---

## 3. `.csv` → `.csv2` 轉檔少一筆資料

**嚴重度：資料遺失。**

```zsh
csv2 -r -i a.csv | wc -l                # 21
csv2 -r -t -i a.csv -o conv.csv2
echo "rc=$?"                            # rc=0
csv2 -r -i conv.csv2 | wc -l            # 20   ← 少一筆
sed -n '2p' conv.csv2 | cut -c1-30      # busybox,...  被吃成第二列標頭
```

反向亦然：`.csv2` → `.csv` 會寫出兩列標頭到一列標頭的路徑，讀回時中文標題列變成第 1 筆資料。

**成因**：`-head 3 -o out.csv2` 的守衛只檢查「有沒有給 `-t`」，沒有檢查
「寫出的標頭列數是否符合目的副檔名所宣告的數量」。README 對該守衛的理由寫的正是
「下次讀取時前面的紀錄會被當成標頭吃掉」——而這裡就是那件事。

---

## 4. `--truncate-partial` 完全無作用

**嚴重度：旗標被接受但不做任何事，使用者得不到任何訊號。**

```zsh
printf 'a,b\n1,2\n3' > p.csv
csv2 -r -t                     -i p.csv >o1.txt 2>e1.txt; echo "rc=$?"   # rc=1
csv2 -r -t --truncate-partial  -i p.csv >o2.txt 2>e2.txt; echo "rc=$?"   # rc=1
diff o1.txt o2.txt && diff e1.txt e2.txt && echo "完全相同 / identical"
```

六種殘缺結尾皆 0 效果：缺尾換行、未閉合引號、結尾逗號、真的被截斷的大檔、以及其中兩種
經由 `-si`。

附帶：`p.csv` 的診斷訊息說的是欄數不符，而非引號／截斷問題——若 `--truncate-partial`
要修好，錯誤分類也要一併看。

---

## 5. `--include-headers` 的 `0a` / `0b` 未實作

README 說兩列標頭會分別回報為紀錄 `0a` 與 `0b`。實際兩列都印 `0`：

```zsh
csv2 -contains csv2 --include-headers -i b.csv2 | head -2
# 0:2	csv2	csv2
# 0:2	csv2	csv2      ← 兩行完全相同，無法分辨英文列與中文列
```

**對中文優先的讀者影響更大**：`--include-headers` 用在 `.csv2` 上，最主要的用途正是
「分辨英文標題列與中文標題列」，而那正是它給出兩個相同位址的情況。

---

## 6. 其餘（皆 `rc=0`，較輕但仍是靜默的）

```zsh
# --en 對 -md 是 no-op：與不給旗標逐位元相同
csv2 -head 1 -md -t --en -i b.csv2 | head -1
csv2 -head 1 -md -t      -i b.csv2 | head -1     # 相同

# -log 的預設門檻不是 WARN
csv2 -head 2 -log L.log -i a.csv >/dev/null
grep -oE '\b(TRACE|DEBUG|INFO|WARN|ERROR)\b' L.log | sort -u
# DEBUG INFO TRACE     ← README 說預設是 WARN

# -head -1 靜默回傳空結果
csv2 -head -1 -i a.csv; echo "rc=$?"             # rc=0，零輸出，stderr 空

# --physical / --a1 只對 -contains 生效
csv2 -head 3 --physical --a1 -i a.csv             # 與不給旗標逐位元相同

# --a1 的列號是紀錄號，不是試算表列號
csv2 -contains "storage, text at scale" --a1 --physical -i b.csv2
# 1:1@L3 [A1]   ← 該儲存格在實體第 3 行，試算表會叫它 A3
csv2 -contains 依據 --include-headers --a1 -i b.csv2
# [E0]          ← A1 記法沒有第 0 列
```

`--a1` 這一條特別值得看：**csv2 自己已經知道正確的行號**——`--physical` 在同一行印出
`@L3`。

---

## 分類

| # | 類別 | 需要 |
|---|---|---|
| 1 | 程式 | 強制標頭，或拒絕該組合 |
| 2 | 程式 | 副檔名與 `--headers` 衝突時拒絕 |
| 3 | 程式 | 守衛改為檢查「標頭列數是否符合副檔名」 |
| 4 | 程式 | 實作它，或移除該旗標 |
| 5 | 程式或文件 | 實作 `0a`/`0b`，或改文件說明目前行為 |
| 6 | 程式或文件 | 逐條決定 |

第 1、2 條的 README 警告已提交（`d4a8e6f`、`d792bdb`），並明確標為**已知缺陷與日期**——
把陷阱寫成「預期介面」會讓人學會與它共存，標成缺陷才能維持修它的壓力。

---

# 第二輪：回合制盲測（2026-08-18）/ Second run: round-based blind testing

方法與第一輪相同（全新 agent、只讀兩份 README、禁讀原始碼／測試／設計文件／`--help`），
但改為**回合制**：一回合只測一件事，回報後停下等待，修完才進下一回合。批次處理會讓修正
對著一份讀者早已走過的 README 進行。

**十九個回合：一個程式缺陷、十一個文件缺陷、兩個測試套件自身的缺陷。**
其餘回合沒有發現，就記為沒有發現。

Same method as the first run, but ROUND-BASED: one thing per round, report, wait,
fix, then continue. Nineteen rounds produced one program defect, eleven
documentation defects, and two defects in the test suite itself.

## 狀態：全部已修 / Status: all fixed

| # | 缺陷 | 類別 | 斷言 |
|---|---|---|---|
| A | 索引自身的損毀能靜默給出錯資料 | **程式** | T68a–T68h |
| B | Linux 上 `replaceItemAt` 使索引無法被替換，並在正常路徑印出警告 | **程式** | T62g–T62i |
| C | 錯誤訊息範例是節錄卻呈現得像完整訊息 | 文件 | T58a–T58d |
| D | `-t` 管選取不管編輯，未記載 | 文件 | T59a–T59h |
| E | 「錯誤會指出是哪一筆、哪一欄」為無條件宣稱，實際八分之一 | 文件 | T60a–T60f |
| F | 失敗的 `--in-place` 保住原檔，未記載 | 文件 | T28c–T28d |
| G | 無 `-si`/`-so` 管線實例；stdout 以 64 KiB 為單位緩衝，未記載 | 文件 | T61a–T61d |
| H | sidecar 檔名從未具體寫出 | 文件 | T62a–T62c |
| I | 上下文模式不標示哪一筆是命中 | 文件＋程式 | T63a–T63h |
| J | README 在 CSV 輸出旁建議 `cut`，未標明適用形狀 | 文件 | T65a–T65c |
| K | `--include-headers` 只有一句話、無實例 | 文件 | T66a–T66e |
| L | `--a1` 的標頭列算術與其拒絕條件未記載 | 文件 | T67a–T67f |
| M | 測試套件自己在 12 處用 `cut -d,` 切 CSV | **測試** | T64a–T64d |
| N | T58 grep 一個 guest 內不存在的 README，拿空字串比對 | **測試** | T58z |

---

## A. 一個索引的損毀能靜默地給出錯資料

**症狀**：在索引的偏移量表裡翻轉一個位元組，`-mid 1,1` 會回傳一段「從欄位中間開始」的
碎片，並以一筆紀錄的身分呈現；`-tail` 安靜地少回一筆。兩者都是 rc=0、stderr 全空。同一個
檔案的 `-r` 完全正確——因為它不使用索引。

```sh
csv2 -tail 4 -i f.csv                      # 產生 f.csv.index
printf '\032' | dd of=f.csv.index bs=1 seek=88 conv=notrunc
csv2 -mid 1,1 -i f.csv                     # -> "lib,2,b"，rc=0
csv2 -r      -i f.csv | head -1            # -> "busybox,1,a"，正確
```

**原因**：載入時的每一項驗證描述的都是「資料檔」——大小、mtime、首尾 64 位元組的雜湊、
項目數是否足夠。**沒有任何一項描述索引自身的內容。** 於是偏移量的損毀通過了全部檢查。

**為何要緊**：README 與 plan 都寫著「過期、截斷、損毀、版本不符——一律丟棄改用掃描」，並
稱這種結果「比沒有索引糟得多」。那句話對「資料檔改變」成立，對「索引自身損毀」不成立。

**修法**：檔頭第 80–88 位元組（原本保留未用）改放一個涵蓋整份索引（含偏移量）的 FNV-1a
檢查碼，`INDEX_VERSION` 由 1 升為 2。實測：對一份 96 位元組的索引，逐一翻轉全部 96 個
位元組位置，全部正確退回掃描並給出正確答案。

**這個檢查碼不是簽章**：能改寫偏移量的人也能改寫檢查碼。它擋的是位元翻轉、寫入不完整、
被部分覆寫的檔案。要證明請用 `--verify-index`（O(n)）。

由盲測第 18 回合發現——那一輪唯一的 TOOL BROKEN。它接續第 10 回合：第 10 回合證明「整份
垃圾」的索引會被攔下，第 18 回合改問「一個仍能通過 O(1) 檢查的『合理』損毀」。


## B. Linux 上索引無法被替換，且在正常路徑印出警告

**症狀（僅 Linux）**：改寫一個「已經存在」的索引時，`FileManager.replaceItemAt` 丟出
例外，catch 發出警告，而那個警告出現在**正常路徑的 stderr** 上——破壞了讓 csv2 能待在
管線裡的那唯一一條承諾。索引也就此不再更新，因此第一次寫出之後這項最佳化永久關閉。

**為何撐過先前的跨平台測試**：沒有任何東西產生錯誤的資料。過期的索引會被丟棄改用掃描，
於是最要緊的那條保證守住了，底下的機制卻什麼也沒做。

**原因**：`Core.swift` 在發現該 API 於 Linux 上「回報成功卻沒有動到目的地」之後已換掉它，
`Index.swift` 卻留著舊呼叫——修正到了資料路徑，沒到它旁邊的索引。

**修法**：改用 `Platform.replaceFile`（POSIX `rename(2)`），與資料路徑一致。
`fileExists` 加 `moveItem` 的組合也拿掉：rename 本身就是原子覆寫，先問一次只是多製造一個
race。斷言為 T62g–T62i（第二次寫出會替換第一次，且 stderr 不說話）。

## C–L. 文件缺陷

十一項，全部由「只讀 README」的讀者在回合制盲測中找到。共同形狀是：**行為是對的，
但文件沒說、說錯、或說得剛好具體到可以拿來寫腳本而其實是錯的。**

| # | 缺陷 | 修法 |
|---|---|---|
| C | 錯誤訊息的 console 範例只顯示一行且以句號結尾，看似完整；真正的訊息還有兩句加一行中文，牴觸 README 自己「錯誤恰好兩行」的規則 | 改為完整訊息＋`echo $?`；T58 把 README 引用的兩行對著執行檔實際輸出比對，使它無法再靜默飄移 |
| D | README 說 `-t` 預設關、不帶標頭寫入有副檔名的路徑會被拒，讀者由此合理推論「編輯也會被拒」——實際不會 | 新增「`-t` 管選取，不管編輯」一節；T59 涵蓋 `-delete -col` 與 `-append` 快路徑這兩個「少一列標頭最難察覺」之處 |
| E | 「錯誤訊息……並指出是哪一筆、哪一欄」是無條件宣稱；實測八則錯誤只有一則兩者都指出 | 改為四類位置分類表＋一句警告：不要寫「預期每則訊息都有位址」的腳本。T60 斷言四類，含「紀錄層級錯誤不得捏造欄位號」 |
| F | 失敗的 `--in-place` 會讓原檔逐位元不變，但該保證只寫給 `-o`——而 `--in-place` 才是沒有退路的那個 | 明文寫出；T28d 補上「旁邊不留暫存檔」這個先前無人斷言的一半 |
| G | 從未展示 `-si`/`-so` 與任何動詞併用；「不緩衝整個檔案」從未被驗證 | 補上管線實例。實測：確實串流（8000 筆時第一批 0.01 秒抵達、輸入持續 3 秒），但 stdout 以 **64 KiB** 為單位緩衝而非逐行，不足時要到結束才出現，看起來像卡住。兩半都寫出，因為第二半正是別人會當成 bug 回報的 |
| H | sidecar 檔名只以抽象方式提過，想寫進 `.gitignore` 的人得自己猜 | 寫出 `packages.csv → packages.csv.index`，並說明為何附加在「完整檔名」之後（否則 `foo.csv` 與 `foo.csv2` 會共用 `foo.index`，而兩者標頭列數不同——正是「很快給你錯資料」那種情況）|
| I | `-A/-B/-C` 隱含 `--filter` 後，送出的是命中與上下文的混合而無任何區分；README 旁邊就寫著「和 grep 一樣」，而 grep 會區分 | CSV 側無法標記（標記＝多一欄＝壞掉的紀錄），改以文件說明；`--json` 側新增 `"match":true/false`，且只在有上下文時出現。T63 兩種形狀都斷言 |
| J | 「或用 `-contains` 再 `cut -f3`」寫在一個輸出為 CSV 的 `--filter` 範例上方幾行，而那個 `cut` 沒有 `-d`（切的是 TAB，只適用於報告）| 完整寫出指令、說明少掉的 `-d` 正是重點、並指出旁邊的陷阱。T65 安全的一半與陷阱的一半都斷言 |
| K | `--include-headers` 只有一句話、沒有實例（其他每項定址功能都有）| 補上三行並列實例。另糾正一個讀者的合理誤解：名稱欄跟隨 `--zh`，而非「命中的那一列」。T66 斷言 |
| L | `--a1` 只有一行；標頭列算術（`.csv`→A2、`.csv2`→A3）未記載，且「只能搭定位報告」這條拒絕不在拒絕表裡 | 補上並列實例與拒絕表列。T67 斷言兩種格式的位移、欄位字母、以及兩條拒絕 |

## M–N. 測試套件自身的缺陷

這兩項不是 csv2 的缺陷，是**測試的**缺陷。列在這裡是因為它們同樣屬於「看起來成功」那一類。

**M：測試套件自己在用 `cut -d,` 切 CSV。** 十二處對 csv2 的輸出使用 `cut -d, -fN`——正是
這整個專案存在所要消滅的作法。在本專案自己的 fixture 上實測是錯的：`cut -d, -f6` 對第 1 筆
回傳 515 位元組儲存格中的 104 位元組，一段從值中間開始的散文碎片。加密版之所以「對」，
只因為那一筆的 `purpose` 剛好沒有逗號——**正確得靠運氣**。

一份證明「逗號切割不安全」的測試，自己卻用逗號切割檢查結果，這個矛盾不能留著：fixture 改動
的那一天，這個檢查會以這支工具存在所要防止的那種方式壞掉，而且是靜默地壞掉。

已改用 `cell()` / `header_cell()`（以 `-delete -col` 投影出該欄再取紀錄或標頭），只用到 csv2
自己定義的操作。**T64 斷言那次替換是「必要的」而非整潔**——若哪天 `cut` 與 csv2 在該 fixture
上一致了，代表 fixture 已失去那個引號內的逗號，同一刻另外幾個案例也悄悄變弱。

**N：T58 拿空字串去比對。** T58 以 grep 讀 `$ROOT/README.md` 來對照執行檔輸出，而 guest 的
payload 從不夾帶 README。grep 回傳空字串，比對照樣進行。

**失敗還算走運。** 假如實際輸出也是空的，它就會**通過**——而一個靠「拿空的比空的」而通過的
測試比沒有測試更糟：它佔住了本該放一個真正檢查的位置。payload 現在夾帶兩份 README，
`T58z` 先斷言檔案存在才進行比對。

---

## 待決（非缺陷）：沒有「依位址讀取」

`record:field` 位址只與**寫入**組合（`-update`、`-delete -cell`）。要讀回一個已知位址的值，
必須繞道 `--json` ＋全檔選取＋外部解析器；本專案的測試套件為此得用兩次 csv2 呼叫加一個
暫存檔來實作 `cell()`。

盲測讀者提議 **`-get r:c`**，與 `-update r:c VAL` 對稱（`-r` 已被讀取動詞佔用），並指出最強的
理由：**位址可能來自外部**——有人從 bug 回報裡打進來、或是上一次執行留下的。`-contains`
完全無法服務那個情境，因為它只能找「你已經知道在裡面」的值。

**這是設計決定，不是缺陷，尚未實作，等待決定。**
