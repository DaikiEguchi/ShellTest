# エラー時の処理テンプレート
# 引数
# $1 : エラーメッセージ
# $2 : 終了ステータス
errorTemplate() {
  echo -e "$1" 1>&2
  echo  "プログラムが異常終了しました。" 1>&2
  
  # pushd された回数だけ popd を実行
  PushdCount=$(dirs -v | wc -l)
  for ((i = 1; i < PushdCount; i++)); do
    popd > /dev/null
  done

  exit $2
}
