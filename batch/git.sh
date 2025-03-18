#!/bin/bash
# テスト用リポジトリのパス：/mnt/c/Users/daiki.eguchi/Desktop/共有用/ShellTest
. $(dirname "$(realpath "$0")")/functions/errorTemplate.sh

while true; do
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
  
  # mainかstgをユーザーに選択させる
  while true; do
    read -p  "最新化するブランチを選択してください。 (main/stg) :" BranchName
    case "$BranchName" in
      main) echo "mainブランチの最新化を行います。"; break;; 
      stg) echo "stgブランチの最新化を行います。"; break;; 
      *) echo "無効な入力です。main または stg を入力してください。";;
    esac
  done

  # 入力確認
  while true; do
    echo "-----------------------------------------------------------------------------------------------"
    echo "ローカルリポジトリのパス : ${LocalPath}"
    echo "ブランチ名 : ${BranchName}"
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
# どこで実行しても動作するように入力されたパスに移動する
pushd $LocalPath > /dev/null

# main/stgブランチへチェックアウトし、最新を取得
echo ">> ローカルリポジトリをリモートリポジトリと同期します。"

fetch_output=$(git fetch 2>&1)
exit_status=$?

# エラーがあった場合の処理
if [ $exit_status -ne 0 ]; then
  # SSH認証エラーの可能性をチェック（例："Permission denied (publickey)"）
  if echo "$fetch_output" | grep -q "Permission denied (publickey)"; then
    errorTemplate "SSH認証エラー：公開鍵認証に失敗しました。" 92
  else
    errorTemplate "${BranchName}ブランチのfetchに失敗しました。" 93
  fi
fi

echo ">> リポジトリの同期が完了しました。"

# main/stgブランチへチェックアウトし、最新を取得
echo ">> ${BranchName}ブランチにチェックアウトします。"

# checkout処理
checkout_output=$(git checkout ${BranchName} 2>&1)
case "$checkout_output" in
  "Switched to branch "*)
    echo "ブランチ '${BranchName}' に移動しました。" ;;
  "Already on "*)
    echo "すでにブランチ '${BranchName}' にいます。" ;;
  *"pathspec "*" did not match"*)
    errorTemplate "ブランチが存在しません。ブランチ名を確認してください。" 91;;
  *"The current branch "*" has no upstream branch"*)
    errorTemplate "リモート追跡ブランチが設定されていません。リモート追跡ブランチを確認してください。" 91;;
  *"Your local changes"*)
    echo "未コミットの変更があります。"
    while true; do
      read -p "変更を退避しますか？（Y/N）" yn
      case $yn in
        [Yy]*)
          read -p "退避メッセージを入力：" $m
          git stash push -u -m "$m"
          if [ $? -ne 0 ]; then
            echo "変更を退避しました。終了後に 'git stash pop stash@{0}' を実行してください。"
          else
            errorTemplate "変更の退避に失敗しました。" 92
          fi
          break ;;
        [Nn]*) echo "変更の破棄、退避、コミットのいずれかを行ってください。"; exit 0;;
        *) echo "無効な入力です。"; continue ;;
      esac
    done
  ;;
  *"Permission denied"*)
    errorTemplate "権限が不足しています。権限を確認してください。" 93;;
  *"detached HEAD state"*)
    errorTemplate "HEADが${BranchName}ブランチに紐づいていません。ブランチを作成してください。" 93;;
  *"resolve your current index first"*)
    errorTemplate "コンフリクトが発生しています。コンフリクトを解消してください。" 91;;
  *) errorTemplate "チェックアウト時に予期しないエラーが発生しました。" 99;;
esac

echo ">> ${BranchName}ブランチを最新化します。"
# git pull の出力と終了ステータスを取得
pull_output=$(git pull 2>&1)
exit_status=$?

# エラーがあった場合の処理
if [ $exit_status -ne 0 ]; then
  # SSH認証エラーの可能性をチェック（例："Permission denied (publickey)"）
  if echo "$pull_output" | grep -q "Permission denied (publickey)"; then
    errorTemplate "SSH認証エラー：公開鍵認証に失敗しました。" 92
  else
    errorTemplate "${BranchName}ブランチのpullに失敗しました。" 93
  fi
fi

echo ">> ${BranchName}ブランチの最新化に成功しました。"
echo "続けてビルドを行う場合、build.shを起動してください。"
