# csv2 驗證量測

驗證腳本量測解析與寫入吞吐量、耐久寫入延遲，以及平行與索引門檻的影響。
它們不取代 [`../test/test_csv2.zsh`](../test/test_csv2.zsh) 的正確性測試。

```zsh
./measure.zsh
./benchmark.zsh
RECORDS=20000 ./measure.zsh
CSV2=/path/to/csv2 ./measure.zsh
```

`measure.zsh` 會寫出 `measure_output.txt`。母專案 runner 會在 aarch64 Linux
guest 執行相同量測，並擷取 `measure_output_linux.txt`。原生 Windows 驗證會寫出
`measure_output_windows.txt`。

資料集是逐列產生；相較於概略的 MB 大小，`RECORDS` 更能可靠控制資料量。量測採用
best-of-N 結果，只有在紀錄數、二進位檔與主機條件相同時才適合互相比較。

解析量測使用含引號逗號的欄位，並搜尋不會命中的值，因此結果代表解析成本，而非
輸出編碼成本。量測也會以相同資料列比較 `.csv` 與 `.csv2`，並回報 `.csv2`／`.csv`
比例。平行效率低於線性加速是預期行為，因為找出紀錄邊界的階段仍是單執行緒。

最新比較（2026-08-31，macOS arm64，200,000 筆，五次取最佳值，單執行緒且不使用索引）：
`.csv` 為 0.556 秒，`.csv2` 為 0.563 秒；加入無反斜線快路徑後，`.csv2`／`.csv` 比例為
1.01 倍。完整結果見
[`measure_output.txt`](measure_output.txt)。

要取得可比較的平行搜尋吞吐量與 RSS 量測，請執行 `./measure_parallel_rss.zsh`。
它使用相符的 `.csv` 與 `.csv2` 資料集，各至少 10,000,000 筆、約 1 GiB，且每筆都命中。
兩種格式都在預設值與 8 MiB 的 `CSV2_PARALLEL_MAX_BYTES` 下執行；結果寫入
`measure_parallel_rss_output.txt`。

最新結果（2026-08-30，macOS arm64，`csv2 0.1.0`，10,000,000 筆，
10 個工作者、4 MiB 區塊、每筆都命中）：`.csv` 吞吐量為 35.8/36.3 MiB/s、峰值 RSS
為 9.28/9.30 MiB；`.csv2` 吞吐量為 31.5/38.5 MiB/s、峰值 RSS 為 51.84/51.69 MiB，
依序對應預設值／8 MiB 上限。`.csv` 語料為 1,307,777,815 位元組，`.csv2` 語料為
1,307,777,833 位元組。
