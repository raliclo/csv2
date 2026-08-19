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
| BB | `-log` 在 40 字元截斷新舊值，而 README 寫「完整記錄」 | **程式＋文件（稽核相關）** |
| CC | 儲存格層級的錯誤位址是「物理行號」卻標著 `record N`，餵不回 `-get`／`-update` | **程式** |
| DD | `-debug=trace` 只回報「被輸出的」紀錄；被排除的一行都沒有 | **程式＋文件** |
| EE | 平行路徑不印 `metrics:` 行，而 README 說 `-debug` 包含它 | **程式＋文件** |
| FF | README 教的 `-contains` → `-update` 組合會靜默雙重跳脫 | **文件（後果是資料損壞）** |
| GG | 名為 `.csv2` 但只有一列標頭的檔案，rc=0 讀出時吞掉一筆；`--json` 的 meta 只是覆述副檔名 | **文件＋缺少能力** |
| HH | 中文 README 有兩段被截斷的句子；英文 `-encrypt` 區塊有一句重複 | 文件 |

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

**待決**：截斷本身可能是刻意的（避免單行 log 爆炸）。若是，README 那句「完整記錄」必須改，
並說明上限；若不是，上限要拿掉或大幅提高。**兩者擇一，不能維持現狀**——目前是「文件承諾一件
程式不做的事」，而那正是本專案定義的最糟狀態。

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

**待決**：可行的方向是讓 `--include-headers` 或 meta 提供「觀察到的」資訊，讓呼叫端有東西可以
斷言；或者至少把 README:327 那句改成它做得到的事。

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
