# アニメーション付きファイルコピー用関数
# 引数
# $1 : コピー元パス
# $2 : コピー先パス
fileCopy() {
  # Gドライブ上のファイルサイズ合計を取得（エラー出力を無視しつつ値だけ拾う）
  TotalSize=$(du -sb "$1" 2>/dev/null | awk '{print $1}')

  # TotalSizeが空文字や数値以外のときにも備えてチェック
  # -z で空文字かどうか、数値比較の前に [[ "$TotalSize" =~ ^[0-9]+$ ]] で数値かどうか確認
  if [[ -z "$TotalSize" || ! "$TotalSize" =~ ^[0-9]+$ || "$TotalSize" -le 0 ]]; then
    echo "コピー対象が存在しない、またはサイズが取得できませんでした。進捗バーをスキップします。"
    # 進捗バーなしでファイルをコピー
    cp -r "$1" "$2"
    if [ $? -eq 0 ]; then
      echo -e "\r$1 を $2 にコピーしました。"
    else
      kill $AnimPid 2>/dev/null
      wait $AnimPid 2>/dev/null
      return 91
    fi
  else

    # 進捗バーを表示しながらの処理（TotalSizeが0より大きい前提）
    CopiedSize=0
    BarWidth=50
    (
      # 0.5秒間隔でローカルへコピー済みバイト数をチェックして進捗バーを更新する
      while [ "$CopiedSize" -lt "$TotalSize" ]; do
        # フォルダサイズを取得
        TmpSize=$(du -sb "$2" 2>/dev/null | awk '{print $1}')
        # 空文字対策としてTmpSizeが空なら0にする
        if [ -z "$TmpSize" ]; then
          TmpSize=0
        fi
        CopiedSize="$TmpSize"
        # 進捗率計算 (整数演算)
        Progress=$((CopiedSize * 100 / TotalSize))
        Filled=$((Progress * BarWidth / 100))
        Empty=$((BarWidth - Filled))
        # \r を使って行頭に戻り、進捗バーを上書き
        printf "\rファイルコピー中: [%-${BarWidth}s] %3d%%" \
          "$(printf '#%.0s' $(seq 1 $Filled))$(printf ' %.0s' $(seq 1 $Empty))" \
          "$Progress"

        sleep 0.5
      done
    ) &
    # アニメーションのプロセスid取得
    AnimPid=$!
    # ファイルをコピー
    cp -r "$1" "$2"
    if [ $? -eq 0 ]; then
      echo -e "\r$1 を $2 にコピーしました。"
    else
      kill $AnimPid 2>/dev/null
      wait $AnimPid 2>/dev/null
      return 92
    fi
    # アニメーション停止
    kill $AnimPid 2>/dev/null
    wait $AnimPid 2>/dev/null
  fi

  return 0
}
