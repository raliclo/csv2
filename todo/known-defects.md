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

# 第 38 回合（2026-08-19）—— 七條，全部親手重現（2026-08-20 逐條複測，全部已解決）
# Round 38 (2026-08-19) -- seven, all reproduced by hand (all resolved, re-measured 2026-08-20)

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

## CC. 儲存格層級的錯誤位址是物理行號，卻標著 `record N`（已修，複測 2026-08-20）

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

## DD. `-debug=trace` 只回報「被輸出的」紀錄（已修，複測 2026-08-20）

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

## EE. 平行路徑不印 `metrics:` 行（已修，複測 2026-08-20）

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

## FF. README 教的 `-contains` → `-update` 組合會靜默雙重跳脫（已由文件解決並由 T96 斷言，複測 2026-08-20）

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

## GG. 檔名可以對格式說謊，而讀取信任檔名（已定案並由 T97a–T97g 斷言，複測 2026-08-20）

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

## HH. 中文 README 的兩段壞句，與英文的一句重複（已修，複測 2026-08-20）

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

## II. `-update` 把命令列上的非 UTF-8 位元組靜默換成 U+FFFD（已修，複測 2026-08-20）

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

### 而那個修法在 Windows 上編不過,是同一天稍後才知道的

`3b90777` 在 macOS 與兩個 Linux 節點上都通過,推上去之後升級 Windows 節點才發現:

```
error: '_open' is unavailable
      |                              `- note: '_open' has been explicitly marked unavailable here
```

Swift for Windows 把 `_open` 標為不可用,那個 `_O_APPEND` 旗標根本拿不到。

**這條的教訓不在於旗標,而在於順序。** 我在本機測完、跑完 guest、提交、推送,然後才
去建 Windows——而 Windows 是三個平台裡**唯一從這裡檢查不到**的那個。前面每一步都
「通過」了,而它們合起來並沒有回答「這段程式編得起來嗎」這個問題。

改法:POSIX 仍用 `O_APPEND`;Windows 改由 `Platform.appendWrite` 在**每一次寫入前**
seek。那與 CRT 對 `_O_APPEND` 的做法相同——把窗口從「handle 的整個生命期」縮到幾個
指令,但沒有關上它。README 兩份都如實寫明這一點。

The fix did not compile on Windows, which was learned only after it had been
committed and pushed: `_open` is marked unavailable in Swift for Windows, so
the flag is unreachable. The lesson is the order, not the flag -- local tests,
guest tests, commit and push all passed, and together they never answered
whether the code builds on the one platform that cannot be checked from here.
---

# 第 41 回合(2026-08-20)—— 用 `claude -p` 跑完的那一次

前三次嘗試分別死於工具權限、`--allowedTools` 的變參吃掉 prompt、以及執行被中止。第四次
以「prompt 走 stdin、`--allowedTools` 單一逗號清單」跑完,交出 26,865 bytes 的報告。

它自己開頭就指出一件我沒想到的事:**「缺陷表已移除」這個說明本身就是汙染。** 那段話告訴
它「csv2 曾有恰好五條已知缺陷、全部已於 2026-08-19 修正、放在 todo/known-defects.md、
而且先前兩個受測 agent 因為這一頁而作廢」——於是它帶著「這是一個狀態良好的工具」的預期
開始測試。汙染的形式從「看到答案」變成「看到答案的形狀」。

## AL. `--a1` 印的是實體行號,而那正是它與 `--physical` 唯一有差別之處(2026-08-20 修正)

```console
$ cat -n nl.csv
     1  a,b
     2  r1,"A
     3  B
     4  C
     5  D
     6  E"
     7  r2,"P
     8  Q
     9  R"
    10  r3,FINDME

$ csv2 -contains FINDME --a1 --physical -i nl.csv
3:2@L10 [B10]	b	FINDME
```

`FINDME` 在第 3 筆資料,而 `.csv` 有一列標頭,所以試算表裡它在**第 4 列**——用 Python 的
`csv` 模組獨立解析確認過:引號內的換行留在儲存格內,整份檔案只有 4 列。

**csv2 說第 10 列。** 那是 `@L10`,一模一樣。rc=0,沒有任何標記。

### 而程式碼裡有一段論證,它對了一半

```swift
// The A1 row is the PHYSICAL line, because that is what a spreadsheet
// calls a row. Using the record number made csv2 print [A1] for a cell
// that any spreadsheet would call A3, and [E0] for a header.
```

「用紀錄號會印出 [A1] 與 [E0]」——**這是對的**。但那不代表正解是實體行號,正解是
**紀錄號加上標頭列數**。一筆一行時兩者相等,於是 README 的每一個範例、repo 裡的每一份
fixture 都同意,而它們全都無法分辨這兩種讀法。

### 它為什麼躲過了所有東西

| 為什麼沒被抓到 | |
|---|---|
| `.csv2` 不可能暴露它 | 該格式禁止裸換行(以反斜線跳脫),紀錄號 + 標頭列數恆等於行號 |
| `TARGET_PACKAGES.csv` 不可能暴露它 | 它沒有引號內換行 |
| T103 守的是**欄名** | `AA`／`AZ`／`BA`／`ZZ`／`AAA` 每一個邊界都對——**列號沒有任何東西守著** |
| README 的規則是散文 | 「`A2` 與 `A3` 才是你實際會點下去的那一格」——一個錯誤的實作滿足了給出的每一個範例 |

**`--a1` 唯一比 `--physical` 多提供一點東西的場合,就是含引號內換行的檔案;而那正好是它
錯的場合。** 在其他所有檔案上,它是 `--physical` 換一種寫法。

受測者的原話值得留著:

> 「我會把差了六列的座標交給同事,rc=0,而且背後還有一次乾淨的驗證。我之所以抓到,只是
> 因為任務要求『驗證那些座標真的落在你指的儲存格上』,而我造了一個對抗性的檔案——那是
> 文件從未建議過要造的。」

> 「這個工具在**另一條程式路徑**上是知道的:
> `DEBUG single-threaded: .csv whose index records a record spanning lines; a record number is
> not a line number here`。**那句話就是這份缺陷報告。**」

`--a1` prints the physical line, and that is the only case where it differs
from `--physical` at all. A record spanning lines still occupies ONE spreadsheet
row, so data record 3 of a one-header `.csv` is row 4; csv2 says row 10. The
code carries an argument for this, and the argument is half right: the record
number alone would indeed print [A1] and [E0], but the answer is record plus
header rows, not the physical line. With one record per line the two are equal,
which is why every example in the README and every fixture in the repo agrees
with both readings. T103 pins the column letters; nothing pinned the row.
---

## AM. 值裡的一個引號,就能改寫稽核紀錄的「內容」(2026-08-20 修正)

整行的偽造已經擋掉了(AI／AJ),但**欄位層級的偽造沒有**:

```console
$ csv2 -update 1:2 'INNOCENT" -> "ALSO INNOCENT' -i q.csv --in-place -log q.log   # rc=0
$ grep update q.log
INFO  update 1:note: "third record" -> "INNOCENT" -> "ALSO INNOCENT"

$ csv2 -get 1:2 -i q.csv
INNOCENT" -> "ALSO INNOCENT
```

一行、一筆、資料本身正確。但用 `"(.*)" -> "(.*)"` 去讀那一行,拿到的是
old = `third record" -> "INNOCENT`、new = `ALSO INNOCENT`;用非貪婪則得到
old = `third record`、new = `INNOCENT`。**兩個都錯**,而真相是 old = `third record`、
new = `INNOCENT" -> "ALSO INNOCENT`。

`"` 不在跳脫集合裡,而它正是值的定界符。

**而 README 從未寫過這一行的文法。** 受測者的話:「文件指定了跳脫集合(`\n \t \r \\`),
卻從來沒說要怎麼剖析一行,因此每一個使用者都得用猜的——而那個猜測會被儲存格內容利用。」

### 為什麼「加進整行的跳脫」行不通

AJ 把跳脫集中在「建構整行」那一點,而那正是它的長處:涵蓋每一則現在與日後的訊息。
但整行跳脫**無法區分「定界用的引號」與「資料裡的引號」**——兩者都在同一個字串裡,跳脫
時已經分不出來了。把 `"` 加進那個集合,只會讓定界符也變成 `\"`,一樣有歧義。

**解法是沿用這個格式自己的慣例**:值裡的 `"` 寫成 `""`,一如 RFC 4180 與 `.csv2` 本身。
它不含反斜線,因此整行跳脫完全不會碰它;剖析方式是任何看得懂 CSV 的人都已經會的那一種。
`reportEscape` 的註解早就寫過這個理由:「沿用既有慣例而非發明新的,讓看得懂檔案格式的人
不必再學一套。」那句話當時只套用在報告上。

## AN. 三個不同的拒絕理由,印出同一句話,而那句話是假的(2026-08-20 修正)

```console
### A: 根本沒有 sidecar
DEBUG single-threaded: .csv with no index proving one record per line; build one with --build-index
### B: sidecar 存在但過期
INFO  index dm.csv.index is stale, ignoring and scanning
DEBUG single-threaded: .csv with no index proving one record per line; build one with --build-index
INFO  index dm.csv.index is stale, ignoring and scanning
### C: sidecar 存在但損毀
DEBUG single-threaded: .csv with no index proving one record per line; build one with --build-index
```

三件事:

1. **B 與 C 的訊息說「沒有索引」,而 sidecar 就躺在資料旁邊。** 它還叫人去
   `--build-index`——而受測者剛剛才做過。它自己的話:「這在幾分鐘之內主動誤導了我。」
2. **C 完全沒有提到那個損毀的 sidecar。** 一個被丟棄的索引,連一個字都沒有。
3. **B 的 INFO 印了兩次。** `CSVIndex.load` 一次執行被呼叫不只一次——與 AH 修正時
   遇到的是同一個形狀,只是這次在 stale 那條路徑上。

### 而我今天自己寫進 README 的那句話,因此是假的

修 AH 時我寫下:

> 「Every path that *declines* an index named it and said why; the one path that
> *trusts* one said nothing at all.」

後半是真的(那是 AH 修好的)。**前半不是。** 我描述的是我希望的對稱,不是我量到的對稱——
而我當時只量了「採信」那一條。

**這是本專案的老毛病又一次:加了一段文字,卻沒有去作廢它所使之為假的東西。**
與 README 狀態表對 `install.zsh` 那次(AF)是同一個模式。

## AO. 平行路徑沒有上界,而 README 說的是另一回事(2026-08-20 文件修正;成因見 AR,同日修正)

README 說:「`-debug` … 每一條路徑都有一行 metrics——平行那一條的 RSS **約為單執行緒的
兩倍**。」

實測(同一個查詢,兩邊都斷言了路徑):

| 檔案大小 | 單執行緒 RSS | 平行 RSS | 平行 ÷ 檔案 |
|---|---|---|---|
| 25,888,899 | 9,207,808 | 60,456,960 | **2.34×** |
| 51,888,899 | 9,207,808 | 102,023,168 | **1.97×** |

**單執行緒對兩種大小都是 9.2 MB——有界,一如文件所述。平行是檔案的兩倍,隨輸入線性成長。**

所以那句話錯的不只是倍數:**它把一個「無界」說成了一個「有界的倍數」。** 25 MB 的檔上
它是 6.6 倍,52 MB 的檔上是 11 倍,而 1 GiB 的檔會是約 2 GiB。

而且它與 `CSV2_PARALLEL_CHUNK_BYTES` 無關——chunk 從 256 KiB 調到 16 MiB,RSS 都在
50–60 MB 之間。所以那不是「工作者各持一塊」的模型,調小 chunk 救不了它。

這與 T9a／T9b／T9c 所守住的那個保證(「RSS 不隨輸入成長」)方向相反。那三條測的是
`-si`／`-so` 串流路徑,而它們是對的;**沒有任何東西測過平行路徑的記憶體**。

## AP. README 的 `<redacted>` 範例,被同一份 README 的拒絕表擋住(2026-08-20 修正)

第 609 行把這段展示成一次可以運作的操作:

```console
$ csv2 -update 1:secret "new value" -i pkgs.csv -o out.csv -log app.log
$ grep update app.log
INFO  update 1:secret: <redacted> -> <redacted>
```

受測者對 `:hash`、`:hmac:`、`:enc:` 欄位各試了 `-update`、`-delete -cell`,以及
`-encrypt`／`-decrypt` 本身,全部 rc=1——被第 852 行那張拒絕表擋住。
`grep -l redacted *.log` 掃過它產生的每一個 log:**一個都沒有**。

**同一份 README 的兩節互相矛盾,而拒絕表贏了。** 那個 `<redacted>` 分支目前無法從
任何記錄在案的路徑抵達。

## AQ. `--verify-index` 的成功訊息,在兩種相反的情況下逐字相同(2026-08-20 文件修正)

```console
$ csv2 --verify-index -i nl2.csv        # 這個檔案每隔一筆就跨行
index OK: 3 records, stride 256, 1 grid points
rc=0
```

README 說 `--verify-index` 證明的三件事之一是「是否有紀錄跨行」。它證明的是**索引對這件事
的宣稱是準確的**,而不是那個宣稱的內容是什麼——而「宣稱為真」與「宣稱為假」印出的是
同一行。

受測者拿它當守衛,然後自己標記為「**我以為成功了,但其實是錯的**」。真正回答那個問題的
是搜尋時的 debug 行(`.csv whose index records a record spanning lines`),它明確且正確。

---

## 第 41 回合的修正,以及其中三件值得單獨記住的事

| | 修法 | 測試 |
|---|---|---|
| AL | `--a1` 的列號改為「紀錄號 + 標頭列數」 | T105 |
| AM | 記入 log 的值裡,`"` 加倍(RFC 4180 慣例) | T106 |
| AN | 三種拒絕分開;丟棄的理由依 sidecar 去重,每次執行說一次 | T107 |
| AO | 文件改寫。**其中的模型是錯的**——真正的成因見 AR,當日修正 | T108 |
| AP | 換成實際會發生的「拒絕」;遮蔽保留為最後防線並註明無可達路徑 | T40／T73 既有 |
| AQ | 寫明它證明的是「宣稱準確」而非「宣稱的內容」 | — |

### 一、修正 AL 之後,整個測試套件一條都沒有變

那不是「沒有副作用」,那是**量測結果**:repo 裡每一份 fixture 都是一筆一行,而在那個世界裡
「紀錄號 + 標頭列數」與「物理行號」恆等。450 條斷言裡,**沒有一條**分辨得出這兩種讀法。
T103 守著欄名的每一個邊界,而列號一個都沒有。

**一個功能可以有一半被完整地測著,另一半完全沒有,而總數看起來很健康。**

### 二、AN 的第一版修法,把「重複」換成了「沉默」

`load` 一次執行被呼叫兩次,於是「ignoring and scanning」印兩次。我先讓純查詢那一次靜音——
而在一個「拒絕平行路徑」的搜尋裡,查詢是**唯一**的一次呼叫,於是理由變成完全不印,而我同時
寫的拒絕訊息卻說「用 -debug 看原因」。

**重複只是雜訊;沉默才是這一帶一再產生的那種缺陷。** 正解是在 `load` 內部依 sidecar 去重
——那是唯一同時看得到兩次呼叫的地方。

### 三、AN 裡有一句假話是我自己在同一天寫下的

修 AH 時我寫進 README:「Every path that *declines* an index named it and said why.」
後半(採信的那條什麼都不說)是我量過的;前半我沒有量,我描述的是我希望的對稱。

**這棵樹上重複出現的那個模式,這次由我親自示範了一遍:加了一段文字,卻沒有去作廢它所使之
為假的東西。** 而抓到它的是一個只讀 README 的受測者。
---

## AR. 平行路徑的記憶體等於檔案大小,而成因是同一個缺陷的第三次出現

**615 MB 的檔案,平行路徑常駐 608 MB;同一個檔案走單執行緒是 9.5 MB。**

```
parallel:         peak_rss_bytes=608305152    2.0 s
single-threaded:  peak_rss_bytes=  9519104   11.5 s
```

### 找到它的那次量測

先前記在 AO 的推論是「工作者各持一塊」,而依那個模型,減少同時在飛的區塊數就能壓下記憶體。
**那個模型是錯的,而拆穿它只花了一次量測**:把批次大小強制降到 1(同時只有一個區塊在飛),

```
batch=1   rss=637206528
batch=2   rss=637796352
batch=5   rss=638992384
batch=10  rss=640581632
```

**百分之零點五。** 任何隨「同時在飛的工作量」而變的東西都不可能是這種行為。工作者因此被
排除,剩下的只有一個「在 pool 之外走過每一個位元組」的迴圈。

### 成因

`planChunks` 為了讓每個區塊知道自己第一筆的編號,會走過**整個檔案**數換行,而它以 1 MiB 的
`Data` 讀取、外面沒有 autorelease pool。在 Darwin 上那些 `Data` 活到行程結束。

**這是同一個缺陷的第三個發生地。** `ByteSource.next` 的註解一字不差地描述過它:

> 「重點是那個 pool,不是那次讀取。沒有它,這裡回傳的每一個 `Data` 在 Darwin 上都會活到
> 行程結束,於是 peak RSS 隨『讀了多少位元組』成長。」

而平行工作者的讀取迴圈在**同一天稍早**才需要過同樣的修正。一段寫得很清楚的註解,擋不住
它自己所描述的那個缺陷在第三個地方重演——因為那段註解在別的檔案裡。

### 修正後

| 檔案 | 修正前 | 修正後 |
|---|---|---|
| 25.9 MB | 38 MB | 12.2 MB |
| 51.9 MB | 66 MB | 14.0 MB |
| 615 MB | 608 MB | **23.1 MB** |

輸出仍與單執行緒逐位元相同(那是平行路徑的驗收條件)。由 **T108** 斷言。

### 而 AO 的數字因此全部作廢

AO 記的是「平行約為檔案的兩倍」。那是在缺陷存在時量的,而且我據此改寫了 README。
**現在那段 README 也錯了,要一起改。** 這正是這棵樹上一再出現的形狀——只是這次被作廢的
是我自己前一輪寫下的東西。

## 而「1 GiB 上限」的處方,對真正的成因無效

使用者要求的是「超過 1 GiB 就減少同時處理的區塊數並排隊」。依 AO 當時的模型那是對的;
依實際成因**它不會有任何作用**——batch=1 與 batch=10 只差百分之零點五。

**如果我照著做而沒有先量,結果會是一個限流器、一份說它有效的文件,以及一個原封不動的
608 MB。** 那正是本專案存在要防的那一類:看起來成功的修正。

真正的成因修好之後,上限仍然被實作了,但它管的是另一件事——見下。

## `CSV2_PARALLEL_MAX_BYTES`:上限管的是輸出,不是讀取

修好 AR 之後,剩下一項**確實**由並行度驅動:一批區塊在飛時,它們的**輸出**必須被持有,
才能依區塊順序寫出——而那個順序正是平行輸出能與單執行緒逐位元相同的原因。

在一個「每一筆都命中」的 615 MB 檔案上(輸出 630 MB):

| 同時在飛 | 峰值 RSS |
|---|---|
| 1 | 52 MB |
| 2 | 63 MB |
| 5 | 102 MB |
| 10 | 160 MB |

這一項壓得下來,因此設了上限。**讀取側不需要上限,它本來就有界**:一個工作者以 64 KiB
為單位讀自己的區塊,從不多持有。

做法是**每一批各自決定**同時在飛幾個區塊,而不是固定:輸出有多大,在搜尋跑完之前沒有人
知道,所以第一批以區塊大小估算(報告很少大於它所描述的資料),之後每一批都用「上一批
實際持有了多少」來決定。預設 1 GiB,`CSV2_PARALLEL_MAX_BYTES` 可覆寫。

**它會說出自己降速了**,帶著數字:

```
DEBUG parallel: holding 2 chunk(s) in flight instead of 10; the last batch held
      about 4194304 bytes per chunk and CSV2_PARALLEL_MAX_BYTES is 8388608
```

安靜地少用幾個工作者,會讓一次「比機器能力慢」的執行無法被解釋——那是 AH 剛修過的
那個形狀。

**它不是「行程總記憶體上限」,文件也不會那樣寫。** 8 MiB 的上限下,實測峰值 RSS 是 58 MB:
上限管的是在飛的輸出,其餘是固定的工作集。一個做不到的保證比沒有保證更糟。

## T108 自己也錯過一次,而錯的方式正是它要測的那一種

第一版 fixture 以「造一個區塊、反覆附加它的 `tail -n +3`」生成,而結果剖析不了——csv2 在
第 1 筆就以欄數錯誤拒絕,那兩次執行以 1 結束、**完全沒有印出 metrics 行**。

於是 `rss_of` 兩邊都回傳空字串,空字串在 zsh 的算術裡是 0,而 0 輕鬆通過了界限:

```
PASS  T108b a 9341460B larger file costs 0B, not the file (bound 2335365B)
```

**一個帶著完整缺陷的建置,通過了一個專門為那個缺陷寫的測試,並且印出了一個看起來很好的
數字。** 現在多了一道「讀數是否為空」的檢查。

第二個錯誤是尺寸選錯:1 MB 對 10 MB 落在「工作集正在爬升」的那一段,而那個爬升比要測的
保留還陡,於是案例在一個**正確的**建置上失敗。改成 10 MB 對 40 MB——兩者都在爬升段之上。
界限取「多出來的輸入的一半」,是在這一組尺寸上、修正前後各量過一次之後定的:
留住輸入是 +39.9 MB,不留住是 +7.1 MB。

The cap governs the OUTPUT held while chunks are in flight, not the read side,
which was bounded already. The real cause of the file-sized memory was a third
occurrence of the missing-autorelease-pool defect, in the loop that walks the
whole file to number the chunks -- and the user's prescription (throttle the
in-flight chunks) would have done nothing about it: batch=1 and batch=10
differed by half a percent. Measuring before implementing is what separated
those.

---

## 這份檔案自己也漂移了,而發現它的方式只是「有什麼要做的嗎」

2026-08-20,在被問到「還有什麼要做的」時,我沒有靠印象回答,而是去讀這個檔案。第 38 回合
那一節的標題寫著:

> 第 38 回合(2026-08-19)—— 七條,全部親手重現,**尚未修**

**七條全部已經解決了。** 逐條複測的結果:

| | 狀態 |
|---|---|
| CC 錯誤位址標著 `record N` 卻是行號 | 已修——現在印 `record 2 (line 3)` |
| DD `-debug=trace` 只報「被輸出的」 | 已修——會報跳過 |
| EE 平行路徑不印 `metrics:` | 已修 |
| FF `-contains` → `-update` 靜默雙重跳脫 | 已由文件解決:README 明寫「第三欄是給人讀的,不是拿來餵回去的」,並給出 `-get` 的正確寫法,由 T96 斷言 |
| GG 檔名對格式說謊 | 已定案(不加偵測、改寫準文件),由 T97a–T97g 斷言 |
| HH 中文 README 兩段壞句 | 已修,英文那處重複也已消除 |
| II 命令列非 UTF-8 靜默替代 | 已修——現在明確拒絕 |

**而那個「尚未修」的標題,存活了一整天。**

這正是本檔案開頭警告過的那件事,只是這次發生在本檔案自己身上:全域 `CLAUDE.md` 的缺陷表
曾經有五條、實測時五條全部不成立;那份表被移除的理由是「一份寫在指令檔裡的缺陷清單,會與
它所描述的程式反向漂移,而且沒有任何東西會回報它」。

**這份檔案的防線是「每一條旁邊都有重現步驟」,而那道防線有效**——七條都能在幾分鐘內複測完。
但它防的是「條目內容錯」,防不了「條目狀態過期」。**沒有任何東西會在一個缺陷被修好時,回頭
去改它上面那個標題。**

做法上的結論:**修好一條缺陷時,同時去看它所屬的那一節的標題。** 一節的標題是對整節的宣稱,
而它比條目更容易被遺忘——因為修東西的人看的是條目。

This file had drifted too, and what found it was the question "anything to be
done". The round-38 heading still said "not yet fixed" for seven findings, all
seven of which were resolved. The per-entry reproductions did their job -- all
seven were re-measured in minutes -- but reproductions guard the CONTENT of an
entry, not its STATUS. Nothing goes back to amend a heading when the thing
underneath it is fixed. When fixing a defect, look at the heading of the
section it lives in: a heading is a claim about the whole section, and it is
easier to forget than the entry, because whoever does the fixing is looking at
the entry.
---

# 四平台矩陣第一次真的同時全綠(2026-08-20),而補齊它時找到兩條

在被問到「還有什麼要做的」之後,我去補一個我知道自己沒做的東西:記憶體那批修改動過
`Platform.swift` 與 `Parallel.swift`,而 Windows 與 WSL 從那之後**只驗過「編得過」,
沒有跑過測試套件**。

## AS. Windows 上 276 條失敗,而成因是一個環境變數

```
經 multissh 執行：  276 條失敗
同一台機器、普通 shell：  0 條失敗
```

**同一棵樹、同一個執行檔、同一個 commit。**

失敗訊息長這樣:

```
csv2: cannot open input file: /c/Users/lowei/proj/csv2/test/.test_csv2.gix09g/cronly.csv
```

這份測試交給 csv2 的是由 `${0:A:h}` 組出的絕對路徑,而在 Windows 上那是 POSIX 形狀的。
**原生 Windows 程式打不開那種路徑。** 讓它一直能運作的,是 MSYS2 在把引數交給原生行程時
改寫成 `C:/...`——這份測試從第一次在那裡執行起就依賴這件事(T58a／T58b 的存在正是因為那個
改寫會出現在 csv2 自己的錯誤訊息裡),但**沒有任何地方說出來,也沒有任何東西確保它是開著的**。

`MSYS2_ARG_CONV_EXCL=*` 會把改寫整個關掉,而它被設在 multissh session 的環境裡。

### 那個差一點

對 276 條失敗的第一個判讀是「記憶體那批修改弄壞了 Windows」。**而建置是通過的**,所以下一步
會是去 bisect csv2——一條完全走錯的路。

排除它的是三次手動量測:相對路徑(可以)、反斜線原生路徑(可以)、以及這份測試使用的 POSIX
路徑(不行)。**第三次指出了成因,而前兩次證明程式本身沒事。**

**修法**:測試自己 `unset MSYS2_ARG_CONV_EXCL`,把這個決定的範圍限制在它自己與它啟動的
行程內,並移除一個沒有人宣告過的、對呼叫者環境的依賴。

## AT. 而套件一跑起來,Windows 就少了 11 筆稽核紀錄

修好 AS 之後,Windows 只剩 **2 條失敗**,而那兩條是 T104a 與 T104c:

```
FAIL T104a 6 concurrent writers lose no entries (got '110', want '121')
```

**121 筆只剩 110 筆,整筆整筆地少,沒有一筆是壞的。** 與 AK 那個 POSIX 缺陷是同一種靜默
遺失,只是小一些。

成因是我自己在同一天寫下的:`_open` 在 Swift for Windows 上不可用,於是我改成「每次寫入前
先 seek」,重現 CRT 對 `_O_APPEND` 的做法,並**如實寫進兩份 README**:「窗口極小但不為零」。

我當時否決 `FILE_APPEND_DATA` 的理由是:「那個保證從這裡也無法比『每次寫入前 seek』驗證得
更徹底。一個說清楚的限制,勝過一個未經驗證的宣稱。」

**那個理由在 T104 開始於 Windows 上執行的那一刻就失效了。** 現在有量測了,而有了量測,
那個更強的做法就變成可以驗證的——於是它從「不該做」變成「該做」。

**修法**:`CreateFileW` 搭配 `FILE_APPEND_DATA`(且不帶 `FILE_WRITE_DATA`),那是 Windows
真正的不可分割追加——由作業系統移到檔尾並寫入,合為一次操作。經 `_open_osfhandle` 交給一個
CRT 描述子,讓其餘程式維持單一條路徑。

**這次先驗才提交**:一個 14 行的探針先在 Windows 節點上編過並跑過,回傳 fd 3。上一次做同一
件事時,我推出去的 commit 在那裡編不過(見 AK 的後記)。

結果:**Windows 零失敗**,而兩份 README 裡「Windows 較弱」那句話改成
「沒有任何平台還有窗口」。

| 平台 | 失敗 | 略過 |
|---|---|---|
| macOS arm64 | 0 | 1 |
| aarch64 Linux guest | 0 | 1 |
| x86_64 WSL2 | 0 | 1 |
| x86_64 Windows MSVC | 0 | 4 |

（此處刻意不寫通過的總數:那個數字每加一個案例就會變，而它一旦寫進文件就沒有東西會回頭
更新它。T69 正是為此存在，而它在 2026-08-20 抓到的就是上面這幾行的舊版本。）

## 這兩條有一個共同點

**AS 讓一個好的程式看起來壞掉了;AT 讓一個壞掉的地方看起來是好的**——因為在我補上這次
執行之前,Windows 上根本沒有東西在跑 T104。

而兩者都只有在「真的去跑那個套件」時才會出現。「建置通過」在兩種情況下都成立,而它一次
也沒有回答過那個真正的問題。

Two findings while filling a gap in the four-platform matrix. AS made a correct
program look badly broken: 276 failures over multissh, zero from an ordinary
shell on the same machine, because MSYS2_ARG_CONV_EXCL=* disables the argument
rewriting the suite has silently depended on since it first ran there. AT was
the reverse -- a real defect that looked fine, because nothing had ever run
T104 on Windows: the seek-then-write append left 110 of 121 entries. Both
appear only when the suite is actually run. "The build succeeds" was true
throughout and never answered the question.
---

# 第 42 回合(2026-08-20)—— 加密、`--filter`、`--pretty`、串流管線

受測者交出 27,401 bytes,第 4 類是空的:「四項任務、約六十次呼叫,沒有找到任何一次
『csv2 成功了而答案是錯的』。」而它自己加了一段限定:

> 「我被預先注入的指令檔告知,最後五條已知缺陷在前天全部驗證為已修。**一個預期找不到東西
> 的測試者,找東西的能力比較差。** 我這個『沒有壞掉的行為』的結論,份量應該打折。」

它在第 1、3 類找到的東西不受這個影響。

## AU. 一個位元組的金鑰檔被靜默接受,而空的會被拒絕(2026-08-20 修正,T109)

```console
$ : > empty.key
$ csv2 -encrypt license -keyfile empty.key -i s.csv -o e0.csv -t
csv2: keyfile is empty or unreadable: empty.key          rc=1   ← 好

$ printf 'a' > tiny.key
$ csv2 -encrypt license -keyfile tiny.key -i s.csv -o e1.csv -t
rc=0                                                             ← 接受,無任何警告
pkg,license:enc:a4d6aee9:jMBdnmEIHsfi91+39h3sJA==

$ for i in 0..255; do try each single byte as the key; done
recovered with byte 97: GPL-2.0                                  ← 98 次
```

**那個不對稱本身就是線索。** 有人已經決定「金鑰檔必須有內容」——只是沒有決定「多少」。
於是 0 bytes 被拒絕,1 byte 通過,而兩者的安全性差別是可以在一秒內窮舉掉的。

### 而 README 對此完全沒有說

`-keyfile PATH` 與「預設是 multissh 的私鑰」就是全部了。**沒有大小、沒有格式、沒有怎麼產生
一把、沒有最小值。** 整份文件裡唯一指向 `mssh-keygen` 的地方,埋在一則「解密失敗」的錯誤
訊息裡。

受測者的話最切中要害:

> 「README 用一整個方框段落警告『不帶金鑰的 `-hash` 擋不住字典攻擊』,並開出 `-keyfile`
> 這帖藥——**然後對它所開的那帖藥的強度隻字不提。** 它拒絕 0 bytes,接受 1 byte。」

> 「唯一完全沒有量測工具的地方就是金鑰強度:沒有旗標、沒有警告、沒有記載的最小值,
> **而這個工具在 1 byte 時的沉默,與它在 32 bytes 時的沉默無法區分。**」

那句話正是本專案的判準:一個看起來成功、而實際上不是的結果。

### 修法的分界線

**建立保護時拒絕,讀取既有檔案時絕不拒絕。** `-encrypt` 與帶金鑰的 `-hash` 是在「產生一個
日後要靠它保護的檔案」,那時可以要求;而 `-decrypt` 面對的是「已經存在的檔案」,若在那裡
套用同一個門檻,就會讓一份用弱金鑰做出來的檔案再也讀不回來——**用一個安全性的理由造成
資料無法取回,那是更糟的交換。**

## AV. `:enc:` 指紋那一段,展示的是沒有任何指令會產生的輸出(2026-08-20 修正)

README 把它寫成一段 console 操作:

```console
$ for i in 1 2 3; do csv2 -encrypt secret -keyfile k.bin -i s.csv -o e$i.csv -t; done
secret:enc:d88cdbf1:…
secret:enc:e16b394a:…
secret:enc:869e54ce:…
```

**那個迴圈一個位元組都不印。** 顯示的三行是「檔案的標頭」,不是程式的輸出;要看到它們得
自己去 `head -1` 每個檔案。

而它牴觸同一份 README 三節之前的兩句話:「正常路徑上不輸出任何東西」與「本工具必須能放進
管線」。

**這與 AP 是同一個形狀,而 AP 才在昨天修過。** README 在 `-log` 那一節甚至為這件事道過歉
(「本節的舊版本把『被遮蔽』的形式當成一次普通操作展示……於是讀者會去試一個不可能成功的
指令」)。同樣的錯誤此刻還在文件的另一處,而且是兩個(加密迴圈與雜湊迴圈)。

## AW. 「結束狀態沒有第三種情況」,而 141 就是第三種(2026-08-20 修正,T110d/e)

README 的「Exit status」一節寫著:**「成功為 0,任何錯誤為非零,沒有第三種情況。」**

```console
$ gen 4.8M | csv2 -si --headers 1 -contains "pkg-" --filter -so | head -1
pipestatus: 120 141 0
stderr bytes: 0
```

**csv2 以 141 結束(128 + SIGPIPE),不印任何東西,不留下任何東西。** 那是正確的 Unix 行為
——而且是俐落的:`| head -1` 是 0.04 秒,`| wc -c` 是 9.7 秒,它死在第一個被阻塞的寫入上,
不會先把 400 MB 讀完。

**行為是對的,那句描述結束狀態的話不是。** 一個把「非零」當成「csv2 失敗了」的呼叫端,
會把一個完全正常的 `| head -1` 誤報成錯誤。而 README 有一節就叫「In a pipeline」,另一節
叫「Exit status」,兩節都沒有提到「下游先離開」——那是管線工具最常見的非成功結局。

## AX. `-md` 對儲存格內容的跳脫沒有記載(2026-08-20 修正,T110a–c)

`|` 變成 `\|`、內嵌換行變成 `<br>`。兩者都沒有寫(有寫的那個 `<br>` 是另一回事:兩列標頭
的接合)。

這不只是缺一句話:**受測者的寬度檢查器因為以 `|` 切欄而得到錯誤答案,差一點就把一個正確
的程式報成缺陷。** 它自己記下了這一段。

## AY. `CSV2_PRETTY_MAX_BYTES` 的「16 MiB」是什麼的 16 MiB(2026-08-20 修正)

表格寫的是「`-md --pretty` 超過此值即拒絕」。超過的是**輸入檔**,還是**要對齊的那批資料**?
是後者:

```console
$ csv2 -mid 150000,150004 -t -md --pretty -i big.csv      # 23 MB 的檔案
rc=0    peak_rss_bytes=9469952
$ csv2 -r -t -md --pretty -i big.csv
csv2: -md --pretty has to hold the whole table to align it, and this one is over 16777216 bytes …
rc=1
```

**拒絕訊息本身是清楚的;讀者最先查閱的那張表不是。** 而真正有用的那個事實——「任意大的
檔案,取一個切片來 `--pretty` 永遠沒問題」——文件裡哪裡都沒有。

## AZ. 標頭被竄改,訊息卻指著某一筆紀錄(2026-08-20 修正)

受測者繞過指紋預檢:把檔頭裡的指紋改成它那把錯金鑰會導出的值。

```console
$ csv2 -decrypt all -keyfile wrongkey.bin -i forged.csv -o cracked4.csv -t
csv2: record 1, column license: authentication failed; the cell was modified after it was encrypted
rc=1
```

**被改的是標頭列 0a,不是第 1 筆的任何儲存格。** AEAD 確實分不出是哪一個被動過——但這則
訊息指著一個錯的地方,而 README 自己那張「錯誤位置」的表承諾:訊息裡的 `record N` 就是
出問題的那一筆。

Round 42's category 4 was empty, and the subject discounted its own verdict:
being told the last five known defects were all verified fixed primes a tester
to expect nothing, and a tester expecting nothing is worse at finding things.
What it did find sits in categories 1 and 3, where that priming does not help.

### AZ 的修法:不去斷言一件它分辨不出來的事

新訊息:

```
csv2: authentication failed at record 1, column license -- that is where it was
DETECTED, not necessarily where the fault is. Any of three produce this and the
tag cannot tell them apart: the key is not the one this column was encrypted
with, the cell was altered after encryption, or the column's header was altered.
Check the header first if you have a key you believe in
```

**受測者觸發它的路徑,原因其實是第一種(金鑰不對),而舊訊息斷言的是第二種。** 它把檔頭的
指紋改寫成自己那把錯金鑰會導出的值,於是 O(1) 預檢通過,剩下 AEAD 標籤去失敗——而標籤能說
的只有「對不上」,說不出是哪一個對不上。

舊訊息挑了三種可能之中的一種寫進去,而且挑錯了。

### 而 T110 的 fixture 被同一個 zsh 陷阱弄壞了第二次

`local` 用在函式之外,zsh 會拒絕。那個拒絕走 stderr,而重導只送 stdout 進檔案,於是 fixture
是壞的、腳本照常往下跑:T110d 第一次失敗時是 rc=1 與 187 bytes 的 stderr,而那與 SIGPIPE
毫無關係。

**同一天稍早,T108 的 fixture 就是被同一個錯誤弄壞的**(見那一節)。第一次我修好它並寫下了
成因;第二次我照樣又犯了。兩處現在都有註解說明為什麼那裡不能用 `local`——而「寫下來」顯然
不足以擋住第二次,把理由放在出事的那一行旁邊或許可以。
---

## BA. 下游離開時,csv2 在 Linux 與 Windows 上崩潰(macOS 不會)(2026-08-20 修正,T110d/e)

第 42 回合的受測者量到「141、不印任何東西、0.04 秒」並稱讚那是正確的 Unix 行為。**它在
macOS 上跑。** 我把那件事寫進兩份 README,並補上 T110d／T110e 去守住它——然後那兩條在
WSL 與 Windows 上失敗了:

```
FAIL T110d ... (got '132', want '141')
FAIL T110e ... (got '2305', want '0')
```

`132 = 128 + 4`,SIGILL。那不是 SIGPIPE,那是崩潰。stderr 上的 2 KB 是這個:

```
Foundation/FileHandle.swift:709: Fatal error: 'try!' expression unexpectedly raised an error:
Error Domain=NSCocoaErrorDomain Code=512 "(null)"
UserInfo={NSUnderlyingError=Error Domain=NSPOSIXErrorDomain Code=32 "Broken pipe"}

*** Signal 4: Backtracing from 0x7fb7a36f8d71... done ***
*** Program crashed: Illegal instruction at 0x00007fb7a36f8d71 ***
```

**swift-corelibs-foundation 的 `FileHandle.write` 內部用 `try!`。** 於是 `EPIPE` 不是被
處理,而是成為 fatal error;程式以 SIGILL 崩潰,並印出一段 backtrace。Darwin 的 Foundation
不是這個實作,所以 macOS 上看不到。

### 這條為什麼要緊

README 有一節叫「In a pipeline」。`| head`、`| less` 提早離開,是管線工具最常見的非成功
結局——而在三個平台中的兩個上,那個結局是**崩潰加上一段對使用者毫無意義的 Swift backtrace**。

而它也讓我昨天寫的那句話變成假的:「它不印任何東西、不留下任何東西」。在 Linux 上它印
2 KB。

### 又是「只在一個平台上量過」

**這與 AT 是同一個形狀,而 AT 是同一天早上的事。** 那次是:Windows 從來沒有跑過 T104,
於是一個真實的缺陷看起來是好的。這次是:那個行為只在 macOS 上被量過,於是我把一個
「只有一個平台為真」的宣稱寫進了文件。

差別在於這一次**測試先寫好了**,所以它在我把節點跑一遍時立刻現形——而寫那個測試的理由,
正是「每一條新寫進文件的宣稱都要有測試撐著」。那條規則今天賺回了它的成本。

csv2 crashes when its reader leaves, on Linux and Windows but not macOS:
swift-corelibs-foundation's FileHandle.write uses `try!`, so EPIPE becomes a
fatal error and the process dies of SIGILL with a backtrace on stderr instead
of dying of SIGPIPE in silence. Same shape as AT earlier the same day -- a
behaviour measured on one platform only -- except this time the test existed
first, so it surfaced the moment the other platforms ran it.

### BA 的修法走了三步,而中間兩步各弄壞一個平台

| 步 | 做法 | 結果 |
|---|---|---|
| 1 | `Platform.writeAll(FileHandle, …)`,取 `.fileDescriptor` | Windows **編不過**:Swift 把 `fileDescriptor` 標為不可用(「Cannot perform non-owning handle to fd conversion」) |
| 2 | 改成 `writeAll(fd:)`,只有 stdout／stderr 走它 | Windows **43 條失敗** |
| 3 | 加上 `_setmode(1, _O_BINARY)`、`_setmode(2, _O_BINARY)` | 四個平台皆零失敗 |

第 2 步的失敗方式值得留下:

```
FAIL T28b --in-place edits via temp file and rename (got 'zzz', want 'zzz')
FAIL T43c ... (got 'ap3,v,s,src,purpose,note,MIT', want 'ap3,v,s,src,purpose,note,MIT')
```

**兩個值印出來一模一樣,而它們不相等。** Windows 的 CRT 以「文字模式」開啟 fd 1 與 fd 2,
於是每一個 `\n` 都變成 `\r\n`。Foundation 寫的是 Win32 handle 而不是 CRT 描述子,所以這個
翻譯在此之前從來沒有出現過。

唯一說出真正問題的是 **T4**——因為它明確去「數 CR 位元組」,而不是去「比對字串」:

```
FAIL T4 mixed CRLF/LF (got 3 lines, 3 CR)
```

**一個為了量測而寫的案例,在 43 個為了比對而寫的案例都只能說「兩個看起來一樣的東西不一樣」
時,說出了原因。**

### 今天第三次:改動弄壞了那個從這裡檢查不到的平台

AK(`_open` 不可用)、AT(`FILE_APPEND_DATA` 之前的 seek-then-write)、以及這一次。

AT 之後我養成了「先送探針上去編一次」的習慣,而**這一次那個習慣沒有擋住**:我探的是
「那個 API 存不存在」,不是「它對位元組做了什麼」。`_write` 存在、編得過、在本機正確——
而它在 Windows 上對每一個換行做的事,探針沒有問。

Fixing BA took three steps and the middle two each broke a platform. Step 2
moved stdout onto `_write` and hit Windows' text-mode CRT: 43 cases failed with
values that print identically and are not equal. The only case that named the
cause was T4, which counts CR bytes instead of comparing strings -- a case
written to measure rather than to compare. Third time today a change that
builds and passes here broke the one platform that cannot be checked from here,
and the probe habit learned from the second one did not help, because the probe
asked whether the API existed and not what it did to the bytes.
---

# 第 43 回合(2026-08-20)—— 編輯動詞、格式跨越、拒絕作為介面、邊界

**這一輪的第 4 類有四條,而且每一條都是「rc=0 而結果是錯的」。** 受測者的話:

> 「這是這個工具自己的招牌失敗,在 README 說已經修好的那條快路徑上重新出現:一次被回報為
> 成功的寫入,產生了一個剛好少掉那一筆寫入的檔案。」

## BB. `-append --in-place` 跳過「最後一筆是否完整」的檢查(2026-08-20 修正,T111a–f)

README 講了兩次,而且是當成**已修的缺陷**在講:

> 「`-append` 到一個最後一筆不完整的檔案 | …**`-o` 與 `--in-place` 一視同仁地檢查——
> 那條快路徑原本會跳過它,產生一個 csv2 隨後拒絕讀取的檔案**」

實測:

```console
$ printf 'id,name,note\nr1,n1,"ok"\nr2,n2,"unclosed\n' > p1.csv

$ csv2 -append 'r3,n3,x' -i p1.csv -o out.csv
csv2: record 3: the input ends inside a quoted field -- the closing quote is missing …
                                                              ← -o：拒絕 ✓

$ csv2 -append 'r3,n3,x' -i p1.csv --in-place
rc=0                                                          ← --in-place：照寫不誤 ✗

$ csv2 -r -i p1.csv
csv2: record 3: the input ends inside a quoted field …        ← 自己讀不回來
```

**而剛寫進去的那一筆,救不回來。** 因為那個引號從未關閉,`r3,n3,x` 現在位在第 2 筆的引號欄位
「裡面」,而文件指定的修復手段會把它丟掉:

```console
$ csv2 -r --truncate-partial -i p1.csv
r1,n1,"ok"
rc=0                          ← r3 不見了。那一筆是幾秒前以 rc=0 寫進去的。
```

短的最後一筆(欄數不足)同樣如此:`-o` 拒絕、`--in-place` rc=0。

**既有的守衛檢查的是「檔案結尾有沒有換行」,而不是「最後一筆完不完整」。** 一個檔案可以
以換行結尾,同時停在一個沒有關閉的引號裡——而那正是這裡的情況。

## CD. `-append` 與 `--truncate-partial` 併用沒有被拒絕(2026-08-20 修正,T91n/o)

文件在兩個地方說它被拒絕:旗標條目(「**與 `-append` 併用時被拒絕**,後者只會增加位元組」)
與拒絕表。

```console
$ csv2 -append 'a,b,c' --truncate-partial -i k.csv -o k7.csv
rc=0        {"meta":{"records":3,…}}        ← 追加確實發生了
```

`-o` 與 `--in-place` 兩種目的地都沒有拒絕。與 BB 合起來,得到的正是 README 預測「所以才要
拒絕」的那個檔案:「那個檔案會同時保留它,並在其後多出一筆完整的紀錄」。

## CE. 同一次執行裡,`-update` 到一筆正被 `-delete` 刪掉的紀錄,會被靜默丟棄(2026-08-20 修正,T111g–k)

```console
$ csv2 -delete 1,1 -update 1:2 'GHOST' -i g.csv --in-place
rc=0
$ csv2 -r -i g.csv
r2,n2,b                       ← GHOST 不在任何地方，也沒有任何訊息
```

**而同一個危險在「欄」這個軸上是被守住的**,訊息一字不差地說明了理由:

```console
$ csv2 -update 1:3 X -delete -col 3 -i f.csv -o dc3.csv
csv2: -update 1:3 targets a column that -delete -col is removing;
      the edit would have no effect and would still be reported as done
rc=1
```

**「那個編輯不會有任何效果,而且仍然會被回報為完成。」** 那句話描述的正是它在紀錄軸上
實際做的事。一條規則被想清楚、寫下來、實作在一個軸上,而另一個軸沒有。

## CF. 教你怎麼跳脫的那則訊息,自己被跳脫了——而這是我今天造成的(2026-08-20 修正,T111l/m)

```
README 說:   undefined escape sequence \q; .csv2 defines only \n, \r and \\
實際印出:   undefined escape sequence \\q; .csv2 defines only \\n, \\r and \\\\
```

照著訊息寫的人:

```console
$ printf 'k,v\nK,V\na,"line one\\nline two"\n' > lit.csv2     # 依訊息寫兩個反斜線
$ csv2 -get 1:2 -i lit.csv2 | od -c
l i n e   o n e   \   n   l i n e   t w o                     ← rc=0，而值是錯的
```

**成因是 AJ 的修法。** 今天早些時候我把跳脫集中到「建構 log 行」那一點,理由是「那是唯一
涵蓋得到日後每一則訊息的地方」——那個理由現在仍然成立,但那個做法**分不出「作者寫的散文」
與「程式插進去的輸入」**。而它們需要的處理正好相反:輸入必須被跳脫,散文必須原樣印出。

於是每一個 csv2 想教你的反斜線,在輸出的路上都被加倍了。

**這是同一天之內,同一段程式的第三次修正**:AI(呼叫那一行沒跳脫)、AJ(訊息沒跳脫)、
現在是 CF(訊息被過度跳脫)。前兩次是「規則沒套到所有地方」,第三次是「規則套到了不該套的
地方」——而三次的根源相同:**沒有分清楚「哪些位元組是資料」。**

Round 43's category 4 has four entries and every one is rc=0 with a wrong
result. The worst reintroduces this tool's headline failure on the fast path
the README says was fixed: `-append --in-place` onto a file whose last record
is open skips the check, writes at rc=0, and the file it produces cannot be
read back -- with the appended record swallowed by the unclosed quote and then
discarded by the documented repair. CF is mine, from this morning: centralising
the escaping fixed two defects and created a third, because a single choke
point cannot tell an author's prose from an interpolated value, and those two
need opposite treatment.

### CD:一個真的測試,斷言了一個真的拒絕,而它從未走到常見的那個情況

T91i／T91j 從存在以來一直通過,它們斷言的是「`--truncate-partial` 與 `-append` 併用會被
拒絕」。而那個拒絕當時只寫在「驗證失敗」的 catch 裡——**它成立的條件,正好就是 T91i／T91j
fixture 的條件:最後一筆不完整。**

健康的檔案上,同樣的組合以 rc=0 被接受,而兩份 README 在兩個地方都說它被拒絕。

**測試是真的、斷言是真的、通過也是真的。它從未走到的那個情況,才是常見的那個。**
現在 T91n／T91o 用一個健康的檔案。

### CF 的修法:讓那個關卡只做它分辨得出來的事

`lineEscape` 只跳脫「會結束一行的東西」——換行與 CR。它守住的性質是「一筆一行、無法靠開出
第二行來偽造」,而那個性質不需要知道哪些位元組是資料。

完整的跳脫回到「值」進入訊息的那一點:`redact`(值)與 `sanitizedCommandLine`(引數)。
那裡知道自己拿到的是資料。

於是三件事同時成立:散文原樣印出、值仍然無歧義、AI 與 AJ 關掉的偽造仍然關著。而**不會被
跳脫兩次**,因為關卡不再碰反斜線。

### 這四條合起來的形狀

| | 規則存在嗎 | 套到哪裡 | 沒套到哪裡 |
|---|---|---|---|
| BB | 是,README 說了兩次 | `-o` | `--in-place`(快路徑唯一服務的目的地) |
| CD | 是,文件說了兩處 | 驗證失敗時 | 檔案健康時 |
| CE | 是,訊息一字不差 | 欄 | 紀錄 |
| CF | 是,而且是我今天才建立的 | 值(正確) | 散文(不該套) |

**四條裡有三條是「一條想清楚的規則,只被套到它適用範圍的一部分」,而第四條是「被套到了不
適用的地方」。** 沒有一條是「沒有人想到這件事」。

Three of the four are a rule that was thought through and applied to part of
where it holds; the fourth is the same rule applied where it does not. None of
them is an oversight about what the right behaviour is -- that was written down
in every case, sometimes twice, sometimes in the message text itself.
---

# 第 44 回合(2026-08-20)—— 並行、就地修正、可讀的交付物、可重現性

## 先記一條「沒有通過驗證」的回報

受測者把 README 這句列為「文件寫錯」:

> 「它也無法在『資料檔改變、而大小、mtime、前後段位元組都沒變』時提供幫助;那個 O(1) 檢查
> 一直就是一個啟發式。」

它說自己造了三次那樣的檔案,包含一次奈秒精確的 `os.utime` 還原,而**索引每次都被判為過期**,
因此結論是「那句話低估了自己的安全性」。

**我重現不出來。** 60,000 筆、約 2 MB 的檔案,改中段一個位元組,`os.utime(ns=…)` 還原:

```console
size same: True  mtime_ns same: True
DEBUG parallel: trusting index z.csv.index, which declares no_embedded_newlines …
```

索引**被採信**。README 那句話成立。

最可能的成因是它的檔案太小:戳記包含前後各 64 bytes 的雜湊,而在一個幾百位元組的檔案上,
「中段」就落在那個範圍裡。

**這一條記在這裡,是因為它值得記。** 受測者三次嘗試都失敗,並且明說「這讓我一直以為是自己的
測試壞了,而不是那句話錯了」——那個誠實的敘述本身就是線索:一個一再失敗的重現,通常是重現
的問題。而它把結論寫成「文件低估了安全性」,方向與這棵樹上多數缺陷相反,更值得停下來量。

## CG. 「run with -debug to see why」——而讀者正在用 -debug(2026-08-20 修正,T112e/f)

```console
$ csv2 -contains y150 -i s.csv -debug
INFO  index s.csv.index is stale, ignoring and scanning
DEBUG single-threaded: .csv whose index s.csv.index was discarded as not describing this file
      -- run with -debug to see why, and --build-index to replace it
```

**理由就印在它正上方那一行。** 而那則訊息叫人去做他正在做的事。

**這是我今天寫的**(AN 的修法)。當時的推理是:理由在 INFO,而 INFO 只在 `-debug` 時才顯示,
所以「去開 -debug」對「沒開 -debug 的人」是對的建議。**那個推理漏掉了「已經開了的人」——
而那正是唯一看得到這則訊息的人。** 沒開 -debug 的人兩行都看不到。

修法是把理由帶進訊息本身,而不是叫人去別的地方找。

## CH. `--verify-index` 對「過期的索引」說的是「沒有索引」(2026-08-20 修正,T112a–d)

```console
$ csv2 --verify-index -i s.csv          # sidecar 存在，只是過期
csv2: no usable index beside s.csv
csv2：s.csv 旁沒有可用的索引
```

**sidecar 就在那裡。** 而這個工具在別的地方對「不存在」與「存在但不能用」是分得很清楚的
——AN 那一條就是為了這個分別而修的,同一天。這裡把兩種狀態合成了一句話。

## CI. `-md` 不輸出 meta 行,而文件指定的補救方法只在 meta 行裡(2026-08-20 修正,T112g–j)

第 43 回合之後,README 寫下了「`-mid` 起點超過結尾會在 rc=0 下輸出空的」以及分辨方法:
「請讀 `--json` 結尾那行 meta 的 `records`」。

而受測者指出那個補救**接不上你真正要交出去的東西**:

```console
$ csv2 -mid 500,505 -t -md -i s.csv      # 檔案只有 299 筆
|a|b|
|---|---|
                                          ← 一張看起來完整的空表格，rc=0
```

`-md` 不輸出 meta 行。**偵測的管道與呈現的管道不相通。**

## CJ. README 的 `--json` 範例說 21 筆——而那是對的(2026-08-20 澄清,T113)

```console
$ csv2 -r --json -i TARGET_PACKAGES.csv | tail -1
{"meta":{"records":22,"matched":0}}
```

README:`{"meta":{"records":21,"matched":3}}`。`matched:3` 仍然正確,筆數不是。

一個「指名了某個 fixture」的範例裡的數字,而那個 fixture 會變。這與 T69 守的是同一類東西
(文件裡會漂移的數字),只是 T69 守的是 PASS 數量。

## CK. 兩個人同時編輯同一個檔案:最後寫的全贏(2026-08-20 記入文件,行為不變)

受測者的量測:5 次試驗,5 次都是——兩個行程 rc=0、兩筆稽核紀錄都宣稱成功、一個編輯消失。

而稽核軌跡因此會說出一件不成立的事:

```
update 200000:name: "name200000" -> "BOB"
wrote 200000 records, 4 fields, atomic rename OK
```

**每一句對那個行程都是真的,而整份軌跡對那個檔案是假的。** BOB 不在檔案裡。

這是 temp file + rename 的內在後果,不是實作錯誤——rename 是不可分割的,因此讀者永遠看到
一個完整的檔案(受測者用 80 次重疊讀取驗證了這一點,0 次撕裂),但兩個寫入者之間沒有任何
互斥。

**兩份 README 對「資料檔的並行」一個字都沒有。** 對 `-log` 有(那是 AK 修的),對資料檔沒有。
而讀者拿到的「讀取端永遠看到完整檔案」這個保證,目前只以實作註記的形式存在
(「寫暫存檔再 rename」),沒有被寫成一個承諾。

Round 44. One reported finding did not survive verification, and it is
recorded because the direction is unusual: the subject concluded the README
UNDERSTATES the O(1) stamp's safety, having failed three times to build a
same-size same-mtime change that the stamp missed. It reproduces here on a
2 MB file. Their file was most likely small enough that its middle fell inside
the head/tail hashes. A reproduction that keeps failing is usually the
reproduction.

### CJ 也沒有通過驗證,而它揭出的是另一件事

README 的範例對它所描述的那份 fixture 是**正確的**:

```
test/fixtures/TARGET_PACKAGES.csv   21 筆   ← README 說 21
母專案的工作複本                     22 筆   ← 受測者手上是這一份
```

**兩份同名,而 README 兩份都沒指名。** 於是那些數字描述的是一個讀者辨認不出來的檔案,而
「哪一份漂移了」也沒有任何東西在看。

修法不是改那個數字,而是:把路徑寫全,並由 **T113** 每次執行都拿範例裡的 meta 行去對照那份
fixture 實際的產出——連同「兩份 README 的數字必須一致」。

**這一輪有兩條回報沒有通過驗證(O(1) 戳記、範例筆數),而兩條都在被查證時變成了別的東西:**
第一條什麼都不是(重現方法有問題),第二條是一個真實但不同的缺陷(同名的兩份檔案)。

### CI 的修法:警告走 stderr,因為那是每一種輸出形狀都載得動的地方

`-md` 不可能有 meta 行——那會破壞表格。而「起點超過結尾」與「終點被截斷」是不同的兩件事:
後者是刻意的、由 T14c 釘住,前者則是「呼叫端要的東西沒有任何一部分可能被回傳」。

因此只有前者發出 WARN,而且走 stderr:每一種輸出形狀都載得動它,不污染任何管線,而 WARN 是
預設門檻所以不必特地要求。結束狀態仍然是 0——那次執行做了它被告知的事。

### CK 沒有改行為,而那是刻意的

加鎖會把「一個純粹的資料工具」變成「一個需要處理鎖檔、陳舊鎖、以及鎖在網路檔案系統上不可靠」
的工具。而真正該說出來的是兩件事,一件是危險、一件是保證,兩件文件都沒寫:

- **危險**:兩個寫入者,最後完成的全贏,靜默,3/3。
- **保證**:讀取端永遠看到完整的檔案,因為 rename 是不可分割的。受測者用 80 次重疊讀取
  量到 0 次撕裂。

**那個保證原本只以實作註記的形式存在**(「寫暫存檔再 rename」)。沒有人能拿一個「沒有被告知
是承諾」的機制去建構東西。兩者現在都寫進了兩份 README。

Two of round 44's reports did not survive verification, and both turned into
something else under it: the O(1) stamp claim was nothing (the reproduction was
at fault), and the stale example number was a real but different defect -- two
files with the same name, and the README naming neither.
---

# 第 45 回合(2026-08-20)—— 外來的檔案、數字、自我診斷、交給新手

受測者最後一段值得先抄下來:

> 「四次我斷定某件事錯了,而錯的是我。……這個工具在被仔細檢視時,表現得比我的眼睛更可靠
> ——而那正是任務 1 那三個『靜默誤讀』要緊的原因:它們是再怎麼小心都抓不到的那一種,
> 因為 csv2 回報的是成功。」

## CL. 一個負數的環境旗標,讓 csv2 靜默崩潰(2026-08-20 修正,T114)

```console
$ CSV2_PARALLEL_MIN_BYTES=-1 csv2 -contains 1 -i tiny.csv
rc=133   stdout 0 bytes   stderr 0 bytes
```

**133 = 128 + 5,SIGTRAP。** 沒有訊息、沒有輸出、沒有任何東西可以讓呼叫端回報。

那正是這個工具存在所要防止的那一類:一次失敗,而它看起來不像任何東西。README 說
「成功為 0,任何錯誤為非零」以及「每一種拒絕都恰好兩行 stderr」——**兩句在這裡都不成立**。

## CM. 而同一族的旗標,三種行為各不相同(2026-08-20 修正,T114)

| 值 | 結果 |
|---|---|
| `CSV2_PARALLEL_MIN_BYTES=-1` | **SIGTRAP,靜默崩潰** |
| `CSV2_MAX_BUFFER_RECORDS=-1` | 不崩潰,但訊息說「超過可緩衝的紀錄上限(-1)」 |
| `CSV2_PARALLEL_MIN_BYTES=16MiB` | **靜默退回預設**,而 `-debug` 用那個變數的名字回報預設值 |

第三種最難察覺:一個以為自己把門檻設成 16 MiB 的人,拿到的是 `under CSV2_PARALLEL_MIN_BYTES
(16777216)`——那個數字剛好也是 16 MiB,於是那一行看起來像是確認,實際上是巧合。若他寫的是
`8MiB`,那一行會顯示 16777216,而他仍然會以為那是他設的值。

**「不要靜默修復格式錯誤的輸入」是這個專案寫在 CLAUDE.md 裡的規則,而環境變數是輸入。**

## CN. 我今天加的那則 WARN,讓四處文件變成假的(2026-08-20 修正)

第 44 回合我為 `-mid` 起點超過結尾加了一則 WARN(CI)。**而我沒有回頭去看它讓什麼變成假的:**

| 文件 | 現在為假 |
|---|---|
| `-mid` 的旗標說明 | 「起點超過結尾時會在 rc=0 下輸出空的——與『存在且為空的視窗』**無法區分**」 |
| 「正常路徑上不輸出任何東西」 | 現在會輸出一行 |
| 「錯誤輸出到 stderr,**恰好兩行**」 | 那則 WARN 是一行,而且只有英文 |
| `csv2view` 一節 | 仍把「`-mid` 起點超過結尾時給出錯誤而非空輸出」列為「尚未做到」 |

**這是同一個模式的第四次,而這次的間隔是幾小時。** AF(README 狀態表)、AN(我寫的
「每一條拒絕都會指名索引」)、AO(平行 RSS 的模型)、現在是 CN。

每一次的形狀都一樣:**加了一段文字,而沒有去作廢它所使之為假的東西。**

## CO. CR 行尾的偵測器,差一個位元組就不觸發(2026-08-20 修正,T115a–d)

csv2 有一個 CR-only 檔案的偵測器,訊息品質很好(`convert it first with: tr '\r' '\n' < file > file.lf`)。

而受測者構造出一個它抓不到的檔案:**以 CR 分隔、但最後有一個 LF**。結果是 0 筆紀錄、rc=0、
`-contains` 找不到任何東西,而 `--verify-index` 說 `index OK`。

**偵測器存在、訊息也寫好了,只是那個檔案剛好差一個位元組就不觸發。**

## CP. UTF-16 的檔案被靜默誤讀(2026-08-20 修正,T115e–g)

csv2 讀進一個 UTF-16 檔案、誤解它,然後把它的 BOM 寫進自己的輸出——**於是 csv2 產生了不是
合法 UTF-8 的位元組**。

那與這個工具對 round-trip 的立場相抵觸,而與文件怎麼說無關。

## 還有一條沒有通過驗證:O(1) 戳記,第二次被回報

受測者說那個戳記「比文件說的更強,因為它也用了 ctime」。

**我用 `os.utime` 還原 mtime(不動 ctime)量過,索引仍然被採信。** 若 ctime 有被檢查,它就
會被拒絕。這一條與第 44 回合那一條是同一個回報,而兩次都沒有通過驗證。

**同一個宣稱連續兩輪被提出、兩輪都推翻不了 README,值得記在這裡**——下一輪若再出現,可以
直接指到這一段,而不必再量一次。

Round 45. A negative environment knob makes csv2 die of SIGTRAP with nothing on
either stream -- a failure that looks like nothing at all, in a tool whose
entire premise is that failures must be loud. The same family of knobs then
behaves three different ways for bad values, one of which silently substitutes
the default and reports it under the variable's own name.

And the WARN added yesterday for CI falsified four places in the documentation,
none of which I went back to look at. Fourth instance of that pattern, this
time hours apart rather than days.

### CP 的回報有一半沒有通過驗證,而剩下的那一半才是真的

受測者說 csv2「把 UTF-16 的 BOM 寫進自己的輸出,於是產生了不是合法 UTF-8 的位元組」。

**輸出是合法 UTF-8。** NUL 也是合法的 UTF-8 碼位,而那正是 UTF-16 在位元組層看起來的樣子。

**但剩下的那一半是真的,而且更重要**:一個 UTF-16 檔案被靜默地當成 UTF-8 讀,rc=0,產出的
紀錄毫無意義。那與「位元組原樣往返」的承諾並不衝突——它就是那個承諾的結果——而問題在於
**沒有任何東西告訴拿著檔案的人,他讀到的不是他以為的東西**。

修法沿用這個工具已經有的那個形狀:CR 偵測器。`FF FE` 與 `FE FF` 不可能出現在 UTF-8 檔案的
開頭,因此看到它不是在猜;拒絕而不是轉換,理由與 CR 那條相同——**猜測編碼,正是一個工具
最後靜默產生出「看似合理而錯誤」的東西的方式。**

### CN:同一個模式的第四次,而這次間隔是幾小時

| | 加了什麼 | 沒有回頭作廢什麼 |
|---|---|---|
| AF | README 描述 `install.zsh` 的行為 | 狀態表裡的「尚未」欄 |
| AN | 「每一條拒絕索引的路徑都會指名它」 | 我沒有量過的那一半 |
| AO | 平行 RSS 的數字 | 那個模型本身(當天被 AR 推翻) |
| CN | `-mid` 的 WARN | 四處:`-mid` 說明、「正常路徑不輸出」、「錯誤恰好兩行」、`csv2view` 的待辦清單 |

**四次的形狀完全相同:加了一段文字,而沒有去看它讓什麼變成假的。**

而這一次多學到一件事:那則 WARN 是**一行、只有英文**,而那與這個工具裡每一則診斷一致——
「兩行雙語」屬於「結束一次執行」的那則訊息。**我原本以為那是不一致,查了程式才知道那是慣例。**
文件現在把那個分界寫出來了,而它原本從來沒有被寫下來過。
---

# 第 46 回合(2026-08-20)—— 把拒絕表逐條打一遍、刻意製造 rc=0 的錯誤答案

**這一輪找到目前為止最嚴重的一條,而它是這個工具自己造出來的那種失敗。**

## CQ. `-append --in-place` 弄壞它自己的索引,於是 `-contains` 在 rc=0 下給出錯的位址(2026-08-20 修正,T116a–d)

```console
$ csv2 --build-index -i a.csv                       # 1100 筆
$ csv2 -append "$(printf '1101,"two\nlines",x')" -i a.csv --in-place
rc=0
$ csv2 --verify-index -i a.csv
index MISMATCH: no_embedded_newlines: index says the file has none, but record 1101 spans lines
```

那筆被追加的紀錄是**合法的 CSV**——引號欄位裡的換行,正是這個工具存在所要處理的東西。而
就地追加的快路徑更新了索引的**筆數、偏移量與新鮮度戳記**,唯獨沒有動 `no_embedded_newlines`。

於是 O(1) 檢查通過了——**戳記是最新的,因為這條路徑剛剛才更新過它**——`-contains` 走上平行
路徑,而「被追加那一筆之後的第一個區塊邊界」以後的每一筆,編號都大了一。

受測者量到的後果:

```
$ csv2 -contains …                     1102:2
$ csv2 -get 1102:2 -i …                no such record; the file has 1101 records
```

**照著 README 自己那套「先找再改」的寫法做,值被寫進了錯的那一列**,rc=0,而稽核軌跡裡那
一筆對「位元組」是真的、對「意圖」是假的。

### 這是 T79 那個缺陷從另一扇門回來

T79 修的是「三個呼叫點設定 `no_embedded_newlines`,其中兩個傳常數」。這一次是第四個地方
——一條**編輯**索引而不是重建它的路徑,而那是唯一一條有這件事可以做錯的路徑。
`-append` 搭配 `-o`、以及 `-update`,都是對的,因為它們重建索引。

**一份索引宣稱了一個沒有任何東西重新推導過的檔案性質。** 一字不差,就是 T79 的那句話。

## CR. 同一格上的兩次 `-update`,第一次被靜默丟棄(2026-08-20 修正,T116e–g)

```console
$ csv2 -update 1:2 'FIRST' -update 1:2 'SECOND' -i u.csv --in-place
rc=0
$ csv2 -get 1:2 -i u.csv
SECOND
```

而這個工具對「`-update` 撞上同一次執行的 `-delete`」的拒絕,理由是:

> **「該編輯不會有任何效果,卻仍會被回報為已完成。」**

那句話**逐字描述了它在這裡做的事**。

值得對照的是「同一個 N 上的兩次 `-insert`」——那是**記錄在案的**行為,兩筆都會寫入,依書寫
順序。兩者的差別是真的:兩次插入產生兩筆紀錄,兩次更新只有一次會留下。

## CS. 一個沒有歸屬動詞的修飾符會被接受並忽略(2026-08-20 修正,T116h–j)

```console
$ csv2 -cell -r -i f.csv
rc=0
$ csv2 -insert 1 'z,z,z' -cell -i i.csv --in-place
rc=0                                    ← 那個「-insert 不可與 -cell 併用」的拒絕沒有觸發
```

`-cell` 與 `-col` 是修飾符,必須依附在一個動詞上。單獨出現時它們什麼也不做,而且不出聲。

而「`-insert -cell` 被拒絕」這件事因此是**位置性**的,不是語意性的:把 `-cell` 寫在兩個位置
參數之後就繞過去了。

**README 記過 multissh 被「被吞掉的選項」咬過一次,而這是同一個形狀。**

## 一條沒有重現:引數錯誤回報了一個不存在的位置

受測者說一個壞掉的 `-append` 引數會被回報成 `header row 0a (line 1), field 3`。

我這裡得到的是:

```
csv2: -append has 2 fields but the header has 3; csv2 will not pad or truncate to fit
```

**沒有位置,而且是對的。** 可能是它的構造不同,也可能是同一天稍早的某個修正順手改掉了。
記在這裡,因為若它再出現,這一段可以省下一次重新量測。

Round 46 found the worst defect so far, and the tool produced it itself: the
in-place append fast path updates an index's record count, offsets and
freshness stamp while leaving its `no_embedded_newlines` claim untouched. Append
a legitimate multi-line record and the index now asserts a property of the file
that nothing re-derived -- T79's sentence, word for word, arriving through a
fourth call site that EDITS an index rather than rebuilding one. The O(1) check
then passes because this path just refreshed the stamp, -contains takes the
parallel path, and following the README's own find-then-edit recipe writes into
the wrong row at rc=0.

### 而 T116 的 fixture 被同一個 zsh 陷阱弄壞了第三次

`local` 用在大括號群組(不是函式)裡,zsh 會拒絕;那個拒絕走 stderr,而群組的 stdout 仍然
寫進檔案,於是 fixture 是壞的、腳本照常往下跑。

**T108、T110,現在是 T116。** 前兩次我都修好了、也都在旁邊寫下了成因,而第三次照樣發生。

「寫下來」擋不住它。三處現在都在出事的那一行旁邊有註解,而那是目前唯一試過還沒失敗的做法
——雖然這句話在第二次之後我也說過。

### CQ 的修法:數換行

每一筆被追加的紀錄都恰好以一個換行結尾。因此 payload 裡的換行數若多於被追加的筆數,就代表
至少有一筆在引號欄位裡帶著換行——而那時 `no_embedded_newlines` 必須變成 false。

不用去解析那一列。**這條路徑之所以是快路徑,正是因為它不解析**;而讓它為了維持一個宣稱而
開始解析,會把它變成它原本要避開的那個東西。

## CT. 雙語編輯又只落地了一半,而這次是我在修 CP 的時候

第 46 回合的受測者指出:**UTF-16 與 CR 的拒絕只寫在中文 README 裡,英文版完全沒有。**
一個只讀英文的人不知道它們存在。

成因與 **AE** 一模一樣:一支同時改兩份檔案的 Python 腳本,在中文那半的 anchor 上 assert
失敗,而**寫入發生在腳本結尾**——於是兩份都沒寫。我重試時只補了中文那一半,因為那是我記得
還沒做的部分。

**AE 之後我寫下的結論是:「失敗之後的重試必須從頭再跑一次完整的腳本。」而我沒有照做。**

同一段時間裡還有第二處:我修掉了英文 `csv2view` 清單裡「`-mid` 起點越界要報錯」那一項
(它已經以 WARN 出貨),卻沒有動中文那一份。中文因此同時說「三件事」又只列了兩件。

### 這一條的修法不是「下次小心」

`T117` 現在比對兩份 README 引用的測試編號集合。一節在某一種語言裡寫著「由 T115 斷言」而在
另一種語言裡根本不存在,會立刻浮出來,**而且不必有人記得去檢查**。

那個不變式本來就會抓到這一次:英文缺 T115,中文有。

它另外還檢查第三件事——README 引用的每一個案例編號,在測試檔裡真的存在。那是反方向的漂移:
文字活得比測試久。

**兩次「雙語只落地一半」都是盲測受測者找到的,而這棵樹上沒有任何東西在看。現在有了。**

Bilingual edits keep landing on one side only, and both times it was a
blind-test subject who noticed. The cause is identical to AE: one script
editing both files, an assertion failing on the second file's anchor, writes
deferred to the end so NEITHER lands, and a retry that only covers the half I
remembered. AE's own conclusion was "a retry must re-run the whole script", and
I did not follow it. T117 now compares the case numbers cited by the two
READMEs, which would have caught this one, and does not depend on anyone
remembering.
---

# 第 47 回合(2026-08-20)—— 把每一個範例跑一遍、索引的每一種不一致、事前成本、可依賴性

受測者的結論值得抄下來:

> 「這個工具狀況良好。**它有一個洞,它知道那個洞,而它選擇了記錄它而不是守住它。**」

## CU. 每一個診斷範例都少了它真正會印出來的前綴

README 印的是:

```
DEBUG parallel: 9 chunks, 10 workers, chunk 512 bytes
```

實際印出來的是:

```
csv2: 2026-08-20T19:32:39.922+08:00 DEBUG parallel: 9 chunks, …
```

**照著印出來的形狀寫的腳本,一行都比對不到。** 兩份 README 加起來約十個這種範例。

而同一段的第一個例子在逐字執行時給出的是**相反的答案**:它展示 `parallel: 9 chunks`,而一個
44 bytes 的檔案得到的是 `single-threaded: file is 44 bytes, under CSV2_PARALLEL_MIN_BYTES`。
那個範例需要的環境變數沒有寫出來。

## CV. 「`records` 是讀了多少筆資料紀錄」在走索引時不成立

受測者量到:`-tail 1` 在讀了 12,288 bytes、只解析一筆之後,回報 `records:600000`。

**它是「抵達的紀錄編號」,不是「讀過的筆數」。** 對一個拿它來估算成本的人,那個差別是全部。

## CW. 「下一個讀完整個檔案的操作會寫回一份好的索引」與旗標說明互相矛盾

`-contains` 與 `-r` 各自讀完了 38 MB,而**兩者都沒有寫索引**。只有 `-tail` 與寫入類的操作會
——那正是 `--build-index` 那個旗標條目自己說的。

**同一份文件的兩節說了不同的事。**

## CX. `-contains` 的旗艦範例,少了它自己下一段所承諾的那個記號

範例展示被截短的值,而**沒有 `…[+N more chars]`**;緊接在它下方的句子寫著「csv2 會標記那個
截斷——絕不靜默」。

## 而第 4 類只有一條,它是一個論證,不是一個新缺陷

受測者把「被信任的過期索引 → 錯誤紀錄編號、rc=0」歸進第 4 類,而且說明了為什麼要這樣歸:

> 「這個工具的宗旨是『**其他任何情況都必須大聲失敗,而不是靜默產生一個半對的檔案**』。
> 一個 rc=0 的錯誤 `record:field` 位址,就是一個靜默的半對答案,而它出自那條 README 自己
> 指認為『唯一可能靜默出錯』的路徑。文件的回應是一段文字。**沒有旗標能說「未經證明的索引
> 就不要信」、沒有自動降級、也沒有 WARN——而 WARN 機制存在,還用在更小的事情上**
> (`-mid` 起點越界就有一個)。」

**它的前提有一半是錯的,而那一半正是重點。**

```console
$ csv2 -contains 'note 39999' -i z.csv          # 被信任的過期索引
40000:2                                          ← 錯
$ csv2 --no-index -contains 'note 39999' -i z.csv
39999:2                                          ← 對
```

**那個旗標存在,而且做的正是它要的事。** 缺的是:README 從來沒有把 `--no-index` 與這個風險
連起來。它被寫成一個機制(「絕不讀寫 sidecar」),而不是一個「你正在問的問題的答案」。

它的第二半則是對的:**在那個唯一可能靜默出錯的分支上,能提醒你的只有一行 DEBUG**,而一個
「起點越界的 `-mid`」拿到的是預設可見的 WARN。這個不對稱是真的。

Round 47's category 4 is one entry and it is an argument rather than a new
defect: the trusted-stale-index gap is documented and unguarded, while the WARN
machinery exists and is spent on smaller things. Half its premise is wrong --
`--no-index` is exactly the flag it says does not exist, and it returns the
right answer -- and that half is the point: the README presents `--no-index` as
a mechanism, never as the answer to the question a reader is actually asking.
---

# 第 48 回合(2026-08-20)—— 讓工具與自己矛盾、無人看管的 cron、可證偽的效能宣稱、監控包裝

## CY. 平行路徑把「區塊結束了」說成「輸入結束了」,而紀錄號也是錯的(2026-08-20 修正,T118)

```console
$ printf 'pkg,note\ntext,text\nzlib,"has a\nraw newline"\nzstd,ok\n' > r.csv2

$ csv2 -r -i r.csv2
csv2: record 1 (line 3), field 2: a raw newline inside a cell; .csv2 keeps one
      record per line, so newlines must be written as \n          ← 正確

$ CSV2_PARALLEL_CHUNK_BYTES=8 csv2 -contains ok -i r.csv2
csv2: record 3: the input ends inside a quoted field -- the closing quote is
      missing. The record is incomplete; pass --truncate-partial to discard it.
```

**三件事同時錯了:**

| | |
|---|---|
| 診斷 | 沒有任何引號未關閉;那是一個 `.csv2` 裡不合法的裸換行 |
| 位置 | 問題在第 1 筆,訊息說第 3 筆 |
| 補救 | `--truncate-partial` 在這裡什麼也不做,而若它真的作用了,它會丟掉一筆**完整**的紀錄 |

而同一個檔案在 chunk ≥ 16 時得到的是正確訊息。**同一支解析器對同一個檔案的內容,說了兩種
互相矛盾的話,取決於一個環境變數。**

### 成因:結束的是「區塊」,不是「輸入」

平行工作者只看得到自己那一塊。當一個區塊邊界落在引號欄位中間,那個工作者讀到自己的結尾時
仍在引號裡,於是報出「輸入在引號欄位中結束」——**而輸入根本沒有結束,是它的視野結束了。**

`CSV2_PARALLEL_CHUNK_BYTES=8` 顯然是荒謬的設定,但那個機制不是:預設 4 MiB 之下,任何一個
大於 4 MiB 的引號儲存格都會產生同一件事。真正的觸發條件是「一個宣稱一筆一行、而實際上不是
的檔案」——而那正是平行路徑所依賴的前提。

**兩者都以 1 結束,所以這是一次大聲的失敗配上一個錯的故事**——是壞掉的種類裡最不糟的一種。
但受測者說得對:**「解析器對一個檔案的內容與自己矛盾」正是這個工具的核心能力所在。**

## 而第 4 類的另一條,是第 47 回合那個論證的再次提出

「被信任的過期索引 → rc=0 的錯誤紀錄編號」。受測者這次明白寫出它為何仍歸在這一類:

> 「被記錄在案並不等於沒有壞。在一個 19.5 MB 的檔案上、沒有任何環境變數、沒有任何不尋常的
> 旗標,`csv2 -contains` 與 `csv2 -get` 對同一個儲存格給出互相矛盾的事實,兩者都是 rc=0,
> 而那個位址會餵給 `-update` 去覆寫錯的那一筆。」

這與第 47 回合是同一個論證,而它上一次促成的是文件修正(把 `--no-index` 寫成那個問題的答案)。
**連續兩輪、兩個獨立的受測者提出同一件事,本身就是一項資料**:那一段文件說服不了讀者,
而那通常代表要改的不是文字。

Round 48. The parallel path tells a different story about the same file
depending on a chunk-size environment variable: a worker whose chunk boundary
lands inside a quoted field reports that the INPUT ended inside a quoted field,
with the wrong record number and a remedy that would discard a complete record.
What ended was the worker's view, not the file. Both paths exit 1, so it is a
loud failure with a wrong story -- the least bad kind of broken -- but a parser
contradicting itself about what a file contains is this tool's core competence.

### CY 的修法不是換一句更好的話

一個在引號中間結束的區塊,只代表一件事:**這個檔案不是一筆一行**,而那正是格式或索引交給
平行路徑的前提。

於是這次執行做這個工具在其他每一處對「前提被推翻」所做的事——**丟掉它、改用掃描**。兩條
路徑因此說法一致,因為說話的是同一段程式。

那則舊訊息仍然存在,而且仍然正確——對一個**真的**在引號欄位內結束的檔案(T118d 守著它)。
它原本唯一的錯,是被說給一個「還有下文」的讀者聽。

## CZ. `-append` 不再是 O(1),而說它是 O(1) 的是我在第 43 回合之後沒改的文件

```
1,877,798 bytes   0.07 s
8,177,798 bytes   0.24 s
34,577,800 bytes  0.92 s
```

**完全線性。** 受測者在一個 591 MB 的檔案上量到「寫 6 個位元組花 11.4 秒」。

成因是我自己的修正:第 43 回合修 **BB** 時,我讓就地追加**每一次都驗證整個檔案**——因為
「最後一筆不完整的檔案」不能安全地被追加,而沒有便宜的方法可以知道。那個交換是對的:

> 另一個選項是「一次被回報為成功的寫入,產生一個這個工具自己拒絕讀取的檔案」。

**但我沒有回頭去改那三處說它是 O(1) 的文件。** 旗標說明、狀態表、以及與 PostgreSQL 的比較
那一節,全都還寫著 O(1)。

**這是同一個模式的第五次**(AF、AN、AO、CN,現在是 CZ):**做了一件正確的事,而沒有去作廢
它所使之為假的東西。** 而這一次被作廢的不是一句描述,是一個**效能承諾**——那是有人會據以
決定「要不要在 cron 裡對一個 591 MB 的檔案每分鐘跑一次」的東西。

三處現在都寫出實測數字,以及那個交換本身。

## DA. 整個工具裡唯一一則三種形狀都不符合的訊息

```
csv2: warning: cannot write log file nolog.log; continuing / 警告：無法寫入 log 檔，操作照常繼續
```

README 記載了三種形狀:錯誤是**恰好兩行**、英文在前中文在後;WARN 是**一行、只有英文**;
而每一行診斷都以 `csv2: <ISO-8601 時間戳> 層級 ` 開頭。

**這一則三種都不是**:一行同時帶著兩種語言、以 ` / ` 相連、沒有時間戳、沒有層級記號,而且
用小寫的 `warning:`。

受測者是在寫「給監控系統用的包裝腳本」時撞到的,而它指出了要害:**這一則訊息伴隨的是一次
rc=0 的執行,因此剖析錯它,就等於完全錯過它。**

它不能直接走 `Logger.warn`——那會同時寫進 log 檔,而剛剛失敗的正是那個 log 檔。因此現在
以相同的形狀組出來,只送到 stderr。

`-append` stopped being O(1) when I fixed BB in round 43 -- the in-place path
now validates the whole file before appending, because a file whose last record
is incomplete cannot be safely appended to and there is no cheap way to know.
The trade was right. Not going back to the three places that promise O(1) was
not. Fifth instance of that pattern, and the first where what was falsified is
a performance promise rather than a description -- the kind of thing someone
decides a cron schedule on.
---

# 第 49 回合(2026-08-20)—— 可量測的句子、三條路做同一件事、每一個數字的邊界、兩份 README 的決策差異

## DB. `-insert 0` 靜默丟掉那一列,而稽核軌跡替它背書(2026-08-20 修正,T119)

```console
$ csv2 -insert 0 'z,z,z' -i g.csv --in-place -log L.log
rc=0                       stderr 0 bytes      檔案逐位元未變

$ grep wrote L.log
2026-08-20T20:43:42.230+08:00 INFO  wrote 2 records, 3 fields, atomic rename OK
```

**「寫了 2 筆、3 欄、atomic rename OK」——而那一列從未進去。** `-insert -1` 也一樣。

而每一個同輩動詞都拒絕 0:

```
-delete 0,0     csv2: -delete takes N or a,b
-head 0         csv2: -head 0: a count must be at least 1
-mid 0,2        csv2: -mid: a must be >= 1; records are numbered from 1
-update 0:1     csv2: -update: expected r:c, got "0:1"
```

**上界有檢查**(`-insert 11` 在 10 筆的檔案上會被拒絕),**下界沒有**。而文件說的是
「合法範圍是 `1..N`」——那句話是我第 43 回合寫的,它描述的是應然,而程式只做了一半。

在批次裡它更糟:**丟掉自己那一列、套用其餘的**,於是產生一個部分完成的結果,rc=0。

受測者的話:

> 「這是一次靜默的、看起來成功的、半對的寫入,而且有一筆稽核紀錄替它作證——正是 README
> 前兩頁說 csv2 是為了終結它而存在的那種失敗。」

## DC. 中文訊息裡夾著沒翻譯的英文,而它們有一半是我今天寫的(2026-08-20 修正,T120)

```
csv2：record 1 (line 2) 有 2 欄…
csv2：…無法使用：stale: the data file changed。
csv2：…its own checksum does not match (damaged)。
```

後兩則裡那些英文,是我在 CG／CH 修正時加的 `lastDiscardReason` 字串——**我只寫了英文,然後
把它插進兩種語言的訊息裡。**

「錯誤恰好兩行、英文在前中文在後」這個契約**依行數成立,依語言不成立**。

## 而第 1 類裡有一條也是我的

英文版的 `csv2view` 一節現在說「csv2 必須先具備的三件事」,而它只列了兩件——因為我在第 47
回合移走了第三件,卻沒改那個數字;中文版我當時改成了「兩件」。

**同一次編輯,兩份檔案,一份改了數字一份沒改。** 與 CT 是同一天的同一個模式,只是方向相反。

Round 49. `-insert 0` discards its row at rc=0 with an audit entry saying the
write happened -- the exact failure this tool's first two pages say it exists to
end -- while every sibling verb refuses zero. The upper bound of the documented
`1..N` is enforced and the lower is not.

### DB 的修法要連「批次」一起管

`-insert 0` 單獨出現時只是丟掉那一列;但在批次裡,它會丟掉自己那一列、**套用其餘的**,
於是產生一個「部分完成」的檔案,rc=0。

因此拒絕發生在**引數解析時**,而不是在套用編輯時——整批一起被擋在任何寫入之前。
T119e/T119f 釘住的正是這一點:含有 `-insert 0` 的批次,其他編輯也不會被套用。

### DC 的成因值得說清楚:一個只寫了一次的字串,被用了兩次

`lastDiscardReason` 是我在 CG／CH 修正時加的,而我只寫了英文。呼叫端把它插進一則雙語兩行
訊息的**兩**半裡,於是中文那一行讀起來是:

```
csv2：索引 … 存在但無法使用：stale: the data file changed。
```

**「恰好兩行、英文在前中文在後」依行數成立、依語言不成立。**

現在它是一對 `(en, zh)`。而 T120b 斷言的是「英文那句**不在**中文行裡」——只斷言「中文在」
的話,一行同時含有兩者也會通過。
---

# 第 50 回合(2026-08-20)—— 把每一個旗標放到它不該在的位置

## DD. 一個旗標被寫進了你的資料

```console
$ csv2 -update 1:1 -t -i f.csv --in-place
rc=0
$ csv2 -get 1:1 -i f.csv
-t
```

`-append --json` 會追加一筆內容是 `--json` 的紀錄。

**這是這個工具的招牌失敗——以 0 結束、輸出看似合理的垃圾——而它是從自己的引數解析器進來的。**

而 README 引用過 multissh 被「未知選項被當成主機名吞掉」咬過的事,作為「未知旗標一律視為
錯誤」的理由。**那條原則本來就在,只是停在「未知」旗標上。**

修法要精確:**只擋已知旗標**,不是「所有以減號開頭的東西」——`-update 1:2 -5` 存的是一個
負數,必須繼續能用。而「值本身就是旗標名」的情況需要一條真的存在的出路,因此加上 `--`:
`-update 1:1 -- -t`。

那份 `KNOWN_FLAGS` 清單由 **T121h** 對照解析器自己的 `case` 檢查——一份放在 switch 旁邊的
名稱清單,正是那種會漂移的東西。

## DE. 一個旗標給兩次,後者靜默取代前者——而其中一個有安全後果

```console
$ csv2 -hash note -hash b -keyfile k.bin -i f.csv -o h.csv -t
rc=0
$ head -1 h.csv
a,b:hmac:76a06e81,note          ← note 是明文
```

**那個檔案存在的全部目的,就是讓 `note` 被遮蔽。**

README 明說編輯動詞「可重複、會累加」,而其餘旗標那條相反的規則從來沒有被寫出來——這讓
「後者取代前者」不只是意外,而是會主動誤導人。

現在 `-i`、`-o`、`-contains`、`-head`、`-tail`、`-mid`、`-get`、`-hash`、`-encrypt`、
`-decrypt`、`-keyfile`、`-log`、`--headers` 給兩次都會被拒絕,訊息裡指名可重複的是哪四個。

## DF. 兩組不可能同時成立的旗標,只有一組被檢查

```console
$ csv2 -update 1:1 'Z' -i ip.csv --in-place -o out.csv
rc=0     ip.csv 逐位元未變     out.csv 被寫出     log 記下了那次編輯
```

`-o` 與 `-so` 是文件裡明訂互斥的;`-o` 與 `--in-place` 的互斥程度完全一樣,而沒有被檢查。
一個要求「就地編輯」的呼叫端,拿到的是 rc=0、一筆稽核紀錄,以及一個沒有被動過的檔案。

同一族的另一個:`--build-index --no-index` 會被當成矛盾拒絕,而 `--verify-index --no-index`
不會——**它讀了 `--no-index` 明令不讀的那個 sidecar,並回報 `index OK`。**

## DG. 稽核軌跡的總結行,描述的是輸入

```console
$ csv2 -delete 1,2 -delete -col 7 -i x.csv --in-place -log W.log
$ grep wrote W.log
wrote 22 records, 7 fields, atomic rename OK
$ csv2 -r --json -i x.csv | tail -1
{"meta":{"records":20,…}}          ← 而且是 6 欄
```

**兩個數字都在描述讀進來的東西**,而那一行是這份軌跡裡「總結結果」的唯一一行——它自己
宣稱的工作,正是記錄改了什麼。

## 而 T122d 第一版通過的理由是錯的

它斷言 `--verify-index --no-index` 會被拒絕,而它在**未修正的建置上也通過**——因為那個
fixture 沒有索引,於是 `--verify-index` 是因為「找不到索引」而失敗的,與 `--no-index`
毫無關係。

現在它先 `--build-index`,並且多了一條 T122d0 斷言「索引存在時,單獨的 `--verify-index`
會成功」——把那個前提本身也釘住。

Round 50 put every flag where it did not belong. The worst: a known flag in a
data position was written into the file at rc=0 -- this tool's founding failure
arriving through its own argument parser, in a document that cites multissh
being bitten by a swallowed option as the reason unknown flags are always an
error. The principle was there and stopped at UNKNOWN flags.
---

# 第 51 回合(2026-08-20)—— 拒絕會不會留下痕跡、拿不到金鑰時能拿到什麼、壞檔案能救回多少

**這一輪找到的是目前為止破壞性最大的一條,而它只需要一個格式完全正確的指令。**

## DH. 對已加密的欄位下 `-hash`,永久銷毀資料,rc=0,不印任何東西(2026-08-20 修正,T124a–e)

```console
$ csv2 -encrypt status -keyfile k.bin -i p.csv -o e.csv -t
$ head -1 e.csv
pkg,status:enc:2da3ce42:J37wDKapSLbFPwOg4wb8tQ==

$ csv2 -hash status -keyfile k.bin -i e.csv --in-place
rc=0                                        ← 什麼都沒印
$ head -1 e.csv
pkg,status:hmac:3bb1e58f                    ← :enc: 與它的 salt 一起沒了

$ csv2 -decrypt all -keyfile k.bin -i e.csv -o back.csv -t
csv2: no encrypted columns found
```

**密文被單向雜湊掉,`:enc:` 標記連同 salt 被覆寫,而正確的金鑰救不回來。**

README 說:「**對一個已經標記過的欄位再次遮蔽會被拒絕,而不是疊加。**」——那句話是假的。
`-encrypt` 對已加密欄位確實有守衛(「column X is already encrypted」),而 `-hash` 沒有。

受測者的話:

> 「這是這個工具明言的頭號大罪,由一個格式完全正確的指令執行完成。」

## DI. 而反方向會產生一個「對自己說謊」的檔案(2026-08-20 修正,T124f–i)

```console
$ csv2 -encrypt status -keyfile k.bin -i h.csv --in-place    # h.csv 的 status 是 :hmac:
rc=0
$ head -1 h.csv
pkg,status:enc:bc4a7672:UusICvta3FyJ8JqIdw+bSA==
```

`-decrypt` 之後會交還一堆十六進位摘要,**掛在一個乾淨的欄名底下,沒有任何東西標記它們是
摘要**。資料沒有被銷毀,但那個檔案現在宣稱了一件不成立的事。

## DJ. `--truncate-partial` 丟掉的不是「一筆」,而是引號打開之後的全部(2026-08-20 修正,T125)

```console
$ cat t.csv                    # 10 筆，引號在第 1 筆就打開
a,b
1,"opens here
2,ok2
...
10,ok10

$ csv2 -r --truncate-partial -i t.csv | wc -l
0                              ← 一筆都不剩
rc=0                           stderr 空無一物
```

文件把它描述成丟棄「**一筆**不完整的紀錄」。從解析器的角度那確實是一筆——但那一筆裝著
其餘九筆的文字。

**而 WARN 機制存在,還為一個小得多的意外而觸發**(起點越界的 `-mid`)。這裡沒有。

## DK. 「輸入在引號欄位內結束」的紀錄編號,差了標頭列數(2026-08-20 修正,T126)

受測者量到:在一個 4 筆的 `.csv2` 上,它指名第 6 筆。那則訊息用的是
`recordsEmitted + 1`,而 `recordsEmitted` 把標頭列也數了進去。

README 說:「錯誤裡的紀錄編號是一個真的位址……它數的是資料紀錄。」

Round 51 found the most destructive defect so far, and it needs one
well-formed command: `-hash` on an already-encrypted column hashes the
ciphertext one way, overwrites the `:enc:` marker together with its salt, exits
0 and prints nothing. The correct key does not help afterwards. The README says
re-masking an already-marked column is refused rather than layered; the guard
exists for `-encrypt` and not for `-hash`.

### DH／DI:兩個守衛各自只看自己那一種標記

```swift
for c in cols where hashMarkerBase(...) != nil { ... }   // -hash 只找雜湊標記
for c in cols where EncMarker.parse(...) != nil { ... }  // -encrypt 只找加密標記
```

**兩者都不看對方的。** 而 README 承諾的是那條通則:「對一個已經標記過的欄位再次遮蔽會被
拒絕,而不是疊加。」——一條**通則**,被實作成兩個各自只認得自己的特例。

拒絕訊息必須說出理由,因為理由就是重點:**這是唯一一個「少了它就救不回來」的拒絕。**

### DK 的成因:修正就在上面幾行,而這個呼叫點沒有用它

`faultAt` 自第 38 回合的 CC 起就已經扣掉標頭列數了。而「輸入在引號欄位內結束」那一則,
一直沿用原始的 `recordsEmitted + 1`。

**同一個檔案裡,同一個偏移,修好了一處、漏掉一處。** 那與 T79(三個呼叫點、兩個傳常數)、
CQ(第四個呼叫點)是同一個形狀,而這次只隔了十幾行。

### DJ 為什麼用「位元組」而不是「筆數」

從解析器內部看,被丟掉的文字**就是一筆**紀錄——未終止的那一筆。去數「讀者本來會在裡面看到
幾筆」,等於去解析一段剛剛被宣告為解析不了的文字。

位元組是這裡唯一誠實的量度,而訊息把那個推論也說出來:「若引號很早就打開,那就是它之後的
全部。」
