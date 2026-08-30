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
輸出編碼成本。平行效率低於線性加速是預期行為，因為找出紀錄邊界的階段仍是單執行緒。
