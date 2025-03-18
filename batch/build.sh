#!/bin/bash

. $(dirname "$(realpath "$0")")/functions/errorTemplate.sh
. $(dirname "$(realpath "$0")")/functions/fileCopy.sh

# 変数定義
EnvPath="/mnt/g/共有ドライブ/ITS_プロジェクト/美術館・予約決済入場システム/01.開発資料/KUM_LP/.env【削除厳禁】/"
GDrivePath="/mnt/g/共有ドライブ/ITS_プロジェクト/美術館・予約決済入場システム/14.リリース資材/" # Gドライブのアップロード先
declare -a LangList # アップロードする言語

while true; do
  # ビルドする環境を選択
  # 選択しないとアップロード先に作成するディレクトリ名のエラーチェックが行えない
  while true; do
    read -p "ビルド環境を選択してください。 (Prod/STG): " EnvSwitch # STG／Prod以外はエラー
    case "$EnvSwitch" in
      Prod) echo "本番環境のビルドを行います。"; break;;
      STG) echo "STG環境のビルドを行います。"; break;;
      *) echo "無効な入力です。Prod または STG を入力してください。";;
    esac
  done

  # ローカルリポジトリのパス入力
  while true; do
    read -p "ローカルリポジトリのパスを入力してください。: " LocalPath
    ls -d $LocalPath/.git > /dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "リポジトリが見つかりません。"
      continue
    fi
    break
  done
  # 相対パスで指定された場合にバグが起きるため、pwdを使用して絶対パスに変換
  LocalPath=$(pwd)

  # アップロード先に作成するディレクトリ名の入力
  while true; do
    read -p "アップロード先に作成するディレクトリ名を入力してください。(YYYYMMDD_改修内容): " UploadDirName
    # 空文字の場合エラー
    if [ -z "$UploadDirName" ]; then
      echo "ディレクトリ名が入力されていません。"
      continue
    fi

    # フォルダが既に存在する場合エラー
    if [ -d "${GDrivePath}${EnvSwitch}資材/${UploadDirName}" ]; then
      echo "そのディレクトリ名は既に存在しています。別の名前を入力してください。"
      continue
    fi
    break
  done

  # 入力確認
  while true; do
    echo "-----------------------------------------------------------------------------------------------"
    echo "ビルド環境 : ${EnvSwitch}"
    echo "ローカルリポジトリのパス : ${LocalPath}"
    echo "アップロード先ディレクトリ名 : ${UploadDirName}"
    echo "-----------------------------------------------------------------------------------------------"
    read -p "以上の内容でよろしいですか？ (Y/N): " yn
    case "$yn" in
      [yY]*) break ;;
      [nN]*) echo "情報の入力をやり直します。"; break ;;
      *) echo "無効な入力です。Y または N を入力してください。";;
    esac
  done
  case "$yn" in
      [yY]*) break ;; 
      [nN]*) continue ;;
  esac
done

while true; do
  # ビルドする言語のリストを作成
  LangList=() 
  for Lang in "jpn" "eng" "tch" "sch" "kor"; do
    while true; do
      read -p "${Lang} : アップロードしますか? (Y/N): " yn
      case "$yn" in
        [yY]*) echo "$Lang をアップロードします。"; LangList+=("$Lang"); break ;; 
        [nN]*) echo "スキップしました。"; break ;;
        *) echo "無効な入力です。Y または N を入力してください。";;
      esac
    done
  done

  # 入力確認
  while true; do
    echo "-----------------------------------------------------------------------------------------------"
    echo "ビルド言語 : ${LangList[@]}"
    echo "-----------------------------------------------------------------------------------------------"
    read -p "以上の内容でビルドを実行してもよろしいですか？ (Y/N) :" yn
    case "$yn" in
      [yY]*) echo "ビルドを実行します。"; break ;; 
      [nN]*) echo "情報の入力をやり直します。"; break ;;
      *) echo "無効な入力です。Y または N を入力してください。";;
    esac
  done
  case "$yn" in
    [yY]*) break ;; 
    [nN]*) continue ;;
  esac
done

# 選択した言語のビルド
pushd "$LocalPath" > /dev/null
for Folder in "${LangList[@]}"; do  
  cd "${Folder}"
  if [ $? -ne 0 ]; then
    errorTemplate "フォルダの移動に失敗しました。" 91
  fi

  if [ $EnvSwitch = "Prod" ]; then
    cp "${EnvPath}.env.prod" "./.env"
  else
    cp "${EnvPath}.env.stg" "./.env"
  fi
  if [ $? -ne 0 ]; then
    errorTemplate ".envのコピーに失敗しました。" 92
  fi
  
  npm run build
  
  if [ $? -eq 0 ]; then
    echo "${Folder}のビルドが完了しました。"
  else
    errorTemplate "${Folder}のビルドが失敗しました。" 93 
  fi
  
  cd ..
done
popd > /dev/null

# アップロードディレクトリの作成
UploadPath="${GDrivePath}${EnvSwitch}資材/${UploadDirName}" # アップロード先のディレクトリ
mkdir "$UploadPath"
if [ $? -eq 0 ]; then
  echo "ディレクトリ ${UploadPath} を作成しました。"
else
  errorTemplate "ディレクトリ ${UploadPath} の作成に失敗しました。" 94 
fi

pushd "$UploadPath" > /dev/null 2>&1
mkdir "${LangList[@]}"
if [ $? -eq 0 ]; then
  echo "ディレクトリ ${LangList[@]} を作成しました。"
else
  errorTemplate "ディレクトリ ${LangList[*]} のいずれかの作成に失敗しました。" 95
fi

# ビルドファイルをGドライブにコピー
for Lang in "${LangList[@]}"; do 
  fileCopy "${LocalPath}/${Lang}/dist/." "${UploadPath}/${Lang}"
  case "$?" in
      91) errorTemplate "\r${LocalPath}/${Lang}/dist/. から ${UploadPath}/${Lang} へのコピーに失敗しました。" 96;;
      92) errorTemplate "\r${LocalPath}/${Lang}/dist/. から ${UploadPath}/${Lang} へのコピーに失敗しました。" 97;;
      0) ;; # 何も処理をせずにcase文を抜ける
      *) errorTemplate "\r${LocalPath}/${Lang}/dist/. から ${UploadPath}/${Lang} へのコピーに失敗しました。" 98;;
  esac
done

popd > /dev/null 2>&1
echo -e "ビルドファイルが正常にGドライブにアップロードされました\nリリースを行うために、release.shを起動してください。"
exit 0
