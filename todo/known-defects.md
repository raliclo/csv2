# csv2 已驗證缺陷 / verified defects

## 這個檔案的規則：**每一個被回報的缺陷都先寫進這裡，然後才修**

**每一回合回報的每一條，一經親手重現，就在那一回合寫進這個檔案——在動手修之前。**
修好之後更新那一條的狀態並附上斷言編號，不要把它刪掉。

理由不是流程潔癖，是這一天付過的代價：第 36 與第 37 回合各有一個**程式**缺陷（索引宣稱了
一個沒有東西推導過的性質；`-si`/`-so` 留住整條串流），當時被直接修掉並只寫進 `plan/plan.md`，
沒有進這個檔案。它們是 Z 與 AA，**補記於 2026-08-19，而那次補記是靠人記得**。

一個只存在於 session 逐字稿裡的已驗證缺陷是最糟的狀態：下一個來看的人會看到一棵乾淨的樹和
一份全過的測試。而「修好了所以不必記」也不成立——**這個檔案存在的價值有一半是那些重現步驟**，
它們是日後判斷「這個修正有沒有退化」的唯一依據。

Every defect reported in a round is written here the moment it is reproduced by
hand, BEFORE it is fixed. When it is fixed, update its status and name the
assertions; do not delete it. Two program defects from rounds 36 and 37 were
fixed straight into plan.md without landing here first -- they are Z and AA,
backfilled on 2026-08-19, which only happened because someone remembered.

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
| O | 五個檔案裡七個過期的 PASS 數字（74／112／25），其中 README 的那個被當成「驗證工具能用」的方法提供 | 文件 | T69a–T69b |
| P | `-get` 的結尾換行是終止符，與「值自己的結尾換行」無法區分，`$(...)` 會靜默吃掉；且「交出邏輯值而非磁碟位元組」未記載 | 文件 | T71a–T71e |
| Q | **`-get` 靜默忽略 `--json`／`--pretty`／`-t`／`-rownum`** | **程式**（我引入的）| T70s |
| R | 無法從外部確認「平行路徑到底有沒有跑」；且平行化的前提條件（只適用 `-contains`、需一筆一行）未記載 | **程式＋文件** | T72a–T72f |
| S | **log 遮蔽只認「本次執行的轉換」，不認「檔案標頭的宣告」**——對已雜湊／已加密的欄位下 `-update`，新值明文進 log | **程式（安全相關）** | T73a–T73f |
| T | **「`-md` 是單向的」在資料不含逗號時不成立**——分隔列被當成第 1 筆資料讀出，rc=0 | **程式** | T74a–T74f |
| U | **同名欄位以「位置在前者」靜默勝出**——`-update 1:note X` 在有兩個 `note` 的檔案上編輯第一個，rc=0 | **程式** | T75a–T75g |
| V | **`--json` 輸出重複鍵**——同名欄位使一個值在「讀者的解析器」手上被毀掉，csv2 rc=0 | **程式** | T75h–T75k |

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

## 已關閉（非缺陷）：沒有「依位址讀取」→ 已加入 `-get r:c`

`record:field` 位址只與**寫入**組合（`-update`、`-delete -cell`）。要讀回一個已知位址的值，
必須繞道 `--json` ＋全檔選取＋外部解析器；本專案的測試套件為此得用兩次 csv2 呼叫加一個
暫存檔來實作 `cell()`。

盲測讀者提議 **`-get r:c`**，與 `-update r:c VAL` 對稱（`-r` 已被讀取動詞佔用），並指出最強的
理由：**位址可能來自外部**——有人從 bug 回報裡打進來、或是上一次執行留下的。`-contains`
完全無法服務那個情境，因為它只能找「你已經知道在裡面」的值。

**已決定並實作（2026-08-18）：`-get r:c`。** 使用者的裁示是「照讀者說的做」。設計理由與
定案的五件事記在 [../plan/plan.md](../plan/plan.md) 的「`-get r:c`」一節；斷言為 T70a–T70m。

本專案測試套件的 `cell()` 輔助函式——原本需要兩次 csv2 呼叫加一個暫存檔——已塌縮成一行
`-get`。那個輔助函式的存在，本身就是這個缺口的證明。

## Q. `-get` 靜默忽略決定輸出形狀的旗標（2026-08-18 引入，同日修正）

**這一條是我自己引入的**，在 `-get` 落地的隔天由自我檢視發現，不是盲測找到的。

`-get` 的輸出器被放在 emitter 選擇鏈的最前面，於是它蓋掉了 `--json`、`--pretty`、`-t`、
`-rownum`——那些旗標被**靜默丟棄**，rc=0。

**為何要緊**：`csv2 -get 1:2 --json` 是很自然會打出來的東西。README 在「值本身的換行有意義」
時，指的正是 `--json`；於是一個照著文件走的讀者，會打出這個指令、得到純粹的值、而且不會有
任何東西告訴他那個旗標沒有生效——**恰好在他之所以加上那個旗標的那個情境裡**。

**修法**：拒絕。`-get` 只有一種輸出形狀，因此每一個決定形狀的旗標都與它牴觸；訊息並指出
替代作法（`-mid r,r`）。斷言為 T70s。

## R. 無法從外部得知「平行路徑有沒有跑」（2026-08-18 發現並修正）

**症狀**：`-debug` 只在平行化「真的發生」時才印出 `parallel: N chunks`；沒發生時什麼都不說。
於是「平行跑了且輸出相同」與「平行根本沒跑」無法區分——**而這兩者恰恰在輸出相同時無法區分**，
也就是在你最需要區分它們的時候。

**它如何被發現**：盲測第 22 回合想證明「平行輸出與單執行緒逐位元相同」，建了能想到最難的
fixture（讓分塊邊界落在一個同時含逗號與換行的引號欄位裡），得到逐位元相同的輸出，然後
**拒絕把那稱為通過**——因為它無法確認平行路徑跑過。

那個拒絕比讀者自己看得到的更正確：**`.csv` 裡的內嵌換行，正是取消該檔案走平行路徑資格的
那個東西。** 它為了施壓分塊邊界而建的 fixture，恰好是平行路徑依設計永遠不會看到的。兩次
執行都是單執行緒的。

**修法**：`canRunParallelSearch` 改為回傳「理由」而非布林；`-debug` 一律印出走的是哪一條路，
包括 `single-threaded: <理由>`。前提條件（只適用 `-contains`、不得有選取／上下文／轉換／
編輯、需 `-i`、多核、達門檻、**一筆一行**）補進兩份 README。斷言為 T72a–T72f，其中 T72f
先以 T72a／T72e 證明「那是兩次不同的執行」，再比對位元組。

## S. log 的遮蔽只認「本次執行」，不認「檔案的宣告」（2026-08-18 發現並修正）

**症狀**：對一個「欄位已被雜湊或加密」的檔案下 `-update`，新值會明文寫進 `-log`。

```sh
csv2 -hash secret -keyfile k.bin -i f.csv -o h.csv -t     # h.csv 的標頭：secret:hmac:d6c8da42
csv2 -update 1:secret 'SUPER SECRET' -i h.csv -o o.csv -log app.log
grep update app.log
# 修正前： update 1:secret: "92f74e54…" -> "SUPER SECRET"      ← 明文
# 修正後： update 1:secret: <redacted> -> <redacted>
```

**它如何被發現**：盲測第 25 回合去查 `-log`，理由是「它是唯一一個會把資料寫進磁碟、卻沒有
任何內容政策記載的功能」，並提問：它是否重新引入了「刻意不提供 `-key`」所要避免的那種暴露。

它發現的是一個**內部不一致**：指令列回顯被主動遮蔽成 `-update 1:4 <value>`，而**兩行之下**
的操作紀錄把同一個字串明文寫出。用它的話說：有東西決定了那個值不該出現，而另一個東西照樣
把它寫了下去。

**查證後發現更糟。** `redactedColumns` 只由 `buildTransform` 依「本次要轉換的欄位」填入。
於是：**放進秘密的那次執行受保護，改動它的那次執行不受保護。** 而後者才是日常操作。

**修法**：新增 `redactColumnsDeclaredByHeader()`，在標頭驗證後、`buildTransform` 之前呼叫。
任何帶有 `:enc:`／`:hash`／`:hmac:` 標記的欄位都進入遮蔽集合。**標頭是檔案自己對「哪些欄位
存放秘密」的陳述**——它比任何單次呼叫都活得久，而且它是唯一可能對「一個不是呼叫者建立的
檔案」說得準的東西。

**刻意保留的部分**：一般欄位的新舊值仍完整記錄。全部遮蔽既安全又毫無價值——一份說不出改了
什麼的稽核軌跡，不是稽核軌跡。T73c 斷言這一點，T73d 則斷言「值確實已寫入檔案」，否則 T73a
可能因為「寫入失敗」而通過。

`-log` 的內容政策先前完全沒有記載，現已補進兩份 README。

## T. 「`-md` 是單向的」在資料不含逗號時不成立（2026-08-18 發現並修正）

**症狀**：把 `-md` 的輸出以 `-so` 加 shell 重導存成 `.csv`，再讀回來——rc=0，而 Markdown
的**分隔列**被當成第 1 筆資料交出來。

```sh
csv2 -r -t -md -i f.csv -so > looks_like.csv
csv2 -r -i looks_like.csv
# |---|---|---|                          ← 分隔列，被當成資料
# |zlib|1.3.2|plain text no commas|
# rc=0
```

**為什麼只在不含逗號時發生**：那份 Markdown 每一行都沒有逗號，於是它是一份合法的「單欄」
CSV——每一行一欄，欄數自然一致，**救了另一個案例的欄數檢查在這裡沒有東西可以察覺**。資料
含逗號時欄數不符，它本來就會大聲失敗。

**於是這條保證在「看起來比較難」的輸入上成立，卻在比較單純的那一種上失效**：任何一張由簡短
純值構成的表格。而它牴觸的是本專案開宗明義的承諾——「其餘一切都必須大聲失敗，而不是靜默
產生一個半正確的檔案」——並且是在一個 csv2 自己產生的檔案上失敗的。

**修法**：解析器在「紀錄恰好一欄、且該欄是一列 Markdown 分隔列」時拒絕，訊息直接指名
Markdown。做法比照既有的 CR-only 偵測（那裡的理由是「診斷成本幾乎為零，少了它代價是一個
下午」）。

**這條拒絕刻意很窄**：真實的單欄 CSV 照常可用（T74d）；「多欄但剛好含有這種值」的檔案完全
不受影響（T74e）——因為在那裡，那個檔案顯然就是 CSV。

## U. 同名欄位以「位置在前者」靜默勝出（2026-08-18 發現並修正）

**症狀**：

```sh
printf 'note,ver,note\nFIRST,1,SECOND\n' > dup.csv
csv2 -update 1:note CHANGED -i dup.csv -o out.csv
csv2 -mid 1,1 -i out.csv
# CHANGED,1,SECOND        ← 改到了第 1 欄，rc=0，什麼都沒說
```

**它如何被發現**：盲測第 27 回合問的是另一件事——`--normalize` 是否也管「欄位名稱」的比對。
答案是不管：名稱以 Swift 的 `String ==` 比較，那是「正規等價」，因此 NFC 的引數找得到 NFD 的
標頭，給不給旗標都一樣；而值是以位元組比較。

那個不對稱本身說得過去（對讀者而言那就是同一個名字），但追查它時浮出一件讀者沒有走到的事：
**如果兩個欄位可以是同一個名字，那一個位址到底指的是哪一個？**

**csv2 回傳第一個。** 而 CSV 並未禁止重複名稱、試算表就會產生。呼叫端要求修改 `note`，拿到的
是兩者之一、由位置決定——**那正是本專案因之而生的那起事故，被那支本該防止它的工具重現了一次。**

**修法**：`resolveColumn` 收集所有匹配；超過一個就拒絕，並指出是哪幾欄，並告知改用欄號。
以欄號定址仍可到達任一欄（T75e）。

**正規等價的比對保留**：NFC 的名稱找得到 NFD 的標頭（T75f），因為那是同一個名字。但這也表示
兩個欄位可以在「位元組並不相同」的情況下相撞（T75g）——因此拒絕這個歧義更要緊，而不是更
不要緊。

## V. `--json` 輸出重複鍵，值在讀者的解析器手上被毀掉（2026-08-18 發現並修正）

```sh
printf 'note,ver,note\nfirst,1,second\n' > dup.csv
csv2 -r --json -i dup.csv
# {"record":1,"line":2,"fields":{"note":"first","ver":"1","note":"second"}}
python3 -c 'import json,sys; print(json.load(sys.stdin)["fields"])'
# {'note': 'second', 'ver': '1'}      ← "first" 消失了，無法取回
```

**這是 U 的同一個根本原因，但透過一扇更糟的門。** U 是「一個位址靜默地挑了一欄」；
V 是「一個值被靜默地**毀掉**」——而且從解析後的物件裡再也無法以任何方式取回。

重複鍵依 RFC 8259 在語法上是合法的（它把「如何解讀」列為未定義），因此 csv2 自己的位元組裡
兩個值都在。**毀掉其中一個的是讀者的解析器**——Python 的 `json` 與 JavaScript 的 `JSON.parse`
都留下最後一個。而 `--json` 存在的全部目的就是「給另一支工具讀」，所以那條路徑是必經的，
不是例外。

因此 README 那句「`fields` 以欄名為鍵，那是不必數欄位就能取出某一欄的方法」，對這種檔案而言
不只是有歧義——**它是假的**：沒有任何工具、任何寫法能取出「第一個 `note`」，因為那個資訊
撐不過這個格式。

**修法**：紀錄形狀的 `--json` 在標頭有重複名稱時拒絕，訊息說出「會發生什麼事」而不只是
「被拒絕」，並指出承載得了它的兩種形狀。**報告形狀不受影響**（T75j）——它每個命中各自成行，
兩個同名欄位就是兩行。欄名不重複的檔案完全不受影響（T75k）。

---

# 第 37 回合驗證的三條 —— 全部已修（2026-08-19）
# Three verified by round 37 -- all fixed (2026-08-19)

**狀態：W、X、Y 三條均已修正，並由 T90a–T90m 與 T91a–T91m 共 26 項斷言涵蓋，macOS 與
aarch64 Linux 兩邊皆通過。本節保留為紀錄：下面的重現步驟仍然有效，只是現在每一條都會以
非零結束、且不動到檔案。**

Status: all three fixed, covered by 26 assertions (T90a-T90m, T91a-T91m),
passing on macOS and in the aarch64 Linux guest. Kept as the record -- the
reproductions below still run, they now exit non-zero and leave the file alone.

修正時發現的兩件事，記在 `plan/plan.md`「每一條寫入捷徑都跳過了慢路徑的驗證」：
**W 的第一版修正是不完整的**——它只涵蓋 `-update` 與 `-delete -cell`，而 `-append` 直接
走過去造成一模一樣的破壞；`-append --in-place` 還需要第二處守衛，因為它不經過 `runEdit`。
以及**修正過程中我自己造出了同一類缺陷的新案例**：讓 `--truncate-partial` 在追加路徑上被
接受，會把不完整的紀錄從解析中丟掉、卻留在檔案裡。

Two things found while fixing, recorded in plan.md: the first fix covered only
two of the four verbs, and honouring `--truncate-partial` on the append path
created a fresh instance of the same defect class.

日期：2026-08-19。來源：README-only 盲測第 36 與第 37 回合。**下列每一條都由本 session
親手重現過**，指令與輸出照抄在下面。

**共同特徵與 2026-08-16 那六條相同：全部在 `rc=0` 下靜默發生。** 而 W 更進一步——它的
稽核紀錄會主動說出一件與事實不符的事。

| # | 回合 | 缺陷 | 類別 | 斷言 |
|---|---|---|---|---|
| Z | 36 | 索引宣稱了一個沒有任何東西推導過的性質；`--verify-index` 為它背書 | **程式** | T79a–T79m |
| AA | 37 | `-si`/`-so` 留住整條串流；而斷言它的 T9 量的是地板 | **程式＋測試** | T9a–T9c |
| W | 37 | `-update` 寫進 `:enc:` 欄 → 整欄永久無法解密，且 log 說 `<redacted>` | **程式（安全相關）** | T90a–T90m |
| X | 37 | `-append --in-place` 不驗證既有檔案，`-append -o` 會驗證 | **程式** | T91a–T91m |
| Y | 37 | EOF 前未閉合的引號：`-append --in-place` 把新紀錄吞進那個欄位 | **程式** | T91c–T91d |

**Z 與 AA 是補記的**（見本檔開頭的規則）。它們當時被直接修掉並只寫進 `plan/plan.md`，
而依這個檔案的規則，它們本來應該在第 36、37 回合當下就落在這裡。

---

## Z. 索引宣稱了一個沒有任何東西推導過的性質（第 36 回合，2026-08-19 修正）

**嚴重度：錯的紀錄號，rc=0，而文件指名用來排除這件事的工具說「index OK」。**
**補記**：當時直接修掉並只寫進 `plan/plan.md`。

索引檔頭帶著 `no_embedded_newlines`，平行搜尋路徑用它斷定「一行就是一筆」。設定它的呼叫點
有三個，其中兩個傳的是常數——一個寫 `spansLines: false`，另一個寫
`rec.line != r.line || false`，而 `r` 是只改了 `number` 的 `rec`，那個比較永遠不可能為真。
**於是 `--build-index` 寫出的每一份索引都宣稱自己有這個性質。**

重現不需要竄改，也不需要特殊檔案——一份引號內含散文的合法 CSV 就夠了：

```sh
python3 -c "
with open('honest.csv','w') as f:
    f.write('id,pkg,note\n')
    for i in range(1,300001):
        v='needle' if i==150000 else 'p%06d'%i
        if i==1000: f.write('%d,%s,\"a note that genuinely\nspans two lines\"\n'%(i,v))
        else:       f.write('%d,%s,\"prose, with a comma %d\"\n'%(i,v,i))
"
csv2 --build-index -i honest.csv       # index built
csv2 --verify-index -i honest.csv      # index OK               rc=0
csv2 -contains needle -i honest.csv    # 150001:2  （宣稱 300001 筆）  rc=0
CSV2_PARALLEL_MIN_BYTES=99999999 csv2 -contains needle -i honest.csv   # 150000:2
python3 -c "import csv;r=csv.reader(open('honest.csv',newline=''));next(r);print(sum(1 for _ in r))"
# 300000                                ← 基準真相
```

**`--verify-index` 漏掉它的原因值得留著**：它檢查格點偏移量與紀錄筆數，而這兩者在這個失敗下
**都完好無損**——在引號欄位裡放一個換行，不會移動任何一筆的起始位元組，也不會改變筆數。變的
只是檔頭裡那個沒有任何東西重新推導過的宣稱，而它恰好就是快路徑真正取用的那一個。

`--no-index` 也不是逃生口：它確實不「寫」sidecar，但平行資格檢查仍然載入了一份，而且從來
沒看過 `o.noIndex`。

**修法**：三個呼叫點由同一個函式回答；`--verify-index` 重新推導那個旗標（只對危險的方向
失敗）；`--no-index` 在該處被遵守；`INDEX_VERSION` 推進到 3，因為磁碟上的 v2 sidecar 帶著
錯誤旗標，而它們的檢查碼、戳記、偏移量全是對的——**只有版本抓得到**。
另外把「索引已記錄跨行」與「沒有索引」兩種拒絕理由分開，因為對前者叫人去 `--build-index`
是無效的建議。詳見 `plan/plan.md`。

---

## AA. `-si`/`-so` 留住整條串流，而斷言它的測試量的是地板（第 37 回合，2026-08-19 修正）

**嚴重度：README 承諾「不整檔緩衝」，而大於記憶體的輸入會讓行程被 OOM 殺掉。**
**補記**：當時直接修掉並只寫進 `plan/plan.md`。

```sh
# 修正前，輸出為零位元組的搜尋
404 MB 進 stdin  →  peak RSS 415 MB   （比值 1.028）
```

兩個獨立的原因，而只有一個在「比大小」時看得見：

1. **輸入端**：`ByteSource.next()` 以 64 KiB 呼叫 `FileHandle.readData`，而讀取迴圈裡沒有
   任何 autoreleasepool。那些 Foundation 物件累積到行程結束，RSS 正比於讀進來的位元組數。
   （**macOS 專屬**——Linux 的 Foundation 沒有 pool、以 ARC 管理 `Data`。）
2. **輸出端**：`emitRecord` 每一筆都**無條件建構**一行 TRACE 訊息，而 `Logger.log` 自己也是
   先組出時間戳與整行、之後才判斷層級。預設門檻是 WARN，因此每筆付兩次字串建構、一個字都
   不會被印出來。

**認出第二項的量測**——同樣的位元組量、二十分之一的紀錄數：

| 輸入 | 紀錄數 | peak RSS |
|---|---|---|
| 79.6 MB | 2,000,002 | 123 MB |
| 90.3 MB | 100,002 | 15.9 MB |

**這一條同時是一個測試缺陷。** T9 全程通過：它的斷言是 `r_big < r_small * 2`，fixture 是
77 KB 與 3.3 MB，而行程與 Foundation 的地板就有 9 MB——一個保留每個位元組的實作在大 fixture
上是 17.7 MB，**仍然小於 9.4 MB 的兩倍，餘裕 6%**。那不是門檻太鬆，是量測被地板淹沒。

**修法**：`Platform.drainingPool`（Darwin 用 pool、其他平台直接執行——寫在 `Platform.swift`，
因為 `autoreleasepool` 在 Linux 的 Swift 上不存在，第一版寫在呼叫點旁邊導致 guest 建置失敗）；
`Logger.log` 的 `message` 改為 `@autoclosure` 且層級判斷排在最前。T9 補上 T9b（兩條大小相差
一倍的串流互相比較，地板抵銷）與 T9c（等位元組、二十分之一紀錄數）。修正後 79／90／181 MB、
10 萬到 400 萬筆，peak RSS 全部是 9.5 MB。

---

## W. `-update` 寫進 `:enc:` 欄位 → 整欄永久無法解密，且 log 說 `<redacted>`

**嚴重度：資料永久遺失，且稽核紀錄具誤導性。** 這是本檔案中最嚴重的一條。

```zsh
head -c 32 /dev/urandom > k.bin
printf 'pkg,ver,secret\nbusybox,1.37.0,s1\nzlib,1.3.2,s2\nzstd,1.5.7,s3\n' > p.csv
csv2 -encrypt secret -keyfile k.bin -i p.csv -o prot.csv -t
# 標頭：pkg,ver,secret:enc:693c4537:d1KibM4UEel69jnnRKOt4g==

csv2 -update 1:secret "newpass" -i prot.csv --in-place -log audit.log
# rc=0
```

檔案現在是：

```
pkg,ver,secret:enc:693c4537:d1KibM4UEel69jnnRKOt4g==
busybox,1.37.0,newpass          ← 明文，躺在一個標記為加密的欄位裡
zlib,1.3.2,g0ineTAQuecnoDuZHm8d/9GvQ6sIm++xk0XWRIps
zstd,1.5.7,Zp8pYnnvKTE35VANU4Fcf69Ebu/fM2A4odrSJC8l
```

```zsh
csv2 -decrypt all -keyfile k.bin -i prot.csv -o back.csv -t
# csv2: record 1, column secret: not a valid encrypted cell
# rc=1
```

**受害的不只是被改的那一筆。** 第 2、3 筆從來沒有被碰過，它們的密文完好無損，但解密在第 1
筆就停住，於是整欄都取不回來。

而這件事在稽核紀錄裡看起來是這樣：

```
INFO  update 1:secret: <redacted> -> <redacted>
```

**遮蔽在此變成了掩蓋。** 遮蔽的規則是「依檔案的宣告」（見上方 2026-08-18 那一條的修法），
而這裡檔案宣告該欄是加密的——所以寫進去的那個**明文**被當成機密遮蔽掉了。日後讀這行 log
的人，會以為那裡發生的是一次正常的加密欄位更新。

`:hmac:` / `:hash` 欄位同樣接受 `-update`，rc=0，明文就留在那裡，而雜湊欄位**連一個會失敗的
驗證都沒有**，因此永遠不會有任何東西發現它。

**修法（已實作）**：四個會寫入原始值的動詞——`-update`、`-delete -cell`、`-insert`、
`-append`——對「檔案宣告為已轉換」的欄位一律拒絕。單格與整列是兩個不同的拒絕，訊息不同；
加密與雜湊的後果不同，訊息與出路也不同（對雜湊欄位說「先解開再改」是做不到的事）。
`-append --in-place` 在 `runAppendFast` 內另有一處守衛，因為它不經過 `runEdit`。
「同一次執行裡轉換並編輯」仍然允許——被加密的就是那個新值。這與 `-decrypt`
「在標記層拒絕、絕不拖到密碼演算法」是同一條原則的另一半。

---

## X. `-append --in-place` 不驗證既有檔案，`-append -o` 會驗證

**嚴重度：產生一個 csv2 自己讀不了的檔案，rc=0。**

```zsh
printf 'pkg,ver,note\nbusybox,1.37.0,core\nzlib,1.3' > b6.csv   # 最後一筆只有 2 欄、無結尾換行
csv2 -append 'zstd,1.5.7,compression' -i b6.csv --in-place
# rc=0

csv2 -r -t -i b6.csv
# csv2: record 2 (line 3) has 2 fields but the header has 3
# rc=1
```

**同一份輸入，換成 `-o` 就被正確拒絕**：

```zsh
csv2 -append 'zstd,1.5.7,compression' -i c6.csv -o c6out.csv
# csv2: record 2 (line 3) has 2 fields but the header has 3
# rc=1
```

同一個動詞、同一份資料、相反的結果，而兩者的差別在 README 裡只是一個 O(1) 的括號註記。
`runAppendFast` 只在格式是 `.csv2` 時呼叫 `checkTornAppend`；`.csv` 缺少結尾換行被視為
「只是不整齊」，而**一筆欄數不足的結尾紀錄根本沒有被檢查**。

**這正是 README「Why this exists」描述的那個事故**——「成功執行、印出改了什麼的清單」——
在這支為了防止它而寫的工具內部重現。

**修法（已實作，且與當初的方向不同）**：原本設想的是「從檔尾讀回一段有界的位元組」。
**那不成立**——讀回一段視窗、解析最後一個換行之後的部分，分不出「半筆」與「一筆含內嵌換行的
完整紀錄」，兩者看起來都是碎片，而答案取決於該紀錄開頭處的引號狀態，那只有從檔案前面解析
才知道。實際做法是：檔案**未以換行結尾時**才完整解析一次。那是唯一「結尾可能只寫了一半」的
狀態，因此正常結尾的檔案仍然是 O(1)，由 T91h 以「那行 O(n) 的 debug 訊息不出現」來斷言。

---

## Y. EOF 前未閉合的引號：`-append --in-place` 把新紀錄吞進那個欄位裡

**嚴重度：追加靜默地沒有發生。**

```zsh
printf 'pkg,ver,note\nbusybox,1.37.0,core\nzlib,1.3.2,"unterminated prose' > e6.csv
csv2 -append 'zstd,1.5.7,compression' -i e6.csv --in-place
# rc=0
```

新的那一筆現在位於那個沒有收尾的引號欄位**內部**——它不是一筆紀錄。讀取時：

```zsh
csv2 -r -t -i e6.csv
# csv2: record 3: the input ends inside a quoted field -- the closing quote is missing.
```

與 X 同一個根本原因（快路徑不驗證），但後果不同：X 產生一個壞檔案，Y 讓一次成功回報的
寫入**實際上沒有發生**。

---

## 附帶：`--truncate-partial` 只做了一半

不是新缺陷，是對既有描述的更正。README 寫的是「丟棄結尾不完整的紀錄」。實測：

| 結尾的樣子 | `--truncate-partial` |
|---|---|
| 未閉合的引號 | **有效**，丟棄該筆，rc=0 |
| 欄數不足的紀錄 | **完全無作用**，訊息與 rc 皆與不給時相同 |

**已定案（2026-08-19）：不擴充這個旗標，改為把文件寫準。** 欄數不足的結尾紀錄「照它所寫的
內容是完整的，只是錯的」——把它歸類為「不完整」，等於讓一個明確的旗標去猜使用者的意圖。
README 現在寫明它丟棄的是「因未閉合引號而在 EOF 處未完成的那一筆」，而欄數不足兩種情況下
都是硬錯誤。另外，`--truncate-partial` 搭配 `-append` 現在會被**拒絕**：追加只會加上位元組，
它移除不了那筆不完整的紀錄，接受它只會讓檔案同時保留半筆、並在其後多出一筆完整的。

（順帶更正一項舊的記載：全域 `CLAUDE.md` 的已知缺陷表說 `--truncate-partial` 完全無作用，
以及 `--include-headers` 的 `0a`／`0b` 未實作。兩者現在都不對——前者對未閉合引號有效，
後者實測輸出 `0a:4` 與 `0b:4`。）

---

# 第 38 回合（2026-08-19）—— 七條，全部親手重現，尚未修
# Round 38 (2026-08-19) -- seven, all reproduced by hand, not yet fixed

**這一回合的盲測仍然不是盲的，而原因值得記下來。** 缺陷表已經從兩個 `CLAUDE.md` 移除並提交，
但受測 agent 仍然逐字引用了它——因為**派出它的那個 session 在啟動時就把那些檔案讀進 context
了**，subagent 繼承的是 context，不是磁碟。全域 `CLAUDE.md` 自己就寫著這件事：「已經在執行中的
session 不會看到這一頁」。

**因此：移除缺陷表只對「新開的 session」有效。要跑一次真正的盲測，必須從一個新 session 派出。**
該回合的 agent 自行重測並推翻了那五條全部，所以下列發現仍然有效；但這個限制本身要記住。

Removing the tables only helps sessions started afterwards: a subagent inherits
its parent's context, not the disk. A genuinely blind round has to be launched
from a fresh session.

| # | 缺陷 | 類別 |
|---|---|---|
| BB | `-log` 在 40 字元截斷新舊值，而 README 寫「完整記錄」 | **程式＋文件（稽核相關）**  — **已修 T92a–T92n** |
| CC | 儲存格層級的錯誤位址是「物理行號」卻標著 `record N`，餵不回 `-get`／`-update` | **程式**  — **已修 T93a–T93h** |
| DD | `-debug=trace` 只回報「被輸出的」紀錄；被排除的一行都沒有 | **程式＋文件**  — **已修 T94a–T94h** |
| EE | 平行路徑不印 `metrics:` 行，而 README 說 `-debug` 包含它 | **程式＋文件**  — **已修 T95a–T95f** |
| FF | README 教的 `-contains` → `-update` 組合會靜默雙重跳脫 | **文件（後果是資料損壞）**  — **已修（文件）T96a–T96e** |
| GG | 名為 `.csv2` 但只有一列標頭的檔案，rc=0 讀出時吞掉一筆；`--json` 的 meta 只是覆述副檔名 | **文件＋缺少能力**  — **已定案並修（文件）T97a–T97g** |
| HH | 中文 README 有兩段被截斷的句子；英文 `-encrypt` 區塊有一句重複 | 文件  — **已修** |
| II | `-update` 把命令列上的非 UTF-8 位元組靜默換成 U+FFFD | **程式（違反核心承諾）**  — **已定案並修 T98a–T98k** |
| JJ | log 的值沒有跳脫，含換行的值可以偽造出一整筆 log 紀錄 | **程式（稽核相關）**  — **已修 T92d–T92h** |

**HH 在第 36 回合就被回報過，我當時沒有修。** 那正是「先寫進這個檔案再修」這條規則要防止的
——一個沒有被寫下來的發現，會在下一輪被重新發現，而中間那段時間它一直是錯的。

---

## BB. `-log` 在 40 字元截斷，而 README 說「完整記錄」

**嚴重度：稽核軌跡不完整，而 rc=0、log 有寫、看起來一切正常。**

README 第 428 行：

> | old and new values in an **ordinary** column | in full; that is the point of an audit trail |

實測：

```sh
python3 -c "print('id,note'); print('1,\"%s\"'%('A'*300))" > lt.csv
csv2 -update 1:note "$(python3 -c 'print("Z"*300)')" -i lt.csv --in-place -log lt.log
grep -o 'update 1:note.*' lt.log
# update 1:note: "AAAA…（40 個）…[+260 more chars]" -> "ZZZZ…（40 個）…[+260 more chars]"
```

兩側都在**第 40 個字元**截斷。`TARGET_PACKAGES.csv` 的 `status_notes`——**這個專案存在的理由
就是那一欄被改壞**——典型長度遠超過 40，因此對那一欄而言，log 保留不下任何可用的舊值。

**已定案並修正（2026-08-19）：不截斷。** 使用者裁決「不應截斷」，理由與這個檔案的存在理由
相同——一份會安靜丟掉資料的稽核軌跡不算稽核軌跡。無界，而超過 **1 MiB** 時發一行 `WARN`
指名大小、並說明 log 仍會完整保留它（否則那個警告會被讀成拒絕）。

**修的順序不能反：先修 JJ 的跳脫，再解除這裡的上限。** 理由見 JJ。
由 T92a–T92n 斷言；詳見 `plan/plan.md`「稽核軌跡不得丟資料」。

---

## CC. 儲存格層級的錯誤位址是物理行號，卻標著 `record N`

**嚴重度：錯誤訊息裡的位址餵不回這支工具，而「位址可以組合」正是它的賣點。**

README 第 249 行：「`N` counts **records, not lines** throughout」。

```sh
printf 'id,val\n編號,值\n1,ok\n2,bad\\qvalue\n' > esc.csv2   # 壞掉的是「資料第 2 筆」
csv2 -r -t -i esc.csv2
# csv2: record 4, field 2: undefined escape sequence \q          ← 4 是物理行號
```

把那個位址拿回來用：

```sh
csv2 -get 4:2 -i fixed.csv2     # csv2: -get: no such record; the file has 2 records   rc=1
csv2 -get 2:2 -i fixed.csv2     # THEBAD                                               rc=0
```

**偏移量恰好等於標頭列數**，因此那是行號。同一支工具的**紀錄層級**錯誤則是對的
（`record 1 (line 3)`，兩個數字都給）。也就是說錯誤通道裡並存兩套編號，而 README 的範例
（`record 3, field 2: undefined escape sequence \q`）示範的正是壞掉的那一套。

---

## DD. `-debug=trace` 只回報「被輸出的」紀錄

**嚴重度：無法回答「為什麼第 N 筆不在我的輸出裡」，而那正是 README 說它要回答的問題。**

README 第 237 行：`-debug=trace  one level lower: every record's selection decision`。

```sh
printf 'pkg,ver\nzlib,1\nzstd,2\nbusybox,3\n' > t.csv
csv2 -contains zlib --filter -i t.csv -debug=trace 2>&1 >/dev/null | grep TRACE
# TRACE select: record 1 line 2 emitted, matched fields [1]
# （第 2、3 筆一行都沒有）
```

**這與本專案自己的原則相矛盾**，而那條原則就寫在 README 的平行路徑那一段：「只回報有趣的
那個情況，會讓沉默變得有歧義」。這裡「讀過但被排除」與「根本沒讀到」（例如 `-mid` 提前停止）
產生**完全相同的證據**：沒有任何一行。

---

## EE. 平行路徑不印 `metrics:` 行

**嚴重度：`peak_rss_bytes` 恰好在「你會想量它」的那種執行上取不到。**

README 第 236 行：`-debug  diagnostics to stderr, including a metrics: line`。

```sh
CSV2_PARALLEL_MIN_BYTES=1000 csv2 -contains pkg299999 -i big.csv2 -debug 2>&1 >/dev/null
# DEBUG parallel: 2 chunks, 10 workers, chunk 4194304 bytes
# DEBUG parallel: 300000 records, 1 matched
# （沒有 metrics: 行）

CSV2_PARALLEL_MIN_BYTES=999999999 csv2 -contains … -debug 2>&1 >/dev/null
# DEBUG single-threaded: …
# DEBUG metrics: read_bytes=… file_bytes=… peak_rss_bytes=…      ← 單執行緒有
```

---

## FF. README 教的 `-contains` → `-update` 組合會靜默雙重跳脫

**嚴重度：對「含換行／TAB／CR／反斜線」的值——也就是這支工具存在的理由——資料被靜默改壞，rc=0。**

```sh
printf 'id,val\n編號,值\n1,X\\nY\\\\Z\n' > u.csv2
csv2 -get 1:2 -i u.csv2 | od -c
# X  \n   Y   \   Z                     ← 儲存的原始位元組

csv2 -contains X -i u.csv2 | cut -f3
# X\nY\\Z                               ← 報告為了「一行一筆」而跳脫（T53 的決定，正確）

V=$(csv2 -contains X -i u.csv2 | cut -f3)
csv2 -update 1:2 "$V" -i u3.csv2 --in-place    # rc=0
csv2 -get 1:2 -i u3.csv2 | od -c
# X   \   n   Y   \   \   Z             ← 跳脫被當成字面，值被改壞
```

**能組合的是「位址」，不是報告裡的那個「值」。** 正確的寫法已經存在——`-contains` 找到位址、
`-get r:c` 取回原始值、`-update` 寫回——但 README 沒有說，而它把 `-contains` → `-update`
當作「尋找與編輯如何組合」的核心示範。

---

## GG. 檔名可以對格式說謊，而讀取信任檔名

**嚴重度：靜默少一筆，rc=0。**

```sh
printf 'pkg,ver,note\nzlib,1.3.2,first\nzstd,1.5.7,second\n' > missing2nd.csv2   # 2 筆資料
csv2 -r --json -i missing2nd.csv2
# {"meta":{"format":"csv2","headers":2,"fields":3}}
# {"record":1,"line":3,"fields":{"pkg":"zstd",…}}
# {"meta":{"records":1,"matched":0}}                ← 只有 1 筆；zlib 被當成第二列標頭吃掉
```

**副檔名宣告格式是設計，不是缺陷**——README 對此有完整的論證。有問題的是它接著說的那句：

> That first line exists precisely so a caller can assert what it is reading（README:327）

**meta 行做不到那件事。** 它印的 `"headers":2` 是「副檔名說了什麼」的覆述，不是對檔案的觀察，
因此任何 `.csv2` 檔案都會得到 `headers:2`，包括這一份。呼叫端拿它斷言，等於拿檔名斷言檔名。

同源的另一半：`-si --headers 1 -so > out.csv2` 會繞過那條轉檔拒絕，以 rc=0 產生一個名為
`.csv2` 的 CSV。值裡有換行時讀回來會**大聲失敗**（正確）；沒有換行時就退化成上面那種靜默少一筆。
README 對 `-md` 明確警告過這條 shell 重導路線，對 CSV 沒有。

**已定案（2026-08-19）：不加偵測，改把文件寫準。** 「一列標題」與「一列資料」在形狀上並無
分別，因此任何偵測器都是猜測——而「由副檔名宣告、絕不偵測」的存在，正是為了把猜測擋在外面。
不對稱維持不變：**寫出**這樣的檔案被拒絕，**讀取**不被拒絕。

README 現在說明 meta 行裡哪些欄位是「數出來的」（`fields`、`records`）、哪些只是「檔名在說話」
（`format`、`headers`），並給出檢查一份「不是你產生的檔案」的做法：`csv2 -head 1 -t`——
兩列標頭加第一筆，第二列裡是標題還是資料，一眼就看得出來。由 T97a–T97g 斷言。

---

## HH. 中文 README 的兩段壞句，與英文的一句重複（第 36 回合已回報，未修）

`README.zh-TW.md` `-encrypt` 條目：

> `-encrypt` 與選取旗標併用原本會在 rc=0 下 標頭一律寫出，給不給 -t 都一樣，搭配選取時亦然。

這是一段缺陷註記被接進功能說明裡的殘骸，中文讀者從這句話得不到任何資訊。

`README.zh-TW.md` `--in-place` 段落：

> 它本來可以從「`--in-place`……以暫存檔加 rename」由 T28c 斷言。

一個中段被刪掉的句子。英文對應處是乾淨的：「Asserted by T28c.」

英文 `-encrypt` 區塊（README:202–206）自身也有問題：**同一段裡把「不論給不給 `-t`，標頭一律
寫出」講了兩次**。在一段與安全有關的說明裡重複，會讓讀者懷疑自己讀錯，而不是更確定——第 37
回合的讀者就明說他因此改為「防禦性地加上 `-t`」。

---

## II. `-update` 把命令列上的非 UTF-8 位元組靜默換成 U+FFFD（2026-08-19，調查 BB 時發現）

**嚴重度：靜默替代，rc=0——而「不做這個替代」是本專案的核心承諾之一。**

```sh
printf 'id,note\n1,ok\n' > nu2.csv
csv2 -update 1:note "$(python3 -c 'import sys; sys.stdout.buffer.write(b"A\xffB")')" \
     -i nu2.csv --in-place
csv2 -get 1:note -i nu2.csv | od -c
# A  ef bf bd  B          ← 存進去的是 U+FFFD，不是 0xFF
```

T8 斷言「非 UTF-8 位元組 round-trip 不被換成 U+FFFD」，而它測的是**讀取**路徑（檔案進、檔案出）。
**寫入路徑上、值來自命令列時，那個保證不成立**：Swift 的 `CommandLine.arguments` 以 UTF-8
解碼 argv 並用替代字元補洞，因此那些位元組在抵達 csv2 自己的程式碼之前就已經沒了。

不是不可修——`CommandLine.unsafeArgv` 拿得到原始位元組——但那是一個決定，不是一行修正：
要嘛保留原始位元組，要嘛在偵測到無效 UTF-8 時拒絕。**目前是第三種：安靜地改掉它。**

由本 session 在調查 BB 的後果時發現，不是盲測 agent 找到的。

---

## JJ. log 的值沒有跳脫：含換行的值可以偽造一整筆紀錄（2026-08-19，調查 BB 時發現）

**嚴重度：稽核紀錄可被它所記錄的資料偽造，rc=0。**

`Logger.redact()` 把值加上引號後直接寫進 log，**沒有經過任何跳脫**。log 是一行一筆的格式，
因此值裡的一個換行就會產生新的一行——而新的那一行的內容完全由值決定：

```sh
printf 'id,note\n1,"harmless"\n' > inj2.csv
csv2 -update 1:note "$(printf 'x"\n2020-01-01T00:00:00+00:00 INFO  nothing happened')" \
     -i inj2.csv --in-place -log inj2.log
cat inj2.log
# …INFO  update 1:note: "harmless" -> "x"
# 2020-01-01T00:00:00+00:00 INFO  nothi…[+11 more chars]"      ← 偽造的紀錄，時間戳由攻擊者選
# …INFO  wrote 1 records, 2 fields, atomic rename OK
```

**40 字元的截斷（BB）沒有擋住這件事，只是把偽造的那一行剪短。** 兩者的關係很重要：
**若只把 BB 的上限移除而不先修 JJ，偽造會從「被剪斷的」變成「完整且可信的」。**

因此修的順序是固定的：**先跳脫，再移除上限。** `reportEscape()` 已經存在，而且正好處理
`\`、TAB、`\n`、`\r` 四個字元——那正是「一筆紀錄一行」所需要的全部。

**已修（2026-08-19）**，與 BB 一起，順序如上。由 T92d–T92h 斷言：含換行的值不會多出一行、
沒有任何一行以那個值試圖偽造的時間戳開頭，而那段文字本身仍然被記錄下來——經過跳脫，
留在它自己那一行裡。

由本 session 在調查 BB 的後果時發現，不是盲測 agent 找到的。

---

# 第一次 Windows 建置（2026-08-19）/ First Windows build (2026-08-19)

`Platform.swift` 的開頭自 2026-08-16 起就寫著：Windows 分支「**已寫出，但從未被編譯或執行過**。
它是移植的起點，不是受支援的平台；在 Windows 上跑出與另外兩者相同的數字之前，本 repo 任何
地方都不該宣稱相反的事。」

2026-08-19 第一次真的去編它，經由 multissh 連到 `MINGW64_NT-10.0-26200`（Swift 6.3.3，
`x86_64-unknown-windows-msvc`）。

| # | 缺陷 | 類別 |
|---|---|---|
| KK | Windows 分支編不過：`GetProcessMemoryInfo` 不在 scope | **程式（平台）**  — **已修** |

## KK. `GetProcessMemoryInfo` 在 Swift 的 WinSDK 裡找不到

```
src\Platform.swift:298:15: error: cannot find 'GetProcessMemoryInfo' in scope
```

**整份原始碼只有這一個錯誤。** 其餘每一行——包含 `PROCESS_MEMORY_COUNTERS` 這個型別本身、
`MoveFileExW`、以及所有 `#if canImport(ucrt)` 分支——都編得過。

原因不是 API 不存在，而是**它不在 Swift 的 WinSDK 模組所匯出的那一組裡**。`GetProcessMemoryInfo`
宣告在 `psapi.h` 並由 `psapi.dll` 匯出；Windows 7 起 kernel32 另外匯出了功能等價的
`K32GetProcessMemoryInfo`，而那一個 Swift 看得見。在該機器上實測：

```swift
import WinSDK
var c = PROCESS_MEMORY_COUNTERS()
c.cb = DWORD(MemoryLayout<PROCESS_MEMORY_COUNTERS>.size)
K32GetProcessMemoryInfo(GetCurrentProcess(), &c, c.cb)   // true
// c.PeakWorkingSetSize == 9129984
```

**這一條之所以值得記在這裡，是因為它證明了那段狀態註記是誠實的。** 那個分支寫了三天，
看起來完全合理，而它一行都沒有編過——只有真的去編，才知道差在哪裡。

## 首次 Windows 執行：17 條失敗，以及它們真正的形狀

修掉 KK 之後 `csv2.exe` 建了起來並跑得動。第一次跑完整套件時有 **17 條失敗**，而它們分成
四群——其中只有一群是 csv2 自己的缺陷。

（此處刻意不寫通過的數量：那個數字每次提交都會變，而 T69 正是為了阻止它被寫進文件而存在。
它剛好在這一段初稿裡抓到了我。）

| # | 症狀 | 真正的原因 | 類別 |
|---|---|---|---|
| LL | `--in-place` 與 `-o` 全部以 `Windows error 5` 失敗 | rename 發生在輸入仍開著的時候 | **程式（平台）**  — **已修** |
| — | T58a/T58b 路徑比對不符 | MSYS2 自動把 POSIX 路徑轉成 Windows 形式 | 測試可攜性 |
| — | T61a/T61c 串流讀到 0 bytes | MSYS 的 FIFO 對原生 Windows 程式不存在 | 測試可攜性 |
| — | T98a–T98g 不拒絕非 UTF-8 參數 | Windows 命令列是 UTF-16，原始位元組看不到 | **平台限制** |

## LL. rename 覆蓋一個「還開著」的檔案，在 Windows 上是 ACCESS_DENIED

```
csv2: cannot rename .../.dc_ip.csv2.csv2tmp.2888 onto .../dc_ip.csv2: Windows error 5
```

`runSelect` 與 `runEdit` 都寫著 `defer { plan.source.close() }`——**而 defer 在函式回傳時才執行**，
那是在 `sink.close()` 完成 rename「之後」。POSIX 允許 rename 覆蓋一個仍被開著的檔案，
**Windows 不允許**。

**這個順序在 macOS 與 Linux 上跑了好幾個月，因為那兩個平台確實不在乎。** 一個平台不在乎的
順序錯誤，在另一個平台上是每一次寫入都失敗。修法是在 rename 之前顯式關閉輸入；defer 保留
作為雙保險（`ByteSource.close` 可安全地被呼叫兩次）。

**單這一條就佔了 17 條失敗中的 10 條。** 修掉後剩下 11 條，而那 11 條沒有一條是 csv2 的缺陷。

## 那三群不是 csv2 的缺陷，但必須被說明

**T58a/T58b**：測試以 `sed "s|$TMP/rm.csv2|vs-sqlite.csv2|"` 正規化訊息裡的路徑。MSYS2 在
呼叫原生 Windows 程式時會自動把 POSIX 路徑轉成 Windows 形式，於是 csv2 印出的是
`C:/Users/...`，而 sed 拿著 POSIX 形式去比對。**修法是讓正規化不依賴路徑形式**——那在每個
平台上都更好。

**T61a/T61c**：測試以 `mkfifo` 建一個具名管線，讓 MSYS 的 shell 餵給原生 Windows 的
`csv2.exe`。**那個 FIFO 對原生程式不存在**，所以什麼都沒送到。這不是串流壞了——串流的性質
由 T9（RSS 上界）在四個平台上斷言。這一條在 Windows 上 SKIP，並說明理由。

**T98a–T98g**：Windows 的命令列是 UTF-16。無效的 UTF-8 位元組在行程啟動之前就已經被
shell／CRT 轉換掉，因此 `CommandLine.unsafeArgv` 裡永遠不會出現它——**csv2 沒有東西可以檢查**。
那個保證在 POSIX 上成立、在 Windows 上無法提供，而**說出這件事比假裝它成立好**。這一條在
Windows 上 SKIP 並說明；README 會標明該保證的適用範圍。

## 結果：四個平台

| 目標 | Triple | 結果 |
|---|---|---|
| macOS | arm64-apple-darwin | 0 失敗、1 略過 |
| Linux guest（QEMU） | aarch64-unknown-linux-gnu | 0 失敗、1 略過 |
| WSL2 | x86_64-unknown-linux-gnu | 0 失敗、1 略過 |
| Windows | x86_64-unknown-windows-msvc | 0 失敗、4 略過 |

Windows 的四個略過各自在略過處指名理由：T47（比對兩個平台，無法從其中之一內部執行）、
T61a／T61c（MSYS 的 FIFO 對原生程式不存在）、T98a–T98g（UTF-16 命令列沒有原始位元組可查）。

**這次驗證的價值不在「多了兩個平台」，而在它證明了兩件本來只能用猜的事**：`Platform.swift`
那段「從未被編譯或執行過」的狀態註記是誠實的（第一次編譯恰好兩個錯誤），以及一個
「在兩個平台上無關緊要的順序」——rename 之前有沒有關掉輸入——在第三個平台上是每一次寫入
都失敗。**那個順序錯誤在 macOS 與 Linux 上存在了好幾個月，而那兩個平台永遠不會說。**

---

# 節點升級暴露的兩條（2026-08-20）/ Two found by the node upgrade (2026-08-20)

`multissh` 的 `helper/upgrade_nodes_csv2.zsh` 會在每個節點上 clone、建置、執行 `install.zsh`，
再以 `command -v csv2` 確認可達。它在 Windows 上回報 `reachable: csv2 0.1.0`——**而那是另一個
執行檔**。

| # | 缺陷 | 類別 |
|---|---|---|
| MM | `install.zsh` 不認得 Windows 的安裝慣例，裝到一個不在 PATH 上的目錄 | **程式（安裝）**  — **已修** |
| NN | 安裝後的驗證以「版本字串」判定身分，而版本字串分不出同版號的兩個建置 | **程式（驗證）**  — **已修** |

## MM. Windows 上 `install.zsh` 裝到了 shell 找不到的地方

`target_dir()` 依序試 `$PREFIX`、`brew --prefix`、Linux 上的 `/usr/local/bin`，最後落到
`$HOME/.local/bin`。**Windows 沒有任何一條適用的分支**，於是它落到
`C:/Users/lowei/.local/bin`——而那不在 PATH 上。

該機器上既有的慣例是：執行檔放 `%LOCALAPPDATA%\csv2\csv2.exe`，由 scoop 的 shim
（`~/scoop/shims/csv2.shim`）指向它，而 `scoop/shims` 在 PATH 上。

```
scoop shim 指向  : C:\Users\lowei\AppData\Local\csv2\csv2.exe
install.zsh 寫到 : C:/Users/lowei/.local/bin/csv2      （與新建置 sha256 相同）
PATH 解析到      : shim → AppData 那一份，8/16 的舊檔
```

**`install.zsh` 本身沒有說謊。** 它印出警告說該目錄不在 PATH 上，並明說「已安裝，但**未以
名稱驗證**」。誤導的是升級腳本自己那行 `command -v csv2 && csv2 --version`——它找到舊的 shim
並回報成功。那一支屬於 multissh，不在此處修，但這裡記下它為什麼會被騙。

## NN. 「同一個版本號」不足以證明「同一個執行檔」

`install.zsh` 已經想到了這個風險，並且有一條專門的檢查：

```
if [[ $FOUND_VERSION != $BUILT_VERSION ]]; then
    die "a fresh shell runs a DIFFERENT csv2: ..."
```

**但它比對的是版本字串。** 兩個都是 `csv2 0.1.0`，於是「跑到的是不是同一個檔案」這個問題，
被一個「答不出這件事」的東西回答了。這與 T69 那些過期數字是同一族的問題，只是方向相反：
那裡的數字會過期，這裡的數字**永遠不會變**——而那正是它分不出東西的原因。

這一條在三個平台上都成立，只是 Windows 的 PATH 順序讓它現形。

---

# 第 39 回合（2026-08-20）—— 半份報告，以及一個關於盲測本身的量測
# Round 39 -- a partial report, and a measurement about blind testing itself

該回合的 agent 在第 4 項任務中途因 API 連線中斷而終止，接續後誠實地回報「完成 1–3、
第 4 項只跑了一個 setup 指令、5 與 6 未開始」，並且**沒有補完任何它沒有實際觀察到的東西**。
一份誠實的半份報告仍然找到四條。

## 最重要的結果不是缺陷，是那個污染量測

我在 prompt 最前面要求它先回答：在跑任何指令之前，它的 context 裡有沒有那張缺陷表。

**它逐字引用了那張表，兩個檔案都引到**——而那張表**已經從磁碟移除並提交**：

```
磁碟現況：global CLAUDE.md    0 筆匹配
          project CLAUDE.md   0 筆匹配
agent 收到：兩份的完整五列表，逐字
```

**因此「回合必須從全新 session 派出」不再是推論，是量出來的。** subagent 收到的是**母 session
啟動時**的 CLAUDE.md 快照，而不是磁碟上的內容。從一個已經在跑的 session 派出的盲測，會被
餵進該 session 啟動當下的所有指令檔——**包括那些之後才被刪掉的東西**。

該 agent 自己指出了這件事最要命的地方：**第 4 項任務（金鑰指紋不符）正是那張表最會污染的
一項**，因為表上有一列就是關於 `-encrypt` 丟失 `:enc` marker。它拒絕在那個狀態下給出結論。

| # | 缺陷 | 類別 |
|---|---|---|
| OO | README 否認 `-contains` 會截斷，而它會 | **文件（且它建議的 `\| cut -f3` 因此交出被截斷的值）**  — **已修** |
| PP | 狀態表把 `install.zsh` 列在「Does not yet」，而下方整段在描述它的行為 | 文件  — **已修** |
| QQ | 「錯誤裡的紀錄號是可以拿來用的位址」——對它所舉的那個**解析錯誤**範例不成立 | 文件（**我今天寫的**）  — **已修** |
| RR | `-insert` 可重複、且索引指向輸入，README 從未提及；批次與逐次靜默分歧 | 文件  — **已修** |
| SS | `--physical` 的輸出樣貌從未展示；沒有「A1 → record:field」的反向查找 | 文件  — **已修** |

## OO. README 說那個 `…` 是排版加的，而它是 csv2 加的

README:290 —— 「the long values are cut short here with `…` for the page, **not by csv2**」

```sh
csv2 -contains "busybox ash cannot parse it" -i TARGET_PACKAGES.csv
# …relying on the #!/usr/bin/env zsh she…[+63 more chars]
```

**是 csv2 截的。** 而它截得很誠實——有 `[+63 more chars]` 標記，不是靜默——所以這是文件缺陷
不是程式缺陷。但那句話存在的唯一目的，就是要讀者不要擔心截斷，而它是假的。

**後果不只是一句話錯**：README 在「For many values at once」推薦
`csv2 -contains busybox -i pkgs.csv | cut -f3`，而那條管線對夠長的值會交出「被截斷、尾巴還
黏著 `[+N more chars]`」的東西——**而長的引號散文正是這支工具存在的理由**。

## PP. 「Does not yet」欄裡列著一個已經能用的東西

狀態表：`| RFC 4180 parsing… | shipping in the rootfs, install.zsh (phase 7) |`

而同一份 README 在下面幾行有一整段描述 `install.zsh` 在三個平台上各裝到哪裡。**兩者只能留
一個。** 那一段是 2026-08-20 加的，加的時候沒有回頭改狀態表——**新增文字沒有讓舊文字失效，
是這一天第二次發生**（第一次是 plan.md 第 7 階段那個「被沒有 Windows build 擋住」）。

## QQ. 那句話是我今天寫的，而它用錯了範例

CC 修好之後我在 README 加上：

> **The record number in an error is an address you can use.** Feed it straight back to `-get`
> or `-update`: a message reading `record 1 (line 3), field 2` means `csv2 -get 1:2`.

而我舉的那個訊息是**解析錯誤**：

```sh
csv2 -r -i bad.csv2      # csv2: record 1 (line 3), field 2: undefined escape sequence \q
csv2 -get 1:2 -i bad.csv2 # 同一個解析錯誤 —— 讀不了的檔案，任何動詞都動不了
```

**位址本身是對的**（它確實指到那一格），錯的是「可以直接餵回去」這個承諾用一個
「檔案根本讀不了」的情況當示範。照字面做的讀者會得出「工具壞了」的結論——而工具沒壞。

## RR. `-insert` 可以重複，而兩種寫法給出不同的檔案

```sh
# 批次：一次跑
csv2 -insert 2 A -insert 4 B -insert 5 C -i f.csv --in-place
# 1,r1 2,A 3,r2 4,r3 5,B 6,r4 7,C 8,r5

# 逐次：三次跑
csv2 -insert 2 A -i f.csv --in-place; csv2 -insert 4 B …; csv2 -insert 5 C …
# 1,r1 2,A 3,r2 4,B 5,C 6,r3 7,r4 8,r5
```

**相同參數、都是 rc=0、檔案不同。**

**程式是對的**：T27 早已定案「所有索引指向輸入，全部收集完一次套用」，批次那個語意就是那個
決定。**錯的是 README 只寫了單數的 `-insert N ROW`**——讀者無從知道它可以重複，也就無從知道
自己選了哪一種語意。該回合的 agent 因此把整個任務 3 當成試誤在做，還額外發現「同一個 N 的
多次插入保持命令列順序」與「`-insert` 與 `-append` 可以同時出現」，兩者同樣沒有記載。

順帶：`-insert 6` 在 5 筆的檔案上（批次）被拒絕，而逐次做到第三步時它是合法的——因為那時
檔案已經有 7 筆。同一組數字，分組方式不同就一個失敗一個成功。

## SS. `--physical` 印出來長什麼樣，從來沒有人寫過

`--a1` 有範例（`1:1 [A2]`），`--physical` 只有一句說明。兩者併用的實際輸出是
`13:6@L14 [F14]`，而那個 `@L` 記號要執行過才知道。

另外：bug 回報給的是 `F14`，而**沒有任何動詞能把 `F14` 變回 `13:6`**。`--a1` 只能為
「你已經靠內容找到的儲存格」加註座標——對「我只有座標」這個情境是循環的。換算規則從
`--a1` 那一段推導得出來，但 README 從未把它寫成規則。

---

# 第 40 回合（2026-08-20）—— 由一個真正的新 session 執行
# Round 40 -- run from a genuinely fresh session

**對照組成立。** 該 session 回報「沒有拿到任何缺陷表」——開新 session 確實關掉了第 39 回合
那個洩漏。但它同時指出**洩漏沒有全關**：`CLAUDE.md` 仍然把介面交給它（`csv2 -r -i`、
`-contains`、`-mid`、`-update … --in-place`、`--json`，以及若干行為宣稱）。那不是過期問題，
是那份檔案本來就該有的內容——它存在的目的就是叫 agent 用 csv2。

**所以：新 session 只修好「過期」那一半，修不好「盲測本來就不夠盲」那一半。**

| # | 缺陷 | 類別 |
|---|---|---|
| TT | `:enc:` 的指紋每次執行都不同，而 README 說指紋「identify which key」 | **文件（安全相關）**  — **已修** |
| UU | `-decrypt` 成功時不記錄金鑰指紋，而 README 的表承諾會記 | **程式（稽核相關）**  — **已修** |

## TT. 同一把金鑰，七個指紋

README:498 —— 「the keyfile **path**, and the key fingerprint | yes — they **identify which
key**, not what it is」

```sh
for i in 1 2 3; do csv2 -encrypt secret -keyfile kA.bin -i s.csv -o e$i.csv -t; head -1 e$i.csv; done
# pkg,secret:enc:d88cdbf1:...
# pkg,secret:enc:e16b394a:...
# pkg,secret:enc:869e54ce:...
```

**三次執行、同一把金鑰、三個指紋。** 它由金鑰**與 salt** 導出，而 salt 每次執行都不同。
對照 `-hash`：

```sh
for i in 1 2 3; do csv2 -hash secret -keyfile kA.bin ... ; done   # 三次都是 secret:hmac:9acc9081
csv2 -hash secret -keyfile kB.bin ...                             # 換金鑰才變：46eabf42
```

**`:hmac:` 是每把金鑰穩定的，`:enc:` 是每次執行都變的**，而 README 用同一句話描述兩者。

**這一條的後果不是理論的。** 該回合的 agent 明白寫下：他在第一次拒絕時把「keyB 的指紋是
81f52c56」記成了一個可以帶到下一個檔案的事實。**那不是關於 keyB 的事實。** 若他把它填進工單、
再拿去比對第二個加密檔，會對同一把金鑰得到不符，並據此判定「金鑰又換了」。

**機制本身是對的**：拒絕時做的是「同一個檔案內」的比較，而那個比較是有效的。錯的是描述——
它讓一個「檔案內有效」的東西看起來像「跨檔案可攜」。

**已定案（2026-08-20）：程式不動，改文件。** 程式碼給了答案：`fingerprint()` 取的是
**推導後金鑰**的 SHA-256 前四位元組，而 `-hash` 以固定 salt（`csv2-hash`）推導、`-encrypt`
每次抽新的 16 bytes salt 並存進標記。**因此那個指紋一直都在正確地識別「推導後的金鑰」**，
而加密的推導後金鑰依設計就是每個檔案一把——那正是解密能以存下的 salt 重新推導的原因。

錯的是那句描述：它用同一句話涵蓋兩種意思不同的指紋。兩份 README 現在分開說明，並明寫
「不要把 `:enc:` 的指紋帶到另一個檔案」。

## UU. 成功的 `-decrypt` 不留下它用了哪一把金鑰

```sh
csv2 -decrypt all -keyfile kA.bin -i e1.csv -o back.csv -t -log d.log    # rc=0
cat d.log
# 2026-08-20T... INFO  csv2 -decrypt all -keyfile kA.bin -i e1.csv -o back.csv -t -log d.log
```

**只有那行 invocation。** 而 `-encrypt` 與 `-hash` 都會記錄指紋：

```
INFO  encrypting columns purpose with key kA.bin (fingerprint a32e19bc)
INFO  hashing columns with a key from kA.bin (fingerprint e7998971)
```

README 的稽核表承諾「the keyfile **path**, and the key fingerprint | yes」，沒有為 `-decrypt`
開例外。而在稽核的意義上，**「誰用哪一把金鑰把這一欄解開了」正是最該留下的那一筆**——
加密是把資料鎖上，解密是把它拿出來。

## 第 40 回合的其餘八條（2026-08-20）

該回合的第 4 類是空的——**「工具沒有壞。三項任務都沒有找到任何程式缺陷。」** 八條全是文件，
而其中一條是 csv2 自己的訊息在誤導。

| # | 缺陷 | 類別 |
|---|---|---|
| VV | `CSV2_PRETTY_MAX_BYTES` 的拒絕訊息說「未對齊的形式呈現結果完全相同」——對 Markdown 為真，對終端機為假，而訊息出現在終端機 | **訊息（誤導）**  — **已修** |
| WW | **沒有任何方法可以量出顯示寬度**——`-debug` 報告每一個數字，就是不報那一個 | **缺少能力**  — **已修** |
| XX | 文件說 `--pretty` 依 UAX #11 對齊；實作其實做了 grapheme clustering 與 emoji presentation，**比文件說的更好** | 文件（低估了正確的程式）  — **已修** |
| YY | `-get` 不在旗標參考區塊裡（散文出現 14 次，區塊 0 次） | 文件  — **已修** |
| ZZ | `-md` 對 `.csv2` 會輸出 `pkg<br>套件`，而 `br>` 在兩份 README 裡出現 0 次；`--zh`／`--en` 這條出路也沒寫 | 文件  — **已修** |
| AB | 沒有記載「不分大小寫搜尋」的做法；可擴展的答案（`--json` 後自行折疊）每一塊都有記載，卻從未被指向這個問題 | 文件  — **已修** |
| AC | `--normalize` 是否也正規化「搜尋字串」未記載（實測：會） | 文件  — **已修** |
| AD | 錯誤金鑰的訊息指向 `mssh-keygen`，而「salt 被改壞、金鑰正確」會得到同一句話 | 訊息  — **已修** |

## WW 是其中最要命的一條，而它要命的方式值得寫下來

該 agent 的原話：

> **這是我找到最要命的缺口：那個缺失的量測，差點讓我對正確的程式碼提出兩份不實的缺陷報告。**

README 指名「顯示寬度」是第四個數字、是 `--pretty` 所依據的東西，然後**不提供任何觀察它的
方法**——`-debug` 報 `read_bytes`、`file_bytes`、`peak_rss_bytes`、`fields`、`records`，
唯獨不報那一個。於是他自己造了量測工具，**造錯了兩次**，才與 csv2 的答案一致。

**一個宣稱了某個性質、卻不給你量它的工具，會把「驗證」變成「造一個你自己的實作再比對」**
——而那個自造的實作出錯時，錯的看起來會是被測的那一方。這與本專案一路在修的東西是同一族：
**能不能區分，比宣稱得對不對更根本。**

## XX：文件低估了正確的程式，而那同樣是缺陷

README 說 `--pretty` 依 **UAX #11** 對齊。實測：天真的「逐 code point 查 UAX #11」在九個
測試值裡錯三個（`⚠️` 得 1、`👨‍👩‍👧` 得 6、`👍🏽` 得 4），而 **csv2 九個全對**——它做的是
grapheme clustering 加 emoji presentation，不只是 UAX #11。

**這一條的方向是反的：程式比文件承諾的更好。** 但它仍然是缺陷——任何想重新實作或驗證它的
人，會照著文件寫出一個較差的東西，然後認為 csv2 錯了。該 agent 差點就是這樣。

## VV：那句話在 Markdown 裡為真，而它印在終端機上

```
csv2: … drop --pretty (the unaligned form renders identically) …
```

```
未對齊： |pkg<br>套件|note<br>說明|
         |zlib|short|
對齊：   | pkg<br>套件 | note<br>說明            |
         | zlib        | short                   |
```

Markdown 算出來是同一張表，**終端機裡不是**。而使用者讀到這則訊息的地方，正是終端機。

---

# 第 41 回合(2026-08-20)—— 兩次執行環境失敗,以及它們照樣抓到的東西
# Round 41 -- two harness failures, and what got caught anyway

前兩次嘗試都沒有跑起來,而**兩次的原因都在我這邊,不在 csv2**:

| 嘗試 | 失敗原因 |
|---|---|
| `claude -p`(無旗標) | 幾乎沒有工具權限——`ls`／`pwd`／`which`／`cat` 通過,連 `csv2 --version` 都被擋 |
| `claude -p --allowedTools Bash Read Write "<prompt>"` | `--allowedTools` 是**變參**,把整個 prompt 當成工具名稱吃掉,於是沒有 prompt 留下 |

正確形式:**prompt 走 stdin、`--allowedTools` 用單一逗號清單**。

**第一次那個受測者的處理值得記住。** 它一個 csv2 指令都沒跑成,而它明說:

> 「第 4 類是空的,**而這個空是毫無證據價值的**。程式從未被執行。不要把這一輪記成
> 『沒有找到工具缺陷』,要記成『工具從未被執行』。」

那正是本專案一路在要求的那種區分——**「沒找到」與「沒找」不是同一件事**,而它自己標明了
是哪一種。

## 而它只靠讀那兩份 README,就抓到三條我今天自己造成的疏漏

| # | 缺陷 | 成因 |
|---|---|---|
| AE | 中文版指紋表格仍說「標識哪一把金鑰」,而同一頁下方說那對 `:enc:` 不成立 | 我的腳本中途 assert 失敗、整份未寫入,重試時只補了一半  — **已修** |
| AF | 中文版狀態表仍把 `install.zsh` 列在「尚未」欄,而下方整段描述它的行為 | 我只改了英文版  — **已修** |
| AG | 中文版的錯誤訊息範例被截斷,少了「合法跳脫序列有哪些」那一半 | 我只改了英文版  — **已修** |

**三條都是同一個模式:我修英文版、把中文版留在後面。** 而 AE 更精確地說是另一種:
**一個 Python 腳本在中途 assert 失敗,整份編輯都沒有寫入,而我重試時只重現了其中一部分**
——我沒有回去確認前面那幾處是否還在。

那個模式與這棵樹上的其他缺陷同形:**一次「部分成功」看起來與「完全成功」沒有分別。**
腳本印出了「zh fixes applied」,而其中一項根本沒有發生。

**做法上的結論**:多步驟的編輯腳本要嘛全做要嘛全不做,而**失敗之後的重試必須從頭再跑一次
完整的腳本**,不能只補「我記得還沒做的那幾項」。

---

## 第三次嘗試被中止,而它的產物仍然是一次量測

第三次 `claude -p` 跑起來了,做完任務 1、深入到任務 2,然後被中止——交出的報告只有
15 bytes:`Execution error`。**但它在 scratchpad 裡留下 31 個檔案**,其中包含兩組可以
直接比對的輸出。那些檔案本身就是量測,不需要它的敘述。

比對的結果是一條真的:

```
fast.txt == slow.txt == ni.txt     一致
i3.out   == n3.out                 一致
i4.out   != n4.out                 *** 不一致 ***
```

**我沒有採信它,我自己從頭重現了一次。** 以下每一個數字都是我這邊跑出來的。

### 那一個位元組

`b4.csv` 與 `big.csv` **只差一個位元組**:offset 11015957,空白(0o40)改成換行(0o12)。
而那個位置落在引號內:

```
…,"Two project⏎fixes were needed. (1) configure hardcoded Apple libtool…
```

引號內的換行是資料,不是紀錄邊界。所以正確答案是 **41140 筆**,而:

| 路徑 | 紀錄總數 | 對不對 |
|---|---|---|
| `--no-index`(循序) | 41140 | ✅ |
| 有索引(平行) | **41141** | ❌ |

從第 23511 筆之後,**每一個印出來的紀錄編號都差一**,rc=0,沒有任何一句抱怨。

### 錯的不是索引建立器

我先懷疑建立器沒看見那個換行。**不是。** 對改過的檔案重新 `--build-index`:

```
wrote index t.csv.index: 41140 records, stride 256, 161 entries
DEBUG single-threaded: .csv whose index records a record spanning lines;
      a record number is not a line number here
```

它看見了,而且正確地讓平行路徑退場。**建立器是對的。**

### 錯的是那個戳記,而它已經被記在 Z

解出 `b4.csv.index` 的檔頭,對照檔案本身:

```
index: version=3 flags=1 (no_embedded_newlines=True) mtimeSec=1787183882 mtimeNsec=391472534
file :          size=22026798                        mtimeSec=1787183882 mtimeNsec=391472534
```

**size 相同、mtime 相同到奈秒,而內容不同。** 戳記無從分辨,於是那個
`no_embedded_newlines=True` 被採信,平行路徑在引號中間切開檔案。

這正是 **Z** 記的那件事(`cp -p`／`rsync -t`／`tar -p` 都保留 mtime)。機制上不是新缺陷。
**新的是它現在可以隨時重現**——在此之前 Z 只是一段推論,沒有人真的造出那個檔案。上面
那一個位元組的做法就是。

### 文件指定的補救有效

```
$ csv2 --verify-index -i b4.csv
index MISMATCH: no_embedded_newlines: index says the file has none, but record 20575 spans lines
csv2: index beside b4.csv does not describe the file
rc=1
```

**指名了紀錄編號,rc=1。** README 說 `--verify-index` 是那個 O(n) 的證明,而它確實是。

## AH. 索引被採信的那一次,log 一個字都不說(2026-08-20 修正)

上面那次靜默給出錯誤答案的執行,**完整的 `-debug` log 是這四行**:

```
INFO  csv2 -contains libcurl -i b4.csv -debug
DEBUG parallel: 6 chunks, 10 workers, chunk 4194304 bytes
DEBUG parallel: 41141 records, 7480 matched
DEBUG metrics: read_bytes=22026798 file_bytes=22026798 peak_rss_bytes=55885824
```

「index」出現 **0 次**。

而每一條**拒絕**平行的路徑都會指名索引並說明理由:

```
DEBUG single-threaded: .csv with no index proving one record per line; build one with --build-index
DEBUG single-threaded: .csv whose index records a record spanning lines; …
DEBUG single-threaded: --no-index, and a .csv needs an index to prove one record per line
```

**這個不對稱正好反了。** `-debug` 能告訴你索引為什麼**沒被用**,卻永遠不告訴你它
**被用了**、用的是哪一個 sidecar。而依 Z,採信索引的那條路徑是**唯一可能靜默給出錯誤
答案**的一條——最需要留下痕跡的那一次,留下的最少。

一個操作者拿到上面那四行,沒有任何辦法看出這次結果依賴了一個他從未檢查過的檔案。

**已修**:平行路徑採信索引時,DEBUG 說出 sidecar 的路徑、它宣告的 `no_embedded_newlines`,
以及那個足以推翻它的 `--verify-index`。由 **T101** 斷言。

那行 log 放在 `runParallelSearch` 裡唯一的使用點,**不是**放在 `parallelDeclineReason`。
第一版放在後者,結果印了兩次——它是純查詢,一次執行會被問不只一次,而讀 log 的人會以為
查了兩個 sidecar。

**T101 的 fixture 換過一次位置,而換的理由值得記下來。** 偏移**不是**從跨行那一筆開始:
區塊內部的解析器正確處理引號,因此第一個區塊連同跨行那一筆全部編號正確。假的
`no_embedded_newlines` 弄壞的是「之後每一個區塊」的 `firstRecord`——那是以「到該位移為止
有幾個換行」推算的。於是編號從**跨行紀錄之後的第一個區塊邊界**才開始出錯(8 KiB 區塊下實測
為第 158 筆)。第一版把 needle 放在第 150 筆,早了一個區塊,**在缺陷完整存在的情況下照樣
通過**——與 T79 當年那個 fixture 是同一個陷阱的不同成因。

**負向對照**:把 `src/Parallel.swift` 的修正 stash 掉重建,T101d/e/f 立刻失敗。而 T101b/c
也失敗——沒有那行 log,測試連自己走在哪一個分支都判斷不了,於是大聲失敗而不是悄悄通過。
那本身就是這條 log 存在的理由。

**而 T101 的第一版在 guest 裡失敗了,原因值得單獨記。** macOS 上 `touch -r` 把 mtime 還原
到奈秒,於是那次同大小改寫溜過了戳記,測試走「被採信」那個分支。aarch64 guest 裡的 busybox
`touch -r` 只保留整秒,同樣的構造在那裡被抓住,測試走了另一個分支——而我在那個分支斷言
`--verify-index` 會**成功**,理由是「被拒絕的索引會被重建」。

**它不會。** 忽略一份過期索引,就只是讓它留在原地;磁碟上那份 sidecar 依然不描述這個檔案,
於是 `--verify-index` 依然(正確地)說不符。這條斷言現在不分支了:**不論 O(1) 戳記有沒有
察覺,O(n) 證明都必須指出不符。**

兩件事因此變得明確:

1. **Z 的可利用性取決於保留 mtime 的那個工具,而不取決於 csv2。** `cp -p` 與 `rsync -t`
   保留的比 busybox `touch -r` 多。缺口在兩個平台上都是真的,只是這個 fixture 只能在工具
   配合的地方把它演示出來。
2. **macOS 從未走到那個分支,所以那個錯誤只可能在 guest 裡浮現。** 這正是「Linux 驗證必須
   開 VM」那條規則今天的具體回報:一條在本機四平台裡有三個都測不到的斷言錯誤。

The asymmetry runs the wrong way: `-debug` explains why an index was *not*
used, and says nothing when one *was*. By Z, the index-trusting path is the
only one that can be silently wrong -- so the run that most needs a trace
leaves the least. An operator holding those four lines has no way to tell the
answer rested on a sidecar they never checked.
---

## AI. 稽核軌跡可以被偽造,而修法早就存在、只是沒有套到這一行(2026-08-20 修正)

`-log` 寫進去的第一行是「這次是怎麼被呼叫的」,而它是**每一次執行都會寫**的一行。
那一行沒有跳脫。於是:

```console
$ csv2 -contains $'needle\n2026-01-01T00:00:00+00:00 INFO  csv2 -delete everything' \
       -i s.csv -log L2.txt
$ cat L2.txt
2026-08-20T08:34:52.967+08:00 INFO  csv2 -contains needle
2026-01-01T00:00:00+00:00 INFO  csv2 -delete everything -i s.csv -log L2.txt
```

**第二行整行都是輸入決定的,包含它自己的時間戳。** 稽核軌跡裡因此有一筆
`-delete everything`,發生在一月一日,而那件事從來沒有發生過。rc=0。

### 這正是 README 說已經修好的那個缺陷

> 「**一筆是一行,而值會被跳脫以維持這一點。** 值裡的換行、TAB、CR 或反斜線寫成
> `\n`、`\t`、`\r`、`\\`。沒有這個,一個含換行的值會開啟新的一行,而那一行的全部內容
> 由那個值決定——一筆偽造的紀錄,帶著它自己選的時間戳,寫在稽核軌跡裡,rc=0。」

一字不差,就是上面發生的事。**修正只套在「值」上,沒有套到「呼叫」那一行。**

而兩者的暴露面不同,且較大的那個沒被修到:`sanitizedCommandLine` 只替換
`-update`／`-insert`／`-append` 的值,其餘引數原樣接上;而值的路徑需要一次編輯,
**這一行只需要 `-contains`**——連對資料的寫入權限都不需要。

### 又是「兩個呼叫點,只修了一個」

與 T79 那條(`no_embedded_newlines` 由三個呼叫點設定、兩個傳常數)、以及 AH 那條
(拒絕的路徑都說話、採信的那條不說)是同一個形狀:**一條規則被建立起來,卻沒有被套到
它適用的每一個地方**,而沒套到的那個地方沒有任何東西會指出來。

### 不在此次修正範圍內的一件事

引數裡的**空白**同樣讓那一行無法被可靠地重新剖析(`-contains "a b"` 與
`-contains a b` 在 log 裡看起來一樣)。那是「歧義」,不是「偽造」——它產生不了一筆
額外的紀錄。這裡要守住的保證是「一筆是一行、而且沒有人能憑輸入寫出一整筆」,
先把那個補上;引號化是另一個決定,需要先想清楚要不要讓那一行變成可以貼回 shell 執行的
東西(那有它自己的風險)。

The audit trail could be forged, and the fix already existed -- it had simply
never been applied to this line. The invocation record, written on EVERY run,
was not escaped, so a newline in any argument opened a second line whose entire
content, including its timestamp, came from the input. That is verbatim the
failure the README describes as fixed; the fix was applied to values only. The
exposure is the larger of the two: values need an edit, this needs only
-contains.
---

## AJ. 同一個偽造,從錯誤訊息那條路照樣成立——而它還打破了第二個保證(2026-08-20 修正)

修好 AI(呼叫那一行)之後,同一個構造換一條路仍然有效:

```console
$ csv2 -update $'1:1\n2026-01-01T00:00:00+00:00 INFO  forged' 'x' -i u2.csv --in-place -log U2.log
$ cat U2.log
2026-08-20T08:40:13.910+08:00 INFO  csv2 -update 1:1\n2026-01-01T00:00:00+00:00 INFO  forged <value> …
2026-08-20T08:40:13.911+08:00 ERROR no column named "1
2026-01-01T00:00:00+00:00 INFO  forged"; the columns are: a, b
```

第一行(AI 已修)是**一行**;第二行不是。錯誤訊息把那個欄名原樣插進去,於是 log 裡多出
第三行,而那一行同樣是一筆完整、帶著自己時間戳的偽造 INFO 紀錄。

**訊息文字進入 log 的路徑有兩條,AI 只修了其中一條。** 又是同一個形狀。

### 而它同時打破了 stderr 那個保證

README 說:

> 「錯誤輸出到 stderr,**恰好兩行**,英文在前、中文在後。」

實際輸出是四行:

```
csv2: no column named "1
2026-01-01T00:00:00+00:00 INFO  forged"; the columns are: a, b
csv2：沒有名為「1
2026-01-01T00:00:00+00:00 INFO  forged」的欄位；本檔案的欄位是：a, b
```

**一個依「兩行」去讀 stderr 的腳本,會把偽造出來的那一行當成錯誤訊息的一部分。**
這條缺陷因此同時使兩份文件宣稱為假,而兩者都是本專案明確承諾過的介面。

### 修在哪一層

修在 `Logger.log` / `logToFileOnly` 建行的那一點,以及 `main.swift` 直接寫 stderr 的
那兩行錯誤。理由是它涵蓋現在與**日後**每一個訊息:任何一則把輸入插進去的訊息都自動
受保護,而不必每加一則訊息就記得跳脫一次——AI 與 AJ 合起來說明的正是「靠記得」行不通。

先確認過沒有任何 log 訊息是刻意帶換行的(唯二兩處 `\n` 是行尾本身),因此在這一層跳脫
不會破壞任何既有輸出。

The same forgery works through the error-message path, which AI did not touch:
text reaches the log by two routes and only one was fixed. It also falsifies a
second documented guarantee -- errors on stderr are promised as exactly two
lines, English then Chinese, and this produces four. Fixed at the line-building
point in Logger and at the two direct stderr writes, because that covers every
message present and future rather than relying on each new one remembering.

### 而修好 AJ 之後,AI 的修法就變成了缺陷

把跳脫放進 `Logger` 的建行處之後,`sanitizedCommandLine`(AI 的修法)與 `redact()` 各自
那一次跳脫就變成第二次:

```
INFO  csv2 -update 1:1\\n2026-01-01T00:00:00+00:00 INFO  forged <value> …
```

`\n` 變成 `\\n`——**那個值再也還原不回去了**。抓到它的是既有的 T92g,而不是我。

**兩個各自都正確的修正,合起來是錯的。** 這與這棵樹上其他缺陷是同一個形狀的反面:那些是
「一條規則沒有被套到所有地方」,這一個是「一條規則被套了兩次」。兩者的共同根源相同——
**規則的施行點沒有被指定成唯一的一個**。

現在它是唯一的一個:`Logger.log` / `logToFileOnly` 建行處,加上 `main.swift` 直接寫 stderr
的兩處。`Ops.swift` 裡那兩次 `reportEscape` 不在此列,它們餵的是「報告」那條 TAB 分隔的
輸出串流,不是 log。由 **T102f** 守住「恰好一次」。

Fixing AJ turned AI's fix into a defect: with escaping centralised at the
line-building point, the earlier per-argument and per-value escapes became a
second pass, and `\n` became `\\n` -- a value that no longer round-trips. Two
fixes, each right alone, wrong together. The existing T92g caught it. The shape
is the mirror image of the others here: not a rule missed in one place, but a
rule applied twice, and the same root cause -- no single designated point of
enforcement. There is one now, and T102f holds it.
---

## AK. 註解寫「一律追加」,而程式做的是「開檔時 seek 一次」(2026-08-20 修正)

八個行程各跑 25 次,同時寫同一個 `-log` 檔:

```console
$ for i in {1..8}; do ( repeat 25 csv2 -contains 1 -i c.csv -log shared.log ) & done; wait
expected 200 lines, got: 98
malformed lines (not starting with a timestamp): 0
```

**一半以上的紀錄消失了,而且沒有一行是壞掉的。** 不是交錯亂碼,是**寫入互相覆蓋**:
每一次執行都 rc=0,每一次都「成功」寫了 log。

成因在 `Logger.openLog`:

```swift
// Append, never truncate: overwriting defeats the only purpose the
// file has, which is being read later.
// 一律追加，絕不覆寫
if let h = FileHandle(forWritingAtPath: path) {
    h.seekToEndOfFile()
```

`seekToEndOfFile()` 是「**開檔的那一刻**跳到尾端」,不是 `O_APPEND`。單一行程下兩者
沒有差別;有第二個行程在中間追加時,這個行程仍然寫在它開檔時記下的那個位移上,直接
蓋掉別人的紀錄。

**註解說的是意圖,程式做的是另一件事,而兩者在單行程下無法區分。** 這與本專案其他缺陷
同形:一個名字或一句註解宣告了某個性質,而沒有任何東西推導過它——T79 的
`no_embedded_newlines` 是同一回事。

### 為什麼這條特別要緊

`-log` 是稽核軌跡。它的**全部價值**在於「日後回頭查時,發生過的事都還在」。一份會在
並行下靜默丟掉一半紀錄的稽核軌跡,比沒有稽核軌跡更糟——因為讀它的人會相信它是完整的。

而並行不是罕見情境:一支在多個檔案上平行跑 csv2、共用同一個 `-log` 的腳本,正是這個
旗標被設計出來要服務的用法。

### 文件現況

README 說 `-log FILE` 會「附加一筆帶時間戳的操作紀錄」,而**單行程下這是真的**。
文件沒有說、也沒有理由讓人懷疑的是:同時有第二個 csv2 在寫時會發生什麼。

The comment says "append, never truncate" and the code seeks to the end once,
at open. Those are the same thing with one process and different things with
two: eight processes appending to one -log file produced 98 of 200 entries,
none malformed, every run exiting 0. An audit trail that silently loses half
its entries under concurrency is worse than none, because whoever reads it
believes it is complete.

**已修**:新增 `Platform.openForAppend`,以 `O_APPEND`(Windows 為 `_O_APPEND`)開檔,
把 seek 與 write 合成單一次核心操作。由 **T104** 斷言:6 個並行寫入者各 20 次,121 行
全數留存;未修正的建置在同一個測試上只留下 69 行。

**Windows 較弱,而文件說明而非假裝。** CRT 的 `_O_APPEND` 是「每次寫入前先 seek」,
窗口極小但不為零。POSIX 上沒有窗口。這一點寫進了兩份 README——一個做不到的保證,
比沒有保證更糟。
