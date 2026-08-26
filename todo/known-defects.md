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

### 怎麼看一條的狀態 / How to read an entry's state

2026-08-20 起,標題本身帶著狀態與斷言編號(例如「(2026-08-21 修正,T148)」)。更早的條目
把狀態寫在內文裡,因為當時還沒有這個慣例——**不要從「標題沒有寫」推論它還沒修**。

而任何一條的**現況**,權威在測試,不在這裡:一條記著斷言編號的條目,只要那個案例還在跑、
還是綠的,它就仍然是修好的;這個檔案保存的是「當初怎麼重現的」,那是日後判斷退化的唯一依據。
這個檔案不會回答「現在會不會發生」,它回答的是「當初是什麼、怎麼看見的」。

From 2026-08-20 the title carries the state and the assertion numbers. Earlier
entries carry it in the body, because the convention did not exist yet -- do not
read a bare title as "not fixed". For whether something holds TODAY the
authority is the suite, not this file: an entry naming an assertion is fixed for
as long as that case runs and passes. What this file preserves is how it was
reproduced, which is the only way to recognise a regression later.

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

## DL. 一個會隨機失敗的測試,而失敗的理由與它所斷言的事無關

T100c 斷言「解密的 log 不帶還原出來的明文」,做法是:

```zsh
printf 'pkg,secret\na,s1\nb,s2\n' > "$TMP/t100.csv"
...
if grep -q 's1' "$TMP/t100.log"; then bad ...
```

而 log 的第一行是**呼叫方式**,裡面含著完整路徑:

```
INFO  csv2 -decrypt all -keyfile /…/.test_csv2.Xs1abc/t100.key -i …
```

`mktemp -d .test_csv2.XXXXXX` 產生六個英數字元。**幾百次執行裡就會有一次含 `s1`**,於是
那個案例為了一個與明文毫無關係的理由失敗。

它在 2026-08-20 觸發了一次:那一次執行有一條失敗,而緊接著的三次都是零失敗。

**一份會亂叫的測試比沒有測試更糟**——它會侵蝕對整套測試的信任,而信任正是那 569 條斷言
唯一的用途。明文現在是 `PLAINTEXT-CANARY-ONE`,一個不可能出現在別處的記號。

掃過整份測試檔找同類:其餘「短字串」比對的都是**指令輸出**(報告位址、解密後的檔案內容、
錯誤訊息),不是含有隨機路徑的檔案。只有這一個。

## 而那次 commit 的訊息說了「零失敗」

我在同一條指令裡跑測試並提交,訊息是事先寫好的。那次執行實際顯示 568 / 1。

**訊息裡的數字沒有被那次執行證實,而它讀起來像是被證實了。** 這與 T69 守的是同一類東西
(文件裡會漂移的數字),只是 T69 看不到 commit 訊息。

沒有機械化的辦法可以擋這一條——commit 訊息不在任何測試的視野裡。能做的只有:**先看完
測試結果,再寫那個數字。**

A test that fails at random, for a reason unrelated to what it asserts. T100c
greps the decrypt log for the plaintext `s1`, and the log's first line is the
invocation, which carries the full path -- including a temp directory named by
six random alphanumerics. One run in a few hundred contains `s1`. It fired
once on 2026-08-20: that run was 568/1 and the next three were 569/0. A suite
that cries wolf stops being read, and being read is the only thing 569
assertions are for.

And the commit message for that run claimed zero failures. The suite and
the commit went out in one command, with the number written in advance. Nothing
mechanical can catch that -- a commit message is outside every test's view --
so the only remedy is to read the result before writing the number.

### 而 T69a 抓到的正是這一段

我在寫「那次執行是 568 / 1」時,又把一個會過期的數字寫進了文件——**而 T69 存在的理由就是
那個**。它在 WSL 與 Windows 上失敗,在 macOS 上沒有,因為我在 macOS 上跑測試的時間點早於
我加上那段文字。

**還有一件事因此浮出來:guest 的 payload 不含 `todo/`**,所以 T69 在 guest 裡根本看不到
`known-defects.md`——它在那裡是一個較弱的檢查。三個平台通過、一個平台失敗,而失敗的那兩個
才是看得到全部檔案的。

T69a caught this very section: writing "568 / 1" put another number that will
go stale into a document, which is precisely what T69 exists to stop. It failed
on WSL and Windows and not on macOS, because the macOS run happened before the
text was added -- and it surfaced something else: the guest payload does not
include `todo/`, so T69 cannot see this file there at all. Three platforms
green and one red, and the red ones were the ones that could see everything.
---

# 第 52 回合(2026-08-20)—— 刻意破壞再試著救回、保真宣稱的極端輸入、動詞兩兩併用

受測者的總結值得原樣抄下:

> 「資料路徑是真的優秀——26 個惡意值在 `--json`、`-get`、`.csv2` 跳脫與一次 308 區塊的平行
> 搜尋之後,原樣存活;加解密逐位元往返。**壞掉的是那套「告訴你發生了什麼」的機制。**
> 這個工具的整個論點是『靜默的半對輸出是敵人』。**而那份沉默,現在住在它的遙測裡。**」

## DM. 跳脫器漏掉 CR-LF 這一對,而它是我這次 session 寫的(2026-08-20 修正,T127)

```console
$ csv2 -contains "$(printf 'needle\r\n2026-01-01T00:00:00+00:00 INFO  csv2 -delete everything')" \
       -i f.csv -log L.log
$ cat L.log
2026-08-20T22:55:51.127+08:00 INFO  csv2 -contains needle^M
2026-01-01T00:00:00+00:00 INFO  csv2 -delete everything -i f.csv -log L.log
```

**單獨的 `\n` 被正確跳脫(1 行);`\r\n` 直接漏過去(2 行)**,而第二行整行由輸入決定,
連它的時間戳都是。

AI／AJ 關掉的那個偽造,從 CRLF 回來了——**而且只需要一次 `-contains` 讀取,完全不需要對
資料有寫入權限。**

### 成因,以及它的諷刺

```swift
for ch in s {
    switch ch {
    case "\\n": ...
    case "\\r": ...
```

**Swift 的 `Character` 是 grapheme cluster,而 CRLF 是「一個」。** 於是它兩個 case 都不匹配。

而 README 自己就警告過這件事——在 `--pretty` 那一節:「那個寬度是 grapheme cluster 加上
emoji presentation,**不是**逐 code point 查 UAX #11」。**同一個語言性質,同一份文件裡寫過,
而我在寫跳脫器時撞了上去。**

### 一個缺陷,三個保證

| 管道 | 被打破的保證 |
|---|---|
| `-log` | 「一筆是一行」——而多出來的那一行是偽造的 |
| 定位報告 | 「一個命中一行」——一個命中變成兩行,於是 `cut -f1` 拿到碎片 |
| stderr | 「錯誤恰好兩行,英文在前中文在後」 |

第二項最貼近本專案的招牌失敗:**它發生在這個工具自己推薦的腳本介面上。**

`reportEscape` 與 `lineEscape` 是同一個形狀,所以兩者都有這個洞。

Round 52. The diagnostic escaper misses a CR-LF pair, because Swift's
`Character` is a grapheme cluster and CRLF is one of them -- so it matches
neither the `\n` case nor the `\r` case. A bare LF escapes correctly; `\r\n`
walks straight through. One defect, three broken guarantees, and a live
audit-trail forgery reachable from a pure read with no write access. The README
warns about exactly this language property, for `--pretty`, a few hundred lines
away from where I wrote the escaper.

## DN. `--build-index` 站在一個編輯動詞旁邊,索引做了,編輯沒做(2026-08-20 修正,T128a/b)

```console
$ csv2 -update 1:2 'CHANGED' --build-index -i b1.csv --in-place
index built: 2 records, stride 256, 1 grid points
rc=0
$ csv2 -get 1:2 -i b1.csv
x                                  ← 那個編輯從未發生
```

`--build-index` **取代**了動詞,而不是加在它旁邊。搭配 `--in-place` 時完全靜默:什麼都沒印,
rc=0,而使用者以為自己改了一格。

`--build-index --no-index` 會被當成矛盾拒絕。`--build-index` 與一個編輯動詞併用,同樣不可能
兩件都做——而它沒有被拒絕。

## DO. `-get` 搭配 `-encrypt`,吐出一段永遠解不開的密文(2026-08-20 修正,T128c)

```console
$ csv2 -get 1:2 -encrypt b -keyfile k.bin -i g.csv
Vjse+Fx4A+B7W/i3CwVWnA7XeZI8SY5g5rDxWQQ=
rc=0
```

**沒有 salt、沒有指紋、沒有標記。** 那段密文所依賴的 salt 只存在於「檔案標頭」裡,而 `-get`
不寫檔案標頭——它印一格。於是輸出的是一段沒有任何東西能還原的位元組。

`-get` 對 `--json`、`--pretty`、`-t`、`-rownum` 都有「被忽略的旗標會被拒絕」的守衛,訊息還
寫得很好。`-encrypt` 不在那張清單上。

## DP. `--in-place` 在 symlink 上,改的是別的東西(2026-08-20 修正,T129)

```console
$ ln -sf g.csv link.csv
$ csv2 -update 1:2 'Z' -i link.csv --in-place
rc=0
$ test -L link.csv && echo symlink || echo "not a symlink"
not a symlink                      ← 連結被換成了一般檔案
$ csv2 -get 1:2 -i g.csv
x                                  ← 而它本來指向的那個檔案，沒有被動過
```

**使用者要求就地編輯,而得到的是:連結不見了、目標沒變、rc=0。**

同一族:一個 mode 444 的唯讀檔會被成功寫入(因為 rename 看的是目錄權限,不是檔案權限),
**而且模式在過程中變成 644**。硬連結同樣會被斷開。

這三件都是「暫存檔 + rename」的內在後果,而文件把 temp+rename 寫成一個**保證**
(「讀取端永遠看不到寫到一半的檔案」),從來沒有寫它的代價。

## DQ. `--include-headers` 沒有 `-contains` 時被靜默忽略(2026-08-20 修正,T128d)

它的三個同輩(`--a1`、`--physical`、`--filter`)在同樣情況下都會拒絕。

Round 52's remaining four are all "accepted, did something other than what was
asked, rc=0": --build-index replaces an edit verb instead of joining it; -get
with -encrypt emits ciphertext whose salt lives only in a file header that -get
does not write; --in-place on a symlink replaces the link and leaves the target
untouched, and on a read-only file succeeds while changing the mode; and
--include-headers without -contains is ignored where all three of its siblings
refuse.

### DP 的修法分成兩半,而其中一半刻意沒有做

**symlink**:`--in-place` 的輸出路徑改為解析過 symlink 的路徑。只解析「輸出」——輸入保留
呼叫端打出來的那個路徑,好讓訊息指名的是他問的那個檔案,而不是一個他從未見過的。

**模式**:rename 之前把原檔的權限位元套到暫存檔上。一個 0600 的檔案原本會被改寫成 0644
——一個「工作就只是改一格」的操作,悄悄改變了誰讀得到它。

**唯讀(0444)仍然會被改寫,而那是刻意的。** rename 需要的是「目錄」的權限,它從來不看那個
檔案;要尊重檔案的唯讀位元,得在寫入前自己檢查,而那會讓 csv2 對「一個唯讀檔案在一個可寫
目錄裡」這件事有意見——那是它不該有的意見。**還原模式擋住的是「悄悄放寬誰讀得到」,
那才是會把資料交給別人的那一半。** 硬連結同樣仍會被斷開,理由相同。

這三件都是 temp+rename 的內在後果,而文件把 temp+rename 寫成一個保證,從來沒有寫它的代價。
現在寫了。

---

## DR. 一個測試,量不到它要保護的那件事——而它保護的地方正好沒有 `stat`(2026-08-20 修正,T129d/T129e)

T129d 在 macOS 上通過,在 aarch64 guest 上失敗,而程式兩邊做的事一模一樣。失敗的是量測手段:

```
guest # stat -c '%a' /tmp/m.csv
/bin/sh: stat: not found
guest # zsh -c "zmodload -F zsh/stat b:zstat"
（空,模組不在）
```

這份 busybox 沒有把 `stat` applet 編進去,guest 的 zsh 也沒有 `zsh/stat` 模組。於是
`file_mode` 兩條分支都給不出東西,比較的是 `""` 對 `"600"`。

**而在此之前它更糟。** 原本寫成:

```zsh
stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f"
```

BSD 與 GNU 的 `stat` 都收 `-f`,而它們用它表達相反的意思:在 macOS 是模式格式,在
Linux 是「檔案系統狀態」。GNU 那個會先把一整段檔案系統資訊印到 **stdout**,然後才以 1
結束——於是 `A || B` 兩半都跑了,`$()` 把兩份都收下,比較的是一大段文字。`2>/dev/null`
蓋掉的,正好是唯一會說出真相的那一句。

修法有兩層:只問每一個 `stat` 它聽得懂的那一句、並要求答案「長得像一個模式」;都拿不到
時,退回每一個 Unix 都有的那份清單(`ls -ld` 的九個權限字元)。

**第二層本身帶著同一個病:那條後備只在「沒有 stat」的地方會被用到,也就是只在沒有東西
能檢查它的地方。** 因此另外加了 T129e——在每一個兩者兼具的平台上,把後備讀到的模式與
`stat` 讀到的對起來。一個解錯的 rwx 解碼器,不該一路潛伏到唯一依賴它的那個地方才發作。

順帶記下:過程中我用了 guest 上一份 14:33 的舊二進位去 probe,看到 644,並一度認定
「`copyMode` 在 Linux 上無效」。那是錯的——同一輪用 Swift 直接測 `stat`/`chmod`,兩者
在 guest 上都正常。**用一份不知道從哪來的二進位去證明一件事,證出來的是那份二進位。**

T129a–d 在 Windows 上改為 SKIP 並寫明理由:MSYS2 的 `ln -s` 在未設 winsymlinks 時是複製,
沒有連結可保留;它回報的模式位元是覆在 ACL 之上、形似 POSIX 的虛構。`copyMode` 在那裡
本來就被編譯掉。

---

## DS. Windows 的驗證有四次是對著另一個目錄做的(2026-08-20 修正於 multissh 端)

不是 csv2 的缺陷,是**把 csv2 送上 Windows 的那條路**的缺陷;記在這裡,因為它讓
「Windows 已驗證」這句話連續四回合為假。

`helper/upgrade_nodes_csv2.zsh` 每次都回報:

```
windows:
  是 checkout，將 pull
  commit: 7607bb9
  build: ok
  install: ok
  verified: C:/Users/lowei/AppData/Local/csv2/csv2.exe IS the build just made
```

而節點始終落後四個 commit。**每一行都是真的,只是講的不是同一個目錄。**

那個 session 設了 `MSYS2_ARG_CONV_EXCL=*`,它把「MSYS2 在參數交給原生程式前改寫路徑」
整個關掉。於是:

```
cd /c/Users/lowei/proj/csv2       shell 內建，看到的是真本
git -C /c/Users/lowei/proj/csv2   原生程式，看到的是 C:\c\Users\lowei\proj\csv2
```

而第二個路徑底下**真的有一棵樹**——更早某次同樣未轉換的 `git clone` 在那裡建立的,
之後每一次 pull 都把它更新到最新。狀態判斷問的是 `git -C`,得到「是 checkout」;
pull 推進的是幻影;`cd $dir` 之後建置的是真本、而它是舊的;最後那道身分檢查拿這份舊
建置去比 shell 會執行的那個檔案,**相符**——因為兩者都是舊的。

這是本專案自己的測試在 2026-08-19 已經撞過一次的同一個變數:`MSYS2_ARG_CONV_EXCL=*`
讓 276 個 Windows 測試以「cannot open input file」失敗,`test_csv2.zsh` 因此在
Windows 上會先 unset 它。**同一個變數、同一個原因、同一台機器,而修正只落在其中一邊。**
那是本專案最常犯的那一類:一條想清楚了、卻只套用到它成立之處的一部分。

修法:遠端區塊開頭 unset 該變數、狀態判斷與 pull 都改走 `cd`、pull 印出
`before -> after`,好讓「什麼也沒做」不能再假裝成一次升級。

順帶:那段遠端指令在一個雙引號字串裡,**註解裡的反引號一樣會開啟命令替換**——
`git -C <posix path>` 於是被當成重導向來解析,`parse error near '>'`。

---

## DT. 我修 DP 的那一行,把 O(1) 的 append 快路徑關掉了——而測試還在說它活著(2026-08-21 修正,T43g/T43h)

DP 的修法是讓 `--in-place` 的輸出路徑改為解析過 symlink 的路徑。而快路徑的守衛是:

```swift
guard o.output == o.input else { return false }   // canUseAppendFastPath
```

**兩個字串。** `resolvingSymlinksInPath()` 不只解 symlink,它還會把路徑正規化:相對路徑
變成絕對路徑,macOS 上 `/private/tmp/...` 變成 `/tmp/...`。於是只要輸入不是「已經是正規
形式的絕對路徑」,`o.output` 就不再等於 `o.input`,快路徑靜默退回全檔重寫。

重現(20 MB、40 萬筆):

```
$ csv2 -append '9,nine,pad' -i ap.csv --in-place -log ap.log
0.48s user   ← 與整檔重寫同一個量級
$ tail -1 ap.log
INFO  wrote 400002 records, 3 fields, atomic rename OK   ← 全檔重寫那條路的訊息
$ grep -c 'append fast path' ap.log
0
```

而 T43d 依然通過,因為它傳的是 `$TMP/big_o.csv`——一個剛好已是正規形式的絕對路徑。
**那個測試釘住的是「快路徑會說自己走了快路徑」,不是「使用者實際會打的路徑會走到它」。**
相對路徑是這支工具最常見的用法,而它從 9132e66 起就一直落在慢路徑上。

這是本輪第三次同一個形狀:一條規則只套用到它成立之處的一部分。DP 想的是「路徑同一性
不能用字串比」,而 `canUseAppendFastPath` 正是另一處用字串比路徑同一性的地方,距離
那一行三個檔案。

修法:快路徑的守衛不該比較路徑。決定它的是「這是不是一次就地追加」,那由 `o.inPlace`
直接回答——而 `-o` 指向輸入本來就已被 main.swift 的同檔拒絕擋掉。測試補上「相對路徑」
與「經 symlink」兩種寫法,因為那正是原本那條測試沒有覆蓋的部分。

補記一筆,因為它自己就是同一個病:第一版的 T43h 只檢查「連結還在、目標長大了」,而**它在
快路徑已死的情況下照樣通過**——重寫那條路也會保留連結(那正是 DP 修的),所以那兩個條件
分不出兩條路。加上 `grep 'append fast path'` 之後,負向控制才讓它跟著 T43g 一起紅。
一個分不出兩者的測試,並沒有釘住它名字所宣稱的東西。

---

## DU. `-o` 指向一個 symlink:連結被換掉,目標沒被寫到,rc=0

DP 已經替 `--in-place` 決定了:連結存活、被編輯的是它指向的那個檔案。`-o` 是同一件事的
另一半,而它沒有被一起改。

```
$ printf 'a,b\n1,x\n2,y\n3,z\n' > src.csv
$ printf 'a,b\n9,old\n' > dst.csv ; chmod 600 dst.csv
$ ln -sf dst.csv dlink.csv
$ csv2 -head 2 -t -i src.csv -o dlink.csv ; echo rc=$?
rc=0
$ [[ -L dlink.csv ]] && echo link || echo replaced
replaced
$ cat dst.csv
a,b
9,old            ← 目標一個字都沒變
```

shell 的 `>` 會跟著連結走,寫進目標。csv2 用的是 temp+rename,而 rename 必然取代那個
「名字」——除非先解析。使用者以為自己寫進了資料目錄裡的那個檔案,實際上是把指路牌拆了、
在原地放了一份複本;而下一次讀那個目標的人,拿到的是舊資料。

第二半更安靜:

```
$ printf 'a,b\n1,x\n2,y\n3,z\n' > s2.csv ; ln -sf s2.csv s2link.csv
$ csv2 -head 2 -t -i s2.csv -o s2link.csv ; echo rc=$?
rc=0
$ cat s2.csv        ← 完全沒變，而 s2link.csv 現在是一個獨立的檔案
```

`-i` 與 `-o` 指的是同一個檔案,而**同檔拒絕比的是字串**,所以它沒有觸發。那條拒絕存在的
理由是「這應該用 `--in-place`」,而繞過它只需要換一種寫法。

**順帶,那條拒絕的說詞對它自己的程式不成立。** 它說「開啟輸出會在輸入讀完前把它截斷」,
但 `-o` 走的是 temp+rename(T43e 正是為此存在的),什麼也不會被截斷:

```
$ printf 'a,b\n1,x\n2,y\n3,z\n' > f.csv
$ csv2 -head 1 -t -i f.csv -o ./f.csv ; echo rc=$?
rc=0
$ cat f.csv
a,b
1,x              ← 正確的結果，沒有資料遺失
```

拒絕仍然是對的——那個操作應該走 `--in-place`,因為只有那條路會保留連結與模式——但理由
要改成真的那一個。

修法:`-o` 的輸出路徑也解析 symlink(與 `--in-place` 同一條規則),同檔比較改用解析後的
路徑,拒絕的訊息改成成立的理由。

---

## DV. 磁碟寫滿:一條路徑當掉並留下暫存檔(rc=134),另一條被 SIGPIPE 殺死(rc=141)(2026-08-21 修正,T131a–d)

第 53 回合盲測發現,以現行建置在一個 8 MiB 的 RAM disk 上重現。

**`-o` / `--in-place`:未捕捉的例外,沒有任何診斷,而且留下暫存檔。**

```
$ df -k . | tail -1        # 只剩約 300 KiB，輸入 540 KB
$ csv2 -update 1:2 'ZZZ' -i d.csv -o out.csv 2>err.txt ; echo rc=$?
rc=134
$ wc -l < err.txt
0                          ← csv2 一個字也沒說
$ ls -la | grep tmp
-rw-r--r--  364544  .out.csv.csv2tmp.90763    ← 而且留在那裡
```

134 是 SIGABRT:`ByteSink.flush()` 的檔案分支走的是 `handle.write(Data(buf))`,而
Foundation 的那個 API 在寫入失敗時會擲出一個沒有人接的例外。原檔逐位元未變——資料保證守住了
——但失敗的形狀是「當掉」,不是「拒絕」。而 README 說錯誤是 stderr 上恰好兩行、每一次拒絕
都以 1 結束。

**`-so`:被 SIGPIPE 殺死,而 README 告訴呼叫者那個狀態是無害的。**

```
$ csv2 -r -t -i d.csv -so > o2.csv ; echo rc=$?
rc=141                     ← 訊號 13
$ ls -l o2.csv
233472                     ← 寫到一半的輸出，stderr 上什麼也沒有
```

`Platform.writeAll` 對**任何**寫入失敗都呼叫 `readerHasGone()`,而它會還原 SIGPIPE 的預設
處置並重新引發。ENOSPC 不是 EPIPE。141 恰好是 README 明講「不是 csv2 的錯誤、可以當成
正常結束」的那一個,於是一個把輸出寫壞的磁碟寫滿事件,長得跟 `| head` 一模一樣。

**兩者是同一句話只想到一半。** `writeAll` 的註解說的是管線斷掉,`flush()` 檔案分支的註解
說的是「它不可能遇到管線斷掉」——兩邊都對,而兩邊都沒有想到「寫入還會因為別的理由失敗」。

## DW. 被訊號中斷時,暫存檔留在目標檔旁邊(README 說不會)(2026-08-21 修正,T131e)

```
$ csv2 -update 1:2 ZZZ -i work.csv --in-place &   # 32 MB 檔
$ kill -INT %1
$ ls -la
-rw-r--r--  4392234  .work.csv.csv2tmp.90673      ← 留下
-rw-r--r--  32400007 work.csv                     ← 原檔完好
```

README:「a failed in-place edit leaves the original **byte-for-byte unchanged**, and
leaves no temp file beside it」。前半成立,後半在「被訊號殺死」時不成立——T28c 測的是一次
**失敗的編輯**(錯誤路徑會呼叫 `abort()`),而不是一個被殺死的行程。SIGINT、SIGTERM、SIGHUP
都會留下,ENOSPC 那條(DV)也會留下。

暫存檔是隱藏檔(`.名字.csv2tmp.PID`),那讓遺留物在 `ls` 下看不見——隱藏本身有它的理由
(避免別的工具用 `*.csv` 掃到一個寫到一半的檔案),但它使這個缺陷更難被發現。

DV／DW 的修法與它們可驗證的邊界:每個 sink 都改走 `Platform.writeAll`,而它現在只在
`errno == EPIPE` 時死於 SIGPIPE,其餘 errno 一律回傳給呼叫端,由 sink 印出慣常的兩行、
刪掉暫存檔、以 1 結束。暫存檔的路徑在建立時就轉成 C 字串並記住,好讓 SIGINT／SIGTERM／
SIGHUP 的處理常式能在不配置任何記憶體的情況下 `unlink` 它。

**ENOSPC 本身沒有進測試,而那是刻意的**——重現它需要建立一個檔案系統,那不是這份測試該做的事。
T131 用的是一個可攜的等價失敗(寫入一個已被 shell 關掉的描述子),而磁碟寫滿的重現步驟留在
上面。SIGKILL 仍然會留下暫存檔,永遠都會;README 現在把這件事、連同那個檔名一起寫出來了。

---

## DX. 工具印出來的位址,它自己不收——而且怪錯了東西(2026-08-21 修正,T132)

第 53 回合。README 承諾:「addresses are `record:field` — the same notation
`-contains` prints, so finding and editing compose」。三處不成立:

**1. `.csv` 的標頭命中是單純的 `0`,而 README 說「絕不會是單純的 `0`」。**

```
$ csv2 -contains name --include-headers -i a.csv
0:1	name	name
```

那句話是在 `.csv2`(兩列標頭)的脈絡裡寫的,卻寫成了通則。一個用 `^0[ab]:` 過濾的腳本,
會漏掉 `.csv` 的每一個標頭命中。

**2. 同一個性質,三個動詞三種說法,其中兩種怪罪的是形狀。**

```
$ csv2 -get 0:1 -i a.csv
csv2: -get addresses data records from 1; 0:1 names a header cell …   ← 講理由
$ csv2 -update 0:1 X -i a.csv --in-place
csv2: -update: expected r:c, got "0:1"                                ← 講形狀
$ csv2 -delete -cell 0:1 -i a.csv --in-place
csv2: -delete -cell: expected r:c, got "0:1"                          ← 講形狀
```

格式本來就是 `r:c`——那是定位報告印出來的。用「格式不對」回答一個格式正確的位址,會把
讀者送去檢查自己的引號。

**3. `--physical` 與 `--a1` 印出的位址,餵回去會指向一個不存在的欄位。**

```
$ csv2 -contains foo --physical -i a.csv
1:1@L2	name	foo
$ csv2 -get '1:1@L2' -i a.csv
csv2: no column named "1@L2"; the columns are: name, value
```

`1:1@L2` 在第一個冒號切開,於是 `1@L2` 成了「欄名」。訊息把讀者送去找一個從來就不是問題
所在的欄位。

修法:標頭位址的解釋移進 `parseCellAddress`,三個動詞因此說同一句;而「欄位解析不到」時
先試著拿掉結尾的 `@L<數字>` 或 ` [<字母><數字>]`,**只有在拿掉之後真的解析得到**才改口說
那是裝飾——因為一個欄位真的可以叫做 `id [primary]`,把別人的欄名說成裝飾是同一個錯誤的反面。

**沒有做的事:讓那兩種帶裝飾的位址「可以被接受」。** 那需要在編輯時驗證 `@L2` 是否仍然
成立——而那其實是有價值的(檔案在你搜尋之後變了,就該拒絕)——但它要的是「由紀錄號求出實體
行號」這條路徑,不是這一輪該加的東西。記在 todo。

---

## DY. 同一個值,兩種位元組:寫出端在三個地方不一致(2026-08-21 修正,T133)

第 53 回合:「M4. The writer is not byte-stable: `-update`ing a whitespace-only cell
with its own value rewrites `"   "` as `   `; `-rownum` quotes differently from `-r`.
Same value, different bytes, spurious git diff — in a tool whose closing argument is
"git can diff it".」

```
$ printf 'a,b\n"   ",x\n' > ws.csv
$ csv2 -update 1:1 '   ' -i ws.csv --in-place      # 用它原本就有的值
$ od -c ws.csv
0000000    a   ,   b  \n               ,   x  \n     ← 引號沒了
$ csv2 -r -i ws2.csv        →  "   ",x
$ csv2 -r -rownum -i ws2.csv →  1,   ,x             ← 只差一個旗標
```

兩件事,兩個原因:

**引號規則**。任何修改都會丟掉 `Field.raw`(那是對的——原樣位元組已不再描述這個值),之後
由 `FieldEncoder` 依「含逗號／引號／CR／LF 才加引號」重新序列化。前後空白不在那份清單裡,
於是 `"   "` 被寫成 `   `。RFC 4180 確實不要求為此加引號,**但那些空白是資料,而且是那種
會安靜消失的資料**——試算表與好幾種解析器會把未加引號欄位前後的空白去掉。規則已加入
「開頭或結尾是空白或 tab」。

**`-rownum`**。`preserveRaw: ctx.preserveRaw && !ctx.rownum`——加了一個欄位就把「照原樣
寫出」整個關掉。而 `preserveRaw` 是逐欄位的,沒有原樣位元組的欄位本來就會退回它的值,所以
那個 `&& !ctx.rownum` 沒有任何理由,只是保守。拿掉之後兩者一致。

**仍然不成立的部分,已寫進 README**:一次編輯之後,沒被動到的欄位逐位元相同,被動到的那些
帶的是 csv2 的引號規則,不是上一個寫入者當初的選擇。一個「每一欄都加引號」的檔案,在被編輯
過的格子上不會維持那個樣子。那不是缺陷,是重新序列化的必然;但它先前沒有被寫下來。

---

## DZ. 三種情況、一句話,以及一個系統早就給了我們的理由(2026-08-21 修正,T134/T135)

第 53 回合的三條訊息缺陷,都是同一個形狀——**一句話涵蓋好幾種情況,而沒有指名其中任何一種**:

| 情況 | 它說的 | 實際 |
|---|---|---|
| sidecar 屬於別的檔案 | `stale: the data file changed` | 資料檔一個位元組也沒變 |
| `-keyfile` 指到一個目錄 | `keyfile is empty or unreadable` | 它是目錄,兩者皆非 |
| sidecar 存在但讀不到 | `reason not recorded` | 理由離一次 `strerror()` 只有一步 |

第一條保留「stale／過期」這個詞(它對「不相符」仍然成立),改掉的是那個它說不出口的斷言:
戳記比對的是大小、mtime 與內容雜湊,它確立「兩者不相符」,說不出是哪一邊動了。訊息現在把
兩種可能都給出來。

第三條之所以「沒有記錄到理由」,是因為那條路徑是 `load` 裡最後一個「安靜的丟棄」:讀不到就
`return nil`。現在會分辨「不存在」(仍然安靜,那是常態不是事件)與「存在但讀不到」(記下
errno 的文字)。

## EA. 測試自己會安靜地弄丟案例(2026-08-21 修正)

寫 T135 時,我把兩個案例寫成呼叫 `assert_fails_with`——**這個檔案從來沒有過這個 helper**。
zsh 在六百行輸出裡印了一行 `command not found`,那兩個案例既沒有 PASS 也沒有 FAIL,而整份
測試以 **0 FAIL** 結束。總數甚至還變大了,因為它們取代掉的舊案例也一起不見了。

**一份會安靜弄丟案例的測試,就是它自己存在要抓的那種失敗,只是對準了自己。**

修法是一個 `command_not_found_handler`,它把這種呼叫變成一次 FAIL。而它第一版同樣只做了
一半:**zsh 是在子 shell 裡執行這個處理常式的**,因此在裡面 `fail=$((fail + 1))` 會遺失
——FAIL 那一行印得出來,計數卻不動。名字現在寫進一個檔案,結算時加回去,並以「故意呼叫一個
不存在的名字」實測過:那一次的失敗數比同一份測試正常執行時多了一個。

---

## EB. 一份 README 寫得對、卻沒有把兩件事接起來(2026-08-21 處理)

第 53 回合最重的一項發現(它的 B4),不是程式錯了,而是**兩段正確的文字之間沒有路**。

`-contains` → `-get` → `-update` 那份「組合配方」(T96)距離索引那一節約七百行,而它從未提到
索引,也從未提到 `--no-index`。一份過期到 O(1) 戳記看不出來的 sidecar(大小、mtime、首尾
位元組都相同)會讓搜尋回報偏掉的紀錄號,於是那三行全部以 0 結束、編輯落在隔壁那一筆上——
正是 README 開頭那個故事的形狀。

`-debug` 那一節把這件事講得很清楚,連 `40000:2` 對 `39999:2` 的例子都有。**但一個擔心正確性
的人不會去讀 `-debug` 那一節。** 該回合的原話:「`--no-index` is presented in the *-debug*
section, which is the last place someone worried about correctness will look.」

處理方式是在配方底下加上那條路:兩行指令(`--verify-index` 與 `--no-index`)、一句話說明
何時需要它們,並指向索引那一節。兩份 README 都加了。

**沒有做的事:在「信任索引」時發出 WARN。** 想過,而它是錯的——那條路徑上每一次使用索引都會
印,而索引本來就是常態;README 定義 WARN 是「一次執行成功了,但做的事幾乎確定不是呼叫端要的」,
而「用了一份戳記說相符的索引」不符合那個定義。csv2 若不做 O(n) 比對就無從知道它錯了,而那正是
`--verify-index` 存在的理由。真正的缺口是「那個答案沒有被放在人們會找的地方」,已經補上。

---

## EC. 第 53 回合測的是 PATH 上那份舊的二進位(2026-08-21,流程)

盲測用的是 `csv2`,也就是 shell 找到的那一個:`/opt/homebrew/bin/csv2`,時間戳 22:33,
早於當天稍晚的 DP/DT/DU 三個修正。因此該回合的 B5 與 M1(「`--in-place` 會毀掉 symlink」)
**回報的是一個已經修好的缺陷**,而報告本身無從知道。

這與 DS 是同一個形狀:**一次驗證,對著一個不是你以為的那個檔案做的。** DS 是升級腳本
建了真本、卻 pull 了幻影;這一次是我派出一輪盲測,而沒有先讓 PATH 上那一份等於剛建好的
那一份。

**流程修正:每一回合派出之前,先執行 `install.zsh`,並以「比對檔案身分」確認**——不是比對
`csv2 --version`,兩個建置都會說 `csv2 0.1.0`(那正是 multissh 的 helper 已經記取的教訓)。

---

## ED. guest 上沒有 `comm`,於是三個案例在那裡從來沒有真的執行過(2026-08-21 修正)

EA 那個 `command_not_found_handler` 在它存在後的**第一次 guest 執行**就抓到了這個:

```
FAIL  T117a cited in English only: FAIL  the suite called "comm", which does not exist …
FAIL  T117b cited in Chinese only: …
FAIL  T121h KNOWN_FLAGS is missing: …
```

這個 rootfs 的 busybox 沒有 `comm` applet。`comm -23 A B` 因此什麼也不產出,而三個案例
比較的都是空字串——**在 guest 上一律 PASS,而它們一次也沒有真的比對過任何東西。**
兩份 README 的案例編號一致性、以及 `KNOWN_FLAGS` 對解析器 case 的覆蓋,在 aarch64 上
從來沒有被檢查過。

改用 `grep -Fxv -f`(每一個 busybox 建置都有)做集合差集。

**這是 EA 那個守衛的第一份回報,而它報的是一個存在已久的洞。** 一個「安靜地什麼都不做」
的外部指令,與一個「不存在的 helper」是同一種失敗;而在此之前,兩者都不會被說出來。

順帶:T135c(讀不到的 sidecar)在 guest 上會 SKIP,因為那裡以 root 執行,而 root 讀得到
mode 000 的檔案。T69b 的預期 SKIP 數已用「與 T135c 相同的探測方式」納入這一項。

---

## EE. Windows 上每一次 `-o` 與 `--in-place` 都無聲死去(2026-08-21 當日修正)

DV 的修法把暫存檔改成「以描述子寫入」,而為了保留 `flushToDisk` 與 `close`,我讓
`openForWrite` 同時回傳一個包住那個 CRT 描述子的 `FileHandle`。macOS 與 Linux 都通過,
Windows 一跑就是 98 個失敗。

隔離出來的樣子很乾淨:

```
1. 編輯輸出到 stdout   → 正常
2. -r -t -i f -o out   → rc=127，stderr 一個字也沒有，檔案沒產生
3. --build-index       → 正常（它不走這條 sink）
```

`-debug` 顯示它走完了參數解析與「不平行」的判斷,然後死在寫入。**在 Windows 上,一個
`FileHandle` 自己帶著一個 HANDLE,而「別人交給它的描述子」不是同一個東西**;對這樣一個
handle 呼叫 `synchronize()` 會讓行程當場消失——沒有訊息、沒有可讀的結束狀態。

修法是把方向反過來:暫存檔在每個平台上都只用描述子——開啟、寫入、`syncFD`、`closeFD`
——完全不建立 `FileHandle`。原本的 `flushToDisk(FileHandle)` 因此移除,它的歷史(2026-08-19
第一次 Windows 編譯時發現 `FileHandle.fileDescriptor` 在 Windows 上不可用)併進了 `syncFD`
的註解——**那段歷史正是它當初收 FileHandle 的理由,不能跟著函式一起消失。**

值得記下的是它「被抓到的方式」:三個平台的測試,只有第三個會說話。macOS 與 Linux 都不介意,
一如 2026-08-19 那次。

---

## EF. stderr 被關掉時,csv2 以 rc=134 當掉——包括「印一則錯誤訊息」這件事本身(2026-08-21 修正,T138)

DV 把每一個 sink 都改成走 `Platform.writeAll`,但**直接寫 stderr 的那幾處不是 sink**:
最上層的錯誤印出、Logger 的回顯、以及 `-debug`。它們仍然呼叫
`FileHandle.standardError.write`,而那在寫入失敗時會擲出一個沒有人接的例外。

```
$ csv2 -get 9:9 -i f.csv 2>&-        # 一則錯誤，而 stderr 已關閉
rc=134
$ csv2 -r -t -i f.csv -debug 2>&- >/dev/null
rc=134
```

管線那一側是對的(`2>&1 | head` 給 141,那是讀端離開),壞掉的是「描述子根本不能寫」的
情況:`2>&-` 在腳本裡是很平常的寫法,而它把「一次本該以 1 結束的拒絕」變成一次當掉。

**它比 DV 更難看:那是「回報一個錯誤」這個動作自己失敗成當機。** 一個以 `2>&-` 執行 csv2
的呼叫端,拿到的結束狀態不是 1 而是 134,而 134 在文件裡不存在。

修法與 DV 相同:那幾處改走 `writeAll(fd: 2, …)`——EPIPE 仍然死於 SIGPIPE(那是對的),
其餘 errno 就當它寫不出去,繼續以「原本要用的那個結束狀態」結束。

---

## EG. `-hash ''` 與 `-encrypt ''`:rc=0、什麼也沒做、沒有任何東西說話(2026-08-21 修正,T140a/b)

第 54 回合最嚴重的一項。

```
$ printf 'name,license\napp,MIT\n' > a.csv
$ csv2 -hash '' -i a.csv -o out.csv ; echo rc=$?
rc=0
$ cmp out.csv a.csv && echo identical
identical                      ← 輸出與輸入逐位元相同
$ head -1 out.csv
name,license                   ← 標頭沒有任何 :hash 標記
```

`,` 與 `,,` 也一樣。**一個「錯的」欄名會被指名拒絕,一個「空的」欄名則被當成「保護零個欄位」
而接受。** 一支腳本的 `$COLS` 變數若碰巧算成空字串,寫出來的就是一個未受保護的檔案,而
README 提供的每一種檢查都會回報成功。

這直接違反本工具寫在最前面的那條要求——「anything else must fail loudly rather than
silently emit a half-correct file」——以及「csv2 does not partially succeed」。

## EH. 欄名是數字時,被靜默地當成欄號(2026-08-21 修正,T140e)

```
$ printf '2,1\nX,Y\n' > n.csv          # 兩欄，名字分別是 "2" 與 "1"
$ csv2 -hash 2 -i n.csv -o nh.csv ; echo rc=$?
rc=0
$ head -1 nh.csv
2,1:hash                                ← 被標記的是「位置 2」，也就是名為 1 的那一欄
```

README 說 COLS 是「欄名、1-based 欄號,或兩者混用」,卻沒有說哪一個優先。答案是「位置永遠
優先」,而且不說話。使用者要求保護名為 `2` 的那一欄,拿到的是另一欄被保護、rc=0、stderr
空白。

**這與 2026-08-18 已經定案的那條規則是同一件事的另一半:** 同名欄位會被拒絕,理由是
「替你挑一個等於猜測」。一個既是合法欄號、又精確命中某個欄名的 token,也是同一種猜測。

---

## EI. 每一個視窗都在結尾之後的那個檔案,正是 WARN 沒有涵蓋的(2026-08-21 修正,T141a/b)

```
$ printf 'a,b,c\n' > hdr.csv        # 有標頭，沒有紀錄
$ csv2 -mid 1,3 -t -i hdr.csv ; echo rc=$?
a,b,c
rc=0                                  ← stderr 一個字也沒有
$ printf 'a,b,c\n1,x,p\n' > one.csv
$ csv2 -mid 5,7 -t -i one.csv
csv2: … WARN  -mid 5 starts after the last record (1) …   ← 這裡才有
```

條件裡有一個 `seen > 0`。而 README 指定用來分辨這件事的第二個管道——`--json` 結尾的
`"records":0`——在「視窗在結尾之後」與「檔案本來就空」兩種情況下說的是同一句話。
**最該發出這個警告的情況,正是它沒有涵蓋的那個。**

## EJ. README 承諾了一條「程式裡不存在」的拒絕(2026-08-21 修正,T141d/e)

拒絕表寫著:「`-o /dev/stdout` → …Use `-so`」。實際上:

```
$ csv2 -r -t -i one.csv -o /dev/stdout
csv2: cannot create temporary file beside /dev/fd/1: No such file or directory
```

既沒說原因、也沒說出路,而且指的是一個呼叫端從來沒有打過的路徑(`/dev/fd/1` 是 shell
展開的結果)。原始碼裡搜不到任何與 `/dev/stdout` 有關的處理——**那條拒絕從來沒有被實作,
只是被寫進了文件。**

現在會在「目的地存在且不是一般檔案」時拒絕(目錄、FIFO、裝置),並在解析 symlink **之前**
做,好讓訊息指名呼叫端打出來的那個路徑。

---

## EK. `--yes` 決定的是演算法,而它被寫成「跳過詢問」(2026-08-21 以文件處理,T142)

```
$ csv2 -hash license -t -i h.csv -o h1.csv       → license:hash
$ csv2 -hash license --yes -t -i h.csv -o h2.csv → license:hmac:9c65c01a
```

`--yes` 在旗標表裡是「接受預設金鑰、不再詢問」。對 `-hash` 而言,那句話的前半(選定一把
金鑰)決定的是「輸出是不是字典可攻破的」,而 README 的警告框花了整整一段講那件事,卻從未
把兩者接起來。

**沒有改行為,而那是刻意的。** 那條規則本身是一致的:有金鑰就 HMAC,沒有就 SHA-256;而
`--yes` 的意思確實是「用預設金鑰」。檔案也記錄了發生的是哪一種——`:hash` 對 `:hmac:<指紋>`
——所以它不是靜默的。缺的是文件,以及**那個沒有人寫下來的後果**:兩個以不同方式雜湊的檔案
永遠不會相等,跨檔案比對會安靜地一個都對不上。兩份 README 現在都寫了,並由 T142 釘住,
連同「同一種選擇之內仍然是確定性的」那一半。

---

## EL. 一份「沒有重現到」的報告,不是一份「不會發生」的證明(2026-08-21,T143)

第 54 回合以八次嘗試想騙過 O(1) 戳記,八次都被攔下,於是結論是:README 對那個戳記的描述
(大小、mtime、首尾位元組)**有誤**,實際的檢查比它宣稱的更強。

**不是。** 同一天手動重現(28 MB、90 萬筆、等長替換、mtime 還原到奈秒):

```
$ csv2 -contains 'v899999' -i b2.csv | cut -f1
900001:2                     ← 錯的
$ csv2 -contains 'v899999' --no-index -i b2.csv | cut -f1
900000:2                     ← 對的
$ csv2 --verify-index -i b2.csv
index MISMATCH: no_embedded_newlines: index says the file has none, but record 450001 spans lines
```

那正是 README 描述的那個風險。**若當時照著那份報告去改文件,結果會是在這個工具最要緊的
正確性宣稱上,加進一句假的安全保證。**

為什麼他們沒重現到,無法完全還原;可以確定的是這件事要三個條件同時成立:替換必須「逐位元組
等長」(否則大小變了)、mtime 必須還原到**奈秒**(戳記存的是 `mtimeNsec`)、而且錯誤的**紀錄
編號**來自「分塊搜尋」,因此檔案必須大到讓平行路徑也啟動。少任何一個,那個風險都不會出現。

**這條極限現在自己有一個測試(T143)。** 理由不是「怕它被修好」,而是:它哪一天不再可重現,
就是那段描述該改的那一天,而在那之前,任何「改成宣稱安全」的編輯都必須先讓這個測試變紅。
寫這個測試時我自己也踩了同一個坑:第一版只降了索引門檻,平行路徑沒有啟動,於是它「證明」
了危險已經消失。

---

## EM. 第 54 回合的訊息與文件那一批(2026-08-21 修正,T144 與兩份 README)

**訊息**

- 欄名清單不加引號:第一欄叫 `a,b` 的檔案會印出 `the columns are: a,b, c`——讀起來是三欄,
  人與腳本都解析不了。現在每個名字都加引號。
- `-get 1:` 回答「expected r:c」:形狀是對的,缺的是欄位。而它有一個真正的答案——名字為空的
  欄位用「欄號」定址。修這一條時撞到 Swift 的 `split` 預設會丟掉空片段,於是 `"1:"` 只切出
  一段,新加的檢查永遠不會命中;要 `omittingEmptySubsequences: false`。
- `--a1 add to the address`:一個旗標配複數動詞,因為兩個旗標共用同一句字串。小事,但它會
  告訴讀者這句話是拼出來的。

**文件**(每一條都已有測試撐著,或本身就是一條拒絕)

- COLS 的三條拒絕:空清單、既是欄號又是欄名的 token、名字裡的逗號沒有跳脫(改用欄號,
  或用只收一個名字的 `-delete -col`)。
- UTF-16 的守衛**只看 BOM**:沒有 BOM 的 UTF-16 檔案會在 rc=0 下解析成沒有意義的紀錄,
  而 csv2 沒有「不會誤傷合法資料」的偵測依據。README 先前把這件事誠實地寫在別處,卻沒有
  寫在讀者會看到的地方。
- 零位元組的檔案會被拒絕。
- `-mid` 的 WARN 是「每次執行一行」,不是「每種輸出形狀一行」;而在空檔案上,`--json` 的
  `records:0` 分不出「視窗落空」與「檔案本來就空」,能分辨的是那行 WARN。

**沒有改的一件,理由寫下來:`-delete -col` 收一個名字,`-hash` 收一份清單。** 看起來不一致,
而改掉它會讓 `-delete -col a,b` 從「刪掉名為 a,b 的那一欄」變成「刪掉 a 與 b 兩欄」——對
擁有這種欄名的人是一次靜默的破壞性變更。現在的行為還讓它成為「唯一抵達得了含逗號欄名的
編輯動詞」。兩份 README 都寫明了。

---

## EN. 一個平台差異被寫進了 `main.swift`,而那個檔案的開頭就說了不要(2026-08-21 當日修正)

EJ 的修法在 `main.swift` 裡直接查 `st.st_mode & S_IFMT`。macOS 與 Linux 編得過;
**Windows 根本建不起來**:

```
error: cannot convert value of type 'UInt16' to expected argument type 'Int32'
```

`st_mode` 在 Windows 上是 `UInt16`、在其他平台是 `Int32`,而 `S_IFMT`、`S_IFDIR` 的型別
也跟著不同。

`src/Platform.swift` 開頭寫著「平台差異住在這裡」,而我把一個平台差異放進了呼叫端。它現在是
`Platform.fileKind(path:)`,回答的就只有 csv2 要問的那一個問題:「暫存檔 rename 得上去嗎?」
Windows 沒有 POSIX 意義下的 FIFO,那一支以 `#if` 排除。

**又是四平台矩陣裡「只有第三個會說話」的那一類**,而這一次它連編都不編——那已經是最溫和的
一種失敗了。

---

## EO. 一則拒絕給的建議,照著做會弄丟一筆紀錄(2026-08-21 修正,T145a/b)

第 55 回合照著訊息去做,然後靠比對紀錄數才發現不對:

```
$ csv2 -r --headers 1 -i vs-sqlite.csv2
csv2: … The suffix declares the format; --headers is for input with no suffix to declare it.
Rename the file or drop --headers.
$ cp vs-sqlite.csv2 renamed.csv          ← 照第一條建議
$ csv2 -r --json -i vs-sqlite.csv2 | tail -1 → {"meta":{"records":22,…}}
$ csv2 -r --json -i renamed.csv    | tail -1 → {"meta":{"records":23,…}}
$ csv2 -get 1:1 -i renamed.csv               → 比較項目     ← 中文標題列，現在是資料
```

兩條建議被並列成等價的,而它們不是:**拿掉 `--headers` 是照檔案原本的樣子讀它;改檔名是
讓副檔名去遷就 `--headers`**,於是 `.csv2` 的第二列標頭變成第 1 筆資料——rc=0、輸出看起來
完全合理、而紀錄數比實際多一筆。

README 在別處把這個風險寫得很清楚(「把只有一列標頭的 `.csv` 改名成 `.csv2`……沒有任何檢查
抓得到」),**而那則訊息本身在推薦它,一句提醒也沒有**。

## EP. `-insert` 越界時,訊息沒有說出那個正解(2026-08-21 修正,T145c/d)

`-insert 99` 在 2 筆的檔案上被正確地拒絕,而 README 在別處說「要加在最後請用 `-append`」。
拿著這則拒絕的人沒有理由會去翻到那一句。只對 `-insert` 加這個提示:`-update` 與 `-delete`
越界沒有對應的正解,硬給一個等於是叫人去做別的事(T145d 釘住這一半)。

## EQ. `-o /dev/stdout` 的失敗訊息,指的是一個呼叫端從未打過的路徑(2026-08-21 修正,T145e/f)

stdout 被導向**一般檔案**時,`/dev/stdout` 解析成 `/dev/fd/1`,而那**是**一般檔案,於是
EJ 那條「不是一般檔案就拒絕」的檢查放行,接著在 sink 裡失敗:

```
csv2: cannot create temporary file beside /dev/fd/1: No such file or directory
```

錯的原因(不是「不存在」,是「/dev 裡建不了新檔案」)、一個呼叫端從未打過的路徑、以及沒有
出路。現在在解析之前先問「目的地的目錄容不容得下一個新檔案」,並把「目錄不存在」與「目錄
不可寫」分成兩句——「請用 `-so`」是 `/dev` 的答案,拿來回答一個打錯的路徑則毫無意義。

補記 EQ 的測試:第一版的 T145e 把 stdout 導到 `/dev/null`,而那是字元裝置——EJ 那道「不是
一般檔案」的檢查本來就會發動,於是**那個寫法對「還帶著這個缺陷的建置」照樣通過**。第 55 回合
撞到的是「導向一般檔案」。改掉之後,把目錄檢查單獨拿掉重建,T145e 與 T145f 一起變紅。
這是本週第三次同一件事:一個分不出兩者的測試,並沒有釘住它名字所宣稱的東西。

---

## ER. 第 55 回合的文件範圍那一批(2026-08-21 處理)

第 55 回合自陳「工具本身沒有壞的」——它找到的每一項都是**文件宣稱的範圍比程式做到的更寬**。
那是比較難察覺的一類:程式的行為始終如一,只是那段文字承諾了更多。

- **「csv2 不會部分成功」對 `-so` 不成立。** 一次會失敗的 `-update` 在 19.5 MB 的檔案上寫出
  198,349 筆有效紀錄才以 1 結束;同一個指令在 12 KB 的檔案上一筆也沒寫(還在緩衝區裡)。
  一條串流收不回來,而「位址在結尾之後」要到讀完才知道。旁邊那一句已經正確地把「失敗不留下
  任何東西」限定在 `-o`;這一句沒有限定,而它是錯的。**沒有改行為**:要修就得緩衝整份輸出,
  而 `-so` 的存在正是為了不那樣做。
- **「讀取端永遠不會看到寫到一半的檔案」屬於「寫入者」。** 對 csv2 的寫入者 180/180 成立;
  對一個普通的 `cat >` 實測 30 次:12 次安靜截斷、18 次大聲報錯、0 次完整。而本文件自己會把
  讀者送去用 `iconv`、`tr`、shell 重導向。
- **沒有任何辦法問「這次讀取是完整的嗎」。** 一個在紀錄邊界被切斷的檔案,是一個比較短的檔案,
  不是格式錯誤的檔案;`records` 回報的是「讀到哪裡」,那正是會錯的那個數字。這是真的,已寫入
  文件——而寫下它,比留給下一個人自己撞上要好。
- **`rm` 掉一個正在被編輯的檔案,它會回來**(rename 重新建立目的地)。機制早就寫了,這個後果沒有。
- **`--physical` 與 `--a1` 那個範例 `13:6@L14 [F14]`**,兩個數字相同只因為那個檔案沒有跨行
  紀錄;實測 `2:2@L4 [B3]`。兩個都對,誤導的是那個範例。
- **`-update 0:1` 的訊息點名了 `-get`**,在一則 -update 的失敗裡讀起來像是訊息本身出錯。

**以及第三次:那個 O(1) 戳記。** 第 54 與第 55 回合都推論「它比文件宣稱的更強」,而兩次都是
因為「用手佈置那個情況」需要三件事同時成立(等長替換、mtime 含奈秒、檔案大到讓分塊搜尋啟動)。
README 現在把那三件寫出來了——**寫出「為什麼難」,是為了不讓第三個讀者得出「所以它是安全的」**。

---

## ES. 我把一段 `ls` 輸出貼進了 README,而釘住那個範例的測試照樣通過(2026-08-21 修正,T147)

第 56 回合在 `--headers` 那個 ```console 範例裡找到一段目錄列表——同一個範例裡出現兩次,
一次在英文訊息前、一次在中文訊息前。那不是 csv2 會印出的東西。

它是這樣進去的:當天稍早我更新 EO 那則訊息在 README 裡的引用時,做法是「在 shell 裡捕獲
指令輸出、再整段替換進去」。那次捕獲把一段裸的 `ls` 一起帶了進來,而**釘住那則引用訊息的
T58 照樣通過**,因為它比對的是「那一行訊息在不在」,而不是「那個區塊裡還有什麼」。

**教訓有兩層。** 第一層:文件的編輯要「讀過結果」才算完成,不能只信任替換成功。第二層是
這一類已經是第四次了(第 56 回合的原話),因此值得一個機械檢查而不是一句提醒——T147 掃描
每個 ```console 區塊,連續三行以上的「裸檔名」即為失敗。範圍刻意窄:被貼進來的 `ls` 就長那樣,
而這些範例裡沒有別的東西長那樣(CSV 有逗號、報告有 tab、訊息有空白)。

---

## ET. 稽核軌跡最薄的地方,正是損失最大的地方(2026-08-21 修正,T148)

第 56 回合。`-log` 那張表寫著「**一般**欄位的新舊值:完整記錄、絕不截斷;那正是稽核軌跡的
意義」,而:

```
$ csv2 -delete -cell 1:2 -i g.csv --in-place -log L.log
$ grep blank L.log
blank 1:notes                       ← 沒有舊值
$ csv2 -delete 1 -i i.csv --in-place -log L3.log
delete record 1                     ← 沒有那筆紀錄的內容
$ csv2 -hash notes -i j.csv -o jh.csv -log L4.log
（只有那一行「執行了什麼指令」——沒有欄名，也沒有「沒有用金鑰」）
```

`-delete -cell` 銷毀的正是「一般欄位的一個值」,而它只記下了「這件事發生過」。**兩者之中
破壞性較大的那一個,記錄得最少。** 一筆被刪除的紀錄是這個工具銷毀得最大的東西,而軌跡只說了
某個編號不見了。而 `-hash`——那個既不可逆、又(無金鑰時)可用字典攻破的操作——的軌跡是三者裡
最弱的。

三處都補上了,並且守住既有的兩條規則:受保護的欄位在被刪除的紀錄裡仍然是 `<redacted>`
(T148d),而一筆含換行的紀錄在 log 裡仍然是「一則」(T148e,與 T127 為引數釘住的是同一個性質)。
`-delete -col` 刻意只記欄名不記各筆的值:那些值就是整個欄位,一筆一則會讓 log 比檔案還大。

---

## EU. `-hash all` 在沒有加密欄位的檔案上:rc=0、什麼也沒做(2026-08-21 修正,T150)

第 56 回合報的是一件小事:「一個名為 `all` 的欄位,無法以名字被 `-decrypt` 定址」。查下去
翻出更大的那一半:

```
$ printf 'a,b\n1,x\n' > plain.csv           # 沒有任何加密欄位
$ csv2 -hash all -i plain.csv -o o.csv ; echo rc=$?
rc=0
$ head -1 o.csv
a,b                                          ← 什麼也沒標記
```

**那正是 EG 那個靜默無操作,換了一條路走回來。** README 只把 `all` 這個關鍵字給了
`-decrypt`(「COLS 可以是 `all`,代表每一個被標記的欄位」),而實作把它給了每一個動詞:
`resolveColumnList` 一看到 `all` 就回傳「所有帶標記的欄位」,對 `-hash` 而言那通常是空的,
於是保護了零個欄位、rc=0。

順帶把小的那一半也修好了:現在 `all` 對 `-hash`／`-encrypt` 就只是一個欄名,所以一個真的
叫做 `all` 的欄位可以被定址。

## EV. 這一輪其餘的文件缺口(第 56 回合)

- **`-o` 會靜默覆寫已存在的目的地**,而 README 把 `-o` 說成「比 `--in-place` 安全的那一個」
  (「用 `-o` 時輸出錯了你手上還有輸入」)。那句話對「輸入」成立,對「目的地原本的內容」不成立
  ——第 56 回合就是這樣弄丟了一個檔案。沒有旗標可以防它,而 shell 的 `>` 也是這樣;要寫的是
  這件事本身。
- **`--`(結束旗標解析)沒有出現在 README**,而 csv2 自己的錯誤訊息會叫人用它。
- **`-so` 是編輯的乾跑**:預覽完全一致、不動檔案、越界會在提交前就被抓到。從未被寫成「安全
  程序」,而那正是讀者在 `--in-place` 那一節找的東西。
- **一個檔案的標頭決定哪些動詞可用**:名為 `x:hash` 的欄位會讓 `-append`／`-insert` 被拒絕。
  行為是對的(那條拒絕有它的理由),但「由檔案內容決定」這件事沒有被寫成一個性質。
- **只有 `-contains` 會用到 sidecar**,而 README 讀起來像是「搜尋與編輯共用同一個錯誤的計數」。
  真正的機制是:印出來的位址是錯的,而你把它餵給 `-get` 時,`-get` 不用索引——於是兩者對不上。
- **`-append --in-place` 不會正規化 BOM**(快路徑只加位元組、不重寫),而 BOM 的規則寫成了通則。

---

## EW. `--` 的文件是我寫錯的,而下一個回合用一個指令就證明了(2026-08-21 修正)

第 56 回合發現 `--` 沒有出現在 README。我把它加了進去,寫成「旗標到此為止:其後一律視為
資料」——那是從錯誤訊息的措辭(「請先結束旗標解析」)推得的,而我沒有測。

第 57 回合測了:

```
$ csv2 -update 1:2 -- --in-place -i f.csv -o out.csv   → rc=0，值寫成了 --in-place
$ csv2 -update 1:2 -- --in-place -i f.csv              → csv2: an edit needs an explicit destination
```

第二行證明了 `-i` **仍然被當成旗標解析**。`--` 讓「下一個引數」成為資料,如此而已——而那
正是這個文法需要的,因為 `-i`、`-o` 本來就會接在值的後面。

**一句從措辭推得、沒有測過的文件,活了不到一小時。** 訊息本身的「結束旗標解析」也一併改成
「用 -- 把它標成資料」,因為那個說法正是這句錯誤文件的來源。

## EX. 只攔了三個訊號,而會結束執行的不只三個(2026-08-21 修正,T131f)

DW 為 SIGINT／SIGTERM／SIGHUP 註冊了清理處理常式。第 57 回合改用 SIGXFSZ、SIGPIPE、
SIGALRM、SIGUSR1 各殺一次,**每一次都留下一個 13 MB 的隱藏暫存檔**——而 README 當時寫的是
「SIGKILL 是那個會留下暫存檔的」。

`SIGXFSZ` 一點也不罕見:一個 `ulimit -f` 或檔案系統配額就會產生它。

現在涵蓋每一個「可攔截、且預設動作是結束行程」的訊號。SIGPIPE 也在其中,而它不會干擾
`readerHasGone()`——那條路徑會先還原 SIG_DFL 再重新引發。

**這與 T79、CQ、DH 是同一個形狀:一條規則,只套用到它成立之處的一部分。** 這次那「一部分」
是「當初想得到的那三個訊號」。

---

## EY. 第 57 回合的文件那一批(2026-08-21 處理,T152/T153)

那一輪寫了「一個工程師真的會寫的腳本」,然後試著用「輸入檔的內容」去弄壞它自己的腳本。
它找到的都是文件層面的,而其中兩件值得寫下來:

**配方掛著 `# round-trips`,而它不 round-trip。** 錯的不是 csv2:

```
$ csv2 -get 1:2 -i nl.csv | od -c        →  x \n \n     （值是 x\n，加上 -get 自己的換行）
$ val=$(csv2 -get 1:2 -i nl.csv); printf '%s' "$val" | od -c  →  x
```

`$( )` 會吃掉結尾的**每一個**換行。一個以換行結尾的值,回來時少一個位元組,並就這樣被寫回去,
rc=0。csv2 交出去的是對的位元組,收回來的是另一組——而中間那一段不是它。兩份 README 現在
帶著這句但書,以及 `printf x` 那個保得住結尾的寫法(T152a/b)。

**沒有任何地方說明「多個位址怎麼一次做完」。** 那一輪照配方寫了「每個位址跑一次 csv2」的迴圈,
第四次失敗時前三次已經寫進去了,rc=1,而從檔案上看不出哪些發生過。可重複的 `-update` 在一次
執行裡是不可分割的——那件事先前只以「`-insert` 的編號怎麼算」的形式被記載過,從來沒有被寫成
「我有 N 個位址時該怎麼辦」的答案(T153)。

其餘:`-contains` 以紀錄號遞增輸出(配方的 `head -1` 依賴它,而沒有人說過,T152d);log 的
第三行 `wrote N records…` 不在那張表裡;一次寫入會順手修好 sidecar,因此**在錯的紀錄上寫完
之後,`--verify-index` 會說 `index OK`**——要在編輯「之前」驗證;而 `--json` 的 `records`
只有在「拿去比對你要求的起點」時才回答得了 `-mid` 那個問題。

---

## EZ. 四個旗標不在 KNOWN_FLAGS 裡,而那份清單的用途就是攔住它們(2026-08-21 修正,T154)

自查時發現,不是任何回合報的——因為**盲測回合被禁止使用 `--help`**,而這正是從那裡看得見的
東西。

```
$ csv2 -update 1:2 --version -i f.csv -o o.csv ; echo rc=$?
rc=0
$ csv2 -get 1:2 -i o.csv
--version                      ← 被當成資料寫進去了
$ csv2 -update 1:2 -r -i f.csv -o o2.csv
csv2: -update -r: -r is a flag, and this position takes DATA …   ← 同一個位置的 -r 會被拒絕
```

缺的是 `version`、`V`、`A`、`B`、`C` 五個名字(`-A`／`-B`／`-C` 是上下文旗標)。

**而 T121h 本來就是為了防止這件事而存在的**——它拿 KNOWN_FLAGS 去對解析器的 case——它沒有
看見:它的樣式在別名處只允許小寫,因此 `case "version", "V":` 這一行**完全不匹配、整行被
跳過**。一個「只在別名全為小寫時才看得見」的檢查,漏掉的正好是唯一有大寫別名的那一行。

順帶,`--help` 少了 `--build-index`:一個真實存在、兩份 README 都寫了的旗標,不在使用者
最先讀到的那段文字裡。現在 T154 兩個方向都釘:解析器認得的每一個旗標都要出現在 `--help`,
而 `--help` 裡的每一個旗標都要是解析器認得的。

**寫這個修正時我自己又造了一個同類的洞**:加進 KNOWN_FLAGS 的那段註解裡有一個帶引號的旗標
名稱,而抽取器讀的是「括號之間每一個帶引號的 token」——於是憑空多出一個不存在的旗標,花了
兩次執行才看出來。那段註解現在寫明「這裡不放加引號的旗標名稱」,理由就在它自己身上。

---

## FA. 編輯路徑上的 `--json` 與 `-md`:被接受、被忽略、rc=0(2026-08-21 修正,T155a)

第 58 回合。同一個軸上的三個旗標,三種行為:

```
$ csv2 -update 1:2 Z --json -i f.csv -o o.csv ; echo rc=$?
rc=0                                   ← 輸出是 CSV，--json 被丟掉了
$ csv2 -update 1:2 Z -md -t -i f.csv -o o2.csv ; echo rc=$?
rc=0                                   ← 同上
$ csv2 -update 1:2 Z --a1 -i f.csv -o o3.csv
csv2: --a1 adds to the address in the locating report …      ← 這個會拒絕
```

而 `-md` 少了 `-t` 時,在編輯路徑上又會因為「完全不同的理由」被拒絕——所以那個旗標**有被
解析、它的前置條件也有被檢查**,只是它要求的那件事最後被丟掉了。

選擇拒絕而不是照做:把一張 Markdown 表格寫進 `.csv` 路徑,會產生一個這支工具隨後拒絕讀取的
檔案,而那正是格式規則存在要防止的失敗。

## FB. 我昨天加的那則 log 紀錄,自己不可解析(2026-08-21 修正,T155d/e)

ET 讓 `-delete` 記下被刪紀錄的內容。第 58 回合隔天指出:

```
$ printf '"a,b",c\n1,2\n' > cm.csv
$ csv2 -delete 1 -i cm.csv --in-place -log L.log
delete record 1: a,b="1", c="2"        ← 讀起來像三個欄位
```

**這棵樹為之存在的那個檔案格式,允許欄名裡有逗號**——README 甚至講了怎麼定址那種欄位——
而我為它寫的稽核紀錄用逗號當分隔符、名字不加引號。現在兩邊都加引號並跳脫。

同一則報告裡的另一半:那行「執行了什麼指令」的紀錄完全不加引號,於是 `-i "my file.csv"`
會記成 `-i my file.csv`——一則指名了「沒有人執行過的指令」的稽核紀錄。

---

## FC. 第 58 回合的機器介面那一批(2026-08-21 處理,T156 與兩份 README)

那一輪把「程式會去解析的每一種輸出」當成契約去攻擊。工具擋住了大部分(欄名裡的引號、換行、
tab、ESC、空欄名,全都產生合法且可還原的 JSON;重複欄名以 rc=1 拒絕),而它找到的是**契約
沒有被寫下來的部分**:

- **`.csv2` 的 JSON 物件多帶一個鍵 `header_zh`**,兩份 README 一次也沒提過(`grep -c` 為 0)。
  唯一的範例是 `.csv` 的五個鍵。「一個做 schema 驗證的消費端,會在遇到第一個 `.csv2` 時壞掉」。
  順帶:`--en`／`--zh` 會改變「定位報告」中間那一欄,在 `--json` 裡什麼也不改——兩件都沒寫。
- **串流被切斷時,那行 meta 不存在**(讀取端提早離開、或 `-so` 編輯在吐出紀錄之後才失敗),
  而沒有帶內建標記可以分辨。README 說「最後一行帶總數」,而那句話在被切斷時不成立。
- **預覽截斷的算術不一致**:截的是「值的 200 個原始字元」,而輸出是在跳脫「之後」;`N` 數的是
  原始字元。於是一個由控制字元組成的值,寫出來的那一行可以長達 800 個字元——**而那正是截斷
  當初要防止的事**。README 原本給的理由(「否則一個 400 bytes 的儲存格會把格式帶走」)撐不住;
  現在寫的是「它限制的是值,不是那一行」,並寫明 `N` 的單位與 `\xNN` 的大小寫。

---

## FD. 一筆跨行的紀錄,讓整個檔案失去 seek(2026-08-21 修正,索引 v4,T157)

第 59 回合量到:15 MB 的 `.csv` 上 `-tail 40` 讀了整個檔案(640 ms),而同樣形狀的 `.csv2`
只讀 6400 bytes(3.7 ms);`-mid` 也一樣(306 ms 對 3.5 ms)。它把這回報成「兩種格式行為不同,
而文件從未說格式有影響」。

**格式不是原因。** 手動確認:

```
$ csv2 -tail 40 -i big.csv  -debug   # 45 萬筆，沒有任何跨行紀錄
DEBUG index hit: record 449961 …  read_bytes=7072      ← .csv 走得到 seek
$ csv2 -tail 40 -i big.csv2 -debug
DEBUG index hit: record 449961 …  read_bytes=7072      ← .csv2 一樣
$ csv2 -tail 40 -i nl.csv   -debug   # 同一個檔案，只有「一筆」改成含引號換行
                                  read_bytes=15300010  ← 整個檔案
```

真正的條件是 `no_embedded_newlines`。`.csv2` 用反斜線跳脫、不可能跨行,所以它永遠滿足;
`.csv` 只要**有一筆**跨行就不滿足——**45 萬分之一的紀錄,代價是整個檔案。**

為什麼原本要那個條件:一個格點只有位元組偏移量,從它恢復解析說不出「落在第幾實體行」,
而 `--physical` 會把行號放進輸出,且有無索引的輸出必須逐位元相同。

修法是把行號存進索引(v4:每個格點 16 bytes——偏移量 + 行號;檔頭多一個 `lastLine`,
讓追加不必掃描就能延續)。那道門因此拿掉了,而它所保護的性質由 T157c/d/e 釘住:
`-tail --physical`、跨過那筆跨行紀錄的 `-mid`、以及一次追加之後,有無索引都逐位元相同。

實測(8 KB 的測試檔):`-tail 40` 從「讀完 8010」變成「讀 2880」;15 MB 的檔案上是
「讀完 15,300,010」變成「讀 7072」。

**這一項本來就在計畫裡**——`csv2view` 那一節寫著它在等的兩件事之一就是「在索引裡存行號,
讓含引號換行的檔案仍然能 seek」。第 59 回合量出了它的代價,而使用者要求把 `.csv` 做得跟
`.csv2` 一樣。現在一樣了。

---

## FE. `--json` 對非 UTF-8 是靜默有損的,而另外兩個形狀都誠實(2026-08-21 修正,T158)

第 59 回合:「`--json` 對非法 UTF-8 與開頭的 U+FEFF 是有損的,而 `-r` 與 `-get` 不是。
沒有任何旗標、WARN、標記或結束狀態,能分辨一行忠實的 `--json` 與一行有損的。」

```
$ printf 'a,b\n1,caf\xe9\n' > bad.csv
$ csv2 -get 1:2 -i bad.csv | od -c
0000000    c   a   f 351  \n              ← 原始位元組
$ csv2 -contains caf -i bad.csv
1:2	b	<non-UTF-8: 63 61 66 e9>       ← 報告誠實地說了
$ csv2 -r -t --json -i bad.csv
{"record":1,…,"b":"caf<U+FFFD>"}          ← rc=0，合法的 JSON，而值變了
```

**而 `--json` 正是這份 README 在「值本身才是重點」時推薦的那個形狀。** 一行合法的 JSON、
一個被替換掉的位元組、rc=0——那是「看起來與成功完全相同」的資料遺失。

修法是拒絕而不是替換:指出是哪一筆哪一欄,並指向 `-get`(交還位元組)與定位報告(以十六進位
指名)。**在一個地方拒絕之所以是對的,正因為另外兩個形狀誠實地回答了同一個問題**——T158b/c/d
把那三件一起釘住,免得日後有人「順手」把另外兩個也改成拒絕。

---

## FF2. 第 59 回合其餘的(2026-08-21 處理,T159 與兩份 README)

**是我昨天寫下、而沒有測試撐著的兩句話:**

- README 承諾 `-delete -col` 會有一則稽核紀錄。**沒有。** 一次移除了整個欄位的執行,留下的
  軌跡沒有指名任何欄位(已修,見 FB 之後的那次提交)。
- 「一次寫入會順手修好 sidecar」寫成了無條件。**在 `CSV2_INDEX_MIN_BYTES` 以下不會**:
  那次寫入不建索引,於是過期的 sidecar 留在原地、`--verify-index` 仍然以 1 結束。
  **證據在小檔案上活著,在大檔案上不會。**

**位址會靜默出錯的方式不只一種。** README 說「有一種」,而第二種更單純:有人在你的兩個指令
之間改了那個檔案。`--verify-index` 與 `--no-index` 對它一點作用也沒有——那兩個守的是 sidecar,
而這裡連 sidecar 都沒有參與。已寫進兩份 README,連同「要嘛把寫入者排成序列,要嘛帶著值走」。

**沒有人寫下來的三件讀取行為**(T159):任何位置的空白行都是硬錯誤(包含「以兩個換行結尾」
的檔案所帶的那一個,而訊息當時談的是欄數);**未加引號欄位裡的裸 CR 在這裡是資料,在
Python 的 `csv` 裡是換行**——同一個檔案,一邊兩筆、一邊三列;NUL 與其他控制位元組原樣接受。

**其餘**:`--headers` 在「路徑不以 .csv／.csv2 結尾」時是必要的,而那個檢查區分大小寫
(`.CSV` 也要);`CSV2_INDEX_MIN_BYTES` 那一列說「不讀也不寫」,而 `--build-index` 是明確的
要求,任何大小都會寫。

---

## FG. `--build-index` 與讀取動詞併用:讀取被靜默丟棄(2026-08-21 修正,T160)

第 60 回合:

```
$ csv2 --build-index -contains v3 -i f.csv ; echo rc=$?
index built: 500 records, stride 256, 2 grid points
rc=0                                   ← 沒有搜尋，而「什麼也沒找到」也是 rc=0
$ csv2 --build-index -get 1:2 -i f.csv
index built: 500 records, stride 256, 2 grid points   ← 於是 val=$(csv2 -get …) 會把這句話寫進儲存格
$ csv2 --build-index -update 1:2 Z -i f.csv --in-place
csv2: --build-index and an edit verb cannot both run …   ← 編輯會被拒絕
```

**那條拒絕是我 2026-08-20 加的(DN),而它只涵蓋了編輯動詞。** 讀取動詞被丟棄的方式完全相同,
而 `-get` 那一條更糟:那句 `index built: …` 會經由 README 自己的 `val=$(csv2 -get …)` 配方
寫進一個資料儲存格,rc=0。

同一條規則,只套用到它成立之處的一半——本專案最常見的缺陷形狀,而這一次是我犯的。

`-r` 不列入拒絕:它同時也是預設值,拒絕它等於拒絕 `csv2 --build-index -i f.csv` 這個最平常
的用法,而那種情況下沒有任何東西被丟棄。

## FH. 「只有 `-contains` 會讀 sidecar」——我寫下、而沒有量過(2026-08-21 修正,T143f/g)

第 56 回合說「只有 `-contains` 使用 sidecar」,我照抄進了兩份 README。第 60 回合量了:

```
$ csv2 -mid 100,110 -i f.csv -debug
DEBUG index hit: record 100 via grid point 1 at byte 4        ← -mid 也讀
$ csv2 -tail 5 -i f.csv -debug
DEBUG index hit: record 496 via grid point 257 at byte 2092   ← -tail 也讀
$ csv2 -get 100:2 -i f.csv -debug
（沒有任何一行提到索引）                                      ← 只有 -get 不讀
```

而那一段正是「告訴讀者何時需要 `--verify-index`」的地方——**他拿到的是錯的那一組**。

兩份 README 已更正,並在原地寫下它為什麼會錯:一句關於行為、取自報告而沒有執行過的話,
是一個猜測。T143f/g 現在把「哪些動詞會讀」逐一量出來。

**寫那個測試時,同一種錯誤又發生了一次**:第一版只探測 `index hit` 這一句,而平行搜尋說的是
`trusting index`——於是它得出「`-contains` 不讀 sidecar」的結論。第二版改對了字串,卻仍然失敗,
因為在這個檔案的 `exec > >(tee …)` 之下,`cmd 2>&1 >/dev/null | grep` 沒有把 stderr 交給那個
grep;改成先捕獲再比對才對。**一個探測,量到的可能是自己的管線。**

---

## FI. `--in-place` 在寫入期間,把一個 0600 檔案的內容變成所有人可讀(2026-08-21 修正,T161)

第 61 回合。暫存檔以 umask 的 0644 建立,而來源的模式要到 rename「之前」才套上去:

```
$ chmod 600 big.csv                 # 15 MB
$ csv2 -update 1:2 Q -i big.csv --in-place &
$ ls -l .big.csv.csv2tmp.*
-rw-r--r--    ← 整個寫入期間，內容對所有人可讀
$ ls -l big.csv
-rw-------    ← 結束之後才是對的
```

README 那句「一次編輯不會改變誰讀得到它」對「完成後的檔案」成立,對「寫入期間」不成立——
而在大檔案上那是一個以秒計的時間窗,檔名還是可預測的(`.<名字>.csv2tmp.<pid>`)。

修法是把暫存檔改成一開始就以 0600 建立:**先私有、最後再放寬,才是對的順序**——寫入期間該
生效的是來源的模式,而 0600 永遠不會比它更寬。

順帶記下同一段文字的另一個缺口:**擴充屬性(xattr)會遺失**,因為暫存檔是一個新檔案,沒有
任何東西把它們複製過去。原本寫著「仍然不會被保留的有兩件」,實際上是三件。

## FJ. 那條拒絕又漏了一半(2026-08-21 修正,T160c/e/f)

FG 才剛把「`--build-index` 與讀取動詞併用」補進拒絕清單,第 61 回合就找出它仍然漏掉的:
`-r`(明確打出來時)、`--json`、`-md`,以及**兩個管理用旗標同時給出**(其中一個會被另一個
丟棄,而完全不涉及動詞)。

`-r` 那一條是我刻意排除的,理由是「它同時也是預設值」。那個理由對「預設」成立,對「一個
真的打了 `-r`、卻沒有拿到輸出的呼叫端」不成立——**同一個字,兩種身分,而我只想到一種。**

---

## FK. 兩個位元組的檔案:一個 UTF-16 BOM 被當成欄名(2026-08-21 修正,T162a)

第 62 回合為每一條「關於輸入」的規則,造出「剛好違反」與「剛好只差一個位元組就滿足」的兩個
檔案。兩條在邊界上破掉,這是其中之一:

```
$ printf '\xff\xfe' > B2.csv      # 兩個位元組：剛好就是一個 UTF-16LE BOM
$ csv2 -r -t -i B2.csv | od -c
0000000  377 376  \n              ← rc=0，成為一個「欄名就是那兩個位元組」的單欄 CSV
$ printf '\xff\xfea' > B3.csv     # 多一個位元組
csv2: this file begins with a UTF-16LE byte-order mark …   ← 這裡才拒絕
```

成因:`if bomPending.count < BOM.count { return }`——`BOM` 是 UTF-8 的那三個位元組,而
UTF-16 的判斷只需要兩個。於是「整個檔案就是兩個位元組」時,那個判斷永遠等不到執行。

**而那正是編輯器把一份空文件存成 UTF-16 時寫出來的檔案。** 對照之下,一個零位元組的檔案
——語意上同樣是空的——會因為「沒有宣告自己的形狀」而被拒絕:**兩條規則在相鄰的大小上互相矛盾。**

## FL. 「任何位置的空白行都會被拒絕」在單欄檔案上不成立(2026-08-21 以文件處理,T162e/f)

```
$ printf 'a\n\n' > one.csv
$ csv2 -r -t --json -i one.csv
{"record":1,"line":2,"fields":{"a":""}}      ← rc=0
```

那條規則是我 2026-08-21 寫的,寫成了全稱。**在單欄檔案裡,一個空白行與「一筆只有一個空欄位
的紀錄」是同一組位元組**,沒有東西可以拒絕——而那個錯誤訊息本身的措辭是從欄數生成的,因此
讀者從文字裡推導不出這個例外。

沒有改行為:拒絕它,等於讓一個單欄檔案沒辦法在自己的一行上放一個空值。改的是文件,並指出
`""` 是「讓檔案自己說清楚」的寫法(讀起來完全一樣)。

順帶補上一條從來沒有寫下來的格式規則:**`.csv2` 必須以換行結尾,`.csv` 不必**——前者「一筆
一行」,停在行中間就是撕裂的最後一筆。

---

## FM. 輸出形狀取決於另一個旗標的「數值」(2026-08-21 修正,T163)

第 62 回合跑了約六十組「拒絕表沒有列出」的旗標配對。這一組會靜默地改變輸出的**形狀**:

```
$ csv2 -contains HIT -A 0 -i ctx.csv | head -1
6:2	b	HIT          ← 定位報告（TAB 分隔）
$ csv2 -contains HIT -A 1 -i ctx.csv | head -1
6,HIT               ← CSV 紀錄
```

README 寫的是「`-A`／`-B`／`-C` **蘊含 `--filter`**」,沒有條件;而實作寫的是
`after > 0 || before > 0`。於是一支寫 `-A "$N"` 的腳本,會依一個變數拿到兩種不相容的格式,
rc=0,什麼也不說——**那正是 README 開頭那句「挑錯的那一個是最容易犯的錯:`-contains` 印的是
報告,不是 CSV」,只是經由一次旗標互動抵達。**

修法:蘊含關係跟著「旗標有沒有被給」走,不跟著它的值走。筆數仍然跟著值走(T163e/f 釘住這一半,
免得修正把 `-A 0` 變成 `-A 1`)。

順帶記下同一組的另一件,那件沒有改:`-A`／`-B`／`-C` 重複給時後者勝出,而 `-C` 會同時設定兩邊,
因此 `-C 1 -A 3` 與 `-A 3 -C 1` 不同。grep 也是這樣,而 README 已寫明。

---

## FN. 「只有 `--json` 對此不出聲」——可量測地錯,而那句是我寫的(2026-08-21 修正,T164)

第 62 回合把這份文件當成「作者的對手」來讀,而它先說了一句公道話:這份文件比多數的誠實,
它按日期認錯、點名打敗過它的盲測回合、把自己給錯的建議與更正並排印出來——**而那正是讓剩下
那些「為自己說話」的句子更難被看見的原因,不是更容易。**

然後它量了這一句:

```
$ csv2 -r -t -md -i lat.csv | od -t x1
… 63 61 66 ef bf bd …        ← U+FFFD，rc=0，什麼也不說
```

`-md` 會替換,而我那句話說的是「只有 `--json` 不出聲」。三個宣稱是對的,第四個不是。

**沒有改 `-md` 的行為**:它是一種算繪、不是一次來回,`--pretty` 甚至會照「替換之後的寬度」
去補欄寬——T136 早就為 `<br>` 說過同一句話。改的是那個句子,並且把「哪些形狀交還位元組、哪些
拒絕、哪些替換」三者一起釘進 T164,免得下次又只描述其中一半。

## FO. 狀態表是十一勝一敗,而那一敗不是能力缺口(2026-08-21 處理)

同一回合:那張「可用／尚未做」的表,唯一的「尚未做」是一個**部署**決定。而實測「這個工具不做」
的有:欄位投影、不分大小寫比對、計數、格式轉換、安全的並行寫入,以及「以程式分辨不同的拒絕」。
每一項在本文後面都有描述——**而讀者最先掃到的那張表,呈現的是一個只剩一件事沒做的工具。**

兩份 README 現在都多一張「不提供／改用什麼」的表,緊接在那張表後面。

---

## FP. `-append --in-place`「從不把檔案讀到結尾」——它會,而且已經會了一段時間(2026-08-21 修正,T165)

第 63 回合。README 用**同一個理由**在三個地方解釋同一件事:

```
README.md:398   fast path never reads the file to the end. An existing …
README.md:1574  --in-place` builds none — its fast path never reads to the end — …
README.md:1733  --in-place` does not replace one either, because its fast path never reads
README.zh-TW.md:327   `-append --in-place` 也不會建,因為它的快路徑根本不會把檔案讀到結尾
README.zh-TW.md:1414  `-append --in-place` 同樣不會替換它,因為它的快路徑根本不會讀到檔尾
```

而 `src/Run.swift` 裡那條路徑上,**每一次追加都無條件呼叫 `validateBeforeAppend()`**,它從第一個
位元組解析到最後一個。那個呼叫是為了修「一筆停在未關閉引號裡的紀錄」而加的——當時連同它上方
那段長註解一起加,註解自己就寫著「代價是一次快路徑當初就是為了避免它的掃描」。**加的時候改了
`-append` 條目的計時表(`:302`,0.07/0.24/0.92 s)與 `:1809`,沒有改那三處**。

實測(本機,中位數 5 次,inode 追加前後相同):

```console
2.0 MB → 50 ms   8.0 MB → 188 ms   35.0 MB → 802 ms
```

線性,與 README 自己 `:302` 的表一致。「O(1) 的是**寫出的位元組**,不是時間」才是真的。

**形狀:一個理由被修掉之後,只有引用它的其中一部分被更新。** 與 DN→FG→FJ 同一族,但這次
被留下的不是一條規則的另一半,而是**同一句話的另外三份副本**。

**而它的後果不只是那三句話。** 那個理由同時被用來正當化一項**行為**:「`-append --in-place`
不會建索引」。README 自己的規則是「下一個**寫入檔案**、或**本來就必須讀到檔尾**的操作,會寫回
一份好的索引」。追加兩項都符合,卻是唯一的例外,而例外的理由已經不成立——那次掃描本來就在跑,
順手記格點幾乎免費。`src/Index.swift` 的 `noteAppend()` 與 `src/Run.swift` 追加尾端的註解,
都還寫著「沒有索引時不在此建立:為了一個 O(1) 的操作去做一次 O(n) 全掃描,會把快路徑的意義
完全抵銷」——那次 O(n) 全掃描已經在那裡了。

修法是讓那次「本來就在跑」的驗證掃描順便建索引,而不是把三句話改成描述一個沒必要的例外。

---

## GA. 追加寫進索引的那個行號,少了「上一筆佔掉的行數」(2026-08-21 修正,T166)

驗證 FP 時自己撞到的,**不是第 63 回合回報的**。

`-append --in-place` 是唯一一條「延續」索引而不是重建索引的路徑,而它這樣算新紀錄的起始行:

```swift
var line = Int(idx.lastLine) + prefix.count   // Run.swift:1631
```

`lastLine` 的定義寫在 `src/Index.swift:40`:**「最後一筆紀錄『開始』的那一行」**。因此這個算式
給的是「上一筆開始的行」,而不是「下一筆開始的行」——中間少了上一筆自己佔掉的行數(至少一行,
引號內含換行時更多)。

重現(header + 第 1 筆跨兩行 + 到第 256 筆,追加第 257 筆恰好落在格點上):

```console
$ export CSV2_INDEX_MIN_BYTES=0
$ csv2 --build-index -i b.csv
index built: 256 records, stride 256, 1 grid points
$ csv2 -append 'r257,n257' -i b.csv --in-place
$ csv2 -mid 257,257 --json -i b.csv | sed -n 2p
{"record":257,"line":258,"fields":{"id":"r257","note":"n257"}}
$ csv2 -mid 257,257 --json --no-index -i b.csv | sed -n 2p
{"record":257,"line":259,"fields":{"id":"r257","note":"n257"}}
```

**rc=0,兩者相差一行,而索引的那一個是錯的。** 直接讀 sidecar 的位元組也看得到:

```console
$ python3 -c "import struct;b=open('b.csv.index','rb').read();d=open('b.csv','rb').read();
off,ln=struct.unpack_from('<QQ',b,96+16);print('stored',ln,'true',d[:off].count(10)+1)"
stored 258 true 259
```

修法不是去補「上一筆佔幾行」——索引裡沒有那個數字,而 v4 也不該為此擴欄。修法是:那條路徑
**現在會把檔案讀到結尾**(見 FP),於是換行數是現成的,新紀錄的起始行 = 檔案裡的換行總數 + 1 +
(補上的那個換行,0 或 1)。這是精確值,而且不依賴索引先前存了什麼。

---

## GB. `--verify-index` 不驗它自己存的行號,所以 GA 通過了驗證(2026-08-21 修正,T166d;它一啟用就抓到 GD 與 GE)

同上一條。GA 那份索引裡有一個確定是錯的行號,而:

```console
$ csv2 --verify-index -i b.csv
index OK: 257 records, stride 256, 2 grid points
$ echo $?
0
```

README 說 `--verify-index` 是「O(n) 的完整比對,涵蓋索引的**全部三項宣稱**:格點偏移量、紀錄
筆數,以及是否有紀錄跨行」。自 v4 起索引存的是**四項**——每個格點還帶一個行號——而驗證沒有跟上。

**形狀:一個格式加了一個欄位,而「證明這份索引是對的」那個函式沒有把新欄位加進證明。** 這與
T79 是同一個門:一份索引宣稱了一件「沒有任何東西重新推導過」的事。差別只在那次是筆數,這次是
行號,而行號更難察覺——它只在 `--json`、`--physical` 與 `@L` 位址上露臉。

---

## FQ. 「holds 9 MB」——那 9 MB 是這個行程的地板,不是 `--pretty` 配置的(2026-08-21 修正,T167)

第 63 回合。`CSV2_PRETTY_MAX_BYTES` 的說明(`:1613`)要教的是「上限量的是**被對齊的材料**,不是
輸入檔」,而它舉的例子把一個數字釘在那個概念上:

> `-mid 150000,150004 -t -md --pretty` on a 23 MB file **holds 9 MB** and succeeds

實測:

```console
$ csv2 -mid 150000,150004 -t -i big.csv | wc -c
     237                                   ← 材料是 237 bytes
$ /usr/bin/time -l csv2 -mid 150000,150004 -t -md --pretty -i big.csv   → 7.45 MB peak RSS
$ /usr/bin/time -l csv2 -tail 1 -i big.csv                             → 7.34 MB peak RSS
```

**那個數字是 `csv2 -tail 1` 也要付的固定開銷**,與 `--pretty`、與「被對齊的材料」都無關。照字面
讀它的人會得到「5 筆佔 9 MB」,於是推出「16 MiB 上限只夠 pretty 兩個這種切片」——與同一句話裡的
「always fine」直接矛盾。

**規則本身是對的**(二分法確認:材料 15.0 MB 通過、18.8 MB 拒絕)。錯的是被拿來教它的那個例子。

---

## FR. 「訊息會指出請求、上限與變數名稱」——`-tail` 是,`-B` 不是,而 `-C` 指的是沒被打過的旗標(2026-08-21 修正,T168)

第 63 回合(前兩項),第三項是驗證時自己撞到的。

```console
$ CSV2_MAX_BUFFER_RECORDS=5 csv2 -tail 6 -i s.csv
csv2: -tail 6 exceeds the buffered-record limit (5); raise CSV2_MAX_BUFFER_RECORDS if you really mean it
$ CSV2_MAX_BUFFER_RECORDS=5 csv2 -contains MIT -B 6 -i s.csv
csv2: -B 6 exceeds the buffered-record limit (5)          ← 沒有變數名稱
$ CSV2_MAX_BUFFER_RECORDS=5 csv2 -contains MIT -C 6 -i s.csv
csv2: -B 6 exceeds the buffered-record limit (5)          ← 使用者打的是 -C
```

安全性質(拒絕而不截斷)在三者上都成立,rc=1。壞掉的是「撞牆的人被告知該轉哪個旋鈕」——第二則
沒說,第三則還指了一個他沒碰過的旗標,於是他會去找自己的指令列裡並不存在的 `-B`。

**形狀:一句涵蓋兩個旗標的宣稱,只被其中一個滿足。** 與 FJ 同族。

---

## FS. 「兩種都很便宜」——實測其中一種比它保護的那次搜尋還貴(2026-08-21 以文件處理)

第 63 回合。README `:530` 對「sidecar 可能過期」給了兩條出路,並稱兩者都 cheap:

```sh
csv2 --verify-index -i f.csv2               # O(n)
csv2 -contains "old" --no-index -i f.csv2
```

實測(17.7 MB / 450,000 筆,中位數 5 次):

```
--verify-index            451 ms
-contains(用索引)         204 ms      → 路線一合計 655 ms
-contains --no-index      528 ms      → 路線二
```

**對「只搜一次」的人,先證明再搜比完全不用索引還慢 1.24 倍。** 兩次以上才划算,損益平衡大約在
1.3 次——而那個數字文件裡沒有。

---

## FT. `-log` 用了一個它自己那一節沒有記載的跳脫,而它給的解碼步驟會解錯(2026-08-21 修正,T169)

第 63 回合。`-log` 那一節(`:862`)把跳脫集合寫成一份**四個的封閉清單**,並在 `:888` 指示讀者
怎麼消化它:

> A newline, tab, CR or backslash is written as `\n`, `\t`, `\r` or `\\`.
> Unescape the line first (`\n`, `\t`, `\r`, `\\`), then read the quoted fields.

實測——值裡有 ESC 與 BEL:

```console
$ csv2 -update 1:2 "$(printf 'e\033[31mR\007b')" -i l.csv --in-place -log lg.txt
$ sed -n 2p lg.txt
2026-08-21T11:52:57.926+08:00 INFO  update 1:b: "old" -> "e\x1B[31mR\x07b"
```

程式是對的:其他控制字元一律寫成 `\xNN`、大寫十六進位——那正是**定位報告**那一節(`:480`)已經
記載的同一套約定。錯的是 `-log` 那一節說自己只有四個,並把一份不完整的解碼步驟講成足夠的。

照那份步驟寫出來的稽核腳本,會把一個 17 字元的值重建成 21 個字面字元,然後回報一個不存在的
不一致——**在這份文件自己稱為「權威、絕不截斷」的那個輸出上**。

---

## FU. argv 在 NUL 處截斷,而同一個邊界上的另一半已經有一條拒絕(2026-08-21 以文件處理,T171)

第 63 回合的第 1 題:只用文件推薦的做法,做出一串「結尾是資料悄悄變短」的指令。

```console
$ printf 'pkg,note\nzlib,before\x00after\nzstd,plain\n' > nul.csv
$ addr=1:2
$ val=$(csv2 -get "$addr" -i nul.csv; printf x); val=${val%x}; val=${val%$'\n'}
$ csv2 -update "$addr" "$val" -i nul.csv --in-place ; echo $?
0
$ csv2 -get 1:2 -i nul.csv | od -t x1 | head -1
0000000 62 65 66 6f 72 65 0a                      ← before,六個位元組不見了
```

**csv2 看不到這件事**:截斷發生在 `execve`,csv2 收到的就是 `before`,而它忠實地寫下了 `before`。
zsh 那一端反而是好的(`set -x` 顯示變數裡的 NUL 完好)。

但這棵樹**已經在這個邊界上蓋了一條拒絕**:拒絕表對「不是合法 UTF-8 的值」寫著「Swift 用替代字元
解 `argv`,位元組已經沒了……把值放進檔案,位元組在那裡活得下來」。也就是說文件**早就認定 argv
是一條有損通道**,而它對同一條通道上「截掉整個尾巴」的那一半,沒有一句話。

兩句各自為真、合起來誤導人的話:

- `:715`「**NUL 與其他控制位元組原樣接受**……它們會 round-trip」——對**檔案**那條路完全成立
  (實測 `-r -t` 位元組相同、`--json` 給 ` `、報告給 `\x00`)。
- `:501–517` 那個「先取值、再寫回」的配方,**把唯一一個 shell 陷阱指名、修好、還自陳上一版
  漏了第三行**。那種「已經徹底審過」的語氣,讀者會當成這個邊界已經關上了。

**唯一記下真相的是稽核軌跡**——`update 1:note: "before\x00after" -> "before"`——而那要你有加 `-log`
(配方沒有),而且要看懂它得先知道 FT 那個沒被記載的 `\xNN`。

程式端沒有可修的東西。文件端有三處:那個配方、那句 round-trip、以及拒絕表裡那條已經在講 argv 的
說明。

---

## FV. 四個沒有標價的保證(2026-08-21 以文件處理,材料上限由 T167 釘住)

第 63 回合的第 4 題。實測(17.7 MB / 450,000 筆):

| 保證 | 文件寫的價錢 | 實測 |
|---|---|---|
| `--build-index`,也就是那個 5.6 ms 視窗的來源 | **沒有** | **505 ms**,是它換來的那次視窗的 24 倍;要約 130 次視窗才回本 |
| `--verify-index` 的 O(n) 證明 | 「O(n) because it has to be」,沒有數字,而且被稱為 cheap | **451 ms**(見 FS) |
| `-o` / `--in-place` 的原子改名 | 名稱、權限(0600)、原子性都寫了 | **峰值磁碟是檔案的 2 倍**——完全沒寫。`:1808` 量化了「寫出的位元組」(改 1 GiB 檔的一格要寫 1 GiB),卻沒說你還要有 1 GiB **可用空間**,而這是文件自己說「唯一沒有退路」的那個保證 |
| `--pretty` 的記憶體 | 只有一個 16 MiB 的材料上限 | 材料 15.0 MB → **峰值 RSS 81 MB,約 5.4 倍**。同一則警告 `CSV2_PARALLEL_MAX_BYTES` 有(「這不是行程記憶體的上限」),`--pretty` 沒有,而這裡的倍數更大 |

---

## FW. `-debug` 的 `metrics:` 印了兩個從未被定義的數字(2026-08-21 以文件處理)

第 63 回合。`-debug` 被賣成量測工具(`:414`「Measure with it rather than guessing」),而它印的是:

```
DEBUG metrics: read_bytes=65536 file_bytes=19688912 peak_rss_bytes=9175040
```

文件只提過 `peak_rss_bytes`。受測者為了確認 `read_bytes` 不是自相矛盾——小檔案上 `-mid 2,3`
同時印出「stopping after record 3」與 `read_bytes=263`(整個檔案)——必須自己造一個 20 MB 的
fixture 才能確定那是「一個 64 KiB 緩衝區」而不是缺陷。那個 64 KiB 的數字出現在文件的另一處
(`:1163`,講 `-so` 的緩衝),兩者從未被連起來。

---

## FX. 拒絕表少了 `-insert`,WARN 清單少了 `--truncate-partial`(2026-08-21 修正,T170)

第 63 回合。兩處都是「程式做了對的事,而清單沒有把它算進去」:

```console
$ csv2 -insert 2 'a,b' -i four.csv -o out.csv
csv2: -insert 2 has 2 fields but the header has 4     ← 對的,但拒絕表只列了 -append
$ csv2 -r -t --truncate-partial -i partial.csv -o clean.csv
WARN --truncate-partial discarded 27 bytes: …         ← 對的,但 :1334 的 WARN 清單只列了兩項
```

一份宣稱自己完整的清單漏掉一項,比沒有清單糟:讀者會用「不在清單上」推論「不會發生」。

---

## FY. `--no-index` 在 `.csv` 上還會放棄平行路徑,而那寫在另一張表裡(2026-08-21 修正,T171)

第 63 回合。`--no-index` 在 `:534` 與 `:1694` 被推薦為「比較慢,但構造上就是對的」。實測慢多少:

```
-contains(用索引,平行)   204 ms
-contains --no-index      528 ms      → 2.6 倍
$ csv2 -contains pkg150000 --no-index -i big.csv -debug
DEBUG single-threaded: --no-index, and a .csv needs an index to prove one record per line
```

原因**程式自己說得很清楚**,而文件把它放在 `:1628` 的平行化要求表裡,離推薦它的那兩處很遠。
推導得出來,但沒有在該說的地方說。

---

## FZ. `-update 1:2 -- --in-place`——第三個「看起來可以貼進終端機」的片段(2026-08-21 修正,T172)

第 63 回合。`:359` 用這串解釋 `--`:

```console
$ csv2 -update 1:2 -- --in-place -i d1.csv -o d1out.csv     ← 這樣才會動
$ csv2 -update 1:2 -- --in-place                            ← 逐字照抄:
csv2: an edit needs an explicit destination …
```

它是片段而不是指令,這沒問題;有問題的是這份 README **已經為了同一件事道歉過兩次**(`-log` 那組、
加密標記那組),而這是第三個。一份自陳「我曾經印出看起來能跑但不能跑的區塊」的文件,再印一個,
會把那份自陳變成裝飾。

---

## GC. 那個檢查碼不是 FNV-1a,而註解說它是(2026-08-21 以文件處理,T166d 把常數釘住)

為了替 GB 寫一個「檢查碼合法、但行號是錯的」索引,我照 `src/Index.swift:160` 的註解在 Python 裡
重寫了那個檢查碼。算出來的值與檔案裡的不符,而**只有最高的三個位元組不同**——那不是「讀錯了
某個欄位」會有的形狀。

原因是這一個字面值:

```swift
h = h &* 0x1000_0000_01b3      // 底線的分組錯了一個 nibble
```

FNV-1a 的 64 位元質數是 `0x100000001b3`(2^40 + 0x1b3)。上面那個是 `0x1000000001b3`
(2^44 + 0x1b3)。實測兩者:

```
以 0x100000001b3   算 → 0x7a5800e06861298f   不符
以 0x1000000001b3  算 → 0xe72f92e06861298f   符合檔案
```

**沒有安全性後果**:乘數仍是奇數,模 2^64 仍是雙射,抓位元翻轉與寫入不完整的能力不變。有後果的
是那個名字——照著註解重新實作的人(我)會算出另一個數字,然後推論那份索引壞了。

**與 FT 是同一個形狀,只是低了一層**:一份「按照文件寫成的讀取器,重現不出工具實際寫下的東西」。
FT 那次是稽核軌跡的跳脫,這次是 sidecar 的檢查碼。

改常數會讓每一份已經在磁碟上的 sidecar 被回報成「已損毀」——對一批毫無損毀的檔案說損毀。因此
改的是名字,不是常數;而測試套件現在用 Python 獨立算一次,把常數釘在「那一行以外的地方」。

---

## GD. `-insert` 建出的索引描述的是另一個檔案,而 `-mid` 照著它回答(2026-08-21 修正,T173)

**這一條是 GB 抓到的。** 在 `--verify-index` 學會比對它自己存的行號之後,既有的 T41b 與 T46b
立刻變紅——而那兩個案例從來沒有動過。順著紅字往回追,發現的不是行號,是這個。

被插入的一列走的是 `emit()`,而不是 `emitData()`。`emit()` 只推進位元組偏移量:它不增加
`outRecords`、不通知 builder、也不推進行號。於是同一次執行寫出了 N+1 筆紀錄,卻建出一份說
「N 筆」的索引,而插入點之後的每一個格點,指的位元組都已經是另一筆紀錄的開頭。

```console
$ export CSV2_INDEX_MIN_BYTES=100        # 300 筆的 ins.csv,在第 5 筆插入一列
$ csv2 -insert 5 'X,Y' -i ins.csv -o ins2.csv
$ csv2 --verify-index -i ins2.csv
index MISMATCH: record 1: index says line 1, actual 2
index MISMATCH: record 257: index says byte 2356, actual 2346
index MISMATCH: record 257: index says line 257, actual 258
index MISMATCH: record count: index says 300, actual 301
```

而讀取端照著它回答:

```console
$ csv2 -mid 257,258 -t -i ins2.csv          $ csv2 -mid 257,258 -t --no-index -i ins2.csv
id,note                                     id,note
r257,n257     ← 這是第 258 筆              r256,n256
r258,n258     ← 這是第 259 筆              r257,n257
```

**rc=0,兩個都沒有出聲,而用了索引的那一個是錯的。** 這正是本設計自己寫下的那句話所指的情況:
「一個會很快給你錯資料的索引,比沒有索引糟得多。」

同一個計數器還餵給稽核軌跡的最後一行。以修正前的二進位檔實測:

```console
$ csv2 -insert 5 'X,Y' -i ins.csv -o ins5.csv -log /dev/stdout | grep wrote
… INFO  wrote 300 records, 2 fields, atomic rename OK      ← 檔案裡有 301 筆
```

**那份「說得出這次寫入做了什麼」的紀錄,少算的正好是它剛剛插入的那一筆。**

修法是 `emitData(ins)`:被插入的一列是輸出的一筆紀錄,就該被當成一筆計。

**形狀:兩個寫出位元組的函式,只有其中一個負責記帳。** 這與 GA 是同一族(唯一一條「延續」索引
的路徑,是唯一一條能把索引記錯的路徑),而它存活得更久,因為 `-insert` 的**資料**一直都是對的
——錯的只有旁邊那份 sidecar,而在 GB 之前,沒有任何東西會去讀它並提出異議。

---

## GE. 一次寫入建出的索引,說第 1 筆在第 1 行(2026-08-21 修正,T174)

同樣由 GB 抓到,是 T41b 紅字裡的第一行。

標頭列是透過 `emit()` 寫出去的,而行號是在 `emitData()` 裡數的。於是標頭推進了偏移量、沒有
推進行號:一份 `.csv2`(兩列標頭)寫出後,索引說第 1 筆在第 1 行,而它在第 3 行。

```console
$ csv2 --verify-index -i ix.csv2
index MISMATCH: record 1: index says line 1, actual 3
```

差距**恰好等於標頭列數**,因此 `.csv` 上是差 1、`.csv2` 上是差 2——每一份由寫入建出的索引都有,
自 v4 加進行號那天起就有,而在 GB 之前沒有任何東西看過它。

修法是把行號的計數移進 `emit()`——也就是那個「每一個離開的位元組都經過」的函式——並讓
`emitData()` 呼叫它,而不是各寫一份。**兩份記帳會分岔,一份不會。**

---

## GF. `--in-place` 接受選取動詞,把檔案截斷成那個選取,rc=0、無聲、且稽核軌跡不記(2026-08-21 修正,T175)

第 64 回合。這是本輪最重的一條,而且它同時是三種沉默。

```console
$ wc -c g.csv
      16 g.csv                      # a,b / 1,x / 2,y / 3,z
$ csv2 -head 1 -t -i g.csv --in-place -log lg.txt
$ echo $?
0
$ wc -c g.csv
       8 g.csv
$ cat g.csv
a,b
1,x
$ cat lg.txt
2026-08-21T12:53:18.907+08:00 INFO  csv2 -head 1 -t -i g.csv --in-place -log lg.txt
```

**三筆紀錄變成一筆,stdout 沒有輸出,stderr 沒有輸出,rc=0,而 log 裡只有那一行「呼叫」——
沒有 `wrote N records`。** 同樣可重現的還有 `-tail 2 -t --in-place`、`-mid 5,9 -t --in-place`。

而 README 對那一行 `wrote N records, M fields, atomic rename OK` 是這樣說的:

> the line that says the write completed, **and the one to look for when asking whether an edit landed**

**於是這個工具最具破壞性的操作,同時是它最少被稽核的操作。** 一個照著 README 的指示去問
「這次執行到底寫了沒有」的稽核者,對一次剛剛丟掉檔案 5/6 內容的執行,會得到「什麼也沒寫」。

**擋在使用者與這件事之間的,是 `-t`——一個關於「標頭」的旗標,不是關於安全的旗標。** 沒有
`-t` 會被那條「寫資料列到宣告了標頭的格式需要 -t」的拒絕擋下;`-i x -o x` 會被擋下並被指向
`--in-place`。因此 `--in-place` 是唯一的入口,而守門的那一個旗標,守的是另一件事。

兩份 README 都沒有寫這件事(受測者對 `--in-place` 逐處 grep 過,每一處都在「編輯」的脈絡裡)。
拒絕表裡有「`-head` 搭配 `-o` 而沒有 `-t`」,沒有「`-head` 搭配 `--in-place` 而**有** `-t`」。

修法是拒絕:`--in-place` 在文件裡的定義是「就地**編輯** -i」,而選取不是編輯。要把一個檔案裁成
一個選取,請寫到新檔案。理由不是純潔性,是這條路徑上「打錯一個旗標」與「按計畫執行」在輸出上
完全無法分辨——而這正是這個專案存在所要消除的那一類失敗。

---

## GG. 錯誤訊息把原始控制位元組送到 stderr,包括會擦掉那一行的 ESC(2026-08-21 修正,T176)

第 64 回合,而它是從「試圖偽造第三行失敗」那個方向找到的:行數的承諾守住了,**跳脫的規則沒有**。

```console
$ csv2 -delete -col "$(printf 'na\033[2Kme')" -i f.csv -o o.csv 2>&1 | head -1 | od -c
0000020    n   a   m   e   d       "   n   a 033   [   2   K   m   e   "
$ csv2 -delete -col "$(printf 'na\tme')" -i f.csv -o o.csv 2>&1 | head -1 | od -c
0000020    n   a   m   e   d       "   n   a  \t   m   e   "   ;       t
```

**stderr 上出現了實際的 ESC 與 TAB 位元組,而它們來自輸入。** README 為「定位報告要跳脫」給的
理由是:「ESC 也能抹掉它正被印出的那一行——也就是承載那個位址的那一行。」同一個危害,同一套
理由,不同的路徑,而那兩條路徑在文件裡只隔一行。

原因是 `lineEscape()` 只處理換行與歸位字元。那是**刻意**的:2026-08-20 試過「全部都跳脫」,結果
弄壞了那些「教你怎麼跳脫」的訊息(`undefined escape sequence \q` 變成 `\\q`),因為一個關卡分不出
「作者的散文」與「插進去的值」。那個決定對**反斜線**是對的。它對**控制字元**不對:csv2 自己的
散文裡沒有 ESC、沒有 BEL、沒有 TAB——那些一律來自資料。

因此修法是把 `lineEscape()` 擴到「C0 控制字元與 DEL」,而**繼續**放過反斜線;那則教學訊息因此
仍然是對的,而終端機注入從每一則訊息上被關掉——包括還沒有人寫的那些。

---

## GH. `ERROR` 那一行分不出「字面的反斜線 n」與「一個換行」,而同一次執行的 `INFO` 那一行分得出(2026-08-21 修正,T176c)

同上一條,而這一半是精確度而不是終端機安全。兩次執行、兩個不同的欄名:

```
INFO  … -delete -col na\nme  …          ← 真正的 LF,被正確跳脫
ERROR no column named "na\nme"; …
INFO  … -delete -col na\\nme …          ← 字面的反斜線 n,被正確加倍
ERROR no column named "na\nme"; …       ← 與上一則逐位元組相同
```

**兩則 INFO 分得出來,兩則 ERROR 一模一樣。** 而 README 給的解碼步驟是「先解開 `\n`、`\t`、`\r`、
`\\` 與 `\xNN`,再讀那些帶引號的欄位」——把它套到任何一則 ERROR 上,都會得到一個帶著「真換行」的
名字。**於是那個從來沒有換行的名字,被讀出了一個換行,而讀的那一端 rc=0,什麼也看不出來。**

修法不是把反斜線也丟給那個關卡(見 GG:那會弄壞教學訊息),而是在**插值的地方**把值完整跳脫——
`no column named "…"` 正是 README 拿來當範例的那一則,它現在走 `reportEscape`。「值」與「散文」
需要相反的處理,而分得出兩者的只有插值的那一點。

---

## GI. `--in-place` 的診斷印的是解析過 symlink 的路徑,`-o` 印的是你打的那一個(2026-08-21 以文件處理)

第 64 回合。macOS 上 `/private/tmp/x` 會變成 `/tmp/x`;相對路徑會被絕對化。

這是 DP 那個修正的**刻意**後果——`--in-place` 的意思是「編輯這個檔案」,而 symlink 不是那個檔案,
因此輸出路徑會被解析。但它從未被寫下來,而它有影響:README 自己說「以程式分辨不同的拒絕」只能靠
比對英文字句,那麼一個想從訊息裡認出「自己那個路徑」的腳本,在 macOS 的 `--in-place` 上會認不出來。

以文件處理:訊息裡的路徑是「csv2 實際會寫的那一個」,而在 `--in-place` 上那是解析過 symlink 的路徑。

---

## GJ. WARN 的判準讀起來是一條原則,實際上是一張封閉清單(2026-08-21 以文件處理)

第 64 回合。README 說:

> 一個 `WARN`,是「執行成功了,但做的事幾乎可以確定不是呼叫端想要的」

接著列了四種具體情況。而 GF——把 22 筆裡的 21 筆銷毀——完全符合那條原則,卻沒有 WARN;
而「什麼也沒選到、什麼也沒破壞」(`-mid` 越過檔尾)反而有。

**讀者無法從那段文字判斷自己拿到的是哪一種承諾。** GF 修掉之後那個具體矛盾消失了,但那段文字
仍然把一張清單寫成一條原則。改法是照實說:那是一張清單,而清單的內容就在下一句裡。

---

## GK. 一個選取加上 `-hash`／`-encrypt`／`-decrypt` 再加 `--in-place`,照樣把檔案截斷——那道守衛是我昨天寫的(2026-08-21 修正,T177)

第 65 回合。GF 修好的那個缺陷,**加一個旗標就回來了**:

```console
$ csv2 -head 1 -t -i T.csv --in-place
csv2: -head selects records; --in-place writes an EDIT back to its input, …
rc=1,22 筆完好                                    ← GF 的守衛,正確

$ csv2 -head 1 -hash license -i T.csv --in-place -log L.log
rc=0
22 筆 → 1 筆
$ cat L.log
… INFO  csv2 -head 1 -hash license -i T.csv --in-place -log L.log
… INFO  hashing columns license with NO key (unsalted SHA-256)
```

**rc=0、兩條輸出流上什麼也沒有、log 裡沒有結果行。** 五種形式全部可重現:`-head`+`-hash`、
`-tail`+`-hash`、`-mid`+`-encrypt`、`-contains --filter`+`-hash`、`-head`+`-decrypt`。

**`-decrypt` 那一個最糟**:六筆 ChaCha20-Poly1305 密文變成兩筆明文,而帶著鹽的檔頭被重寫。
README 對那個鹽的說法是「沒有它,密文再也沒有任何人解得開」。四筆密文與它們的鹽一起消失,rc=0。

**原因是我寫的那道守衛用錯了謂詞。** 它問的是「有沒有編輯動詞?」

```swift
if o.edits.isEmpty && o.encryptCols == nil && o.decryptCols == nil && o.hashCols == nil {
```

而規則是「有沒有**選取**?」。`-hash` 讓第一個條件為假,於是守衛整個跳過。而拒絕表裡我自己寫的
那一列說的是另一件事:「a SELECTION with `--in-place`」——**表寫的是規則,程式做的是另一個謂詞**,
兩者恰好在要命的地方分岔。

而這條路徑之所以連 `editing and selection cannot be combined` 那道舊守衛也躲過,是因為那道守衛
的清單是 `-insert`/`-append`/`-delete`/`-update`。**`-hash` 掉在兩道守衛中間。**

**形狀:一條規則被實作成「另一個剛好在當時等價的條件」。** 這與 DN→FG→FJ 同族,而這次的
「當時」只有一天——GF 是 2026-08-21 修的,GK 是同一天被找到的。修法是照規則本身寫:
`selecting || (沒有編輯也沒有轉換)`。而「有轉換、沒有選取」必須繼續可用——
`-r -hash col --in-place` 重寫每一筆、不丟掉任何一筆,那正是就地保護存在的用途。

---

## GL. 每一次保護寫入的稽核軌跡,都少了那一行「結果」(2026-08-21 修正,T177d)

同一回合。README 對 `wrote N records, M fields, atomic rename OK` 的說法是:

> **the one to look for when asking whether an edit landed**

實測(修正前):

| 執行 | 有那一行嗎 |
|---|---|
| `-update … --in-place -log` | 有 |
| `-delete 2 --in-place -log` | 有 |
| `-hash license -o … -log` | **沒有** |
| `-encrypt license -keyfile … -o … -log` | **沒有** |
| `-head 1 -hash license --in-place -log`(毀掉 21 筆) | **沒有** |

**原因與 GK 同源**:`-hash`/`-encrypt`/`-decrypt` 沒有「編輯」,因此 `main()` 把它們送去
`runSelect` 而不是 `runEdit`——而那一行寫在 `runEdit` 裡。於是「結果無法還原」的那一類編輯,
恰恰是那行「結果」缺席的那一類。

一個照著 README 的指示去問「這次執行到底寫了沒有」的稽核者,對一次剛剛把一整欄變成雜湊、
或剛剛毀掉 21 筆的執行,得到的答案是「什麼也沒寫」。

---

## GM. 「加上 `--yes` 會讓輸出更強」——實測用一次 `csv2` 呼叫就把六個值全部還原(2026-08-21 以文件處理,T178)

第 65 回合。README 的 `-hash` 一節花了很多篇幅警告「不加金鑰的雜湊可以用字典還原」,接著說:

> **Pass `-keyfile` and it becomes HMAC-SHA256.** … the digests now depend on a secret and
> **the word list is useless without it**.
> So adding `--yes` to make a script non-interactive **strengthens the output**.

而 `--yes` 的意思是「不詢問、直接用預設金鑰」,那把預設金鑰是**這台機器上的一個檔案**:

```console
… INFO  using the default multissh key at /Users/…/.multissh/generated/mldsa44-ed25519.key.raw (--yes)
… INFO  hashing columns license with a key from … (fingerprint 9c65c01a)
```

攻擊者不需要讀那個檔案,也不需要看到明文——他只要能執行 `csv2`:

```console
$ printf 'w,license\n1,Zlib\n2,MIT\n…\n' > wordlist.csv
$ csv2 -hash license --yes -i wordlist.csv -o wl.csv -t     # rc=0，一次呼叫
$ head -1 wl.csv ; head -1 受害檔.csv
w,license:hmac:9c65c01a
pkg,ver,license:hmac:9c65c01a                                ← 同一個指紋
```

以摘要對接後:**六個值全部還原**。不加金鑰的那種還原了五個;「被強化過」的這種還原了六個。

那句話把「有金鑰」與「有秘密」混為一談。一把「這台機器上任何行程都能用一個有文件記載的單字
旗標取得」的金鑰,對「本地讀取者」不是秘密——而本地讀取者正是整個 `-hash` 一節所設想的威脅
(「任何拿到這個雜湊過的檔案的人」)。

**兩個加重情節,而且都出自 README 自己**:檔案裡的標記 `license:hmac:9c65c01a` **公告了**
這次用的是預設金鑰;而 README **把那個指紋印在文件裡**,所以攻擊者連猜都不必猜。受測者第一次
就重現出 `9c65c01a`。

`-keyfile` 搭配一把真正隨機的 32 位元組金鑰是穩的——同樣的攻擊在金鑰不對時什麼也還原不出來。
缺陷限於 `--yes`,而 README 恰恰是在「非互動、沒有人在看」的場合推薦它。

程式端不改:`--yes` 的用途就是「不要問我」,而它記錄了自己用了哪一把。改的是那句話。

---

## GN. 訊息裡的路徑有四種呈現,而我昨天寫的那兩句話把它們都說反了(2026-08-21 以文件處理)

第 65 回合。GI 那一條我以文件處理,而**我寫下的那段話沒有量過**:

> `-o` echoes what you typed … A diagnostic names the path csv2 will actually write, which
> under `--in-place` is the resolved one

實測:

| 訊息 | 打的 | 印出來的 |
|---|---|---|
| `-o md1.csv` 的拒絕 | `md1.csv` | `/private/tmp/…/md1.csv` — 絕對化 |
| `--in-place` 選取守衛 | `s.csv` | `s.csv` — 照打的 |
| `cannot open input file` | `./nope.csv` | `./nope.csv` — 照打的 |

**兩句都說反了。** 而真正的規則其實簡單,且與程式一致:**輸入路徑照打的印,輸出路徑印解析過的**
——因為 `--in-place` 只解析「輸出」(那是 DP 那個修正的內容),而選取守衛引用的是 `-i` 的參數,
所以它照打的印。

**形狀:一句「為了補上文件缺口」而寫、卻沒有量過的話。** 這與 FH（「只有 `-contains` 會讀
sidecar」）、FN（「只有 `--json` 對此不出聲」）是同一族,而這是第三次。

---

## GO. `-rownum`:一個「顯示」旗標寫出了一個真的欄位,而 `--en`／`--zh` 清不掉它(2026-08-21 修正,T179)

第 65 回合,三件相關的事。

**(a) `-md` 的標頭。** `-rownum` 的那一格被寫死成 `rownum<br>列號`:

```console
$ csv2 -r -t -rownum -md --en -i pkgs.csv2      → |rownum<br>列號|pkg|ver|note|
$ csv2 -r -t -rownum -md --zh -i pkgs.csv2      → |rownum<br>列號|套件|版本|備註|
$ csv2 -r -t -rownum -md -i pkgs.csv            → |rownum<br>列號|pkg|ver|note|
```

README 對 `--en`／`--zh` 的說法是「gives one clean row instead」,而它們唯獨清不掉 csv2 自己
發明的那一格;而一份**只有一列標頭**的 `.csv`,在一張「以『資料有兩列標頭』來解釋合併」的表格裡,
得到一個 `<br>` 格與其他純文字格並排。已修:那一格現在跟著其他每一欄的規則走。

**(b) `-rownum` + `--json` 被安靜地忽略。** 沒有 rownum 鍵、`fields` 不變、rc=0——而
`--a1`、`--physical` 在同樣的情況下被拒絕,`-get` 更是**指名 `-rownum`** 並以「它會被忽略」
為由拒絕。已修:`--json` 也拒絕它。

**(c) `-rownum` + `-o` 把生成的欄位寫進檔案,而其後每一個位址都永久位移一格。**

```console
$ csv2 -head 2 -t -rownum -i pkgs.csv -o rn.csv
$ head -1 rn.csv                → rownum,pkg,ver,note
$ csv2 -get 1:1 -i pkgs.csv     → zlib
$ csv2 -get 1:1 -i rn.csv       → 1
```

而 README 對位址穩定性的說法是:「an address you found earlier … **has to keep meaning the
same cell no matter which display flags a later run uses**」。跨過 `-o` 之後那句話不成立。

(c) 未改行為:把列號輸出成一欄是正當的匯出需求,而沒有別的做法可以達成。改的是文件——那個
代價現在寫在旗標條目裡,而不是只寫「讀取者會看到 rownum 在第 1 欄」。

---

## GP. 讀標記的兩個建議用 `cut -d,` 切 CSV——正是這個工具存在所要防止的那件事(2026-08-21 修正,T180)

第 65 回合。README 印了兩次:

```sh
head -1 masked.csv | cut -d, -f7            # -hash 那一節
head -1 e$i.csv | rev | cut -d, -f1 | rev   # -encrypt 那一節
```

在最後一欄的欄名含有帶引號的逗號時(README 自己說那是真實且可達的:「`-delete -col a,b`
指的是一個叫做 `a,b` 的欄位,而那也是含逗號的欄名唯一抵達得到的方式」):

```console
$ head -1 cmh.csv
pkg,"secret, real:hash"
$ head -1 cmh.csv | rev | cut -d, -f1 | rev
 real:hash"                                   ← 半個值，rc=0
```

而同一份 README 在另一處說:「**Do not reach for `cut` against `--filter` or `-mid` output:
that is CSV… That failure is why csv2 exists; getting it from csv2's own output would be a
poor joke.**」**標頭那一行也是 CSV。**

正確的工具存在、而且有記載,只是從來沒有被當成「怎麼讀標記」的答案:

```console
$ csv2 -r -t --json -i cmh.csv | head -1
{"meta":{…,"protected":{"secret, real":"hash"}}}
```

兩個配方都已改成這一個。這條同時違反了本機全域 `CLAUDE.md` 的第一條規則,而那條規則的理由,
正是這棵樹付過的代價。

---

## GQ. `-hash`／`-encrypt`／`-decrypt` 在文件裡沒有被歸類,而三道守衛對它們的答案各不相同(2026-08-21 修正)

第 65 回合把 GK 與 GL 的共同根因指了出來,而它是文件問題:**保護動詞是「編輯」還是「選取」,
文件從來沒說。** 它們不在拒絕表列出的編輯動詞清單裡(`-insert`/`-append`/`-delete`/`-update`),
不在選取清單裡(`-head`/`-tail`/`-mid`/`-contains`/`-r`),自己住在 `PROTECTION` 一節。

於是三道守衛給了三種答案:對 `--in-place` 它們算編輯(GK),對「編輯+選取」那道守衛它們不算編輯,
對「編輯需要明確目的地」那條規則它們也不算——因此:

```console
$ csv2 -hash license -i s.csv          # 沒有 -o、沒有 -so、沒有 --in-place
pkg,ver,license:hash
zlib,1.3.2,dc65a73a…                   ← 直接寫到 stdout，rc=0
```

那是第五種輸出模式,而那張拒絕表的四動詞清單沒有涵蓋它。同樣沒有記載的還有:`-hash` **一律**
寫出標頭(文件只為 `-encrypt` 寫了這件事),以及 `-hash` 會標記 `.csv2` 的**兩列**標頭。

已修:兩份 README 現在明說保護動詞是「會重寫每一筆的編輯」、它們一律寫標頭、沒有目的地時寫到
stdout,而且它們不能與選取合用於 `--in-place`。

---

## GR. 中文 README 還留著英文版剛剛以「危險」為由刪掉的那條 WARN「原則」(2026-08-21 修正)

第 65 回合。GJ 的修正只做了一半:英文版把 WARN 從「一條原則」改成「一張封閉清單」並寫明理由,
而 `README.zh-TW.md` 在兩處仍然寫著

> **一次成功、但幾乎確定不是呼叫端本意的執行**,會有一行 WARN

**只讀中文的人拿到的,正是英文版說「會毀掉資料」的那個讀法。** 而在 GK 尚未修好時,他拿到的是
一個「確實會成功並毀掉 21 筆、而且完全不印 WARN」的工具。

**形狀:一份雙語文件,只修了一半。** 這是本專案的雙語規則存在的理由,也是它第一次被違反。

---

## GS. 「三條拒絕跟著它」——實際上有四條(2026-08-21 修正)

第 65 回合。COLS 那一段說有三條拒絕跟著欄位清單,而實測有四條:一個「名字同時匹配到兩欄」的
token 也會被拒絕,而那條拒絕寫在文件的另一個地方。數字已改,並把第四條指到它所在的位置。

---

## GT. 一份 `.csv2` 戴著 `.csv` 的名字——反方向文件寫得很長,這個方向一句也沒有(2026-08-21 修正)

第 65 回合。README 用一整段加一個工作範例加 T97 描述「`.csv` 改名成 `.csv2`」會怎麼樣,而
「`.csv2` 改名成 `.csv`」一句也沒有——同一次改名的另一個方向,產生同一類的靜默損壞:那一列
中文欄名成為第 1 筆資料,搜尋得到、也定址得到,rc=0。

而 README 推薦的自我檢查在這個方向上幫不上忙:`--json` 的第一行會說 `{"format":"csv","headers":1}`
——那句話對「名字」為真,對「內容」什麼也沒說。已補上一段,連同「怎麼確認」的實際做法。

---

## GU. `--normalize` 沒有 `-contains` 時被安靜地接受(2026-08-21 修正,T181)

第 65 回合。它的兩個鄰居 `--filter` 與 `--include-headers` 都會因「需要 -contains」而被拒絕,
而 `--normalize` 不會:rc=0,什麼也不做。`--normalize` 決定的是一次搜尋怎麼比較,沒有別的東西
會讀它。已修:同樣拒絕,並在訊息裡順帶說明「儲存的內容永遠不會被正規化」。

---

## GV. 「絕不要把 `--headers` 與編輯動詞合用」——沒有強制、沒有後果,而且與兩行之上的一條要求矛盾(2026-08-21 修正)

第 65 回合。`--headers` 條目結尾寫著 `never combine it with an edit verb`。實測三種形式:

```console
$ csv2 -update 1:2 X --headers 1 -i UP.CSV -o OUT.CSV     rc=0，正確
$ csv2 -update 1:2 X --headers 1 -i UP.CSV --in-place     rc=0，正確
$ cat s.csv | csv2 -update 1:2 X --headers 1 -si -so      rc=0，正確
```

**而第三種是被要求的**:同一個條目的第一句就說 `--headers` 對 `-si` 是**必要**的。於是那句話
禁止的,正是文件自己規定必須做的事。

「不一致」的那個情況(`--headers` 與副檔名不符)本來就已經是一條拒絕。那句話沒有守著任何東西,
只是讓讀者相信有一個他找不到的危險。已刪除,並改成那句真正成立的話。

---

## GW. CR 行尾的守衛:規則說的是「行尾」,測的是「數量」,而兩邊都裂開了(2026-08-21 修正,T180)

第 66 回合,而它是本輪最重的一條——**因為其中一半是「rc=0、沒有任何輸出、資料被讀成別的東西」**。

守衛的自陳理由是「本檔案使用 CR 行尾(OS X 之前的 Mac 慣例)」;實際的判斷是
`crAsDataCount > lfCount`。

**(a) 在理由不成立的地方觸發。**

```console
$ python3 -c "open('cr3.csv','wb').write(b'a,b\n1,x\r\r\ry\n')"
$ csv2 -r -i cr3.csv
csv2: this file uses CR line endings … convert it first with: tr '\r' '\n' < file > converted.csv
$ echo $?
1
```

**那個檔案沒有使用 CR 行尾。** 它有兩行、都以 LF 結尾,它有一筆紀錄,欄位 `b` 的值是
`x\r\r\ry`——而那正是 README 自己承諾過的資料。訊息陳述了一件關於這個檔案的假話。

邊界(LF 固定為 2):`CR=1 rc=0`、`CR=2 rc=0`、`CR=3 rc=1`。而 **照著訊息給的建議做會毀掉資料**:

```console
$ tr '\r' '\n' < cr3.csv > converted.csv
$ csv2 -r --json -i converted.csv
csv2: record 2 (line 3) is a blank line, …
```

**(b) 在理由成立的地方沉默,rc=0,而答案是錯的。**

```console
$ python3 -c "open('t3.csv','wb').write(b'col\r\"L\nL\nL\nL\"\rzz\r')"
$ csv2 -r --json -i t3.csv
{"meta":{"format":"csv","headers":1,"fields":1}}
{"record":1,"line":2,"fields":{"col\r\"L":"L"}}
{"record":2,"line":3,"fields":{"col\r\"L":"L"}}
{"record":3,"line":4,"fields":{"col\r\"L":"L\"\rzz\r"}}
{"meta":{"records":3,"matched":0}}
$ echo $?      → 0，stderr 0 bytes
```

那個檔案**確實**以 CR 結尾:一欄、欄名 `col`、第 1 筆是一個內含 `L\nL\nL\nL` 的引號欄位、
第 2 筆是 `zz`。csv2 把它讀成**三筆**,欄名成了 `col\r"L`,引號欄位沿著它自己的換行被撕開,
開引號成了標頭的一部分、閉引號成了值的一部分。CR=3、LF=3,於是 `CR > LF` 為假,守衛從未執行。

**而 README 把這個失敗描述成「已經修好」**:「原本它問的是『有沒有完全沒有 LF』,而一個結尾的
LF 就足以讓它閉嘴」。那次修正把問題從「完全沒有 LF」改成「CR 比 LF 多」。**新的問題有同一個洞,
只是從一個 LF 漲到三個。**

**修法不是再調一次數量,而是換一個精確的判斷:標頭列裡有沒有裸 CR。** 一個以 CR 結尾的檔案
沒有 LF 去結束它的第一行,因此它的全部內容都落在第一筆紀錄裡——證據永遠在標頭列。這條規則:

- 抓得到上面三種形狀(多欄、單欄、CR 與 LF 一樣多);
- 不會誤傷「紀錄裡的資料 CR」,那條承諾與它的位元組往返都完好;
- 而一個確實屬於「欄名」的 CR 仍然到得了——加一對引號,而引號內的 CR 從來就不算數。

**形狀:一條規則被實作成一個「大致相關」的統計量。** 與 GK 同族,但這一次那個統計量從一開始
就不等價,只是在當時的測試資料上剛好一致。

---

## GX. `-i` 指向一個 FIFO,得到的是「這個檔案是空的」(2026-08-21 修正,T181)

第 66 回合。

```console
$ mkfifo fifo.csv
$ { sleep 0.2; printf 'a,b\n1,x\n2,y\n' > fifo.csv } &
$ csv2 -r -i fifo.csv
csv2: fifo.csv: expected 1 header row(s), found 0
```

**那條串流有三行。** 而 README 把那句訊息記載為「零位元組檔案」的診斷——被貼進一張工單時,
它告訴第二個讀者「你的輸入是空的」。同樣的位元組走 `-si` 讀得完全正確。

兩個原因,兩個都修了:

1. **新鮮度戳記在解析之前讀走了頭尾各 64 個位元組**,而在管線上那些位元組不會回來。
   `FileStamp.of` 現在對「非一般檔案」回傳 nil——那正是這棵樹在其他每一處用來表達
   「這個輸入沒有索引」的寫法。
2. **`runSelect` 把輸入開了兩次**:`planIndex(o, plan: try openInput(o), …)` 開一次只為了
   讀那份 plan 的格式,然後丟掉,接著再開一次真正來讀。在一般檔案上那是免費的;在 FIFO 上
   第一次把管線抽乾,第二次在等一個早已離開的寫入端。現在只開一次。

修好之後,`-r`、`-contains`、`-mid`、`-tail`、`-get`、`-head` 在 FIFO 上都給出正確答案。

---

## GY. 硬連結不是一種拼法,而 `-i x -o y` 只比對拼法(2026-08-21 修正,T182)

第 66 回合。README 說那條拒絕涵蓋「不論那兩者怎麼拼寫」。實測 `./x`、`././x`、絕對路徑、
symlink 全部抓得到,而硬連結抓不到:

```console
$ ln same.csv hard.csv          # 兩者 inode 都是 175352245
$ csv2 -update 1:2 Z -i same.csv -o hard.csv ; echo $?
0
```

同一個 inode、同一個檔案,沒有拒絕——而那次執行悄悄地把連結斷開了:`hard.csv` 成了一個新的
inode,`same.csv` 留著舊內容。沒有資料遺失,因此這是本輪四條之中最輕的一條;但那句
「不論怎麼拼寫」是假的。已修:`sameFile` 現在在路徑比對之外,也比對 (dev, ino)。

Windows 上回傳 nil 而不比對:那裡的 CRT 對所有檔案都回報 inode 0,比對的答案會是
「每個檔案都是彼此」。

---

## GZ. 十六個 NUL 是一把合格的金鑰,而十五個隨機位元組不是(2026-08-21 修正,T183)

第 66 回合。那個 16 位元組下限的自陳理由是:

> A key this short is searched exhaustively in less time than this run took.

```console
$ head -c 15 /dev/urandom > k15.bin
$ csv2 -hash secret -keyfile k15.bin …     → 拒絕
$ python3 -c "open('kzero.bin','wb').write(b'\x00'*16)"
$ csv2 -hash secret -keyfile kzero.bin …   → rc=0，secret:hmac:b610bfce
```

**十六個 NUL 一次就被猜中。** 而被拒絕的那把 15 位元組隨機金鑰,大約強上 10^36 倍。規則說的是
「金鑰不可以被搜尋得到」,條件測的是 `size >= 16`。

而「16 個 NUL」不是一個假想的檔案:那正是一個**被截斷、或從未被寫入**的金鑰檔的樣子。

已修:建立保護時,拒絕「整個檔案只有一種位元組」的金鑰檔。這不是熵的估算——csv2 不做那種
判斷,一個「把呼叫端真正的金鑰擋下來」的判斷比「接受了一把差金鑰」更糟——而「只有一種位元組」
不是判斷。讀取一個「已經用弱金鑰做出來」的檔案仍然不被拒絕,與長度那條規則一致。

---

## HA. 那條 `--in-place` 拒絕的理由,對它擋下的一部分指令為假(2026-08-21 修正)

第 66 回合。那句話是我在第 64 回合寫的:

> writing a selection there would discard every record the selection does not name

而 `-mid ,`(README 說它「兩端皆開,等於每一筆」)與短檔案上的 `-head 99`(README 說它會截斷)
**指名了所有紀錄**。訊息對它們是假的。

已改成一句對它擋下的每一次執行都成立的話:選取不是編輯,而「這一次究竟會不會丟掉東西」在讀完
檔案之前無從得知——那正是它被「拒絕」而不是被「衡量」的理由。

**形狀:一條拒絕用一個「具體後果」當理由,而那個後果只在多數情況下成立。** 與 GW 同族:
一條規則,配上一個大致相關的說法。

---

## HB. `-append` 搭配 `--truncate-partial` 的訊息,斷言了一件關於檔案的事,而它沒有讀過那個檔案(2026-08-21 修正)

第 66 回合。

```console
$ printf 'a,b\n1,x\n' > ap.csv        # 完整、以 LF 結尾、沒有未關閉的引號
$ csv2 -append '9,z' --truncate-partial -i ap.csv --in-place
csv2: --truncate-partial is refused with -append: appending can only add bytes and
      cannot discard the incomplete record, …
```

**沒有「那筆不完整的紀錄」。** 這條拒絕只看旗標、在讀檔之前就觸發,於是它對完整的檔案也會
觸發,而讀者會照著訊息去找一個不存在的損壞。已改成「不論檔案內容為何」的說法:兩個旗標作為
一個要求就是不相容的。

---

## HC. 五個 `pkgs.csv`(2026-08-21 記錄,未改)

第 66 回合。README 裡的 `pkgs.csv` 在不同段落是不同的檔案:2 欄、4 欄、`pkg,ver`、`a,b`、
以及叫做 `packages.csv` 的 `pkg_name,version,source,license`。**讀者無法建出一個檔案去跑
所有範例**;受測者建了六個。

這一條沒有改,因為改法有兩種,而兩種都比現況糟:給每個區塊一個獨立的檔名(讀者要記六個名字),
或統一成一個 fixture(每個範例都得重寫,而它們各自在示範不同的東西)。記錄在此,是因為
「同一個名字在不同段落是不同的檔案」這件事,值得下一個讀者知道——尤其是在一份「叫人逐字執行
範例」的文件裡。

D6 的另一半已修:`-contains busybox` 那個區塊少印了一個命中(見 README 的更正)。

---

## HD. `-o /dev/null` 以 SIGTRAP 當機,exit 133,兩條輸出流上一個位元組也沒有(2026-08-21 修正,T184)

第 67 回合。**這一條是我前一天(GY,硬連結)的修正帶進來的**,而它把一條「有記載、正確、
兩行」的拒絕變成一次無聲的當機。

```console
$ csv2 -r -t -i t1.csv -o /dev/stdout > o.out 2> o.err
$ echo $?
133                                    # 128 + SIGTRAP
$ wc -c o.out o.err
       0 o.out
       0 o.err
```

`/dev/null`、`/dev/zero`、以及「cwd 裡指向它們的一個 symlink」都一樣,三次執行皆可重現。
而**旁邊的鄰居都是好的**:`-o` 指向目錄、`-o` 指向 FIFO,都得到那條正確的兩行拒絕。

原因在 `Platform.fileNode`:

```swift
return (UInt64(st.st_dev), UInt64(st.st_ino))
```

Darwin 的 `st_dev` 是**有號**的 32 位元 `dev_t`,而一個裝置節點的值是**負的**(`/dev/null`
是 -1)。`UInt64(-1)` 是一個 Swift trap。那條拒絕就寫在當機的下一行,永遠到不了。

**這同時打破了那句全域宣稱**:「每一種拒絕都以 1 結束……每一次都是恰好兩行 stderr」。
這裡是 exit 133、零行。而 README 拿來當這條拒絕範例的,正是 `-o /dev/stdout`。

修法是 `UInt64(bitPattern: Int64(st.st_dev))`——那個身分只會被拿去比對相等,位元樣式就是
它需要的全部。

**形狀:一個修正,在一條沒有測試覆蓋的路徑上,把「拒絕」換成了「當機」。** 前一天那個修正
有它自己的測試(T182),而 T182 測的是硬連結;沒有任何案例把 `-o` 指向一個裝置。現在有了。

---

## HE. `--truncate-partial` 說它丟掉了幾個位元組,而那個數字是編出來的(2026-08-21 修正,T185)

第 67 回合。

```console
$ printf 'a,b\n1,x\n2,"unclosed and this trails on' > part.csv
$ wc -c part.csv
      38 part.csv
$ csv2 -r -t --truncate-partial -i part.csv -o clean.csv
WARN  --truncate-partial discarded 55 bytes: an unterminated record beginning at byte 8
$ wc -c clean.csv
       8 clean.csv
```

**檔案 38 個位元組,走掉 30 個,它說 55**——比整個檔案還多。掃過一輪之後,規律是
`回報值 = 2·B + 1`(B 是開引號之後的位元組數),而真值是 `B + 前綴`:短尾巴時**少報**
(3 個位元組走掉、它說 1),長尾巴時多報將近兩倍。

原因:

```swift
let dropped = rawBuf.count + valBuf.count
```

`rawBuf` 裝的是「抵達時的位元組」(含開引號),`valBuf` 裝的是「解碼後的值」——**同一段文字
被數了兩次。**

**而同一句話的另一半永遠是對的**:「beginning at byte 8」每一次都正確。一個精確、可驗證的
子句,緊挨著一個編造的子句——那正是讓編造的那一半顯得可信的原因。

**工具裡沒有任何東西能檢查它**:這個數字沒有 `--json` 欄位、沒有 `-log` 條目、也沒有
`-debug` 行。那則 WARN 是它唯一的報告,而兩份 README 都承諾了它。修法是
`offset - recOffset`——從「這一筆開始的地方」到「輸入用完的地方」。六種大小實測全對。

---

## HF. 那張「封閉的四項 WARN 清單」漏了第五項,而它是最不該漏的那一項(2026-08-21 修正)

第 67 回合。README 在第 64 回合被改成:

> **It is a list, not a policy** — these four and no others

而:

```console
$ csv2 -r -i o1.csv -log adir 2>&1 >/dev/null
csv2: … WARN  cannot write log file adir; continuing without one
$ echo $?
0
```

**第五個 WARN,層級是 WARN,rc=0,在正常路徑上。** 而它是這張清單最不能漏掉的一個:
**呼叫端要的是一份稽核軌跡,那次執行以 0 結束,沒有任何 log 檔存在,而全部的通知就是
stderr 上一行英文。**

那正是第 64 回合被刪掉的那條「原則」所涵蓋的情況——「一次成功、但幾乎確定不是呼叫端本意的
執行」——而刪掉它的理由是「讀者無法分辨自己拿到的是原則還是清單」。**於是那張清單也不完整。**
一個為那四個 WARN 寫了處理常式的人,沒有處理到「他的稽核軌跡靜靜消失了」那一個。

---

## HG. `--json` 丟掉了 `0a`／`0b` 的區別,而那個區別存在的全部理由就是「分得出來」(2026-08-21 修正,T186)

第 67 回合。README 對那兩個標籤的說法是:「so that a hit in the English title row and one in
the Chinese title row are **distinguishable**」。

```console
$ csv2 -contains pkg    --include-headers --json -i h2.csv2 | sed -n 2p
{"record":0,"field":1,"header_en":"pkg","header_zh":"套件","value":"pkg","line":1}
$ csv2 -contains 套件   --include-headers --json -i h2.csv2 | sed -n 2p
{"record":0,"field":1,"header_en":"pkg","header_zh":"套件","value":"套件","line":2}
```

**兩者都是 `"record":0`**,只剩實體行號可以分辨——而那是在「給程式看的」那個輸出形狀裡。
定位報告分得出來,JSON 分不出來,而 README 把 JSON 推薦為「每個命中自己一行、不受影響」的
那一個。已修:命中標頭時多一個 `header_row` 鍵(`"0a"`／`"0b"`／`"0"`),資料命中則沒有。

---

## HH. 三個功能對「標頭列算不算一筆紀錄」的答案不一致(2026-08-21 以文件處理)

第 67 回合。同一個檔案、同一次搜尋:

```console
$ csv2 -contains pkg --include-headers -i h1.csv
0:1	pkg	pkg                          # 報告：有一個命中
$ csv2 -contains pkg --include-headers --json -i h1.csv | tail -1
{"meta":{"records":2,"matched":0}}       # matched：什麼也沒中
$ csv2 -contains pkg --include-headers --filter -i h1.csv
pkg,ver,note                             # --filter：它「是」一筆紀錄，在這裡
```

而 `-A`/`-B`/`-C` 的上下文進不去標頭列,動詞也拒絕定址它。

**咬得最痛的是 `matched`**,因為 README 指名它是那個「有沒有」的檢查:「A search that matches
nothing exits 0 … To ask the question, read `matched` from the trailing `--json` meta line.」
搭配 `--include-headers` 時,那個檢查對一個「它自己剛剛印出來的命中」回答「沒有」。

還有 `--filter --include-headers -t`:那列標頭會在輸出裡出現兩次,一次作為標頭、一次作為資料。
csv2 讀得回來(往返是自洽的),因此不算壞掉——但沒有任何地方寫過它。

**行為未改**:`matched` 數的是紀錄,而標頭列不是紀錄,那與 csv2 在其他每一處劃線的方式一致;
改的是文件——三個後果現在都寫在 `--include-headers` 那一節裡,連同「用了它就改數命中行數」。

---

## HI. `--en` 與 `--zh` 併用:後面那個安靜地贏(2026-08-21 修正,T187)

第 67 回合。

```console
$ csv2 -contains zlib --en --zh --include-headers -i h2.csv2   → 1:1  套件  zlib
$ csv2 -contains zlib --zh --en --include-headers -i h2.csv2   → 1:1  pkg   zlib
```

rc=0,什麼也沒說,而且與順序有關。**而這個工具拒絕 `--headers 1 --headers 2`,理由是
「安靜地取最後一個,就是 `-hash note -hash ver` 把 note 以 rc=0 留在明文的那條路」。**
同一類危險,兩種處理方式。

已修:兩個都給會被拒絕。順帶發現解析處本來就會互相清除(`--zh` 會把 `enOnly` 設回 false),
因此「兩個都給」與「只給了後面那個」在狀態上一模一樣——要看得見它,得數旗標而不是看狀態。
同一個旗標給兩次則得到另一則訊息,因為那是另一種錯誤。

**順帶記下第 67 回合查出來的一條通則,而它從未被寫進文件**:除了 `-A`/`-B`/`-C`(後者是
「後面那個贏」)之外,**重複給同一個旗標一律被拒絕**。README 只寫了那個例外,於是只讀 README
的人會把例外當成通則。兩份 README 現在都寫了這條規則。

---

## HJ. `-o ""` 走到了同一個條件,卻走了另一條路(2026-08-21 修正,T184c/d)

第 67 回合。

```console
$ csv2 -r -t -i o1.csv -o ""
csv2: cannot rename /tmp/…/.round67.csv2tmp.73581 onto /tmp/…/round67: Is a directory
```

空的 `-o` 解析成目前目錄,於是暫存檔落在呼叫端本來想寫的地方的**上一層**,而失敗以一個原始的
rename errno 抵達——沒有中文那一行、沒有指出出路、還洩漏了內部暫存檔名。同一個條件
(`-o adir`,目的地是一個目錄)在一行之外有一條正確的兩行拒絕。已修:空的 `-o` 在最前面就被拒絕。

---

## HK. 「M 是幾欄」與其他三個沒有記載的數字(2026-08-21 以文件處理)

第 67 回合的第 1 題:每一個印出來的數字,造一個「兩種合理讀法會給出不同答案」的輸入。

- **`wrote N records, M fields`**:`M` 是「一列有幾欄」,不是「寫出了幾個欄位」。3 筆 3 欄的
  檔案說 `3 records, 3 fields`——而寫出的欄位是 9 個。**這是 README 叫稽核者去找的那一行**,
  而它的兩個數字裡有一個從未被定義。已補。
- **`[+N more chars]` 的「字元」是「字素叢集」**:五個家庭 emoji 落在截斷之後回報
  `[+5 more chars]`,而不是 35(Unicode 純量)或 55(UTF-16 單元)。README 為 `--pretty`
  仔細定義過這個單位,在這裡沒有。已補。
- **`-debug` 的 `format=csv fields=7 records=3`** 完全沒有記載,而它的 `records=` 遵循的是
  「讀到的最高一筆」那條規則,只能靠推。(未補:那一行屬於 `-debug`,而 `-debug` 的每一行都是
  「現在正在查問題的人」看的,不是穩定介面。)
- **格點數是 ceil,而且第 1 筆有一個格點**:900,000 筆得到 3516 個格點。README 說「每 256 筆
  一個位元組偏移量」,讀起來是 3515。(未補:差一個的數字,而那句話要改對得把「第 1 筆也是一個
  格點」寫進去,那會讓一句已經夠長的話再長一截。記在這裡。)

---

## HL. 「每一個旗標重複給都會被拒絕」——十六個布林旗標不會,而那句話是我前一天寫的(2026-08-22 修正,T188)

第 68 回合。第 67 回合我查出「重複的旗標會被拒絕」這條從未被寫進文件的通則,並把它寫進了
旗標清單:

> REPEATS  giving the same flag twice is REFUSED, for every flag except -A/-B/-C

實測:

```console
$ csv2 -r --json --json -i pkgs.csv ; echo $?
{"meta":…}  …
0                                   ← stderr 0 bytes
```

十六個布林旗標——`-r -t --json --json-ascii --pretty --filter --include-headers --normalize
--physical --a1 --no-index --yes --truncate-partial -rownum -debug --in-place`——全部安靜地
接受重複。**而我當初查證的是十一個「帶值的」旗標,一個布林的都沒跑過**,就寫下了一個全稱。

**沒有資料會因此遺失**:一個布林旗標沒有第二個「值」可以丟掉,而那條拒絕的理由(「第二個值
可能是想改變什麼」)對它沒有著力點。因此改的是那句話,不是程式。

**形狀:第三次了。** FH(「只有 `-contains` 會讀 sidecar」)、FN(「只有 `--json` 對此不出聲」)、
GN(路徑呈現的那兩句)、HI 底下那條通則,現在是 HL——**每一次都是「為了補上文件缺口而寫的一句話,
從手邊剛好驗過的那幾個例子推出全稱」**。這一次的間隔是一天。

現在有 T188 同時釘住兩半,下一個要寫這句話的人得在兩個方向上都寫對。

---

## HM. `read_bytes` 的粒度規則,在它存在所要展示的那條路徑上是假的(2026-08-22 修正,T189)

第 68 回合。那個條目(也是我寫的,第 63 回合)說:

> read_bytes … moves in whole 64 KiB buffers, never past the end of the file

實測:

```console
$ csv2 -tail 1 -i big.csv        read_bytes=6272     file_bytes=19600004
$ csv2 -mid 1,1 -i pkgs.csv      read_bytes=49       file_bytes=62
```

6272 不是 65536 的倍數;49 比整個檔案還少。**那條規則對「掃描」為真,對「seek」為假**——而
seek 正是這個數字存在所要展示的那條路徑:`read_bytes < file_bytes` 就是索引起了作用。

更糟的是那句話推出的結論:它告訴讀者「小於一個緩衝區的檔案上,`read_bytes == file_bytes`
必然成立,因此什麼也證明不了」。而 62 位元組的檔案上它是 49——一個那條規則說「不可能發生」
的差。

**形狀與 HL 同族**:我量了掃描路徑,然後把結論寫成了全稱。

---

## HN. `--verify-index` 證明幾項宣稱:旗標條目說四項,另外兩處說三項(2026-08-22 修正)

第 68 回合。2026-08-21(GB)把行號加進了那份證明,並把旗標條目從「三項」改成「四項」——而
文件裡另外兩處仍然寫著三項,並且逐項列出時漏掉行號。實測:四種宣稱都會發出 `index MISMATCH:`。

**這正是這份文件自己的主題**:一個數字被改對了一處,而引用它的另外兩處沒有跟上。與 FP
(`-append` 那三句)是同一族,只是這次間隔是一天而不是幾個月。

---

## HO. log 裡「刪除一筆紀錄」的範例,把欄名印成沒有引號的樣子(2026-08-22 修正)

第 68 回合。log 那張表印的是:

```
delete record 1: a="1", notes="…"
```

而實際輸出是:

```
delete record 2: "a"="4", "b"="5", "c"="6"
```

**欄名也有引號**——因為一個欄名裡可以有逗號或 `=`。而 README 給出那一節的理由正是
「好讓腳本可以照著讀」;一個照著那個範例寫成的剖析器,會把那一行切錯。

---

## HP. `-insert -cell` 的拒絕,指名了「別人檔案裡的兩個欄位」(2026-08-22 修正,T190)

第 68 回合。

```console
$ csv2 -insert -cell 1 'x' -i onecol.csv -so      # 這個檔案只有一欄，叫做 a
csv2: -insert -cell does not exist: … so status_notes ends up under license. …
```

`status_notes` 與 `license` 是本專案自己 fixture 裡的兩個欄名。**在一個單欄檔案上,那則訊息
指名了兩個不存在的欄位**,而它讀起來像是在描述「你剛剛傳進來的那個檔案」。

已改成一個看得出來是舉例的說法:「原本第 5 欄的值會跑到第 6 欄的名字底下」。**當一則訊息
看不到那個檔案時,它的舉例就必須看得出來是舉例。**

---

## HQ. 四件「量得到、而文件沒說」的事(2026-08-22 修正,T191 釘住其中一件)

第 68 回合。

- **`-o` 新建一個檔案時,那個檔案是 0600,不是你的 umask。** 被帶到暫存檔上的模式來自「被取代的
  那個檔案」,而新建時沒有那個檔案。`umask 022` 下 `-o new.csv` 得到 `-rw-------`,而覆蓋一個
  0644 檔案得到 `-rw-r--r--`。預設在安全的那一邊,而在把輸出交給另一個使用者的管線之前,
  這件事得先知道。已補,並由 T191 釘住兩個方向。
- **`-o` 的「目的地」也會拿到 sidecar。** `-append -i a.csv -o b.csv` 在 `b.csv` 旁邊建了索引,
  而 `a.csv` 旁邊沒有。索引那一節只點名了 `-append --in-place`。
- **被訊號結束時,結束狀態是 `128 + signo`。** 文件釘住了 0、1、141,也承諾了暫存檔會被清掉,
  卻從未說過那個結束狀態。八種訊號實測:130、143、129、131、153、142、158、159。一個把
  「不是 0、也不是 141」當成「csv2 拒絕了我的輸入」的腳本,會把一次排程逾時誤讀成拒絕——
  而那正是本節警告過「它會那樣誤讀一個 `head`」的同一件事。已補。
- **`--verify-index` 的「以 1 結束」有兩種,而它們對「資料有沒有被讀過」說的是相反的話。**
  戳記就否決掉的那一種,stdout 上什麼也不印;而「戳記接受、資料不同意」的那一種,會在
  stdout 上為每一項不成立的宣稱印一行。已補:stdout 是空的,就表示那份 sidecar 從未被比對過。

---

## HR. 那張拒絕表被當成一份封閉合約來測,而它不是(2026-08-22 以文件處理)

第 68 回合的第 4 題:把拒絕表當合約,每一列兩個方向都測。**27 列全部觸發得到**,反方向也全部
成立(表沒說的地方確實不觸發)。而受測者另外撞到**九條不在表上的拒絕**:`-o` 目錄不存在、
`-o` 寫不進去、`--headers` 的值錯、`-get`／`-update` 的位址語法、`-mid` 的語法、金鑰檔找不到、
`-i` 是一個目錄……

而 README 自己在另一處寫著:「一張自稱完整的表,會被當成完整的來讀。」

**改法是說清楚,而不是把表養大。** 兩份 README 現在都寫明:這張表列的是「值得一提的組合」,
不列一般的引數錯誤,也不列那些寫在別處散文裡的（重複旗標、`--headers` 與副檔名不符、
重複遮蔽、`0a:` 定址、COLS 的四條、`--verify-index` 搭配動詞、環境變數上限）。

同一題還發現拒絕表的 `-md -o out.csv2` 那一列:**從一個 `.csv` 出發根本抵達不了它**——先觸發的
是第一列那條「不做格式轉換」的拒絕。已在那一列寫明要從 `.csv2` 出發。

---

## HS. 「值、列或搜尋字串不是合法 UTF-8」那條拒絕,不涵蓋 COLS(2026-08-22 以文件處理)

第 68 回合。

```console
$ csv2 -hash $'caf\xe9' -i pkgs.csv
csv2: no column named "caf<U+FFFD>"; the columns are: "pkg", "ver", "note"
```

那個 U+FFFD——正是那條拒絕存在所要防止的東西——出現在診斷訊息裡。**沒有資料被存下來**,那次
執行同樣以 1 結束,因此沒有損害;但那一列讀起來像是在講「所有引數」,而讀者無從得知
`-hash`／`-encrypt`／`-decrypt`／`-delete -col` 走的是另一條路。已在那一列寫明。

---

## HT. 兩個追加在同一個檔案上競賽:兩次編輯都遺失、一個檔案被毀掉,或一筆沒有人寫過的紀錄(2026-08-22 修正,T192)

第 69 回合,而這是本輪——也可能是這一系列——最重的一條:**它正是這個工具存在所要防止的那一類失敗,
由這個工具自己產生。**

```console
$ csv2 -append 'AAAA,BBBB' -i S.csv --in-place &
$ csv2 -append 'C,'        -i S.csv --in-place &
```

兩種結果,而 csv2 自己的 log 就把機制寫了出來:

```
INFO append fast path: wrote 12 bytes to D.csv (file was 237793 bytes)
INFO append fast path: wrote 11 bytes to D.csv (file was 237793 bytes)
```

**兩個行程都量到 237,793 位元組,而兩個都寫在那個偏移量上。** 較短的那次蓋在較長的那次上面:

- 有時剩下的碎片是一個**裸換行**,於是 `csv2 -r` 拒絕了一個 csv2 剛剛寫出來的檔案
  ——兩個寫入者都以 rc=0 結束,都記下了成功;
- 有時剩下的碎片本身是一筆**格式完整的紀錄**——`AAAA,BBBB` 被蓋掉頭部之後留下的 `A,BBBB`
  ——於是檔案以 rc=0 乾乾淨淨地讀得回來,含有一筆**沒有任何行程追加過的紀錄**。
  受測者第一次試就中了這一種。

**而那一行程式上方的註解,寫的正是它沒有做的事:**

```swift
// ONE write() per call. POSIX makes the offset update and the write atomic
// for O_APPEND, so two concurrent appends do not interleave …
h.seek(toFileOffset: size)
h.write(Data(payload))
```

那不是 O_APPEND,那是「先算出檔尾、再寫到那裡」——**而 `-log` 檔案早就為了同一個理由搬離了
這個構造,就在隔壁一個原始檔裡**,那裡的註解還寫著「六個行程寫 120 筆只剩 110 筆」。README 對
log 說的是「沒有任何平台有那個窗口」。資料檔有。

README 對並行寫入者的最壞情況說了三次:「其中一次編輯會遺失」。這裡是兩次都遺失、一個檔案被毀掉,
或者一筆紀錄被憑空造出來。

**修法**:那次寫入改走一個以 `O_APPEND` 開啟的描述子。並且——因為兩個追加現在都會完整落地——
每一邊事後都會用一次 stat 發現「檔案長大的量比自己寫的多」,並以 WARN 說出來,同時**不去更新
索引**:各自算出來的偏移量已經不是紀錄的所在,而一份「說錯紀錄從哪裡開始」的索引比沒有索引更糟。
那份 sidecar 於是原封不動地留著,下一次讀取把它當成過期的丟棄。

**形狀:一則註解宣稱了一個性質,而那個性質從來不在那段程式碼裡。** 這與 GW（規則說「行尾」、
測的是「數量」）同族,但更難察覺:那裡的兩句話至少描述同一件事,這裡的註解描述的是**另一個
系統呼叫**。

---

## HU. `--in-place`「同樣走暫存檔加 rename」——`-append` 不走(2026-08-22 修正)

第 69 回合,而它是 HT 的另一半。旗標清單說 `--in-place` 是「就地編輯 -i，同樣走暫存檔加 rename」,
而受測者量了 inode:

```console
$ csv2 -append … -i race.csv --in-place    → inode 不變，檔案長大 33 bytes
$ csv2 -update 1:1 UPD -i race.csv --in-place → inode 改變
```

**追加不用暫存檔、也不 rename**,而 README 那句「讀取端永遠不會看到一個寫到一半的檔案」正是
建立在那個機制上,而且沒有為 `-append` 留任何例外。兩份 README 現在都寫明了這個例外,連同它的
後果:追加對「讀取端」不是原子的,而追加途中當機可能留下半筆紀錄——那是其他每一種編輯都不會
發生的事。

---

## HV. `read_bytes` 的規則,兩次都是從手邊的例子推出的全稱(2026-08-22 第二次修正,T189)

第 69 回合。HM(第 68 回合)把「一律以整個 64 KiB 緩衝區推進」改成「seek 時絕不是倍數」。實測:

```console
$ csv2 -mid 200000,200000 -i big.csv -debug     # 已索引，seek 到 byte 7754630
read_bytes=65536
$ csv2 -mid 2,3 --no-index -i big.csv -debug    # 掃描，提早停止
read_bytes=65536
```

**兩個一模一樣。** 一次 seek 只有在「起點距離檔尾不到一個緩衝區」時才會回報非倍數,而 README
舉的兩個例子(29,790 與 62 位元組的檔案)都比一個緩衝區小,那個條件在它們身上恆真。

**我把一個假的全稱換成了另一個假的全稱。** 現在寫的是那個真正成立的東西:那個數字唯一能讀出
來的是 `read_bytes < file_bytes`——「這次執行不必碰整個檔案」——而它分不出「seek」與「提早停止」。

**還有第二件事**:第 68 回合我只改了英文那一頁。於是兩份 README 在同一個旗標上互相矛盾,
**而沒有被改到的中文那一頁,反而是比較準確的那一份**。這次兩頁一起改。

---

## HW. 那份「找值」配方會把 csv2 的結束狀態吃掉(2026-08-22 修正)

第 69 回合的第 4 題:只照這份 README 寫出它正在教你寫的那支維護腳本。配方是:

```sh
addr=$(csv2 -contains "old" -i f.csv2 | head -1 | cut -f1)
```

而當要找的值剛好等於某個旗標名稱時:

```console
$ csv2 -contains --in-place -i maint.csv ; echo $?
csv2: -contains --in-place: --in-place is a flag, and this position takes DATA…
1
$ csv2 -contains --in-place -i maint.csv 2>/dev/null | head -1 | cut -f1 ; echo $?
0                                          ← 那條拒絕不見了
$ csv2 -contains -- --in-place -i maint.csv
3:2	note	--in-place                     ← 那個值就在那裡
```

**`| head -1` 讓整條管線的結束狀態變成 `head` 的**,於是一次「被拒絕」對腳本而言是 rc=0、
`addr` 是空的——與「沒找到」無從分辨。而多數維護腳本會把「沒找到」當成「沒事要做」而跳過:
**於是在「資料剛好等於一個旗標名稱」的那一天,它會安靜地跳過真正該做的工作**,而那正是
README 自己說「腳本會在那一天壞掉」的那一天。

第二件事:**沒有任何地方說「搜尋字串也坐在資料位置上」**。`--` 那個條目唯一的範例是 `-update`。

配方已改:加上 `set -o pipefail`,並在搜尋字串上也加 `--`。

---

## HX. 「讀 meta 行的 matched」被指定了兩次,而一次也沒有被示範過(2026-08-22 修正)

同一回合、同一支腳本。README 說「要問『有沒有找到』,請讀 `--json` 結尾那行 meta 的 `matched`」
——在兩個地方說——**而從來沒有示範過怎麼在 shell 裡讀它**,儘管它為了「不分大小寫比對」寫出了
一整段 Python。受測者的第一版腳本因此死在一個 `bad math expression` 上。

已補上一段四行的配方,連同 `tail -1`、`pipefail`,以及「命中標頭不算在裡面」的提醒。

---

## HY. 一次編輯會重寫每一個紀錄分隔符,而那句話寫在 1,400 行之外(2026-08-22 修正)

第 69 回合。在一個 CRLF 檔案上改一格:

```
改之前：CR 位元組 = 5
改之後：CR 位元組 = 0        ← 只更新了第 4 筆的一格
```

**這是有記載的**——「輸出在每個平台上一律以 `\n` 作為紀錄分隔符」——但那句話在「這個專案為什麼
存在」那一節裡,離 `-update`／`--in-place` 一千四百行遠。而在它們附近,腳本作者會先讀到的是
另外兩句:「一個 csv2 讀進來、又沒有改動的欄位,會原樣寫回去」、「一次編輯之後,沒有被碰過的
欄位逐位元相同」。**兩句對「欄位」都為真,對「檔案」都不真。**

任何「對整個檔案」的驗證——檢查碼、`diff`、「我沒指名的紀錄應該沒變」——在 CRLF 輸入上都是錯的。
已在編輯那一節寫明,並指出該改比對「值」。

---

## HZ. 三件小的:拒絕不帶時間戳、`-o` 路徑的例外、以及那個 12/18(2026-08-22 修正)

第 69 回合另外三條,都是「一句話涵蓋得太寬」:

- **「每一行診斷訊息都以 `csv2: <時間戳> 層級` 開頭」**——WARN 與 DEBUG 是,而**拒絕不是**:
  結束一次執行的那兩行是 `csv2: <訊息>`,沒有時間戳、也沒有層級。
- **「`-o` 的拒絕印的是絕對路徑」**——「目錄不存在」那一條印的是你打的樣子,因為沒有東西可以
  拿來解析。而在一份「分辨拒絕只能靠比對英文字句」的文件裡,拼法是合約的一部分。
- **`cat > file` 那場競賽的 12/18**——受測者量到 5/25。那個比例不是 csv2 的性質,而是「讀取端的
  EOF 落在離紀錄邊界多遠」的性質。會重現的是「一次完整的都沒有」。

---

## IA. `-md` 把控制字元原樣送到終端機,而定位報告為了同一個理由跳脫它們(2026-08-22 修正,T193)

第 70 回合的第 4 題:造一個檔案,讓別人用這個工具讀它時得到假的東西。**成功了,而且很小。**

README 為定位報告的跳脫給的理由是:「一個存著 `ESC [ 3 1 m` 的儲存格,會從第三欄裡面把輸出
重新上色;而 ESC 也能抹掉它正被印出的那一行。」那個理由是對的,那道保護也有效——**而它只套用在
一種給人看的形狀上**。

```console
$ csv2 -contains X -i ctl.csv | cat -v
1:2	b	X\x1BY\x08Z\x07W|V\\U       ← 報告：三個都跳脫了
$ csv2 -r -t -md -i ctl.csv | cat -v
|1|X^[Y^HZ^GW\|V\\U|                ← -md：只有 | 與 \ 被跳脫
```

而 `-md` 正是同一份文件稱為「一種**算繪**……`-md` 是拿來讀的」的那個形狀。

**可用的攻擊**(只用退格,不含任何 `|`,因此 `\|` 那道跳脫從未觸發):

```console
$ csv2 -r -t -md -i audit.csv | cat -v
|evilpkg|GPL-3.0^H^H^H^H^H^H^HMIT    |
$ csv2 -get 2:2 -i audit.csv | cat -v
GPL-3.0^H^H^H^H^H^H^HMIT
```

在任何「退格會移動游標」的終端機上,那一列算繪成 `|evilpkg|MIT    |`。**一個執行「這份文件
說是拿來讀的那個指令」的稽核者,會替一個 GPL-3.0 的套件讀到 MIT**,rc=0,stderr 空無一物。

`--pretty` 剛好擋得住這一個 payload——它把那些退格算進欄寬,那一列會明顯變短——但那是對齊的
意外,不是一道防線,而文件也沒有把它當成防線提供。

已修:`-md` 現在以與定位報告相同的約定跳脫控制字元(TAB 是 `\t`,其餘是 `\xNN`)。
`-get` 與 CSV 形狀仍然交還位元組,那是它們的工作。

**形狀:一個理由被寫下來、被實作在一個地方,而同一份文件在另一處指名的「給人讀的形狀」沒有拿到它。**
與 FJ、GK 同族——**一條規則只套用在它成立範圍的一部分**,而這次那個範圍是「人會讀的輸出」。

---

## IB. 「每一條路徑都有一行 metrics」——十條裡有五條沒有(2026-08-22 修正)

第 70 回合。README 說 `-debug` 會「在**每一條路徑**上」印出一行 metrics。實測:

```
-r / -contains / -get / -tail / -hash -so      → 有
--build-index / --verify-index                 → 沒有
-update --in-place / -append --in-place / -delete --in-place → 沒有
```

**五條沒有,而缺掉的那一半全是「寫入」**——正是呼叫端最想看到成本的那些執行。已修:五條都補上。
（那一行是 `-debug` 用來「量而不是猜」的工具,而它在「會改動檔案」的那些路徑上不存在。）

---

## IC. `read_bytes` 的規則,第三次寫錯(2026-08-22 以「只寫量測」處理)

第 70 回合。HV(第 69 回合)把那句話改成「它分不出 seek 與提早停止:
`-mid 200000,200000` 在已索引的檔案上回報 65536,加上 `--no-index` 也是」。實測:

```
-mid 200000,200000              → 65536
-mid 200000,200000 --no-index   → 7864320      ← 相差 120 倍
```

一次「掃描到第 20 萬筆」必須讀 7.8 MB,它不可能回報 65536。**我把一個假的全稱換成了第二個,
再換成第三個。**

**這一次的處理方式不同:那個條目現在只印五行實測數字,以及一句它們撐得住的話**
——`read_bytes < file_bytes` 表示這次執行不必碰整個檔案——並且明說「比這更精確的說法已經錯過
三次」。兩份 README 一起改。

**形狀:HL 說過的那件事,第四次。** 差別在於這次不再嘗試寫出規則,而是把量測留在原地。

---

## ID. 三處「說了兩次而彼此不同」的話(2026-08-22 修正)

第 70 回合的第 3 題:先讓兩份副本互相比對,再去比對程式。

- **`--verify-index` 檢查幾項宣稱**:五處說「四項」,一處(`README.md:1975`)說「三項」。
  程式站在「四項」那邊。而諷刺的是,同一個檔案在 190 行之後寫著「這一段到 2026-08-22 之前
  都還寫著『三項』——正是這份文件本身一直在講的那種漂移」——**它修好了一份副本,而漏掉了
  190 行之前的另一份**。
- **WARN 清單是四項還是六項**:英文說六,中文的旗標清單說六,而中文另一處說
  「一張封閉的四項清單」。程式站在「六項」那邊。而那句話自稱「封閉」。
- **重複的旗標**:英文有「布林旗標例外」那一段,中文沒有——中文留著的正是 2026-08-22 之前
  的英文原文。程式站在英文那邊。

**三處都是同一件事:一次修正只落在一份副本上。** 這正是 HV 的另一半(那次我只改了英文,
而沒被改到的中文反而是準的)。三處都已改。

---

## IE. 兩件「四份副本一致、而程式不同意」的事(2026-08-22 修正)

同一回合。與 ID 相反的形狀——不是副本之間漂移,而是**所有副本一起錯**:

- **「兩邊都會警告」**:並行追加時,實際上只有**後完成的那一個**會警告。先完成的那一個去看
  檔案大小時,只看得到自己那一次寫入。四處(兩份 README 各兩處)都寫著「每一個」/「兩邊」。
  這是我在第 69 回合寫下的,而我沒有量過「幾則警告」。
- **「每一個錯掉的格點一行」**:一個格點的偏移量與行號都錯時,`--verify-index` 會印**兩行**。
  兩份 README 都說一行,而同一句話正在警告「可能印出好幾千行」——那個數字因此也偏低。

---

## IF. Windows 的建置失敗了,而那台節點拿舊的二進位檔跑了新的測試(2026-08-22 修正,測試前置檢查)

第 70 回合的修正推到節點之後,Windows 回報了 11 個失敗——其中五個是
`[-update 1:2 Z --in-place] printed 0 metrics lines`,而那一行 metrics 就在旁邊的原始碼裡。

實情:

```
error: 'fileDescriptor' is unavailable
  |            `- note: 'fileDescriptor' has been explicitly marked unavailable here
```

第 69 回合那個 `O_APPEND` 修正用了 `ah.fileDescriptor`,而 `FileHandle.fileDescriptor`
在 Windows 上被標記為不可用。**建置失敗,那台節點保留了它原本就有的二進位檔,而套件拿「新的
測試」去跑「舊的程式」。** 於是失敗看起來像是程式有缺陷,而不是像「一次從未跑起來的建置」。

**升級腳本印過 `build: FAILED`。是我盯著它的那個指令,把那一行濾掉了**——我只 grep 了
`pull:` 與 `^PASS`。

三個修正:

1. **程式**:改用 `Platform.openAppendFD(path:)`,在兩個平台上都直接取得描述子——Windows 那半
   本來就在 `openForAppend` 裡(`CreateFileW` + `_open_osfhandle`),只是被包進了一個
   `FileHandle`,而那個包裝正好擋住了唯一能拿到 fd 的路。
2. **測試**:套件現在在做任何事之前,先問「有沒有任何 `src/*.swift` 比這個二進位檔新」。有的話
   就以「STALE BINARY」中止,並指名是哪些檔案。**一個比原始碼舊的二進位檔,是這套測試會拿到的
   最糟的東西**:每個案例照樣執行、多數照樣通過,而失敗的那些會指向錯的地方。
   （只在 `src/` 存在時檢查——一台只拿到二進位檔的節點也是合法的執行方式。）
3. **我自己**:監看遠端執行時,不要只 grep 自己預期的那幾行。

**形狀:一個「看起來像被測物的缺陷」的失敗,其實是工具鏈的失敗。** 這與 DP（`git -C` 落在
幽靈目錄,連續四次回報成功）是同一族——那一次也是「每一行都是真的，只是講的不是同一個東西」。

---

## IG. `-i` 與 `-o` 之外的那些檔案:三種「rc=0、兩條輸出流皆空」的毀損(2026-08-22 修正,T195)

第 71 回合的第 3 題:文件對「一個輸入、一個輸出」寫得很完整,那「第二個檔案」呢?

那道同檔案守衛比對的是 `-i` 與 `-o`,**而且只有這兩個**。文件把那次比對描述得非常仔細——拼法、
symlink、`(device, inode)`、僅限 POSIX 的但書——卻從未說出它**沒有涵蓋**哪些檔案。三種:

**(a) `-o` 指向金鑰檔。**

```console
$ csv2 -encrypt secret -keyfile mykey.bin -i src.csv -o mykey.bin -t
$ echo $?
0
$ cat mykey.bin
id,secret:enc:6e69740e:rNjMxv/5bdL5qI+yGurANA==
1,0an52UEk2Lst03eFmRuAsq5XwZ9/nnz0XYIeMlAAstkV
```

**密文被寫在「唯一能解開它的那把金鑰」上面。** stdout 0 bytes,stderr 0 bytes,rc=0。

**(b) `-o` 指向 `-log` 檔。** log 的內容被寫進去了,然後被那次 rename 蓋掉——**那次執行把自己的
稽核軌跡改名蓋掉了**,而 `-log` 那一節稱它為「稽核軌跡」。

**(c) `-log` 指向正在被讀的那個 CSV。**

```console
$ csv2 -contains a -i g.csv -log g.csv
csv2: record 4 (line 5) has 1 fields but the header has 2; …
$ cat g.csv
pkg,note
a,1
2026-08-21T19:18:34 INFO  csv2 -contains a -i g.csv -log g.csv
```

csv2 把呼叫紀錄追加進了它自己的輸入,然後解析失敗。**那個檔案從此每一次讀取都以 1 結束**,
而錯誤訊息指名了一筆紀錄與一個欄位——完全正確,也完全沒有用:錯的是那個別名,不是那筆紀錄。

修法是「把那個已經存在的比對再問三次」。而 (c) 教了第二件事:**這個檢查必須在 log 被開啟之前
做**。先寫在 `validate()` 裡時,`-log` 指向輸入仍然會讓那個輸入多出一行 ERROR——訊息是對的,
檔案照樣被弄壞了,**而弄壞它的正是那則訊息**。

---

## IH. 一則把整列標頭倒出來的診斷(2026-08-22 修正,T196)

第 71 回合。一個「第一欄名字有 50,000 個字元」的檔案:

```console
$ csv2 -hash NOSUCH -i longname.csv -o zz.csv -t
csv2: no column named "NOSUCH"; the columns are: "NNNN…（五萬個 N）…", "b"
第一行長度：50,057 bytes
```

「恰好兩行」的承諾成立,而那一行有 50 KB——就在承載診斷的那一行上。**定位報告正是為了同一個
理由把值切在 200 個字元,而且說了出來**;一個「列出有哪些可用」的診斷卻沒有這條規則。而這則
訊息在文件裡的範例是 `no column named "caf<U+FFFD>"`——沒有標頭傾印,也沒有長度。

已修:每個名字切在 60 個字元(用與定位報告相同的 `…[+N more chars]` 標記),清單最多列 12 欄,
其餘用數的。

---

## II. 「引述路徑的訊息不動」——只有反斜線不動(2026-08-22 修正)

第 71 回合。那句話是我在第 64 回合寫的:

> A message quoting a PATH is left alone: a Windows path is full of backslashes …

實測:

```console
$ csv2 -r -i "$(printf 'no\nsuch.csv')"
csv2: cannot open input file: no\nsuch.csv          ← 換行被跳脫了
$ csv2 -r -i "$(printf 'x\x1b[2Ky.csv')"
csv2: cannot open input file: x\x1B[2Ky.csv         ← ESC 被跳脫了
```

**程式是對的**——那正是「一次拒絕是兩行、一筆 log 是一行」得以成立的原因。錯的是那句話:那個
豁免只涵蓋反斜線。而它有後果:同一份文件說輸入路徑「照你打的樣子出現」,又說「分辨拒絕只能靠
比對英文字句」——於是一個想從訊息裡把路徑撈回去的腳本,會拿到一個不存在的檔名。

**形狀:又一個「從眼前那一個例子推出的全稱」。** 這是這一族的第五次(FH、FN、GN、HL、II)。

---

## IJ. 「約 130 次視窗才回本」——那個除法除錯了東西(2026-08-22 修正)

第 71 回合。README 說 `--build-index` 的 505 ms「換來的 -mid 視窗是 4 ms——大約要 130 次視窗
才回本」。130 ≈ 505 ÷ 4:**那是拿成本去除以「那個便宜的操作」,而不是除以「省下來的量」。**

沒有索引的視窗要 179 ms(文件自己在另一處寫 277 ms)。回本點是 505 ÷ (179 − 4) ≈ **3 次**,
而不是 130 次——**高估了大約 40 倍**,而且就在一段「重點是索引很貴」的文字裡。而同一份文件在
兩個螢幕之外,把同一種回本點算對了(「大約從第二次搜尋起才划算,因為那次證明只付一次」)。
**兩處、兩種算法,其中一種是錯的。**

---

## IK. 兩件文件沒說、而它們是「第二個檔案」的性質(2026-08-22 修正)

同一回合:

- **`-md` 沒有 200 字元的截斷。** 一個 400,000 字元的儲存格,在定位報告裡是 230 bytes 的一行
  (切了、也標了),在 `-md` 裡是 400,005 bytes 的一行。`-md` 是同一份文件稱為「給人讀」的那個
  形狀——它有兄弟的「跳脫」規則,沒有兄弟的「截斷」規則,而沒有任何一句話承認這件事。
  已補:那是刻意的（報告是預覽,`-md` 算繪的是資料）,而現在寫出來了,連同「先用 -mid 切片」。
- **`wrote index …` 不在 log 那張表裡。** 那張表列了八種行,而這一行不在其中——**而它是唯一
  一行帶著絕對路徑的 log,也是唯一一行講「輸入以外的另一個檔案」的**。已補進表裡。

---

## IL. `--verify-index` 的「一個格點兩行」——受測者說不會發生,而它會(2026-08-22 以文件處理)

第 71 回合回報:那句「一個格點的偏移量與行號都錯時會印兩行」在它的 fixture 上從未發生,
976 個壞掉的格點各印一行,只講位元組。

**親手重現後,那句話是對的,而受測者的 fixture 不是**:把一筆紀錄切成兩筆,會讓其後每一筆的
「編號」加一、也讓每一行的「行號」加一——**兩者互相抵銷**,於是每個格點所指的行號仍然對得上,
只有位元組那一項會觸發。直接竄改一份 sidecar 的格點(偏移量 +7、行號 +3,再重算檢查碼)之後:

```console
$ csv2 --verify-index -i gp3.csv
index MISMATCH: record 257: index says byte 3851, actual 3844
index MISMATCH: record 257: index says line 261, actual 258
```

**兩行,同一個格點。** 已在文件裡補上那個「為什麼你多半只會看到一行」的理由——那是一份被竄改的
sidecar 才會有的樣子,不是一個被改動的檔案通常會有的。

---

## IM. T34b「密文被竄改即解密失敗」——它不可能失敗,而且有兩個各自獨立的理由(2026-08-25 修正,T34b)

不是盲測回合找到的:是使用者在 2026-08-24 的 `859c24c` 修了那段 `sed` 的可攜性之後,
順著那個修正往下看才發現的。

那個案例原本這樣製造「被竄改的密文」:

```zsh
ct=$(cell "$TMP/enc.csv" 1 6)
flip=$(print -r -- "$ct" | sed 's/^A/B/; t; s/^./A/')
"$CSV2" -update '1:6' "$flip" -i "$TMP/enc.csv" -o "$TMP/tamper.csv" 2>/dev/null
assert_fails "T34b …" -- "$CSV2" -decrypt status_notes … -i "$TMP/tamper.csv" …
```

**理由一(所有平台):那次 `-update` 會被拒絕。**

```console
$ csv2 -update 1:6 "$flip" -i enc.csv -o tamper.csv
csv2: -update 1:6 targets a column this file declares transformed; a raw value written
      there cannot be decrypted, and it takes the whole column with it …
```

那道守衛是後來才加上的,而且是對的。於是 **`tamper.csv` 從來沒有被建立**,而下一行的
`-decrypt` 失敗的理由是 `cannot open input file: tamper.csv`——`assert_fails` 只看結束狀態,
於是回報 PASS。**給它真的密文、給它空字串、什麼都不給,它都以同一種方式通過。**

**理由二(macOS):那段 sed 從來沒有跑起來過。**

```console
$ print -r -- 'AbCd' | sed 's/^A/B/; t; s/^./A/'
sed: 2: "s/^A/B/; t; s/^./A/": undefined label '; s/^./A/'
（輸出為空）
```

BSD sed 把分號之後的文字讀成那個無標籤 `t` 的「標籤」。因此在 macOS 上 `flip` 一直是空字串
——而那個空字串又被上面那道守衛擋下。**同一個綠勾,兩個獨立的理由,而其中沒有一個是 AEAD。**

**修法有三處,而第三處是這次自己撞到的:**

1. 竄改改用 **shell** 逐位元組造出那個檔案,不經過 csv2——那道守衛是對的,測試不該繞過它,
   而是不該用它。
2. 斷言那則**訊息**(`authentication failed`),不只是結束狀態。`assert_fails` 分不出
   「認證失敗」與「檔案不存在」,而那正是這個案例好幾個月什麼也沒證明的原因。
3. 給它**自己的 fixture 與自己的檔名**。第一次改寫時我用 `${line##*,}` 去取密文——而
   `TARGET_PACKAGES.csv` 上被加密的是七欄中的第六欄,鄰居還含有帶引號的逗號,於是我竄改到的是
   `license`,而 `-decrypt status_notes` **成功了**(rc=0、訊息為空)。改用一個「被加密的欄位就是
   最後一欄、且不含引號逗號」的小 fixture 之後才對。第二次又撞到:那個小 fixture 寫在
   `$TMP/enc.csv` 上面,於是 T35b 與 T39 對著一個它們從未要求過的檔案失敗——**共用的名字就是
   共用的 fixture,不論有沒有人打算讓它共用。**

**形狀:一個後來加上的、正確的守衛,讓一個更早的測試的「準備步驟」失效,而那個測試的斷言太寬,
察覺不到自己已經什麼都沒在測。** 這與 T43h、T135b、T145e、T151e、T164d 是同一族——
「一個分不出它當初要分辨的那兩件事的測試」——而這一個是其中活得最久的。

---

## IN. `-log` 指向金鑰檔:金鑰在被使用之前被改掉,而沒有任何備份救得回來(2026-08-25 修正,T198)

第 72 回合的第 1 題:每一條拒絕比的是什麼,以及那個「很像被比的東西、但不是它」的東西。
**它在我上一輪剛寫好的那道守衛裡找到了答案。**

IG 加了四對比對:`-o` 對金鑰檔、`-o` 對 log、`-log` 對輸入、`-keyfile` 對就地編輯的輸入。
**沒問到的那一對是 `-log` 對 `-keyfile`。**

```console
$ csv2 -encrypt note -keyfile k1.bin -i a.csv -o enc1.csv -t -log k1.bin
$ echo $?
0
$ wc -c k1.bin          # 原本 32 bytes
     318
```

**那把金鑰在被推導之前,先被追加了一行「呼叫紀錄」。** 於是這次執行加密所用的金鑰材料是
「原本的 32 個位元組 + 一行 log」——一個只存在了幾毫秒、而且從來沒有以那個樣子被寫在任何地方
的值。接著結果那一行又被追加上去,因此:

- 磁碟上的金鑰檔**多了一行**,解不開;
- 事前留的備份**少了一行**,也解不開。

受測者不相信備份會失敗,於是把那個被改過的金鑰檔在每個換行位置截斷、逐一試解——只有
「原本 32 bytes + 第一行 log」那個中間狀態解得開。**要救回那些資料,得先猜到發生了這件事,
再把那個位元組數重建出來。**

rc=0、兩條輸出流上什麼也沒有。而 `-log` 正是一個謹慎的操作者「在做不可逆的事情時」會加上的旗標。

---

## IO. 每一道「這一欄受保護嗎」的守衛都只讀 0a 那一列(2026-08-25 修正,T197)

同一回合、同一題。`-hash`／`-encrypt` 會把標記寫進 `.csv2` 的**兩列**標頭,而每一道讀它的守衛
讀的都是**第一列**。把 0a 的標記拿掉、留下 0b:

```console
$ head -2 e_a.csv2
pkg,ver,secret
套件,版本,機密:enc:a9d5f8ba:0hrHQjKsbpjgv1MYPB303g==

$ csv2 -update 1:secret NEW -i e_a.csv2 -o xa.csv2 ; echo $?
0                                      ← 明文被寫進加密欄
$ csv2 -hash secret -keyfile k.bin -i e_a.csv2 -o rehash.csv2 -t ; echo $?
0
$ head -2 rehash.csv2
pkg,ver,secret:hmac:a9f37ec7
套件,版本,機密:hmac:a9f37ec7             ← `:enc:` 標記與它的 salt，兩列都沒了
```

**那正是 README 稱為「這個工具做得出來最糟的一件事」的那一件**,而它在 2026-08-20 被修過一次
——那次修的是「每個動詞只認得自己那一種標記」。**規則現在跨動詞是通則了,卻對「哪一列標頭」
留著一個特例。**

而文件推薦的那個程式化檢查也漏接:

```console
$ csv2 -head 1 -t --json -i e_a.csv2 | head -1
{"meta":{"format":"csv2","headers":2,"fields":3}}        ← 說：什麼都沒被保護
$ csv2 -contains ':enc:' --include-headers -i e_a.csv2
0b:3	secret	機密:enc:a9d5f8ba:0hrHQjKsbpjgv1MYPB303g==   ← 標記就在那裡
```

**兩個 csv2 指令對同一個檔案說法不同,而 README 叫你拿來寫腳本的是說錯的那一個。**

修法不是「兩列都讀、取聯集」——那會修好漏接、卻留下一個自相矛盾的檔案。**兩列互相矛盾的檔案
會被拒絕**,由每一個動詞、在其他一切之前拒絕,並指出是哪一欄、兩列各說了什麼。而「兩個來源
互相矛盾」時,這正是這支程式其餘部分一貫的答案。

順帶記下一條沒有寫過的規則:一個以 `:hash`／`:hmac:`／`:enc:` 結尾的欄名是**保留字**。一個
純粹叫做 `secret:hash` 的欄位會被當成受保護的、而且改不動——安全的那一邊,但那則訊息描述的是
一個它讀錯了的檔案。已寫進兩份 README。

---

## IP. 一段以 CR 分行的內文,配上一個正常結束的標頭(2026-08-25 修正,T199)

第 72 回合。GW（第 66 回合）把 CR 的判斷從「數量」換成「標頭列裡的裸 CR」,而那對「每一行都以
CR 結尾」的檔案是精確的。**它看不見這一種:**

```console
$ printf 'a\n1\r2\r3\r' > cr3.csv          # (echo a; cat old_mac_body) > f.csv
$ csv2 -r --json -i cr3.csv
{"record":1,"line":2,"fields":{"a":"1\r2\r3\r"}}
{"meta":{"records":1,"matched":0}}
rc=0
```

**三筆變成一筆,rc=0,沒有 WARN。** 那個檔案裡的每一個計數都錯了,錯的倍數就是它的行數,
而文件指定的那個「有沒有」的檢查會很有把握地回報一個錯的數字。多欄的版本會報錯,但報的是
欄數不符——那與 README 自己為「沒有 BOM 的 UTF-16」寫下的自白是同一件事:「它也可能以一則
關於欄數的訊息失敗……那是意外,不是檢查。」

修法是第二個判斷,同樣精確:**檔案的最後一個位元組是不是裸 CR**。以 CR 分行的內文一定以 CR 結束;
而 GW 當初修掉的那個誤判(`1,x\r\r\ry\n`)以換行結束,不受影響。

---

## IQ. gzip 檔案叫做 `.csv`,以 rc=0 被讀成一筆二進位紀錄(2026-08-25 修正,T200)

同一回合。`FF FE` 有一條拒絕,而 `1F 8B` 沒有:

```console
$ gzip -c full.csv > gzdata.csv
$ csv2 -contains x -i gzdata.csv ; echo $?
0                        ← 在一個壓縮檔裡搜尋，回報「沒找到」
```

**那正是這個工具存在所要避免的答案**——一個看起來像成功的失敗。已加上同一條拒絕,並指出
`gunzip -c`。

---

## IR. `-o SEL.CSV2` 繞過了 `-o sel.csv2` 會撞到的那條拒絕(2026-08-25 修正,T200c)

同一回合。副檔名的判斷是大小寫敏感的——而在 macOS 與 Windows 上,`SEL.CSV2` 與 `sel.csv2`
是**同一個檔案**:

```console
$ csv2 -head 3 -i v.csv2 -o sel.csv2
csv2: …/sel.csv2 declares a format with a header, so writing data rows there needs -t; …
$ csv2 -head 3 -i v.csv2 -o SEL.CSV2 ; echo $?
0                        ← 同一個目錄、同一個檔案系統，不帶標頭就寫出去了
```

那個結果讀回去時,兩筆資料被當成標頭列吃掉,rc=0——**正是那條拒絕所要防止的損害**。

修法把「輸出」與「讀取」這兩個問題分開:**讀取問的是「呼叫端宣告了什麼」,而 csv2 不猜,
因此 `-i S.CSV` 仍然需要 `--headers`;寫出問的是「下一個讀者會認為這是什麼」**,而下一個讀者
可能是試算表,也可能是一個在大小寫不敏感檔案系統上的 csv2。輸出那一側因此改為大小寫不敏感。

另一半的繞道(先寫成沒有副檔名的檔案、之後再改名——一個寫 `$@.tmp` 的 Makefile 預設就是這樣)
攔不到,而那件事現在寫在註解裡。

---

## IS. `-insert`／`-append` 不套用 csv2 自己的加引號規則(2026-08-25 修正,T201)

第 72 回合的第 4 題（把每一種輸出餵給下一個讀者）。

```console
$ csv2 -update 1:2 ' leading'  -i w.csv -o w1.csv -t   →  r1,"   leading"     加了引號
$ csv2 -append  'r2, leading'  -i w.csv -o w3.csv -t   →  r2,  leading        沒有引號
```

csv2 自己兩種都讀得回來。而那條規則所為之存在的東西——「試算表與好幾種解析器會把未加引號欄位
前後的空白去掉」——不行。而 README 把那條規則寫成:「**你給的**、結尾帶空白的值,落地時會被
加上引號。」一列你打進來的紀錄,讀起來就在那句話的涵蓋範圍內。

原因是編輯路徑以 `preserveRaw` 寫出,而一列被插入的紀錄帶著它的「字面位元組」走了那條路。
修法是在 `parseRowLiteral` 裡把 `raw` 清掉:**一列被交進來的紀錄沒有 raw 可以保留**——它是在
命令列上打出來的,不是從檔案裡讀出來的。

同一題還有一條只寫進文件的:**csv2 不會替試算表擋下一條公式**。以 `=`、`+`、`-`、`@` 開頭的值
對 Excel／LibreOffice／Sheets 是一條公式,而 csv2 把它當成文字原樣存下——「為了討好下游的讀者
而竄改一個值」正是這個工具唯一不會做的事。文件先前對此完全沒有提過,而它明確地把輸出送去試算表。

---

## IT. 一個副檔名判斷,兩種答案——而其中一種是我前一天造出來的(2026-08-25 修正,T200f/g/h)

第 73 回合的第 1 題:「這份文件一再說『規則是通則、實作是特例』——那就找出它宣稱為通則、卻沒有
被套用的那一個地方。」**它找到的那個地方,是我前一天才造出來的。**

IR（第 72 回合）為了擋下 `-o SEL.CSV2` 這個繞道,把 `declaresFormat`（寫出那一側）改成大小寫
不敏感,而 `Format.from`（讀取那一側）維持敏感。**於是同一支程式裡有兩個副檔名判斷**,而它們
對同一個名字給出不同的答案:

```console
$ csv2 -r -t -i q.csv -o probe.CSV2       # 「絕不轉換格式」那道守衛（讀取側）
rc=0                                       → 這個副檔名什麼都沒宣告
$ csv2 -head 1 -i q.csv -o probe2.CSV2    # -t 那道守衛（寫出側）
csv2: probe2.CSV2 declares a format with a header …
rc=1                                       → 這個副檔名宣告了 .csv2
```

**那則訊息是一句假話。** 而後果不只是話說得不對:

```console
$ csv2 -r -t -i 單列標頭.csv -o conv.csv2
csv2: the input has 1 header row(s) and …/conv.csv2 declares 2 by its suffix …   rc=1
$ csv2 -r -t -i 單列標頭.csv -o conv.CSV2
rc=0                                       ← 同一個 inode（大小寫不敏感的檔案系統）
$ csv2 -r --json -i conv.csv2 | tail -1
{"meta":{"records":2,"matched":0}}         ← 檔案裡有三筆
```

**一筆紀錄被當成標頭列 0b 吃掉,rc=0,兩條輸出流上什麼也沒有**——而那正是那條「絕不轉換格式」的
拒絕（T56d）存在所要防止的損害。反方向也一樣:一份 `.csv2` 寫進 `.CSV`,那列中文標題成為第 1 筆
資料。

修法是回到「一條規則」:**兩側共用同一個大小寫不敏感的判斷**。舊規則是「這個檢查區分大小寫,
因此名為 `.CSV` 的檔案也需要 `--headers`」——而「由宣告決定、絕不偵測」這件事並不要求那樣:
以大小寫不敏感的方式比對 `.CSV`,讀的仍然是呼叫端給的那個名字,不是從內容去猜。而在「`S.CSV`
與 `s.csv` 是同一個檔案」的那兩個平台上,把它們當成兩種格式,不是任何人能夠據以行動的規則。

**形狀:一個為了修掉「特例」而做的修正,自己造出了一個新的特例——而且只花了一天。** 這正是
第 73 回合第 1 題所要找的東西,而它在最新的那一層找到了。

---

## IU. 一次追加寫的行尾,取決於檔案最後兩個位元組——而那兩個位元組不一定是終止符(2026-08-25 修正,T202)

同一回合。追加快路徑這樣決定要寫 LF 還是 CRLF:

```swift
h.seek(toFileOffset: size - 2)
endsWithCRLF = (最後兩個位元組 == CR LF)
```

**只有在「檔案最後一筆有終止符」時,那兩個位元組才回答得了這個問題。** 一個 CRLF 檔案的尾巴
若沒有終止符——匯出程式被切斷、寫入撕裂、任何停在紀錄中間的情況——那兩個位元組就是某個「值」的
最後兩個位元組:

```console
$ printf 'a,b\r\n1,x\r\n2,y' > c2.csv        # CRLF，最後一筆沒有終止符
$ csv2 -append '3,z' -i c2.csv --in-place
$ od -c c2.csv
a , b \r \n 1 , x \r \n 2 , y \n 3 , z \n     ← 補上的是裸 LF，追加的也是
```

於是一個「其他每一筆都以 CRLF 結尾」的檔案，尾端多了兩筆 LF 結尾的紀錄。而那段程式自己的註解
寫著:「配合檔案『已經是的樣子』,是唯一能讓它保持自身一致的答案。」——那個意圖是對的,而那個
探測達不到它。

修法:那次追加**本來就會把整個檔案讀過一遍**（為了驗證最後一筆是完整的),而那次掃描知道
「這個檔案最後一個終止符是什麼」。尾巴沒有終止符時就用它。補上的那個終止符同樣跟著檔案走——
對一個 CRLF 檔案補一個裸 LF,會讓「被追加那一筆的前一筆」與檔案裡其他每一筆都不同。

**形狀:一個「用最後兩個位元組去問一個關於整個檔案的問題」的探測。** 與 GW（用數量去問行尾）
同族,而這次那個近似值只在「檔案結束得整齊」時等於真值。

## IV. install.zsh 挑 rc 檔的依據,是「執行它的那個 shell」而不是「這個帳號的 shell」(2026-08-25 修正,T203a)

WSL 節點在 2026-08-25 重裝後回來,csv2 建好了、裝到 `~/.local/bin` 了,而 `upgrade_nodes_csv2.zsh`
回報 `reachable: NO -- the shell cannot find csv2 at all`。install.zsh 對這件事印的建議是:

```console
$ ./install.zsh
WARNING: /home/lowei/.local/bin is not on your PATH
  add to ~/.zshrc:  export PATH="/home/lowei/.local/bin:$PATH"
```

那句話寫死了 `~/.zshrc`。而那個節點的實況是:

```console
$ getent passwd lowei | awk -F: '{print $NF}'
/bin/bash
$ ls -a ~ | grep -E '^\.(bashrc|profile|bash_profile|zshrc)$'
.zshrc                       ← 家目錄裡唯一存在的 rc 檔
```

**登入 shell 是 bash,而唯一存在的 rc 檔是 `.zshrc`。** 照著那句建議做,會把完全正確的一行
寫進一個沒有任何東西會讀的檔案,然後看著 `command not found` 繼續發生。

`~/.zshrc` 是從哪裡來的?從 install.zsh 自己的 `#!/usr/bin/env zsh`——寫那句話的人（我）用
「這支腳本執行時所在的 shell」代替了「這個人打開終端機會拿到的 shell」。那兩者在開發機上
一直相等,因為開發機的登入 shell 就是 zsh。

修法:問這個帳號(`getent passwd`,退回 `$SHELL`),再由它決定檔案。並且真的去寫,不只是建議。

**形狀:一個從手邊的例子推廣出來的普遍宣稱。** 與 FH、FN、GN、HL、II 同族——這一次那個
「手邊的例子」是執行環境本身。

## IW. 對 zsh 而言 `.zshrc` 是錯的檔案,而錯的方式正好蓋住當初壞掉的那件事(2026-08-25 修正,T203b/c)

接續 IV。把檔案改成由帳號決定之後,zsh 那一支我寫的是 `~/.zshrc`——那是「大家都知道」的答案,
也是 install.zsh 原本那句建議說的。

但 **zsh 只有在 shell 是互動的時候才讀 `.zshrc`**。而在 WSL 上需要 csv2 的是什麼?是
`record_release.zsh`,它經 multissh 執行,拿到的是一個**非互動、非登入**的 shell。那種 shell
讀的是 `.zshenv`,而且只有 `.zshenv`。

也就是說:寫進 `.zshrc` 會修好「有人坐在終端機前打 csv2」,而讓「當初唯一真的失敗的那支腳本」
繼續失敗——同時這支安裝程式會回報成功。

那個節點自己早就知道這件事,它的 `.zshrc` 第一段就寫著:

```
# The Swift toolchain PATH is in ~/.zshenv, because `zsh -lc` (used by the
# build harness) does not read this file.
```

修法:zsh 寫 `~/.zshenv`。bash 沒有對應物(`BASH_ENV` 預設沒設),所以 bash 只能做到
`.bashrc` 加一個會 source 它的登入檔——而那個差別現在會被說出來,見 IY。

**形狀:一個修法選了「慣例上正確」而不是「對這個用途正確」的位置,而它失敗的方式,恰好是
原本那個症狀不會顯現的那一面。**

## IX. `--uninstall` 只收回安裝寫過的兩個檔案中的一個(2026-08-25 修正,T203f)

bash 的安裝會寫兩個檔案:`~/.bashrc`(互動)與一個登入檔(讓登入的 bash 去 source 前者)。
`--uninstall` 迭代的卻是 `rc_files()`——那是「今天要寫哪一個」的清單,只有一個元素。

```console
$ HOME=$T SHELL=/bin/bash ./install.zsh --prefix $T/bin      # 寫了 .bashrc 與 .profile
$ HOME=$T SHELL=/bin/bash ./install.zsh --prefix $T/bin --uninstall
removed the csv2 block from /tmp/.../.bashrc
removed /tmp/.../bin/csv2
$ grep -c '>>> csv2' $T/.profile
1                                    ← 還在，而且上面標著是 csv2 放的
```

留下的那個區塊不只是垃圾:它標著 `# >>> csv2 install.zsh >>>`,宣稱自己屬於一個已經被移除的
安裝,而下一個讀到它的人沒有辦法知道該不該動它。

修法:移除時問比較寬的那個問題——`rc_candidates()`,列出「這支腳本曾經可能寫過」的每一個
檔案。並且在拿掉那個「讓登入 shell 去讀 .bashrc」的區塊時說出代價:`~/.bashrc` 裡其他東西
會跟著在下次登入時安靜失效。

**形狀:一條規則只套用到它成立範圍的一部分。** 與 GK、IG/IN、IO、IT 同族;這一次是「寫」與
「收回」用了兩份不同寬度的清單。

## IY. 「全新的 shell 找得到它」這件事,從來沒有被真的問過(2026-08-25 修正,T203g)

install.zsh 的驗證用的是:

```zsh
RESOLVED=$(zsh -lc 'command -v csv2')
```

**`zsh -c` 不會重設 PATH。** 它繼承呼叫者匯出的 PATH。所以這一行問的是「csv2 在我已經有的
那個 PATH 上嗎」,而不是「一個全新的 shell 找得到它嗎」。當初在此親眼看到:

```console
$ T=$(mktemp -d)
$ HOME=$T SHELL=/bin/bash ./install.zsh --prefix $T/bin
verified: a fresh bash runs /opt/homebrew/bin/csv2, and it is the file just installed
                            ^^^^^^^^^^^^^^^^^^^^^^^^ 不是剛裝的那一個所在的目錄
```

它「驗證」通過了,而它解析到的是開發機上原本就有的那一支;雜湊比對之所以相符,只是因為那一支
恰好也是同一次建置。換一台機器,這就是 NN(scoop shim 那次)會再發生一遍的條件。

同一段還有第二個問題:記錄「是哪一種 shell 回答的」那個變數寫在函式裡,而呼叫端是
`x=$(f)`——**subshell**,於是那個記錄隨它一起消失。一個量對了、卻報告不出來的檢查。

修法:用 `env -i` 加一份白名單變數啟動 shell,並依序問三次——`-c`(經 ssh 的腳本)、`-lc`
(登入 shell)、`-lic`(互動終端機),回報第一個成功的那一種。結果以全域變數回傳。

這件事一被問對,開發機自己就給出了一個當天沒人知道的答案:

```console
$ env -i HOME=$HOME zsh -c 'command -v csv2'      # 什麼都沒有
$ env -i HOME=$HOME zsh -lc 'command -v csv2'
/opt/homebrew/bin/csv2
```

`/opt/homebrew/bin` 是 `/etc/zprofile` 的 path_helper 放進去的,而那是**登入**才會讀的檔案。
因此 `ssh mac 'csv2 --version'` 在這台機器上會失敗——這件事在此之前沒有被寫下來過。

**形狀:一個量到了「與它宣稱的東西相鄰」的檢查。** 與 NN 同族(比對永遠不會變的版本號),
而這一次相鄰的那個東西是「呼叫者的環境」。

## IZ. 「那個目錄在不在 PATH 上」不是「shell 叫不叫得出 csv2」(2026-08-25 修正,T203h)

修好 IV–IY 之後,install.zsh 決定「要不要寫 rc 檔」的依據仍然是:

```zsh
case ":$PATH:" in *":$DEST_DIR:"*) on_path=1 ;; esac
```

這個問法在兩個方向上都答錯:

```console
$ multissh -F win.conf winnode 'case ":$PATH:" in *":$(cygpath -u "$LOCALAPPDATA")/csv2:"*)
      echo yes;; *) echo no;; esac'
no                                   ← 目錄不在 PATH 上
$ multissh -F win.conf winnode 'command -v csv2'
/c/Users/lowei/scoop/shims/csv2      ← 而 csv2 叫得出來，經由 shim
```

於是新的 install.zsh 會在那台機器上判定「不在 PATH 上」,建立 `~/.bashrc`、並往它既有的
`~/.profile` 附加一段——**去修一個沒有壞的東西**,而且留下一個標著 csv2 的區塊。反方向同樣
會錯:一個目錄可以在 PATH 上,而更前面某個目錄提供的是另一個建置(那正是 NN)。

修法:不要問字串,問結果。先問「一個從零開始的 shell 執行到的是不是我剛放的那個檔案」;不是的話,
再問「這個環境呢」;兩者都不是,才寫 rc。Windows 節點因此走第二支,什麼都不寫,並且說出
「以空環境啟動的 shell 找不到它」。

**形狀:一個以「近似值」代替「所問之事」的判斷。** 與 IU(用最後兩個位元組問整個檔案)、
GW(用數量問行尾)同族。

## JA. 判斷「這是不是我剛裝的那個檔案」時比對了內容,而不是身分(2026-08-25 修正,T203i)

IZ 的第二支——「這個環境叫得出 csv2 嗎」——我寫成:

```zsh
[[ "$(sum_of "$(resolved_target $_inherited)")" == "$(sum_of "$DEST")" ]]
```

當場就答錯了:

```console
$ T=$(mktemp -d)
$ HOME=$T SHELL=/bin/zsh ./install.zsh --prefix $T/bin
已裝到 /tmp/.../bin/csv2，而目前這個 shell 以 `csv2` 執行到的就是它。
$ ls -a $T
.  ..  bin                          ← 沒有寫 .zshenv，而那個 prefix 仍然叫不出來
```

shell 執行到的其實是 `/opt/homebrew/bin/csv2`。它與剛裝的那份**位元組相同**,因為兩者是同一次
建置——於是雜湊比對說「是同一個」,而它們是不同路徑上的不同檔案。

位元組相等是「shell 會不會執行到這支程式」的正確問法(那正是 NN 要的),卻是「這是不是我剛放的
那個複本」的錯誤問法。同一個比較,在相鄰的兩個問題上,一個對一個錯。

修法:身分用 `-ef`(同一個 device 與 inode),內容用雜湊,兩者不互相代替。

**形狀:一個在相鄰問題之間被沿用的正確工具。** 這一次沿用的方向,恰好是它不成立的那一邊。

## JB. 一份「戳記接受、偏移量已錯」的索引,會讓 `-mid` 拒絕一個完全正常的檔案,並指控資料(2026-08-25 修正,T204)

第 74 回合盲測回報,經親手重現。README 的契約寫得很清楚,而且不只一處:

> The index is always an optimisation and never a precondition.
> Stale, truncated, corrupt or a version behind — all discarded in favour of a
> scan, **none an error**.

當 O(1) 戳記**拒絕**那份 sidecar 時,這條契約成立,實測確認過。問題出在戳記**接受**它、
而偏移量已經不對的時候:

```console
$ { printf 'id,value\n'; i=1; while (( i <= 2000 )); do printf '%d,value%06d\n' $i $i; ((i++)); done } > sm.csv
$ csv2 --build-index -i sm.csv
index built: 2000 records, stride 256, 8 grid points

$ python3 - <<'PY'                # 大小不變、mtime 還原到奈秒、頭尾 64 位元組不動
import os
st=os.stat('sm.csv'); d=open('sm.csv','rb').read()
d=d.replace(b'\n500,value000500\n', b'\n500,value0005001\n')     # 長一個位元組
d=d.replace(b'\n1800,value001800\n', b'\n180,value001800\n')     # 短一個位元組
open('sm.csv','r+b').write(d); os.utime('sm.csv', ns=(st.st_atime_ns, st.st_mtime_ns))
PY

$ grep -c '^$' sm.csv
0                                  ← 檔案裡沒有任何空白行

$ csv2 -mid 1500,1500 -i sm.csv
csv2: record 1281 (line 1282) is a blank line, and a blank line is not a record
with 2 empty fields; remove it. A file that ends with two newlines has one
$ echo $?
1

$ csv2 -mid 1500,1500 --no-index -i sm.csv
1500,value001500                   ← 同一個檔案、同一個指令，正確且 exit 0
```

`-tail 1` 同樣:

```console
$ csv2 -tail 1 -i sm.csv
csv2: record 1793 (line 1794) is a blank line ...          exit 1
$ csv2 -tail 1 --no-index -i sm.csv
2000,value002000                                            exit 0
```

`-debug` 說出了發生什麼事:

```
DEBUG index hit: record 1500 via grid point 1281 at byte 20662
```

那個位元組不是紀錄的開頭,是前一筆的終止符。解析器從一個 `\n` 開始讀,得到一個空白行,
然後照規矩拒絕它。

**兩件事各自都是缺陷:**

1. **索引成了必要條件。** 一個索引造成的 mis-seek,把一個「有索引時比較快、沒索引時也會對」
   的操作,變成了一個失敗的操作。契約說這不該發生。
2. **那則訊息指控的是資料,而它裡面每一個事實都來自那份壞掉的索引。** 「record 1281」與
   「line 1282」都是從錯誤的格點推導出來的;檔案裡沒有空白行,也沒有第 1281 筆的問題。
   一個照著這則訊息去做的人,會在檔案裡找一個不存在的空白行——而問題在 sidecar 裡。

`--verify-index` 抓得到,而且說得準確:

```console
$ csv2 --verify-index -i sm.csv
index MISMATCH: record 513: index says byte 8093, actual 8094
index MISMATCH: record 769: index says byte 12189, actual 12190
```

前提條件（大小相同、mtime 到奈秒相同、頭尾各 64 位元組相同）正是 README 已經記載、且由 T143
釘住的那個已知缺口。因此這**不是**一個新的缺口,是那個已知缺口的一個「不只是安靜答錯」的
新後果:README 一貫預測的是「安靜地給出錯一位的紀錄編號、exit 0」,而那個確實也重現得到;
它從未說過同一種過期還有一個「大聲拒絕一個正常檔案」的形態。

**形狀:一條「絕不成為必要條件」的規則,只在它被檢查出來的那條路徑上成立。** 與 IX、IG/IN
同族——契約在「戳記拒絕」時被遵守,而在「戳記接受但內容已錯」時沒有。

## JC. 一則拒絕開出的處方,照抄下來會得到另一個錯誤(2026-08-25 修正,T205a)

第 74 回合順帶回報。把一個「長得像旗標」的值存進儲存格時:

```console
$ csv2 -update 1:2 -append -i t.csv --in-place
csv2: -update -append: -append is a flag, and this position takes DATA. csv2 will
not treat a flag as data. If the value really is -append, mark it as data with --:
-update -- -append
                    ^^^^^^^^^^^^^^^^^^ 照這樣打
$ csv2 -update -- -append -i t.csv --in-place
csv2: -update: expected r:c, got "-append"          ← 得到另一個錯誤
```

正確的形式是 `csv2 -update 1:2 -- -append`。那個位址在訊息被組出來之前就已經被消耗掉了,
而訊息用 `\(flag) -- \(v)` 去重建一個指令——對只吃一個引數的動詞(`-encrypt COL`)這是對的,
對 `-update r:c VALUE` 就少了中間那一個。

修法:不要印一個它組不出來的完整指令。改成指出「把 `--` 放在那個值的正前面」,並只示範
`-- -append` 那一段——那對每一個動詞都成立。

**形狀:一個從「手邊的動詞」推廣出來的處方。** 與 FH、FN、IV 同族;這一次推廣的是引數的個數。

## JD. `-append` 撞到撕裂的尾巴時,建議一個 `-append` 自己會拒絕的旗標(2026-08-25 修正,T205b)

同一回合。

```console
$ printf 'a,b\n1,"oops\n' > q.csv
$ csv2 -append '2,y' -i q.csv --in-place
csv2: record 1: the input ends inside a quoted field -- the closing quote is
missing. The record is incomplete; pass --truncate-partial to discard it.
                                          ^^^^^^^^^^^^^^^^^^ 照這樣做
$ csv2 -append '2,y' --truncate-partial -i q.csv --in-place
csv2: --truncate-partial is refused with -append, whatever the file contains: ...
      If the file does have a torn tail, write a clean copy first
      (csv2 -r -t --truncate-partial -i FILE -o CLEAN) and append to that
```

第二則拒絕是對的,而且給了可用的做法,因此沒有資料處於風險中——但第一則把人送進一堵牆。
那則訊息來自解析器,而解析器不知道自己是被哪一個動詞叫起來的;`--truncate-partial` 對
`-r` 是對的建議,對 `-append` 不是。

修法:`-append` 的那次前置掃描把這個錯誤接住,換成它自己那一版的處方(先寫乾淨副本,再對它
追加)。解析器那一則不動——它對其他每一個動詞都是對的。

**形狀:一則對「呼叫它的人是誰」一無所知的訊息,而處方恰好取決於那件事。**

## JE. `install.zsh --prefix` 沒有寫在任何地方,而它是「試用一次」唯一安全的做法(2026-08-26 修正,README)

第 75 回合。任務要求把 csv2 裝進一個用完即丟的 HOME 與 prefix,並證明「一個空環境的 shell」
執行得到它。那個回合做到了,但它明白指出:

> `--prefix` appears nowhere in either file — the only match for the string is
> `$(brew --prefix)`, a shell command inside a sentence.

README 寫了 `--uninstall` 與 `--no-rc`,沒有寫 `--prefix` 與 `--dry-run`。於是那個省略讀起來
像「沒有這個選項」。而在一台有 Homebrew 的機器上,唯一有記載的行為就是「裝進
`$(brew --prefix)/bin`」——該回合查過,那裡已經有一個 621,000 bytes 的 csv2,與當時的建置大小
不同。**只讀 README 的人照做,會覆蓋掉使用者實際在用的那一份。** 那個回合刻意沒有走那條路,
而它用的 `--prefix` 是任務給的,不是文件給的。

修法:把四個選項列成一張表,並說明「不給 `--prefix` 時目的地是它替你選的,而那會覆蓋既有的
那一份」。

**形狀:一份「列了一部分選項」的文件。** 列出兩個而漏掉兩個,比一個都不列更糟——因為它讀起來
像是完整的。

## JF. 「一次 delete 之後,紀錄編號變成什麼」從未被寫出來(2026-08-26 修正,T206a/b)

同一回合。任務直接問「之後的紀錄編號是什麼」,而 README 只在一個 `-insert` 例子的輸出裡
「隱含地」回答過。同一個回合也把「不同的編輯動詞能不能在一次執行裡混用」當成一場賭注:

> The README says `-insert`, `-delete`, `-update` and `-delete -cell` "can
> **each** be given more than once in a run" — that grants repetition of each
> verb, not mixture of different verbs. It works, but I ran it as a bet.

兩件事都成立,實測確認:

```console
$ csv2 -insert 3 'NEW,9' -delete 2 -i t.csv --in-place    # 混用，一次原子編輯
$ csv2 -r -t -rownum -i t.csv
rownum,pkg,ver
1,r1,1
2,NEW,9      ← 兩個索引都是對「送達時的檔案」計數
3,r3,3
4,r4,4       ← 刪除之後連續編號，沒有缺口
5,r5,5
```

修法:兩句話都寫進批次編輯那一節,並由 T206a/b 釘住。

**形狀:一份文件在一個例子的輸出裡回答了問題,而讀者是在別處問的。**

## JG. 「它不會重新編號任何東西」——講的是位址,而讀者是在問編輯(2026-08-26 修正,README)

同一回合,而這一條是上一條的一半原因。`-rownum` 那個條目開頭是:

> prepend a record-number column. **It does NOT renumber anything**: see
> "Two numberings" below.

它的意思是「`-rownum` 那一欄不會改變位址」——讀取時 `1:1` 仍然指第一筆的第一欄。但它坐落在
一個叫「兩套編號」的章節旁邊一個螢幕的距離,而那正是一個人想知道「刪除會不會重新編號」時
會走到的地方。第 75 回合原話:

> it reads as the opposite of the truth.

修法:把那句話改成「它不會改變任何**位址**」,並加一句括號明說「這句話對編輯做了什麼隻字未提」。

**形狀:一句在它自己的段落裡正確的話,放在讀者帶著另一個問題抵達的位置上。**

## JH. 「不讀檔就計數」的建議,指向的是會讀完整個檔案的那條路(2026-08-26 修正,T206c/d/e)

同一回合。「不提供的功能」那張表對 `-count` 的答覆是「`--json` 結尾那行 meta 的 `records`」,
而取得它最直覺的方式是 `csv2 -r --json`——那會讀過每一個位元組。該回合自己從兩個不同章節推導出
便宜的寫法,並量了出來:

```console
$ csv2 -r      --json -i big.csv -debug     read_bytes=2777795   records:200000
$ csv2 -tail 1 --json -i big.csv -debug     read_bytes=960       records:200000
```

**但那個便宜是有前提的,而該回合沒有量到那一半。** 親手補測:

```console
$ rm -f big.csv.index
$ csv2 -tail 1 --json -i big.csv -debug
read_bytes=2777795 file_bytes=2777795        ← 沒有 sidecar 時，它會讀完整個檔案
$ ls big.csv.index
no                                            ← 而且在 16 MiB 門檻以下不會留下一份
```

因此「用 `-tail 1` 計數比較便宜」若寫成無條件成立,會變成下一個回合的 DOC WRONG。

修法:把便宜的寫法連同 `sed` 取值一起寫出來,並把「sidecar 就是這個技巧的全部,而它不是自動的」
寫在同一段。T206c 釘住便宜的那一半,T206d/e 釘住貴的那一半。

**形狀:一個從「量到的那個案例」推廣出去的效能宣稱。** 與 FH、FN、IV 同族;這一次少掉的前提是
「有沒有索引」。

## 非缺陷:第 75 回合回報 install.zsh 每次都印出一份 16 行的目錄列表(2026-08-26 查證,不成立)

那個回合把這一項放進 TOOL BROKEN,描述得很具體:

> `install.zsh` prints an unadorned 16-line directory listing of the repo root
> before its banner, on every invocation — install, re-install, and
> `--uninstall` alike. It looks like an unquoted glob or a stray `ls`.

**不是 install.zsh。** 那是這台機器的 zsh 有一個 `chpwd` hook,每次 `cd` 都會執行 `ls`;
那個回合的指令是 `… ./install.zsh …`,於是列表來自它自己那個
`cd`。逐字證明:

```console
$ /Volumes/LinuxCS/sos/csv2/install.zsh --dry-run | head -4     # 完全沒有 cd
csv2 install / 安裝
  from    : /Volumes/LinuxCS/sos/csv2/release/csv2 (csv2 0.1.0)
  to      : /opt/homebrew/bin/csv2
  (dry run — nothing will be written / 預演，不會寫入任何東西)

$ cd /Volumes/LinuxCS/sos/csv2 && ./install.zsh --dry-run | head -4    # 有 cd
（同樣四行，沒有列表——列表是 cd 印的，不在管線裡）
```

記在這裡是因為**下一個回合很可能會再報一次**,而那時應該花三十秒否證、而不是三十分鐘去找一個
不存在的 glob。

**形狀:一個被讀成程式輸出的環境產物。** 與這棵樹上其他幾次同族——每周用量上限、
`/Volumes/LinuxCS` 中途卸載、重裝後的 WSL 缺一把預設金鑰。TOOL BROKEN 是最該先懷疑的那一類,
而這一次它是空的。

## JI. `--normalize` 會拿走一個命中,而 README 只描述它多加一個(2026-08-26 修正,T207a/b/c)

第 76 回合,經親手重現。README 只說:

> **`--normalize` applies to the search string too**, not only to the cells — so
> a needle typed in NFC finds a cell stored in NFD.

那是真的,而且是「變寬」。但那個折疊同樣作用在儲存格上:

```console
$ od -A n -c acc.csv | head -2
   i  d  ,  w  o  r  d \n  1  ,  c  a  f  e \n  2
   ,  c  a  f  é ** \n  3  ,  c  a  f  e  ́ ** \n      ← 第 3 筆是 NFD

$ csv2 -contains cafe -i acc.csv
1:2	word	cafe
3:2	word	café          ← 找得到，因為 NFD 的位元組確實以 c-a-f-e 開頭

$ csv2 -contains cafe --normalize -i acc.csv
1:2	word	cafe          ← 那個命中不見了
```

兩個答案對它們各自被問的問題而言都是對的,而第二個幾乎總是人們想要的那一個。問題在於文件:
**它把 `--normalize` 描述成只會讓網變寬**,而一支「為了保險而加上它」的腳本,會安靜地找到更少。
第 76 回合的原話:「This is the one gap I would actually expect to cost someone data.」

反方向的「變寬」仍然成立,因此這個旗標也不是單純比較窄:

```console
$ csv2 -contains café -i acc.csv               # NFC 的搜尋字串
2:2	word	café
$ csv2 -contains café --normalize -i acc.csv
2:2	word	café
3:2	word	café                                 ← 多了 NFD 那一格
```

修法:把「它也可能拿走一個命中」連同上面兩段實測寫進同一節,並明說「請決定你要的是哪一種比較,
不要把這個旗標當保險加上去」。T207a/b/c。

**形狀:一句只描述了單一方向的說明。** 那個機制是對稱的（兩邊都折疊）,而文字只講了其中一邊。

## JJ. `.csv2` 儲存格裡的原始 tab 沒有被寫出來過(2026-08-26 修正,T207d/e)

同一回合。README 把 `.csv2` 的跳脫列為 `\n`、`\r`、`\\`,並說儲存格不得含原始換行——對「鍵盤上
緊鄰它們的那個字元」隻字未提。該回合的任務要求把「反斜線、tab、換行、雙引號」四個字元放進同一格,
於是它只能靠實驗確立:

```console
$ csv2 -update 1:2 $'A\\B\tC' -i t.csv2 --in-place
$ od -A n -c t.csv2 | tail -1
   \  \  B \t  C \n                    ← 反斜線被跳脫成 \\，tab 原樣留著
$ csv2 -get 1:2 -i t.csv2 | cmp - <(printf 'A\\B\tC'; printf '\n') && echo same
same
```

tab 合法、原樣儲存、逐位元取回。會混淆的是:`-contains` 的定位報告**確實**會把 tab 跳脫成 `\t`
——那是「一個命中要留在一行裡」的報告格式,不是檔案格式,而文件沒有把這兩件事分開講。

修法:在那一段加上「tab 不需要跳脫,會以原始位元組儲存」,並說明為什麼只有那三個要跳脫,以及
定位報告為何不同。T207d/e。

**形狀:一份「列舉了三項」的清單,讀者需要的是第四項。** 與 JE（install.zsh 列了兩個選項、漏了
兩個）同族——列出一部分比一個都不列更糟,因為它讀起來像完整的。

## JK. 「管線沒有任何特別之處」——而其實有四件事不一樣(2026-08-26 修正,T207f/g)

同一回合。「在管線裡」那一節的開場白是:

> `-si` and `-so` compose with every verb; **there is nothing special about a
> pipeline except that stdin has no suffix**

該回合量出至少四件事不一樣,其中兩件用「同樣的位元組」就能顯示:

```console
$ csv2 -contains xyz -i big.csv -debug          # 檔案，且旁邊有索引
DEBUG parallel: 8 chunks, 10 workers
$ cat big.csv | csv2 -si --headers 1 -contains xyz -debug
DEBUG single-threaded: stdin                     ← 同樣的位元組，另一條路徑
$ cat big.csv | csv2 -si --headers 1 --build-index
csv2: --build-index needs -i FILE                exit 1
```

不一樣的四件事:沒有平行搜尋(分塊要 seek)、索引不讀也不寫、`--build-index` 被拒絕、輸出以
64 KiB 區塊緩衝而非逐行。最後一項文件本來就在下一段講了,而那正好使開場白更容易被信——它被
它自己的下一段打臉,而讀者帶進管線的是開場那一句。

修法:刪掉那個宣稱,改成一張列出四項差異的表。T207f/g。

**形狀:一句「總括的否定」,寫在一段其實有四個例外的說明前面。**

## JL. `-log` 的「軌跡沒有記下什麼」表格自稱完整,而它漏了最嚴重的那一項(2026-08-26 修正,README)

同一回合。那張表列了五項,而該回合找到第六項,並指出它比那五項更嚴重:

```console
$ printf 'k,note\r\n1,alpha\r\n2,beta\r\n' > crlf.csv
$ csv2 -update 1:2 ALPHA -i crlf.csv --in-place -log t.log
$ grep update t.log
INFO  update 1:note: "alpha" -> "ALPHA"          ← 一格
$ diff <(...) crlf.csv | wc -l
（每一行都變了——因為一次編輯會把每個紀錄分隔符重寫成 LF）
```

那五項讓軌跡「少了脈絡」;這一項讓軌跡**低報那次變更**。一個拿著軌跡去和 diff 對帳的人對不起來,
而軌跡不會給他任何提示。這個行為在四節之外有記載（「對 CRLF 輸入做校驗和或 diff 都是錯的」）,
但那張「自稱是清單」的表格沒有它。

第二項遺漏,同樣不在表上:**沒有「是誰」**。軌跡裡沒有任何東西說出是哪個帳號執行的。

修法:兩項都加進那張表,並在 CRLF 那一列指回下方那段附註。

**形狀:一張自我宣稱完整的清單。** 一份「不完整但沒有自稱完整」的清單只是缺了東西;一份自稱是
「第二個讀者還原不出來的全部」的清單漏了一項,會讓人以為自己已經知道全部的風險。

## JM. 一句從註解沿用、從未被量過的話,被抄進了一個「主旨正是『動手前先量』」的 commit(2026-08-26 修正,T129e 在 guest 上執行)

2026-08-26 把 `stat(1)` 換成 `zstat` 時,我在四個平台裡量了三個——macOS、WSL、Windows 的 MSYS
zsh——然後對第四個寫下:

> Empty on a platform without the module: the aarch64 guest's zsh does not carry
> zsh/stat, which is why file_mode has an ls fallback at all.

那句話不是量出來的,是從這個檔案裡一則既有註解沿用的:

```
#   - The aarch64 guest has NO stat at all: this busybox was built without the
#     applet, and zsh/stat is not in its module set either.
```

那則註解寫於 busybox 沒有 `stat` applet 的年代,前半句當時為真;後半句沒有任何東西釘住它。
我把它抄進了兩則新註解、一則 SKIP 訊息、一封給母 session 的訊息,以及一個 commit message
——**而那個 commit 的主旨正是「動手之前先在每個平台上量」**。

母 session 在準備依此去改 buildroot 的 zsh 模組集之前先對 guest 實測,結果相反:

```
/usr/lib/zsh/5.9.999.3-test/zsh/stat.so     14272 bytes
zmodload zsh/stat                           rc=0
zstat -H h -- /etc/hostname                 size=12 mode=644 inode=106
```

我們自己的 harness 獨立證實了同一件事:在 `8a13b47` 上的 guest 執行中,**T129e 不在 SKIP 清單裡**
（7 個 SKIP 是 T143、T145e、T146e、T135c、T166e、T203e/f、T47）——它在 guest 上執行且通過。

修法:四處註解與一則 SKIP 訊息全部更正,並在每一處寫下「這句話原本是哪裡來的、為什麼從未被量」。
`zstat_mode` 的「回傳空的」保留,因為呼叫端不該被迫假設——但它現在明說那不是對任何一個現有平台的
描述。

**形狀:一句在註解裡的宣稱,比它所描述的系統活得更久。** 與 2026-08-19 那張「五條全部已不成立」的
缺陷表同族,也與這棵樹一再記下的那句話同族——一份寫在指令檔裡的清單,會與它所描述的程式反向漂移,
而沒有任何東西會回報它。差別在於這一次漂移的載體是一則程式碼註解,而它被一次「以嚴謹為題」的
修改抄了出去。

**副作用（保留）：** 為了繞過那個不存在的限制而寫的 T129f 是有價值的,理由與那個限制無關:
T129e 比的是兩個「讀取器」,因此它只說「它們一致」,不說「其中任何一個是對的」——兩個錯得一樣的
讀取器一樣會通過。T129f 比的是 `chmod` 設進去的那個值,不牽涉第二個讀取器,而且用 754 而不是 600,
會運動到 600 用不到的 r-x 與 r--。
