#!/bin/bash

# ダウンロードした資材を削除
removeMaterials() {
  if [ -z $1 ]; then
    echo "パスが指定されていないため資材を削除できません。\nディレクトリ $1 手動で削除してください。" 1>&2
    exit 90;
  else
    while true; do
      read -p "リリース資材 $1 を削除しますか？（Y/N）" yn
      case $yn in
        [Yy]*)
          rm -rf "$1"
          if [ $? -eq 0 ]; then
            echo "リリース資材を削除しました。"
          else
            echo "リリース資材削除時にエラーが発生しました。\nディレクトリ $1 を手動で削除してください。" 1>&2
            exit 90;
          fi
          break ;;
        [Nn]*)
          echo "$1 に資材が残っています。手動で削除してください。"; break ;;
        *) echo -e "\n無効な入力です。"; continue ;;
      esac
    done
  fi
}

# 1つ目の引数が --dryrun か空以外ならエラー
if [ "$1" != "--dryrun" ] && [ -n "$1" ]; then
  echo "引数の指定が誤っています。\nコマンド例: release.sh [--dryrun]" 1>&2
  exit 91;
fi

# dryrunモードで実行するか確認
Dryrun=$1
while true; do
  if [ "$Dryrun" == "--dryrun" ]; then
    echo "Dryrunモードで実行します。s3へのアップロード及びキャッシュ削除は行われません。"; break;
  else
    read -p "Dryrunモードではありません。s3へのアップロード及びキャッシュ削除を行いますか？（Y/N）: " yn 
    case "$yn" in
      [Yy]*) break ;;
      [Nn]*) echo "終了します。" ; exit 0 ;;
      *) echo "無効な入力です。"; continue ;;
    esac
  fi
done

# 環境設定
while true; do
  while true; do
    echo "アップロード先の環境を指定してください。"
    read -p "本番環境は【Prod】、STG環境は【STG】を入力します。:" EnvSwitch # STG／Prod以外はエラー
    case "${EnvSwitch}" in
    STG) break ;;
    Prod) break ;;
    *) echo "無効な入力です。"; continue ;;
    esac
  done
  
  while true; do
    read -p "s3へアップロードするディレクトリ名を入力してください。 (YYYYMMDD_改修内容):" TargetDir # YYYYMMDD_改修内容
  
    # 空文字の場合エラー
    if [ -z "$TargetDir" ]; then
      echo "ディレクトリ名が入力されていません。"; continue;
    fi
  
    GDrivePath="/mnt/g/共有ドライブ/ITS_プロジェクト/美術館・予約決済入場システム/14.リリース資材/${EnvSwitch}資材/" # Gドライブ資材パス
    GDriveMaterialsPath="${GDrivePath}${TargetDir}"  # s3へアップする資材
    LocalMaterialsPath="/tmp/${TargetDir}" # ダウンロードした資材のローカルパス
  
    # ローカルにディレクトリが存在するかチェック
    ls "${LocalMaterialsPath}" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "ディレクトリ ${LocalMaterialsPath} は重複しているため作成できません。別のディレクトリ名を入力してください。";
      continue;
    fi
  
    # Gドライブディレクトリが存在しない場合エラー
    ls ${GDriveMaterialsPath} >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "Gドライブにディレクトリが見つかりません。";
      continue;
    fi
  
    echo "リリース資材：${TargetDir}を指定しました。";
    break;
  done
  
  while true; do
    echo "-----------------------------------------------------------------------------------------------"
    echo "リリース資材パス : ${GDriveMaterialsPath}"
    echo "一時保存先 : ${LocalMaterialsPath}"
    echo "-----------------------------------------------------------------------------------------------"
    read -p "以上の内容でよろしいですか？ (Y/N): " yn

    case "$yn" in 
      [Yy]*) echo "リリース資材のコピーを開始します。"; break ;;
      [Nn]*) echo "情報の入力をやり直します。"; break ;;
      *) echo -e "\n無効な入力です。 Y または N を入力して下さい。"; continue ;;
    esac
  done
  case "$yn" in
    [Yy]*) break ;;
    [Nn]*) continue ;;
  esac
done

declare -A Buckets  # アップロード先のバケット
declare -A Caches   # キャッシュ削除するディストリビューション
declare -a LangList # ダウンロードする言語のディレクトリ名を格納

# 環境ごとのCloudFrontキャッシュID
declare -A CachesLP=(
  ["jpn"]="E3TE08POZO2UOW"
  ["eng"]="E20UX5B79JV5ET"
  ["sch"]="E1OFD73IQK9O01"
  ["tch"]="E3ATS60KPL9YC8"
  ["kor"]="E1VT6M8ES25ZYV"
)

declare -A CachesSTG=(
  ["jpn"]="E20KP53UMC03EM"
  ["eng"]="E1F9KY64BZS6FW"
  ["sch"]="EUER28XLCD2VE"
  ["tch"]="E10ZMCIH460UBJ"
  ["kor"]="E2M1GWBWNSXKO4"
)

# ダウンロード処理
# ローカルにダウンロード先ディレクトリを作成
mkdir "${LocalMaterialsPath}"
if [ $? -ne 0 ]; then
  echo "ディレクトリが作成できませんでした。" 1>&2
  exit 92;
fi
echo "ディレクトリ ${LocalMaterialsPath} を作成しました。"

# Gドライブ上のファイルサイズ合計を取得（エラー出力を無視しつつ値だけ拾う）
TotalSize=$(du -sb "${GDriveMaterialsPath}" 2>/dev/null | awk '{print $1}')

# TotalSizeが空文字や数値以外のときにも備えてチェック
# -z で空文字かどうか、数値比較の前に [[ "${TotalSize}" =~ ^[0-9]+$ ]] で数値かどうか確認
if [[ -z "${TotalSize}" || ! "${TotalSize}" =~ ^[0-9]+$ || "${TotalSize}" -le 0 ]]; then
  echo "コピー対象が存在しない、またはサイズが取得できませんでした。進捗バーをスキップします。"

  # 進捗バーなしでそのままコピー実行
  cp -r "${GDriveMaterialsPath}/." "${LocalMaterialsPath}"
  if [ $? -eq 0 ]; then
    echo "リリース資材のコピーに成功しました。"
  else
    echo "ダウンロード時にエラーが発生しました。" 1>&2
    removeMaterials $LocalMaterialsPath
    exit 93;
  fi

else
  # 進捗バーを表示しながらの処理（TotalSizeが0より大きい前提）
  CopiedSize=0
  BarWidth=50

  (
    # 0.5秒間隔でローカルへコピー済みバイト数をチェックして進捗バーを更新する
    while [ "${CopiedSize}" -lt "${TotalSize}" ]; do
      # ファイルサイズを取得
      TmpSize=$(du -sb "${LocalMaterialsPath}" 2>/dev/null | awk '{print $1}')
      # 空文字対策としてTmpSizeが空なら0にする
      if [ -z "${TmpSize}" ]; then
        TmpSize=0
      fi
      CopiedSize="${TmpSize}"

      # 進捗率計算 (整数演算)
      Progress=$((CopiedSize * 100 / TotalSize))
      # 進捗率が100%を超えないように調整
      if [ "${Progress}" -gt 100 ]; then
        Progress=100
      fi
      Filled=$((Progress * BarWidth / 100))
      Empty=$((BarWidth - Filled))

      # \r を使って行頭に戻り、進捗バーを上書き
      printf "\rダウンロード中: [%-${BarWidth}s] %3d%%" \
        "$(printf '#%.0s' $(seq 1 ${Filled}))$(printf ' %.0s' $(seq 1 ${Empty}))" \
        "${Progress}"

      sleep 0.5
    done
  ) &
  # アニメーションのプロセスid取得
  AnimPid=$!

  # Gドライブからローカルに資材をコピー
  cp -r "${GDriveMaterialsPath}/." "${LocalMaterialsPath}"
  if [ $? -eq 0 ]; then
    # 成功時メッセージ
    echo -e "\rリリース資材のコピーに成功しました。"
  else
    # コピーに失敗したらダウンロードエラー処理
    kill ${AnimPid} 2>/dev/null
    wait ${AnimPid} 2>/dev/null
    echo "ダウンロード時にエラーが発生しました。" 1>&2
    removeMaterials $LocalMaterialsPath
    exit 94;
  fi

  # アニメーション停止
  kill ${AnimPid} 2>/dev/null
  wait ${AnimPid} 2>/dev/null
fi

# 言語リストをダウンロードファイルを元に作成
for Dir in ${LocalMaterialsPath}/*; do
  LangList+=("$(basename "${Dir}")")
done

# 環境別に言語をキーにマッピング
for Region in "${LangList[@]}"; do
  Prefix=""
  # 地域ごとにプレフィックスを変更（jpnはkumのみ）
  if [ "${Region}" == "jpn" ]; then
    Prefix="kum"
  else
    Prefix="${Region}-kum"
  fi
  # 配列の設定
  if [ "${EnvSwitch}" == "STG" ]; then
    Buckets["${Region}"]="s3://${Prefix}-stg-lp-clitest"
    Caches["${Region}"]=${CachesSTG[${Region}]}
  elif [ "${EnvSwitch}" == "Prod" ]; then
    Buckets["${Region}"]="s3://${Prefix}-lp-clitest"
    Caches["${Region}"]=${CachesLP[${Region}]}
  fi
done

# アップロード処理: 選択した言語ごとにs3へsync
for Lang in "${LangList[@]}"; do
  Bucket=${Buckets["$Lang"]}
  aws s3 sync "${LocalMaterialsPath}/${Lang}" "${Bucket}" ${Dryrun}
  if [ $? -eq 0 ]; then
    if [ "${Dryrun}" == "--dryrun" ]; then
      echo "Dryrun ${Bucket}へアップロードに成功しました。"
    else
      echo "${Bucket}へアップロードに成功しました。"
    fi
  else
    echo "${Backet}へアップロードに失敗しました。" 1>&2
    removeMaterials $LocalMaterialsPath
    exit 95;
  fi
done

# CloudFront キャッシュ削除: 選択した言語ごとにInvalidationを実行
if [ "${Dryrun}" != "--dryrun" ]; then
  for Lang in "${LangList[@]}"; do
    Cache=${Caches[${Lang}]}
    echo -e "キャッシュを削除しています。${Lang}-${EnvSwitch}:${Cache}"

    aws cloudfront create-invalidation --distribution-id "${Cache}" --paths "/*"
    if [ $? -eq 0 ]; then
      echo -e "キャッシュ削除に成功しました。${Lang}-${EnvSwitch}:${Cache}\n"
    else
      echo "キャッシュ削除に失敗しました。${Lang}-${EnvSwitch}:${Cache}." 
      removeMaterials $LocalMaterialsPath
      exit 96;
    fi
  done
else
  echo "Dryrunモードのためキャッシュ削除は行われませんでした。"
fi

# ダウンロードした資材を削除
removeMaterials $LocalMaterialsPath

echo "プログラムは正常に終了しました。"
