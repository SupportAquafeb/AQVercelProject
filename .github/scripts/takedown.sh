#!/usr/bin/env bash
# takedown.sh — 商品圖圖床每週下架（change retire-vm-img-upload）
#
# 刪掉 origin/main 上 image/ 第一層、副檔名 jpg（不分大小寫）、「上架時間」早於現在減 N 天的檔案，
# 一個 commit 推回 main。上架時間＝最後一次改到這個路徑的 commit 時間（重新上傳同名檔會重新計時）。
# 其他檔案（txt、子資料夾）一律不動；查不到時間的保留。
#
# 原始碼在 USDARS/devops-tools 的 scripts/image-upload/takedown.sh，部署到 SupportAquafeb/AQVercelProject 的
# .github/scripts/takedown.sh，兩邊內容必須逐位元組相同（以 git blob SHA 驗收）。
#
# 不下載任何圖片：只讀 commit 與 tree。
#   - git log 一定要 --no-renames：改名偵測會比對內容，在 blob:none 的 clone 裡等於把圖逐張抓回來。
#   - 用臨時 index 組新 tree，write-tree 一定要 --missing-ok（2026-11-17 實測：不加會把 blob 全抓回來）。
#
# 用法：takedown.sh [--days N] [--dry-run]
# 結束碼：0 成功（0 張時不 commit）、2 repo 是淺層的、3 推送 3 次都失敗、64 參數錯誤
# 有 GITHUB_OUTPUT 時寫入 removed=<張數> 與 commit=<推上去的 commit，沒有推就是空字串>。
set -euo pipefail

days=7
dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --days)
      [ $# -ge 2 ] || { echo "takedown: --days needs a value" >&2; exit 64; }
      days="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "takedown: unknown argument: $1" >&2; exit 64 ;;
  esac
done
case "${days}" in ''|*[!0-9]*) echo "takedown: --days must be a whole number" >&2; exit 64 ;; esac

remote=origin
branch=main
ref="refs/remotes/${remote}/${branch}"

if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
  echo "takedown: repository is shallow; full commit history is required" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# 臨時 index：不碰工作目錄，也不受 sparse checkout 影響（Actions 只 checkout .github）
idx_git() { GIT_INDEX_FILE="${work}/index" git -c core.sparseCheckout=false -c index.sparse=false "$@"; }

write_output() { # $1 = removed, $2 = commit
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    { echo "removed=$1"; echo "commit=$2"; } >> "${GITHUB_OUTPUT}"
  fi
}

# 算出要下架的路徑，NUL 分隔寫進 ${work}/old，張數放進 count。
# 在目前的 shell 執行（不放進 $(...)），set -e 才管得到裡面的 git 失敗（bash 3.2 不會把 errexit 帶進 command substitution）。
select_old() {
  local cutoff
  cutoff=$(( $(date +%s) - days * 86400 ))
  git ls-tree -z "${ref}" image/ > "${work}/tree"
  git -c core.quotepath=false log -z --no-renames --name-only --format='%x01%ct' "${ref}" -- image/ > "${work}/log"
  # log 的格式：每個 commit 先一筆 \x01<時間>，接著是它改到的路徑（第一筆前面帶一個換行）；
  # 由新到舊讀，第一次看到某路徑時的時間就是它最後一次被改的時間。
  perl -e '
    use strict; use warnings;
    my ($cutoff, $tree, $log) = @ARGV;
    local $/ = "\0";
    my (%when, $t);
    open(my $L, "<", $log) or die "takedown: cannot read $log\n";
    while (my $r = <$L>) {
      chomp $r; $r =~ s/^\n//;
      next if $r eq "";
      if ($r =~ /^\x01(\d+)$/) { $t = $1; next; }
      $when{$r} = $t if defined $t && !exists $when{$r};
    }
    open(my $T, "<", $tree) or die "takedown: cannot read $tree\n";
    my @old;
    while (my $r = <$T>) {
      chomp $r;
      my ($meta, $path) = split /\t/, $r, 2;
      my (undef, $type) = split / /, $meta;
      next unless $type eq "blob" && $path =~ m{\Aimage/[^/]+\.jpg\z}i;
      next unless exists $when{$path};
      push @old, $path if $when{$path} < $cutoff;
    }
    print "$_\0" for sort @old;
  ' "${cutoff}" "${work}/tree" "${work}/log" > "${work}/old"
  count="$(tr -cd '\0' < "${work}/old" | wc -c | tr -d ' ')"
}

attempt=1
while :; do
  select_old
  echo "takedown: ${count} file(s) older than ${days} day(s)"
  tr '\0' '\n' < "${work}/old"

  if [ "${dry_run}" = 1 ] || [ "${count}" = 0 ]; then
    [ "${dry_run}" = 1 ] && echo "takedown: dry run, nothing changed"
    write_output 0 ""
    exit 0
  fi

  rm -f "${work}/index"
  parent="$(git rev-parse "${ref}")"
  idx_git read-tree "${parent}"
  idx_git update-index --force-remove -z --stdin < "${work}/old"
  tree="$(idx_git write-tree --missing-ok)"
  commit="$(git commit-tree "${tree}" -p "${parent}" -m "下架：${count} 張（上傳超過 ${days} 天）")"

  if git push --quiet "${remote}" "${commit}:refs/heads/${branch}"; then
    echo "takedown: pushed ${commit}"
    write_output "${count}" "${commit}"
    exit 0
  fi
  if [ "${attempt}" -ge 3 ]; then
    echo "takedown: push failed 3 times; nothing was taken down" >&2
    exit 3
  fi
  attempt=$(( attempt + 1 ))
  echo "takedown: push rejected; fetching and recomputing (attempt ${attempt}/3)" >&2
  git fetch --quiet "${remote}"
done
